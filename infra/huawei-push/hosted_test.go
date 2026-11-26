package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func fakeHostedAccountKit(t *testing.T, now time.Time) (*huaweiAccountClient, *huaweiAccountClient) {
	t.Helper()
	var desktopPolls atomic.Int32
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Error(err)
			http.Error(w, "invalid form", 400)
			return
		}
		switch r.URL.Path {
		case "/oauth2/v3/device/code":
			if r.Form.Get("client_id") != "desktop-app" || r.Form.Get("scope") != "openid" {
				t.Errorf("unexpected start request: %v", r.Form)
			}
			fmt.Fprintf(w, `{"device_code":"desktop-code","user_code":"A-123","verification_url":"https://oauth-login1.cloud.huawei.com/oauth2/v3/device","create_time":%d,"expire_in":300,"scan_expire_in":120,"interval":5}`, now.Unix())
		case "/oauth2/v3/token":
			client := r.Form.Get("client_id")
			code := r.Form.Get("code")
			account := ""
			switch {
			case client == "desktop-app" && r.Form.Get("grant_type") == "device_code" && code == "desktop-code":
				if desktopPolls.Add(1) == 1 {
					http.Error(w, `{"error":1101,"sub_error":20412}`, 400)
					return
				}
				account = "alice"
			case client == "mobile-app" && r.Form.Get("grant_type") == "authorization_code":
				account = code
			default:
				t.Errorf("unexpected exchange: %v", r.Form)
			}
			if account == "" || r.Form.Get("client_secret") != client+"-secret" {
				http.Error(w, `{"error":1101,"sub_error":20155}`, 400)
				return
			}
			fmt.Fprintf(w, `{"access_token":%q,"refresh_token":"unused-refresh-token","token_type":"Bearer","expires_in":3600}`, client+"/"+account)
		case "/token-info":
			client, account, _ := strings.Cut(r.Form.Get("access_token"), "/")
			if account == "wrong-audience" {
				client = "another-app"
			}
			fmt.Fprintf(w, `{"client_id":%q,"union_id":%q,"type":0,"scope":"openid","expire_in":3600}`, client, account)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(server.Close)
	client := func(id string) *huaweiAccountClient {
		account := newHuaweiAccountClient(id, id+"-secret")
		account.httpClient = server.Client()
		account.oauthBaseURL = server.URL
		account.tokenInfoURL = server.URL + "/token-info"
		return account
	}
	return client("desktop-app"), client("mobile-app")
}

func hostedRequest(handler http.Handler, method, path, token string, body any) *httptest.ResponseRecorder {
	var buffer bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buffer).Encode(body)
	}
	req := httptest.NewRequest(method, path, &buffer)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)
	return w
}

func requireHostedStatus(t *testing.T, response *httptest.ResponseRecorder, expected int) {
	t.Helper()
	if response.Code != expected {
		t.Fatalf("HTTP status = %d, want %d, body = %s", response.Code, expected, response.Body.String())
	}
}

func getHostedBody(t *testing.T, response *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	requireHostedStatus(t, response, 200)
	var body map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	return body
}

func TestHostedPushAccountIsolationAndRevocation(t *testing.T) {
	now := time.Date(2026, 11, 24, 0, 0, 0, 0, time.UTC)
	desktopKit, mobileKit := fakeHostedAccountKit(t, now)
	var deliveries []notification
	send := func(_ context.Context, value notification, _ time.Time) (string, error) {
		deliveries = append(deliveries, value)
		return "sent", nil
	}
	path := filepath.Join(t.TempDir(), "push.json")
	open := func() *hostedPushServer {
		server, err := newHostedPushServer(path, desktopKit, mobileKit, send, func() time.Time { return now })
		if err != nil {
			t.Fatal(err)
		}
		return server
	}
	server := open()

	start := getHostedBody(t, hostedRequest(server, "POST", "/v1/desktop/login", "", struct{}{}))
	if start["userCode"] != "A-123" || start["intervalSeconds"] != float64(5) ||
		start["expiresIn"] != float64(300) || start["verificationUrl"] != "https://oauth-login1.cloud.huawei.com/oauth2/v3/device" {
		t.Fatalf("unexpected login start: %#v", start)
	}
	pollInput := map[string]any{"flowToken": start["flowToken"]}
	if got := getHostedBody(t, hostedRequest(server, "POST", "/v1/desktop/login/poll", "", pollInput)); got["status"] != "slow_down" {
		t.Fatalf("early poll: %v", got)
	}
	now = now.Add(5 * time.Second)
	if got := getHostedBody(t, hostedRequest(server, "POST", "/v1/desktop/login/poll", "", pollInput)); got["status"] != "pending" {
		t.Fatalf("Huawei pending poll: %v", got)
	}
	now = now.Add(5 * time.Second)
	poll := getHostedBody(t, hostedRequest(server, "POST", "/v1/desktop/login/poll", "", pollInput))
	if poll["status"] != "signed_in" {
		t.Fatalf("desktop login failed: %#v", poll)
	}
	desktop := poll["accessToken"].(string)
	if got := getHostedBody(t, hostedRequest(server, "POST", "/v1/desktop/login/poll", "", pollInput)); got["status"] != "expired" {
		t.Fatalf("reused flow: %v", got)
	}
	mobileLogin := func(code, token string) *httptest.ResponseRecorder {
		return hostedRequest(server, "POST", "/v1/mobile/login", "", map[string]string{"code": code, "pushToken": token})
	}
	mobileAlice := getHostedBody(t, mobileLogin("alice", "alice-device"))["accessToken"].(string)
	mobileAliceOther := getHostedBody(t, mobileLogin("alice", "alice-other-environment"))["accessToken"].(string)
	mobileAlicePhase := getHostedBody(t, mobileLogin("alice", "alice-other-phase"))["accessToken"].(string)
	mobileBob := getHostedBody(t, mobileLogin("bob", "bob-device"))["accessToken"].(string)
	requireHostedStatus(t, mobileLogin("wrong-audience", "unverified-device"), 401)
	requireHostedStatus(t, mobileLogin("bob", "alice-device"), 409)
	register := func(session, token, environment, phase string) *httptest.ResponseRecorder {
		return hostedRequest(server, "PUT", "/v1/mobile/registration", session, map[string]any{
			"pushToken": token, "environmentIds": []string{environment}, "phases": []string{phase},
		})
	}
	requireHostedStatus(t, register(desktop, "desktop-device", "env-1", "completed"), 401)
	requireHostedStatus(t, register(mobileAlice, "alice-device", "env-1", "completed"), 204)
	requireHostedStatus(t, register(mobileAliceOther, "alice-other-environment", "env-2", "completed"), 204)
	requireHostedStatus(t, register(mobileAlicePhase, "alice-other-phase", "env-1", "failed"), 204)
	requireHostedStatus(t, register(mobileBob, "bob-device", "env-1", "completed"), 204)

	event := map[string]string{
		"eventId": "event-1", "environmentId": "env-1", "threadId": "thread-1", "phase": "completed", "occurredAt": now.Format(time.RFC3339),
	}
	requireHostedStatus(t, hostedRequest(server, "POST", "/v1/desktop/events", mobileAlice, event), 401)
	requireHostedStatus(t, hostedRequest(server, "POST", "/v1/desktop/events", mobileAlice, nil), 401)
	event["pushToken"] = "bob-device"
	requireHostedStatus(t, hostedRequest(server, "POST", "/v1/desktop/events", desktop, event), 400)
	delete(event, "pushToken")
	for _, offset := range []time.Duration{-2*time.Minute - time.Second, 31 * time.Second} {
		event["occurredAt"] = now.Add(offset).Format(time.RFC3339)
		requireHostedStatus(t, hostedRequest(server, "POST", "/v1/desktop/events", desktop, event), 400)
	}
	event["occurredAt"] = now.Format(time.RFC3339)
	var requests sync.WaitGroup
	for range 6 {
		requests.Add(1)
		go func() {
			defer requests.Done()
			response := hostedRequest(server, "POST", "/v1/desktop/events", desktop, event)
			if response.Code != 204 || response.Body.Len() != 0 {
				t.Errorf("event returned %d with body %s", response.Code, response.Body.String())
			}
		}()
	}
	requests.Wait()

	server = open()
	if !server.deliverOne(context.Background()) || server.deliverOne(context.Background()) ||
		len(deliveries) != 1 || deliveries[0].Token != "alice-device" ||
		deliveries[0].EnvironmentID != "env-1" || deliveries[0].ThreadID != "thread-1" {
		t.Fatalf("unexpected deliveries: %+v", deliveries)
	}
	requireHostedStatus(t, hostedRequest(server, "POST", "/v1/desktop/events", desktop, event), 204)
	event["eventId"] = "event-2"
	requireHostedStatus(t, hostedRequest(server, "POST", "/v1/desktop/events", desktop, event), 204)
	requireHostedStatus(t, hostedRequest(server, "DELETE", "/v1/session", mobileAlice, nil), 204)
	requireHostedStatus(t, hostedRequest(server, "GET", "/v1/session", mobileAlice, nil), 401)
	for server.deliverOne(context.Background()) {
	}
	if len(deliveries) != 1 {
		t.Fatalf("delivery after mobile revocation: %+v", deliveries)
	}
	session := getHostedBody(t, hostedRequest(server, "GET", "/v1/session", desktop, nil))
	expiresAt, err := time.Parse(time.RFC3339, session["expiresAt"].(string))
	if err != nil || expiresAt.Sub(now) != 30*24*time.Hour {
		t.Fatalf("unexpected session expiry %v (%v)", expiresAt, err)
	}
	now = expiresAt
	requireHostedStatus(t, hostedRequest(server, "POST", "/v1/desktop/events", desktop, event), 401)
	requireHostedStatus(t, hostedRequest(server, "GET", "/v1/session", mobileBob, nil), 401)

	persisted, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(persisted, []byte(desktop)) || bytes.Contains(persisted, []byte(mobileBob)) ||
		bytes.Contains(persisted, []byte("unused-refresh-token")) {
		t.Fatal("account credentials or session bearers stored in plaintext")
	}
	info, err := os.Stat(path)
	if err != nil || (runtime.GOOS != "windows" && info.Mode().Perm() != 0600) {
		t.Fatalf("unexpected state permissions: %v %v", info, err)
	}
}

func TestHostedPushRetriesOnlyPendingRecipients(t *testing.T) {
	now := time.Date(2026, 11, 24, 0, 0, 0, 0, time.UTC)
	desktopKit, mobileKit := fakeHostedAccountKit(t, now)
	var ids []string
	var attempts = map[string]int{}
	send := func(_ context.Context, value notification, _ time.Time) (string, error) {
		attempts[value.Token]++
		ids = append(ids, value.ID)
		if value.Token == "retry-device" && attempts[value.Token] == 1 {
			return "", errors.New("Huawei unavailable")
		}
		return "sent", nil
	}
	path := filepath.Join(t.TempDir(), "push.json")
	open := func() *hostedPushServer {
		server, err := newHostedPushServer(path, desktopKit, mobileKit, send, func() time.Time { return now })
		if err != nil {
			t.Fatal(err)
		}
		return server
	}
	server := open()
	start := getHostedBody(t, hostedRequest(server, "POST", "/v1/desktop/login", "", struct{}{}))
	pollInput := map[string]any{"flowToken": start["flowToken"]}
	now = now.Add(5 * time.Second)
	if got := getHostedBody(t, hostedRequest(server, "POST", "/v1/desktop/login/poll", "", pollInput)); got["status"] != "pending" {
		t.Fatalf("Huawei pending poll: %v", got)
	}
	now = now.Add(5 * time.Second)
	desktop := getHostedBody(t, hostedRequest(server, "POST", "/v1/desktop/login/poll", "", pollInput))["accessToken"].(string)
	for _, token := range []string{"sent-device", "retry-device", "disabled-device"} {
		mobile := getHostedBody(t, hostedRequest(server, "POST", "/v1/mobile/login", "", map[string]string{
			"code": "alice", "pushToken": token,
		}))["accessToken"].(string)
		requireHostedStatus(t, hostedRequest(server, "PUT", "/v1/mobile/registration", mobile, map[string]any{
			"pushToken": token, "environmentIds": []string{"env-1"}, "phases": []string{"completed"},
		}), 204)
		if token == "disabled-device" {
			requireHostedStatus(t, hostedRequest(server, "PUT", "/v1/mobile/registration", mobile, map[string]any{
				"environmentIds": []string{}, "phases": []string{},
			}), 204)
		}
	}
	event := map[string]string{
		"eventId": "retry-1", "environmentId": "env-1", "threadId": "thread-1", "phase": "completed", "occurredAt": now.Format(time.RFC3339),
	}
	requireHostedStatus(t, hostedRequest(server, "POST", "/v1/desktop/events", desktop, event), 204)
	for server.deliverOne(context.Background()) {
	}
	if attempts["sent-device"] != 1 || attempts["retry-device"] != 1 || attempts["disabled-device"] != 0 {
		t.Fatalf("initial delivery attempts: %v", attempts)
	}

	server = open()
	now = now.Add(30 * time.Second)
	for server.deliverOne(context.Background()) {
	}
	if attempts["sent-device"] != 1 || attempts["retry-device"] != 2 || attempts["disabled-device"] != 0 ||
		len(ids) != 3 || ids[0] != ids[1] || ids[1] != ids[2] {
		t.Fatalf("retry attempts = %v, provider message IDs = %v", attempts, ids)
	}

	now = now.Add(3 * time.Minute)
	requireHostedStatus(t, hostedRequest(server, "POST", "/v1/desktop/events", desktop, event), 204)
	requireHostedStatus(t, hostedRequest(server, "DELETE", "/v1/session", desktop, nil), 204)
	requireHostedStatus(t, hostedRequest(server, "POST", "/v1/desktop/events", desktop, event), 401)
	response := hostedRequest(server, "GET", "/healthz", "", nil)
	if body, _ := io.ReadAll(response.Body); response.Code != 200 || len(body) == 0 {
		t.Fatalf("unexpected health response: %d %s", response.Code, body)
	}
}
