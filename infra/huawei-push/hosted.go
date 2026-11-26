package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"
)

const (
	hostedMaxFlows    = 256
	hostedMaxSessions = 256
)

type hostedPushServer struct {
	path       string
	desktopKit *huaweiAccountClient
	mobileKit  *huaweiAccountClient
	send       func(context.Context, notification, time.Time) (string, error)
	now        func() time.Time
	mux        *http.ServeMux
	wake       chan struct{}
	loginSlots chan struct{}

	mu        sync.Mutex
	state     hostedState
	dirty     bool
	polling   map[string]bool
	rateStart time.Time
	rates     map[string]int
}

func newHostedPushServer(
	path string,
	desktopKit, mobileKit *huaweiAccountClient,
	send func(context.Context, notification, time.Time) (string, error),
	now func() time.Time,
) (*hostedPushServer, error) {
	if path == "" {
		return nil, errors.New("HUAWEI_PUSH_STATE_FILE is required")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, err
	}
	state, err := loadHostedState(path)
	if err != nil {
		return nil, err
	}
	server := &hostedPushServer{
		path: path, desktopKit: desktopKit, mobileKit: mobileKit, send: send, now: now,
		mux: http.NewServeMux(), wake: make(chan struct{}, 1), loginSlots: make(chan struct{}, 16),
		state: state.snapshot(now()), polling: make(map[string]bool),
	}
	server.mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeHostedJSON(w, struct {
			Status string `json:"status"`
		}{"ok"})
	})
	server.mux.HandleFunc("POST /v1/desktop/login", server.startDesktopLogin)
	server.mux.HandleFunc("POST /v1/desktop/login/poll", server.pollDesktopLogin)
	server.mux.HandleFunc("POST /v1/mobile/login", server.loginMobile)
	server.mux.HandleFunc("PUT /v1/mobile/registration", server.registerMobile)
	server.mux.HandleFunc("POST /v1/desktop/events", server.postEvent)
	server.mux.HandleFunc("GET /v1/session", server.getSession)
	server.mux.HandleFunc("DELETE /v1/session", server.revokeSession)
	return server, nil
}

func (server *hostedPushServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	server.mux.ServeHTTP(w, r)
}

func readHostedJSON(w http.ResponseWriter, r *http.Request, value any) bool {
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 24<<10))
	if err != nil {
		var size *http.MaxBytesError
		if errors.As(err, &size) {
			http.Error(w, "Request too large", http.StatusRequestEntityTooLarge)
			return false
		}
	}
	data = bytes.TrimSpace(data)
	if err != nil || len(data) == 0 || data[0] != '{' || decodeSingleJSON(bytes.NewReader(data), value) != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return false
	}
	return true
}

func writeHostedJSON(w http.ResponseWriter, value any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(value)
}

func respondHostedRateLimit(w http.ResponseWriter) {
	w.Header().Set("Retry-After", "60")
	http.Error(w, "Rate limited", http.StatusTooManyRequests)
}

func (server *hostedPushServer) allowLocked(family, key string, limit, total int, now time.Time) bool {
	window := now.Truncate(time.Minute)
	if !server.rateStart.Equal(window) {
		server.rateStart = window
		server.rates = make(map[string]int)
	}
	bucket := family + ":" + key
	if server.rates[family] >= total || server.rates[bucket] >= limit {
		return false
	}
	server.rates[family]++
	server.rates[bucket]++
	return true
}

func (server *hostedPushServer) beginLogin(w http.ResponseWriter, r *http.Request, family string, limit, total int) bool {
	address, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		address = r.RemoteAddr
	}
	server.mu.Lock()
	allowed := server.allowLocked(family, address, limit, total, server.now())
	server.mu.Unlock()
	if allowed {
		select {
		case server.loginSlots <- struct{}{}:
			return true
		default:
		}
	}
	respondHostedRateLimit(w)
	return false
}

func (server *hostedPushServer) commitLocked(next hostedState) error {
	if err := writeHostedState(server.path, next); err != nil {
		return err
	}
	server.state = next
	server.dirty = false
	return nil
}

func (server *hostedPushServer) commitRequestLocked(w http.ResponseWriter, next hostedState) bool {
	if err := server.commitLocked(next); err != nil {
		log.Printf("Huawei push state write failed: %v", err)
		http.Error(w, "Push service unavailable", http.StatusServiceUnavailable)
		return false
	}
	return true
}

type hostedSessionResponse struct {
	AccessToken string    `json:"accessToken,omitempty"`
	ExpiresAt   time.Time `json:"expiresAt"`
}

type hostedPollResponse struct {
	Status      string     `json:"status"`
	AccessToken string     `json:"accessToken,omitempty"`
	ExpiresAt   *time.Time `json:"expiresAt,omitempty"`
}

func (server *hostedPushServer) startDesktopLogin(w http.ResponseWriter, r *http.Request) {
	if !readHostedJSON(w, r, new(struct{})) || !server.beginLogin(w, r, "desktop-start", 12, 60) {
		return
	}
	defer func() { <-server.loginSlots }()
	device, err := server.desktopKit.startDeviceLogin(r.Context())
	if err != nil {
		http.Error(w, "Account service unavailable", http.StatusServiceUnavailable)
		return
	}

	now := server.now().UTC()
	expiresAt := minTime(now.Add(min(device.ExpiresIn, 30*time.Minute)), device.CreatedAt.Add(device.ExpiresIn))
	seconds := int(expiresAt.Sub(now) / time.Second)
	if seconds < int(device.Interval/time.Second) {
		http.Error(w, "Account service unavailable", http.StatusServiceUnavailable)
		return
	}
	token := hostedToken()
	server.mu.Lock()
	defer server.mu.Unlock()
	next := server.state.snapshot(now)
	if len(next.Flows) >= hostedMaxFlows {
		respondHostedRateLimit(w)
		return
	}
	next.Flows[hostedHash(token)] = hostedFlow{
		DeviceCode: device.DeviceCode, ExpiresAt: expiresAt, NextPollAt: now.Add(device.Interval), Interval: device.Interval,
	}
	if server.commitRequestLocked(w, next) {
		writeHostedJSON(w, struct {
			FlowToken       string `json:"flowToken"`
			VerificationURL string `json:"verificationUrl"`
			UserCode        string `json:"userCode"`
			IntervalSeconds int    `json:"intervalSeconds"`
			ExpiresIn       int    `json:"expiresIn"`
		}{token, device.VerificationURL, device.UserCode, int(device.Interval / time.Second), seconds})
	}
}

func minTime(left, right time.Time) time.Time {
	if left.Before(right) {
		return left
	}
	return right
}

func (server *hostedPushServer) pollDesktopLogin(w http.ResponseWriter, r *http.Request) {
	var input struct {
		FlowToken string `json:"flowToken"`
	}
	if !readHostedJSON(w, r, &input) {
		return
	}
	if !validHostedToken(input.FlowToken) {
		http.Error(w, "Invalid login flow", http.StatusBadRequest)
		return
	}
	if !server.beginLogin(w, r, "desktop-poll", 180, 600) {
		return
	}
	defer func() { <-server.loginSlots }()

	key := hostedHash(input.FlowToken)
	now := server.now().UTC()
	server.mu.Lock()
	flow, found := server.state.Flows[key]
	if !found || !flow.ExpiresAt.After(now) {
		server.mu.Unlock()
		writeHostedJSON(w, hostedPollResponse{Status: "expired"})
		return
	}
	if now.Before(flow.NextPollAt) || server.polling[key] {
		server.mu.Unlock()
		writeHostedJSON(w, hostedPollResponse{Status: "slow_down"})
		return
	}
	flow.NextPollAt = now.Add(flow.Interval)
	server.state.Flows[key] = flow
	server.polling[key] = true
	server.mu.Unlock()

	tokens, err := server.desktopKit.exchangeDeviceCode(r.Context(), flow.DeviceCode)
	var account huaweiAccountIdentity
	if err == nil {
		account, err = hostedIntrospect(r.Context(), server.desktopKit, tokens.AccessToken)
	}

	now = server.now().UTC()
	server.mu.Lock()
	defer server.mu.Unlock()
	delete(server.polling, key)
	if !flow.ExpiresAt.After(now) {
		writeHostedJSON(w, hostedPollResponse{Status: "expired"})
		return
	}
	if err != nil {
		switch hostedAccountErrorKind(err) {
		case huaweiAccountPending:
			writeHostedJSON(w, hostedPollResponse{Status: "pending"})
		case huaweiAccountSlowDown:
			flow.Interval += 5 * time.Second
			flow.NextPollAt = now.Add(flow.Interval)
			server.state.Flows[key] = flow
			writeHostedJSON(w, hostedPollResponse{Status: "slow_down"})
		case huaweiAccountExpired, huaweiAccountDenied, huaweiAccountInvalid:
			next := server.state.snapshot(now)
			delete(next.Flows, key)
			if server.commitRequestLocked(w, next) {
				writeHostedJSON(w, hostedPollResponse{Status: "expired"})
			}
		default:
			http.Error(w, "Account service unavailable", http.StatusServiceUnavailable)
		}
		return
	}
	next := server.state.snapshot(now)
	delete(next.Flows, key)
	response, status := insertHostedSession(next, "desktop", hostedHash(account.UnionID), "", now)
	if status != http.StatusOK {
		respondHostedRateLimit(w)
		return
	}
	if server.commitRequestLocked(w, next) {
		writeHostedJSON(w, hostedPollResponse{Status: "signed_in", AccessToken: response.AccessToken, ExpiresAt: &response.ExpiresAt})
	}
}

func hostedIntrospect(ctx context.Context, kit *huaweiAccountClient, accessToken string) (huaweiAccountIdentity, error) {
	identity, err := kit.introspect(ctx, accessToken)
	if err != nil && hostedAccountErrorKind(err) == huaweiAccountUnavailable && ctx.Err() == nil {
		return kit.introspect(ctx, accessToken)
	}
	return identity, err
}

func hostedAccountErrorKind(err error) huaweiAccountErrorKind {
	var failure *huaweiAccountError
	if errors.As(err, &failure) {
		return failure.Kind
	}
	return huaweiAccountUnavailable
}

func insertHostedSession(next hostedState, role, account, pushToken string, now time.Time) (hostedSessionResponse, int) {
	var existingCount int
	for key, session := range next.Sessions {
		if pushToken != "" && session.PushToken == pushToken {
			if session.Account != account {
				return hostedSessionResponse{}, http.StatusConflict
			}
			delete(next.Sessions, key)
			continue
		}
		if session.Role == role && session.Account == account {
			existingCount++
		}
	}
	limit := 16
	if role == "mobile" {
		limit = 8
	}
	if len(next.Sessions) >= hostedMaxSessions || existingCount >= limit {
		return hostedSessionResponse{}, http.StatusTooManyRequests
	}
	token := hostedToken()
	expiresAt := now.Add(hostedSessionTTL).Truncate(time.Second)
	next.Sessions[hostedHash(token)] = hostedSession{
		Account: account, Role: role, PushToken: pushToken, ExpiresAt: expiresAt,
	}
	return hostedSessionResponse{AccessToken: token, ExpiresAt: expiresAt}, http.StatusOK
}

func (server *hostedPushServer) loginMobile(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Code      string `json:"code"`
		PushToken string `json:"pushToken"`
	}
	if !readHostedJSON(w, r, &input) {
		return
	}
	if !validHuaweiCredential(input.Code, huaweiAccountMaxCredential) || !validHuaweiCredential(input.PushToken, 4096) {
		http.Error(w, "Invalid account code or push token", http.StatusBadRequest)
		return
	}
	if !server.beginLogin(w, r, "mobile-login", 20, 100) {
		return
	}
	defer func() { <-server.loginSlots }()

	tokens, err := server.mobileKit.exchangeAuthorizationCode(r.Context(), input.Code)
	var account huaweiAccountIdentity
	if err == nil {
		account, err = hostedIntrospect(r.Context(), server.mobileKit, tokens.AccessToken)
	}
	if err != nil {
		switch hostedAccountErrorKind(err) {
		case huaweiAccountInvalid, huaweiAccountDenied, huaweiAccountExpired:
			http.Error(w, "Invalid or expired account authorization", http.StatusUnauthorized)
		default:
			http.Error(w, "Account service unavailable", http.StatusServiceUnavailable)
		}
		return
	}
	now := server.now().UTC()
	server.mu.Lock()
	defer server.mu.Unlock()
	next := server.state.snapshot(now)
	response, status := insertHostedSession(next, "mobile", hostedHash(account.UnionID), input.PushToken, now)
	switch status {
	case http.StatusConflict:
		http.Error(w, "Cannot register this device", status)
	case http.StatusTooManyRequests:
		respondHostedRateLimit(w)
	default:
		if server.commitRequestLocked(w, next) {
			writeHostedJSON(w, response)
		}
	}
}

func (server *hostedPushServer) sessionLocked(w http.ResponseWriter, r *http.Request, role string, now time.Time) (string, hostedSession, bool) {
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if ok && validHostedToken(token) {
		key := hostedHash(token)
		session, found := server.state.Sessions[key]
		if found && session.ExpiresAt.After(now) && (role == "" || session.Role == role) {
			return key, session, true
		}
	}
	w.Header().Set("WWW-Authenticate", "Bearer")
	http.Error(w, "Unauthorized", http.StatusUnauthorized)
	return "", hostedSession{}, false
}

func (server *hostedPushServer) readSessionJSON(w http.ResponseWriter, r *http.Request, role string, value any) bool {
	server.mu.Lock()
	_, _, ok := server.sessionLocked(w, r, role, server.now())
	server.mu.Unlock()
	return ok && readHostedJSON(w, r, value)
}

func (server *hostedPushServer) getSession(w http.ResponseWriter, r *http.Request) {
	server.mu.Lock()
	defer server.mu.Unlock()
	_, session, ok := server.sessionLocked(w, r, "", server.now())
	if ok {
		writeHostedJSON(w, hostedSessionResponse{ExpiresAt: session.ExpiresAt})
	}
}

func (server *hostedPushServer) revokeSession(w http.ResponseWriter, r *http.Request) {
	server.mu.Lock()
	defer server.mu.Unlock()
	now := server.now()
	key, _, ok := server.sessionLocked(w, r, "", now)
	if !ok {
		return
	}
	next := server.state.snapshot(now)
	delete(next.Sessions, key)
	if server.commitRequestLocked(w, next) {
		w.WriteHeader(http.StatusNoContent)
	}
}

func (server *hostedPushServer) registerMobile(w http.ResponseWriter, r *http.Request) {
	var input struct {
		PushToken      string   `json:"pushToken"`
		EnvironmentIDs []string `json:"environmentIds"`
		Phases         []string `json:"phases"`
	}
	if !server.readSessionJSON(w, r, "mobile", &input) {
		return
	}
	server.mu.Lock()
	defer server.mu.Unlock()
	now := server.now()
	key, session, ok := server.sessionLocked(w, r, "mobile", now)
	if !ok {
		return
	}
	disable := len(input.EnvironmentIDs) == 0 || len(input.Phases) == 0
	if input.EnvironmentIDs == nil || len(input.EnvironmentIDs) > 32 || input.Phases == nil || len(input.Phases) > 4 ||
		((!disable || input.PushToken != "") && !validHuaweiCredential(input.PushToken, 4096)) {
		http.Error(w, "Invalid push registration", http.StatusBadRequest)
		return
	}
	for _, environment := range input.EnvironmentIDs {
		if !validPushIdentifier(environment, 255) {
			http.Error(w, "Invalid environment", http.StatusBadRequest)
			return
		}
	}
	for _, phase := range input.Phases {
		if _, ok := hostedPhaseBodies[phase]; !ok {
			http.Error(w, "Invalid notification phase", http.StatusBadRequest)
			return
		}
	}
	if !server.allowLocked("registration", key, 30, 240, now) {
		respondHostedRateLimit(w)
		return
	}
	if disable {
		if session.RegistrationID == "" {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		session.RegistrationID = ""
		session.EnvironmentIDs = nil
		session.Phases = nil
	} else {
		slices.Sort(input.EnvironmentIDs)
		slices.Sort(input.Phases)
		input.EnvironmentIDs = slices.Compact(input.EnvironmentIDs)
		input.Phases = slices.Compact(input.Phases)
		if session.RegistrationID != "" && session.PushToken == input.PushToken &&
			slices.Equal(session.EnvironmentIDs, input.EnvironmentIDs) && slices.Equal(session.Phases, input.Phases) {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		for id, other := range server.state.Sessions {
			if id != key && other.ExpiresAt.After(now) && other.PushToken == input.PushToken {
				http.Error(w, "Cannot register this device", http.StatusConflict)
				return
			}
		}
		session.PushToken = input.PushToken
		session.RegistrationID = hostedToken()
		session.EnvironmentIDs = input.EnvironmentIDs
		session.Phases = input.Phases
	}
	next := server.state.snapshot(now)
	next.Sessions[key] = session
	if server.commitRequestLocked(w, next) {
		w.WriteHeader(http.StatusNoContent)
	}
}
