package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"runtime"
	"strings"
	"syscall"
	"time"
	"unicode"

	"golang.org/x/net/websocket"
)

const (
	t3ReadScope    = "orchestration:read"
	t3AccessType   = "urn:ietf:params:oauth:token-type:access_token"
	t3RequestID    = "1"
	t3IOTimeout    = 10 * time.Second
	t3PingInterval = 25 * time.Second
)

var errT3Pairing = errors.New("pair the Huawei Push companion with T3 Code again")

var t3Dialer = &net.Dialer{
	Timeout: t3IOTimeout,
	ControlContext: func(_ context.Context, _, address string, _ syscall.RawConn) error {
		host, _, err := net.SplitHostPort(address)
		if err != nil || !t3LoopbackIP(host) {
			return errors.New("T3 server must use a loopback address")
		}
		return nil
	},
}

var t3HTTP = &http.Client{
	Transport:     &http.Transport{DialContext: t3Dialer.DialContext},
	Timeout:       t3IOTimeout,
	CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
}

type t3Connection struct {
	BaseURL       string `json:"baseUrl"`
	EnvironmentID string `json:"environmentId"`
	AccessToken   string `json:"accessToken"`
}

type t3Descriptor struct {
	EnvironmentID string `json:"environmentId"`
	Protocol      int    `json:"orchestrationProtocolVersion"`
}

func t3LoopbackIP(host string) bool {
	ip, err := netip.ParseAddr(host)
	return err == nil && ip.Zone() == "" && ip.Unmap().IsLoopback()
}

func t3LocalOrigin(value *url.URL) bool {
	return (value.Scheme == "http" || value.Scheme == "https") &&
		(value.User == nil && value.RawQuery == "" && !value.ForceQuery) &&
		(strings.EqualFold(value.Hostname(), "localhost") || t3LoopbackIP(value.Hostname()))
}

func validT3Credential(value string) bool {
	return value != "" && len(value) <= 8192 && strings.IndexFunc(value, func(r rune) bool {
		return unicode.IsControl(r) || unicode.IsSpace(r)
	}) == -1
}

func pairT3(ctx context.Context, pairingLink string) (t3Connection, error) {
	u, err := url.Parse(strings.TrimSpace(pairingLink))
	if err != nil || !t3LocalOrigin(u) || u.EscapedPath() != "/pair" {
		return t3Connection{}, errors.New("enter a T3 Code /pair link on this computer")
	}
	fragment, err := url.ParseQuery(u.EscapedFragment())
	if err != nil || len(fragment) != 1 || len(fragment["token"]) != 1 || !validT3Credential(fragment.Get("token")) {
		return t3Connection{}, errors.New("the T3 Code pairing link needs one pairing token")
	}
	origin := (&url.URL{Scheme: u.Scheme, Host: u.Host}).String()
	descriptor, err := describeT3(ctx, origin)
	if err != nil {
		return t3Connection{}, err
	}

	form := url.Values{
		"grant_type":           {"urn:ietf:params:oauth:grant-type:token-exchange"},
		"subject_token_type":   {"urn:t3:params:oauth:token-type:environment-bootstrap"},
		"requested_token_type": {t3AccessType},
		"subject_token":        {fragment.Get("token")},
		"scope":                {t3ReadScope},
		"client_label":         {"Huawei Push Companion"},
		"client_device_type":   {"desktop"},
		"client_os":            {runtime.GOOS},
	}
	var result struct {
		AccessToken string `json:"access_token"`
		TokenType   string `json:"token_type"`
		Scope       string `json:"scope"`
	}
	if err := t3JSON(ctx, http.MethodPost, origin+"/oauth/token", "", form, &result); err != nil {
		return t3Connection{}, fmt.Errorf("T3 pairing exchange failed: %w", err)
	}
	if result.TokenType != "Bearer" || result.Scope != t3ReadScope || !validT3Credential(result.AccessToken) {
		return t3Connection{}, errors.New("T3 did not grant a read-only bearer session")
	}
	return t3Connection{BaseURL: origin, EnvironmentID: descriptor.EnvironmentID, AccessToken: result.AccessToken}, nil
}

func describeT3(ctx context.Context, origin string) (t3Descriptor, error) {
	var descriptor t3Descriptor
	if err := t3JSON(ctx, http.MethodGet, origin+"/.well-known/t3/environment", "", nil, &descriptor); err != nil {
		return t3Descriptor{}, fmt.Errorf("T3 environment discovery failed: %w", err)
	}
	if descriptor.Protocol != 2 || descriptor.EnvironmentID == "" {
		return t3Descriptor{}, fmt.Errorf("%w: this T3 server does not advertise orchestration protocol 2", errT3Pairing)
	}
	return descriptor, nil
}

func t3JSON(ctx context.Context, method, endpoint, bearer string, form url.Values, result any) error {
	var body io.Reader
	if form != nil {
		body = strings.NewReader(form.Encode())
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, body)
	if err != nil {
		return errors.New("invalid T3 API request")
	}
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	if form != nil {
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	req.Header.Set("Accept", "application/json")
	res, err := t3HTTP.Do(req)
	if err != nil {
		return errors.New("could not reach the local T3 server")
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		if bearer != "" && (res.StatusCode == http.StatusUnauthorized || res.StatusCode == http.StatusForbidden) {
			return fmt.Errorf("%w: T3 rejected the session (HTTP %d)", errT3Pairing, res.StatusCode)
		}
		return fmt.Errorf("unexpected T3 response (HTTP %d)", res.StatusCode)
	}
	const maxResponse = 64 << 10
	data, err := io.ReadAll(io.LimitReader(res.Body, maxResponse+1))
	if err != nil || len(data) > maxResponse || json.Unmarshal(data, result) != nil {
		return errors.New("invalid JSON response from T3")
	}
	return nil
}

func watchT3(ctx context.Context, connection t3Connection, handle func(context.Context, pushEvent) error) error {
	origin, err := url.Parse(connection.BaseURL)
	if err != nil || !t3LocalOrigin(origin) || origin.Path != "" || origin.Fragment != "" ||
		connection.EnvironmentID == "" || !validT3Credential(connection.AccessToken) {
		return fmt.Errorf("%w: invalid local T3 connection", errT3Pairing)
	}
	state := shellState{environmentID: connection.EnvironmentID, startedAt: time.Now().Truncate(time.Millisecond)}
	for delay := time.Second; ; delay = min(2*delay, 30*time.Second) {
		attemptStartedAt := time.Now()
		err := streamT3(ctx, origin, connection, &state, handle)
		if errors.Is(err, errT3Pairing) {
			return err
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if time.Since(attemptStartedAt) >= time.Minute {
			delay = time.Second
		}
		if err := waitT3(ctx, delay); err != nil {
			return err
		}
	}
}

func streamT3(ctx context.Context, origin *url.URL, connection t3Connection, state *shellState, handle func(context.Context, pushEvent) error) error {
	descriptor, err := describeT3(ctx, connection.BaseURL)
	if err != nil {
		return err
	}
	if descriptor.EnvironmentID != connection.EnvironmentID {
		return fmt.Errorf("%w: another T3 environment is using the paired address", errT3Pairing)
	}
	var session struct {
		Authenticated bool     `json:"authenticated"`
		Scopes        []string `json:"scopes"`
	}
	if err := t3JSON(ctx, http.MethodGet, connection.BaseURL+"/api/auth/session", connection.AccessToken, nil, &session); err != nil {
		return err
	}
	if !session.Authenticated || len(session.Scopes) != 1 || session.Scopes[0] != t3ReadScope {
		return fmt.Errorf("%w: the T3 session is expired, revoked, or lacks the read-only scope", errT3Pairing)
	}
	var ticket struct {
		Ticket string `json:"ticket"`
	}
	if err := t3JSON(ctx, http.MethodPost, connection.BaseURL+"/api/auth/websocket-ticket/rpc", connection.AccessToken, nil, &ticket); err != nil {
		return err
	}
	if !validT3Credential(ticket.Ticket) {
		return errors.New("T3 did not issue a WebSocket ticket")
	}
	wsURL := *origin
	wsURL.Scheme = "ws" + strings.TrimPrefix(origin.Scheme, "http")
	wsURL.Path = "/ws"
	wsURL.RawQuery = url.Values{"wsTicket": {ticket.Ticket}, "orchestrationProtocol": {"2"}}.Encode()
	config, err := websocket.NewConfig(wsURL.String(), connection.BaseURL)
	if err != nil {
		return errors.New("invalid T3 WebSocket endpoint")
	}
	config.Dialer = t3Dialer
	dialCtx, cancelDial := context.WithTimeout(ctx, t3IOTimeout)
	ws, err := config.DialContext(dialCtx)
	cancelDial()
	if err != nil {
		return errors.New("could not open the T3 WebSocket")
	}
	streamCtx, stopStream := context.WithCancel(ctx)
	stopOnCancel := context.AfterFunc(streamCtx, func() { _ = ws.SetDeadline(time.Now()) })
	defer func() {
		stopOnCancel()
		stopStream()
		_ = ws.SetDeadline(time.Now())
		_ = ws.Close()
	}()

	payload := make(map[string]int64)
	if state.cursor != nil {
		payload["afterSequence"] = *state.cursor
	}
	if err := sendT3(ws, map[string]any{"_tag": "Request", "id": t3RequestID, "tag": "orchestration.subscribeShell", "headers": [][]string{}, "payload": payload}); err != nil {
		return err
	}
	go pingT3(streamCtx, ws)
	for {
		var frame struct {
			Tag       string      `json:"_tag"`
			RequestID string      `json:"requestId"`
			Values    []shellItem `json:"values"`
		}
		_ = ws.SetReadDeadline(time.Now().Add(3 * t3PingInterval))
		if err := streamCtx.Err(); err != nil {
			return err
		}
		if err := websocket.JSON.Receive(ws, &frame); err != nil {
			return errors.New("T3 WebSocket stream ended")
		}
		switch frame.Tag {
		case "Defect":
			return errors.New("T3 shell subscription failed")
		case "Exit":
			if frame.RequestID == t3RequestID {
				return errors.New("T3 shell subscription ended")
			}
		case "Chunk":
			if frame.RequestID != t3RequestID {
				continue
			}
			for _, item := range frame.Values {
				if err := state.observe(item, time.Now(), func(event pushEvent) error {
					return retryT3Delivery(ctx, event, handle)
				}); err != nil {
					return err
				}
			}
			if err := sendT3(ws, map[string]string{"_tag": "Ack", "requestId": t3RequestID}); err != nil {
				return err
			}
		}
	}
}

func sendT3(ws *websocket.Conn, message any) error {
	_ = ws.SetWriteDeadline(time.Now().Add(t3IOTimeout))
	if err := websocket.JSON.Send(ws, message); err != nil {
		return errors.New("could not write to the T3 WebSocket")
	}
	return nil
}

func pingT3(ctx context.Context, ws *websocket.Conn) {
	ticker := time.NewTicker(t3PingInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if sendT3(ws, map[string]string{"_tag": "Ping"}) != nil {
				return
			}
		}
	}
}

func retryT3Delivery(ctx context.Context, event pushEvent, handle func(context.Context, pushEvent) error) error {
	deliveryCtx, cancel := context.WithDeadline(ctx, event.OccurredAt.Add(pushEventMaxAge))
	defer cancel()
	for delay := time.Second; deliveryCtx.Err() == nil; delay = min(2*delay, 15*time.Second) {
		if err := handle(deliveryCtx, event); err == nil {
			return nil
		}
		_ = waitT3(deliveryCtx, delay)
	}
	// An expired notification frees the cursor to process later updates.
	return ctx.Err()
}

func waitT3(ctx context.Context, delay time.Duration) error {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}
