package main

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"reflect"
	"strings"
	"testing"
	"time"
)

const (
	testHuaweiAccountID      = "12345"
	testHuaweiAccountSecret  = "secret+/="
	testHuaweiAccountCode    = "code+/="
	testHuaweiAccountAccess  = "access+/="
	testHuaweiAccountRefresh = "refresh+/="
)

func TestHuaweiAccountDeviceLogin(t *testing.T) {
	client := newTestHuaweiAccountClient(t, func(w http.ResponseWriter, r *http.Request) {
		assertHuaweiAccountForm(t, r, "/oauth2/v3/device/code", url.Values{
			"client_id": {testHuaweiAccountID},
			"scope":     {"openid"},
		})
		io.WriteString(w, `{"device_code":"code+/=","user_code":"USER-CODE","verification_url":"https://oauth-login1.cloud.huawei.com/oauth2/v3/device","create_time":1770000000,"expire_in":1800,"scan_expire_in":120,"interval":3}`)
	})
	got, err := client.startDeviceLogin(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	want := huaweiAccountDeviceCode{
		DeviceCode: testHuaweiAccountCode, UserCode: "USER-CODE",
		VerificationURL: "https://oauth-login1.cloud.huawei.com/oauth2/v3/device",
		CreatedAt:       time.Unix(1770000000, 0).UTC(), ExpiresIn: 30 * time.Minute,
		ScanExpiresIn: 2 * time.Minute, Interval: 3 * time.Second,
	}
	if got != want {
		t.Fatalf("device code = %#v, want %#v", got, want)
	}
}

func TestHuaweiAccountDeviceLoginRejectsUntrustedVerificationURL(t *testing.T) {
	for _, verificationURL := range []string{
		"http://oauth-login1.cloud.huawei.com/oauth2/v3/device",
		"https://oauth-login1.cloud.huawei.com.example.com/oauth2/v3/device",
		"https://oauth-login1.cloud.huawei.com:444/oauth2/v3/device",
		"https://example.com@oauth-login1.cloud.huawei.com/oauth2/v3/device",
		"https://oauth-login1.cloud.huawei.com/other",
		"https://oauth-login1.cloud.huawei.com/oauth2/v3/device?device_code=code",
	} {
		t.Run(verificationURL, func(t *testing.T) {
			client := newTestHuaweiAccountClient(t, func(w http.ResponseWriter, r *http.Request) {
				io.WriteString(w, `{"device_code":"code","user_code":"USER-CODE","verification_url":"`+verificationURL+`","create_time":1770000000,"expire_in":1800,"scan_expire_in":120,"interval":3}`)
			})
			_, err := client.startDeviceLogin(context.Background())
			assertHuaweiAccountError(t, err, huaweiAccountUnavailable, 0, 0)
		})
	}
}

func TestHuaweiAccountTokenGrants(t *testing.T) {
	for _, test := range []struct {
		name        string
		grant       string
		parameter   string
		value       string
		call        func(*huaweiAccountClient, context.Context, string) (huaweiAccountTokens, error)
		body        string
		wantRefresh string
	}{
		{"device code", "device_code", "code", testHuaweiAccountCode, (*huaweiAccountClient).exchangeDeviceCode, `{"token_type":"Bearer","expires_in":3600,"access_token":"access+/=","refresh_token":"refresh+/=","id_token":"unused"}`, testHuaweiAccountRefresh},
		{"authorization code", "authorization_code", "code", testHuaweiAccountCode, (*huaweiAccountClient).exchangeAuthorizationCode, `{"token_type":"Bearer","expires_in":3600,"access_token":"access+/=","refresh_token":"refresh+/="}`, testHuaweiAccountRefresh},
		{"refresh", "refresh_token", "refresh_token", testHuaweiAccountRefresh, (*huaweiAccountClient).refresh, `{"token_type":"Bearer","expires_in":3600,"access_token":"access+/="}`, testHuaweiAccountRefresh},
		{"refresh rotation", "refresh_token", "refresh_token", testHuaweiAccountRefresh, (*huaweiAccountClient).refresh, `{"token_type":"Bearer","expires_in":3600,"access_token":"access+/=","refresh_token":"new-refresh"}`, "new-refresh"},
	} {
		t.Run(test.name, func(t *testing.T) {
			client := newTestHuaweiAccountClient(t, func(w http.ResponseWriter, r *http.Request) {
				assertHuaweiAccountForm(t, r, "/oauth2/v3/token", url.Values{
					"client_id": {testHuaweiAccountID}, "client_secret": {testHuaweiAccountSecret},
					"grant_type": {test.grant}, test.parameter: {test.value},
				})
				io.WriteString(w, test.body)
			})
			got, err := test.call(client, context.Background(), test.value)
			if err != nil {
				t.Fatal(err)
			}
			want := huaweiAccountTokens{AccessToken: testHuaweiAccountAccess, RefreshToken: test.wantRefresh, ExpiresIn: time.Hour}
			if got != want {
				t.Fatalf("tokens = %#v, want %#v", got, want)
			}
		})
	}
}

func TestHuaweiAccountRejectsMalformedTokenExchange(t *testing.T) {
	for _, test := range []struct {
		name string
		body string
	}{
		{"missing refresh token", `{"token_type":"Bearer","expires_in":3600,"access_token":"access+/="}`},
		{"missing lifetime", `{"token_type":"Bearer","access_token":"access+/=","refresh_token":"refresh+/="}`},
		{"trailing content", `{"token_type":"Bearer","expires_in":3600,"access_token":"access+/=","refresh_token":"refresh+/="}{}`},
		{"oversize including whitespace", `{"token_type":"Bearer","expires_in":3600,"access_token":"access+/=","refresh_token":"refresh+/="}` + strings.Repeat(" ", huaweiAccountMaxResponse)},
	} {
		t.Run(test.name, func(t *testing.T) {
			client := newTestHuaweiAccountClient(t, func(w http.ResponseWriter, r *http.Request) {
				io.WriteString(w, test.body)
			})
			_, err := client.exchangeAuthorizationCode(context.Background(), testHuaweiAccountCode)
			assertHuaweiAccountError(t, err, huaweiAccountUnavailable, 0, 0)
		})
	}
}

func TestHuaweiAccountDevicePollingOutcomes(t *testing.T) {
	for _, test := range []struct {
		name          string
		status        int
		body          string
		kind          huaweiAccountErrorKind
		code, subCode int
	}{
		{"not scanned", 400, `{"error":1101,"sub_error":20411}`, huaweiAccountPending, 1101, 20411},
		{"not approved", 400, `{"error":1101,"sub_error":20412}`, huaweiAccountPending, 1101, 20412},
		{"user code expired", 400, `{"error":1101,"sub_error":20404}`, huaweiAccountExpired, 1101, 20404},
		{"device code expired", 400, `{"error":1600,"sub_error":16003}`, huaweiAccountExpired, 1600, 16003},
		{"quota exhausted", 400, `{"error":1101,"sub_error":20407}`, huaweiAccountExpired, 1101, 20407},
		{"authorization cancelled", 400, `{"error":1101,"sub_error":20414,"error_description":"code+/= secret+/= access+/= refresh+/="}`, huaweiAccountDenied, 1101, 20414},
		{"misconfigured credentials", 400, `{"error":1203,"sub_error":12304}`, huaweiAccountInvalid, 1203, 12304},
		{"wrong main error", 400, `{"error":1203,"sub_error":20411}`, huaweiAccountInvalid, 1203, 20411},
		{"provider outage", 400, `{"error":1203,"sub_error":56100}`, huaweiAccountUnavailable, 1203, 56100},
		{"HTTP limit", 429, `rate limit`, huaweiAccountSlowDown, 0, 0},
		{"HTTP bad gateway", 502, `bad gateway`, huaweiAccountUnavailable, 0, 0},
	} {
		t.Run(test.name, func(t *testing.T) {
			client := newTestHuaweiAccountClient(t, func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(test.status)
				io.WriteString(w, test.body)
			})
			_, err := client.exchangeDeviceCode(context.Background(), testHuaweiAccountCode)
			assertHuaweiAccountError(t, err, test.kind, test.code, test.subCode)
		})
	}
}

func TestHuaweiAccountIntrospection(t *testing.T) {
	for _, test := range []struct {
		name      string
		nspStatus string
		body      string
		wantError huaweiAccountErrorKind
	}{
		{"Huawei user", "", `{"type":0,"client_id":"12345","scope":"profile openid","union_id":"AbC_123","expire_in":1123,"open_id":"unused"}`, ""},
		{"missing token type", "", `{"client_id":"12345","scope":"openid","union_id":"AbC_123","expire_in":1123}`, huaweiAccountInvalid},
		{"application token", "", `{"type":1,"client_id":"12345","scope":"openid","union_id":"AbC_123","expire_in":1123}`, huaweiAccountInvalid},
		{"different app", "", `{"type":0,"client_id":"123456","scope":"openid","union_id":"AbC_123","expire_in":1123}`, huaweiAccountInvalid},
		{"different scope", "", `{"type":0,"client_id":"12345","scope":"notopenid","union_id":"AbC_123","expire_in":1123}`, huaweiAccountInvalid},
		{"missing union ID", "", `{"type":0,"client_id":"12345","scope":"openid","expire_in":1123}`, huaweiAccountInvalid},
		{"invalid union ID", "", `{"type":0,"client_id":"12345","scope":"openid","union_id":" AbC_123","expire_in":1123}`, huaweiAccountInvalid},
		{"expired identity", "", `{"type":0,"client_id":"12345","scope":"openid","union_id":"AbC_123","expire_in":0}`, huaweiAccountInvalid},
		{"overflowing expiry", "", `{"type":0,"client_id":"12345","scope":"openid","union_id":"AbC_123","expire_in":9223372036854775807}`, huaweiAccountInvalid},
		{"provider invalid session", "102", `{"error":"invalid session access+/="}`, huaweiAccountInvalid},
		{"error status overrides identity", "102", `{"type":0,"client_id":"12345","scope":"openid","union_id":"AbC_123","expire_in":1123}`, huaweiAccountInvalid},
		{"provider expired session", "6", `{"error":"session timeout"}`, huaweiAccountExpired},
		{"provider unavailable", "1302", `{"error":"flow control"}`, huaweiAccountUnavailable},
		{"unexpected response", "", `{"error":"access+/="}`, huaweiAccountInvalid},
	} {
		t.Run(test.name, func(t *testing.T) {
			client := newTestHuaweiAccountClient(t, func(w http.ResponseWriter, r *http.Request) {
				assertHuaweiAccountForm(t, r, "/rest.php?nsp_fmt=JSON&nsp_svc=huawei.oauth2.user.getTokenInfo", url.Values{"access_token": {testHuaweiAccountAccess}})
				w.Header().Set("Content-Type", "text/plain;charset=utf-8")
				if test.nspStatus != "" {
					w.Header().Set("NSP_STATUS", test.nspStatus)
				}
				io.WriteString(w, test.body)
			})
			got, err := client.introspect(context.Background(), testHuaweiAccountAccess)
			if test.wantError != "" {
				assertHuaweiAccountError(t, err, test.wantError, 0, 0)
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if want := (huaweiAccountIdentity{UnionID: "AbC_123", ExpiresIn: 1123 * time.Second}); got != want {
				t.Fatalf("identity = %#v, want %#v", got, want)
			}
		})
	}
}

func TestHuaweiAccountRevoke(t *testing.T) {
	for _, test := range []struct {
		name      string
		status    int
		body      string
		wantError huaweiAccountErrorKind
	}{
		{"success", 200, `{}`, ""},
		{"already revoked", 400, `{"error":1203,"sub_error":31204}`, ""},
		{"malformed success", 200, `null`, huaweiAccountUnavailable},
	} {
		t.Run(test.name, func(t *testing.T) {
			client := newTestHuaweiAccountClient(t, func(w http.ResponseWriter, r *http.Request) {
				assertHuaweiAccountForm(t, r, "/oauth2/v3/revoke", url.Values{"token": {testHuaweiAccountRefresh}})
				w.WriteHeader(test.status)
				io.WriteString(w, test.body)
			})
			err := client.revoke(context.Background(), testHuaweiAccountRefresh)
			if test.wantError != "" {
				assertHuaweiAccountError(t, err, test.wantError, 0, 0)
			} else if err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestHuaweiAccountDoesNotForwardCredentialsOnRedirect(t *testing.T) {
	client := newTestHuaweiAccountClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/oauth2/v3/token" {
			t.Error("provider redirect was followed")
			http.Error(w, "unexpected request", http.StatusBadRequest)
			return
		}
		http.Redirect(w, r, "/forwarded/"+testHuaweiAccountSecret, http.StatusTemporaryRedirect)
	})
	_, err := client.exchangeAuthorizationCode(context.Background(), testHuaweiAccountCode)
	assertHuaweiAccountError(t, err, huaweiAccountUnavailable, 0, 0)
}

func newTestHuaweiAccountClient(t *testing.T, handler http.HandlerFunc) *huaweiAccountClient {
	t.Helper()
	server := httptest.NewTLSServer(handler)
	t.Cleanup(server.Close)
	client := newHuaweiAccountClient(testHuaweiAccountID, testHuaweiAccountSecret)
	client.httpClient.Transport = server.Client().Transport
	client.oauthBaseURL = server.URL
	client.tokenInfoURL = server.URL + "/rest.php?nsp_fmt=JSON&nsp_svc=huawei.oauth2.user.getTokenInfo"
	return client
}

func assertHuaweiAccountForm(t *testing.T, request *http.Request, target string, want url.Values) {
	t.Helper()
	if request.Method != http.MethodPost || request.URL.RequestURI() != target || request.Header.Get("Content-Type") != "application/x-www-form-urlencoded" || request.TLS == nil {
		t.Errorf("incorrect Huawei request method, URL, content type or TLS: %s %s", request.Method, request.URL)
	}
	if err := request.ParseForm(); err != nil {
		t.Error(err)
	}
	if !reflect.DeepEqual(request.PostForm, want) {
		t.Errorf("form = %v, want %v", request.PostForm, want)
	}
}

func assertHuaweiAccountError(t *testing.T, err error, wantKind huaweiAccountErrorKind, wantCode, wantSubCode int) {
	t.Helper()
	var providerError *huaweiAccountError
	if !errors.As(err, &providerError) || providerError.Kind != wantKind || providerError.ProviderCode != wantCode || providerError.SubCode != wantSubCode {
		t.Fatalf("error = %#v, want kind %s with codes %d/%d", err, wantKind, wantCode, wantSubCode)
	}
	for _, credential := range []string{testHuaweiAccountSecret, testHuaweiAccountCode, testHuaweiAccountAccess, testHuaweiAccountRefresh} {
		if strings.Contains(err.Error(), credential) {
			t.Fatal("provider error exposed a credential")
		}
	}
}
