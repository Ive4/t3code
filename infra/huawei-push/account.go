package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"math"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"time"
)

const (
	huaweiAccountOAuthURL      = "https://oauth-login.cloud.huawei.com"
	huaweiAccountTokenInfoURL  = "https://oauth-api.cloud.huawei.com/rest.php?nsp_fmt=JSON&nsp_svc=huawei.oauth2.user.getTokenInfo"
	huaweiAccountMaxCredential = 8192
	huaweiAccountMaxResponse   = 32 << 10
)

type huaweiAccountErrorKind string

const (
	huaweiAccountPending     huaweiAccountErrorKind = "pending"
	huaweiAccountExpired     huaweiAccountErrorKind = "expired"
	huaweiAccountDenied      huaweiAccountErrorKind = "denied"
	huaweiAccountInvalid     huaweiAccountErrorKind = "invalid"
	huaweiAccountSlowDown    huaweiAccountErrorKind = "slow_down"
	huaweiAccountUnavailable huaweiAccountErrorKind = "unavailable"
)

type huaweiAccountError struct {
	Operation    string
	Kind         huaweiAccountErrorKind
	Status       int
	ProviderCode int
	SubCode      int
	NSPStatus    int
}

func (failure *huaweiAccountError) Error() string {
	return "Huawei Account Kit " + failure.Operation + ": " + string(failure.Kind)
}

type huaweiAccountDeviceCode struct {
	DeviceCode      string
	UserCode        string
	VerificationURL string
	CreatedAt       time.Time
	ExpiresIn       time.Duration
	ScanExpiresIn   time.Duration
	Interval        time.Duration
}

type huaweiAccountTokens struct {
	AccessToken  string
	RefreshToken string
	ExpiresIn    time.Duration
}

type huaweiAccountIdentity struct {
	UnionID   string
	ExpiresIn time.Duration
}

type huaweiAccountClient struct {
	clientID     string
	clientSecret string
	httpClient   *http.Client
	oauthBaseURL string
	tokenInfoURL string
}

func newHuaweiAccountClient(clientID, clientSecret string) *huaweiAccountClient {
	return &huaweiAccountClient{
		clientID: clientID, clientSecret: clientSecret,
		oauthBaseURL: huaweiAccountOAuthURL, tokenInfoURL: huaweiAccountTokenInfoURL,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
			CheckRedirect: func(*http.Request, []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
	}
}

func (client *huaweiAccountClient) startDeviceLogin(ctx context.Context) (huaweiAccountDeviceCode, error) {
	const operation = "device start"
	if !validHuaweiCredential(client.clientID, 64) {
		return huaweiAccountDeviceCode{}, &huaweiAccountError{Operation: operation, Kind: huaweiAccountInvalid}
	}
	var result struct {
		DeviceCode      string `json:"device_code"`
		UserCode        string `json:"user_code"`
		VerificationURL string `json:"verification_url"`
		CreateTime      int64  `json:"create_time"`
		ExpiresIn       int64  `json:"expire_in"`
		ScanExpiresIn   int64  `json:"scan_expire_in"`
		Interval        int64  `json:"interval"`
	}
	failure := client.postAccountForm(ctx, operation, client.oauthBaseURL+"/oauth2/v3/device/code", url.Values{
		"client_id": {client.clientID},
		"scope":     {"openid"},
	}, &result)
	if failure != nil {
		return huaweiAccountDeviceCode{}, failure
	}

	expiresIn := huaweiAccountSeconds(result.ExpiresIn)
	scanExpiresIn := huaweiAccountSeconds(result.ScanExpiresIn)
	interval := huaweiAccountSeconds(result.Interval)
	createdAt := time.Unix(result.CreateTime, 0).UTC()
	if !validHuaweiCredential(result.DeviceCode, huaweiAccountMaxCredential) || !validHuaweiCredential(result.UserCode, 256) ||
		(result.VerificationURL != "https://oauth-login1.cloud.huawei.com/oauth2/v3/device" &&
			result.VerificationURL != huaweiAccountOAuthURL+"/oauth2/v3/device") ||
		result.CreateTime <= 0 || createdAt.Year() < 1970 || createdAt.Year() > 9999 ||
		expiresIn == 0 || scanExpiresIn == 0 || interval == 0 || scanExpiresIn > expiresIn || interval > expiresIn {
		return huaweiAccountDeviceCode{}, &huaweiAccountError{Operation: operation, Kind: huaweiAccountUnavailable, Status: http.StatusOK}
	}
	return huaweiAccountDeviceCode{
		DeviceCode: result.DeviceCode, UserCode: result.UserCode, VerificationURL: result.VerificationURL,
		CreatedAt: createdAt, ExpiresIn: expiresIn, ScanExpiresIn: scanExpiresIn, Interval: interval,
	}, nil
}

func (client *huaweiAccountClient) exchangeDeviceCode(ctx context.Context, code string) (huaweiAccountTokens, error) {
	return client.exchangeAccountTokens(ctx, "device_code", "code", code)
}

func (client *huaweiAccountClient) exchangeAuthorizationCode(ctx context.Context, code string) (huaweiAccountTokens, error) {
	return client.exchangeAccountTokens(ctx, "authorization_code", "code", code)
}

func (client *huaweiAccountClient) refresh(ctx context.Context, refreshToken string) (huaweiAccountTokens, error) {
	return client.exchangeAccountTokens(ctx, "refresh_token", "refresh_token", refreshToken)
}

func (client *huaweiAccountClient) exchangeAccountTokens(ctx context.Context, grantType, parameter, value string) (huaweiAccountTokens, error) {
	if !validHuaweiCredential(client.clientID, 64) || !validHuaweiCredential(client.clientSecret, huaweiAccountMaxCredential) ||
		!validHuaweiCredential(value, huaweiAccountMaxCredential) {
		return huaweiAccountTokens{}, &huaweiAccountError{Operation: grantType, Kind: huaweiAccountInvalid}
	}
	var result struct {
		AccessToken  string  `json:"access_token"`
		RefreshToken *string `json:"refresh_token"`
		TokenType    string  `json:"token_type"`
		ExpiresIn    int64   `json:"expires_in"`
	}
	failure := client.postAccountForm(ctx, grantType, client.oauthBaseURL+"/oauth2/v3/token", url.Values{
		"client_id": {client.clientID}, "client_secret": {client.clientSecret},
		"grant_type": {grantType}, parameter: {value},
	}, &result)
	if failure != nil {
		return huaweiAccountTokens{}, failure
	}

	var refreshToken string
	if result.RefreshToken != nil {
		refreshToken = *result.RefreshToken
	} else if grantType == "refresh_token" {
		refreshToken = value
	}
	expiresIn := huaweiAccountSeconds(result.ExpiresIn)
	if !validHuaweiCredential(result.AccessToken, huaweiAccountMaxCredential) || !validHuaweiCredential(refreshToken, huaweiAccountMaxCredential) ||
		result.TokenType != "Bearer" || expiresIn == 0 {
		return huaweiAccountTokens{}, &huaweiAccountError{Operation: grantType, Kind: huaweiAccountUnavailable, Status: http.StatusOK}
	}
	return huaweiAccountTokens{AccessToken: result.AccessToken, RefreshToken: refreshToken, ExpiresIn: expiresIn}, nil
}

func (client *huaweiAccountClient) introspect(ctx context.Context, accessToken string) (huaweiAccountIdentity, error) {
	const operation = "introspect"
	if !validHuaweiCredential(client.clientID, 64) || !validHuaweiCredential(accessToken, huaweiAccountMaxCredential) {
		return huaweiAccountIdentity{}, &huaweiAccountError{Operation: operation, Kind: huaweiAccountInvalid}
	}
	var result struct {
		ClientID  string `json:"client_id"`
		Scope     string `json:"scope"`
		UnionID   string `json:"union_id"`
		Type      *int   `json:"type"`
		ExpiresIn int64  `json:"expire_in"`
	}
	failure := client.postAccountForm(ctx, operation, client.tokenInfoURL, url.Values{"access_token": {accessToken}}, &result)
	if failure != nil {
		return huaweiAccountIdentity{}, failure
	}

	expiresIn := huaweiAccountSeconds(result.ExpiresIn)
	if result.Type == nil || *result.Type != 0 || result.ClientID != client.clientID ||
		!slices.Contains(strings.Fields(result.Scope), "openid") || !validHuaweiCredential(result.UnionID, 256) || expiresIn == 0 {
		return huaweiAccountIdentity{}, &huaweiAccountError{Operation: operation, Kind: huaweiAccountInvalid, Status: http.StatusOK}
	}
	return huaweiAccountIdentity{UnionID: result.UnionID, ExpiresIn: expiresIn}, nil
}

func (client *huaweiAccountClient) revoke(ctx context.Context, token string) error {
	const operation = "revoke"
	if !validHuaweiCredential(token, huaweiAccountMaxCredential) {
		return &huaweiAccountError{Operation: operation, Kind: huaweiAccountInvalid}
	}
	var result map[string]json.RawMessage
	failure := client.postAccountForm(ctx, operation, client.oauthBaseURL+"/oauth2/v3/revoke", url.Values{"token": {token}}, &result)
	if failure != nil {
		if failure.ProviderCode == 1203 && failure.SubCode == 31204 {
			return nil
		}
		return failure
	}
	if len(result) != 0 {
		return &huaweiAccountError{Operation: operation, Kind: huaweiAccountUnavailable, Status: http.StatusOK}
	}
	return nil
}

func (client *huaweiAccountClient) postAccountForm(ctx context.Context, operation, endpoint string, form url.Values, result any) *huaweiAccountError {
	failure := huaweiAccountError{Operation: operation, Kind: huaweiAccountUnavailable}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil || request.URL.Scheme != "https" {
		return &failure
	}
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	response, err := client.httpClient.Do(request)
	if err != nil {
		return &failure
	}
	defer response.Body.Close()

	failure.Status = response.StatusCode
	if response.StatusCode == http.StatusTooManyRequests && operation == "device_code" {
		failure.Kind = huaweiAccountSlowDown
		return &failure
	}
	if response.StatusCode >= http.StatusInternalServerError || response.StatusCode == http.StatusTooManyRequests ||
		(response.StatusCode >= http.StatusMultipleChoices && response.StatusCode < http.StatusBadRequest) {
		return &failure
	}
	if status := response.Header.Get("NSP_STATUS"); status != "" && status != "0" {
		failure.NSPStatus, _ = strconv.Atoi(status)
		switch failure.NSPStatus {
		case 6:
			failure.Kind = huaweiAccountExpired
		case 102:
			failure.Kind = huaweiAccountInvalid
		}
		return &failure
	}
	if response.StatusCode >= http.StatusBadRequest {
		failure.Kind = huaweiAccountInvalid
	}

	body, err := io.ReadAll(io.LimitReader(response.Body, huaweiAccountMaxResponse+1))
	if err != nil || len(body) > huaweiAccountMaxResponse {
		return &failure
	}
	body = bytes.TrimSpace(body)
	if len(body) == 0 || body[0] != '{' {
		return &failure
	}
	var providerError struct {
		Error   json.RawMessage `json:"error"`
		SubCode int             `json:"sub_error"`
	}
	if err := json.Unmarshal(body, &providerError); err != nil {
		return &failure
	}
	if response.StatusCode != http.StatusOK || len(providerError.Error) != 0 || providerError.SubCode != 0 {
		failure.SubCode = providerError.SubCode
		_ = json.Unmarshal(providerError.Error, &failure.ProviderCode)
		failure.Kind = huaweiAccountProviderErrorKind(operation, failure.ProviderCode, failure.SubCode)
		return &failure
	}
	if err := json.Unmarshal(body, result); err != nil {
		return &failure
	}
	return nil
}

func huaweiAccountProviderErrorKind(operation string, code, subCode int) huaweiAccountErrorKind {
	if operation == "device_code" {
		switch {
		case code == 1101 && (subCode == 20411 || subCode == 20412):
			return huaweiAccountPending
		case code == 1101 && subCode == 20414:
			return huaweiAccountDenied
		case code == 1101 && (subCode == 20404 || subCode == 20406 || subCode == 20407), code == 1600 && subCode == 16003:
			return huaweiAccountExpired
		}
	}
	if code == 1203 {
		switch subCode {
		case 11205:
			return huaweiAccountExpired
		case 500, 1203, 56000, 56100, 56200, 57000:
			return huaweiAccountUnavailable
		}
	}
	if operation == "authorization_code" && code == 1101 && subCode == 20155 {
		return huaweiAccountExpired
	}
	return huaweiAccountInvalid
}

func huaweiAccountSeconds(seconds int64) time.Duration {
	if seconds <= 0 || seconds > math.MaxInt64/int64(time.Second) {
		return 0
	}
	return time.Duration(seconds) * time.Second
}
