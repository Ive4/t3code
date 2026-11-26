package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestSetupPairsAndSignsInBeforeInstallingStartup(t *testing.T) {
	expiry := time.Now().Add(time.Hour).UTC()
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/desktop/login":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"flowToken": "flow", "verificationUrl": "https://oauth-login1.cloud.huawei.com/oauth2/v3/device",
				"userCode": "A1B2", "intervalSeconds": 5, "expiresIn": 60,
			})
		case "/v1/desktop/login/poll":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"status": "signed_in", "accessToken": "huawei-token", "expiresAt": expiry,
			})
		case "/v1/session":
			if r.Method != http.MethodDelete || r.Header.Get("Authorization") != "Bearer huawei-token" {
				t.Error("logout did not revoke the signed-in desktop session")
			}
			w.WriteHeader(http.StatusNoContent)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(upstream.Close)
	path := filepath.Join(t.TempDir(), "config.json")
	installed := 0
	handler := newSetupHandler("127.0.0.1:7000", "/private", path, upstream.URL,
		func(context.Context) (t3Connection, error) {
			return t3Connection{BaseURL: "http://127.0.0.1:3773", EnvironmentID: "desktop-id", AccessToken: "t3-token"}, nil
		}, func() error { installed++; return nil })
	call := func(method, endpoint, origin, body string) *httptest.ResponseRecorder {
		t.Helper()
		r := httptest.NewRequest(method, "http://127.0.0.1:7000"+endpoint, strings.NewReader(body))
		r.Header.Set("Origin", origin)
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		return w
	}
	if result := call("POST", "/private/pair", "https://example.org", "{}"); result.Code != 403 {
		t.Fatalf("cross-origin mutation status %d", result.Code)
	}
	if result := call("GET", "/state", "", ""); result.Code != 404 {
		t.Fatalf("unprotected setup response status %d", result.Code)
	}
	const origin = "http://127.0.0.1:7000"
	if result := call("POST", "/private/pair", origin, "{}"); result.Code != 200 || installed != 0 {
		t.Fatalf("pair result %d, startup calls %d", result.Code, installed)
	}
	if result := call("POST", "/private/login", origin, "{}"); result.Code != 200 || !strings.Contains(result.Body.String(), "image/png") {
		t.Fatalf("login did not supply a QR code: %d", result.Code)
	}
	result := call("POST", "/private/login/poll", origin, `{"flowToken":"flow"}`)
	if result.Code != 200 || installed != 1 || strings.Contains(result.Body.String(), "huawei-token") {
		t.Fatalf("poll result %d, startup calls %d, unexpected bearer %v", result.Code, installed, strings.Contains(result.Body.String(), "huawei-token"))
	}
	config, err := readConfig(path)
	if err != nil || config.HuaweiToken != "huawei-token" || config.T3.EnvironmentID != "desktop-id" {
		t.Fatalf("did not save both authorizations: %v", err)
	}
	if result := call("POST", "/private/logout", origin, "{}"); result.Code != 200 {
		t.Fatalf("logout status %d", result.Code)
	}
	config, err = readConfig(path)
	if err != nil || config.HuaweiToken != "" || config.T3.AccessToken == "" {
		t.Fatalf("logout did not preserve T3 pairing: %v", err)
	}
}

func TestPushServerURLAllowsHTTPSAndLoopback(t *testing.T) {
	for _, value := range []string{"https://push.example.org/", "http://127.0.0.1:8080", "http://[::1]:8080"} {
		if _, err := pushServerURL(value); err != nil {
			t.Errorf("valid server URL %s rejected: %v", value, err)
		}
	}
	for _, value := range []string{"http://push.example.org", "https://name@push.example.org", "https://push.example.org/a", "https://push.example.org/?q=x", "https://push.example.org/#x"} {
		if _, err := pushServerURL(value); err == nil {
			t.Errorf("invalid server URL %s accepted", value)
		}
	}
}
