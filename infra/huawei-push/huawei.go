package main

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"slices"
	"strings"
	"time"
)

const huaweiJWTAudience = "https://oauth-login.cloud.huawei.com/oauth2/v3/token"

type huaweiClient struct {
	endpoint   string
	key        *rsa.PrivateKey
	keyID      string
	issuer     string
	httpClient *http.Client
}

func loadHuaweiClient(accountFile string, projectID string) (huaweiClient, error) {
	value, err := os.ReadFile(accountFile)
	if err != nil {
		return huaweiClient{}, errors.New("could not read HUAWEI_PUSH_SERVICE_ACCOUNT_FILE")
	}
	return parseHuaweiClient(value, projectID)
}

func parseHuaweiClient(value []byte, projectID string) (huaweiClient, error) {
	var account struct {
		ProjectID  string `json:"project_id"`
		KeyID      string `json:"key_id"`
		SubAccount string `json:"sub_account"`
		PrivateKey string `json:"private_key"`
	}
	if err := json.Unmarshal(value, &account); err != nil || account.KeyID == "" || account.SubAccount == "" {
		return huaweiClient{}, errors.New("invalid Huawei service account JSON")
	}
	if projectID == "" {
		projectID = account.ProjectID
	}
	if projectID == "" || strings.TrimSpace(projectID) != projectID || strings.ContainsAny(projectID, "/?#") {
		return huaweiClient{}, errors.New("invalid Huawei Push Kit project ID")
	}
	block, _ := pem.Decode([]byte(account.PrivateKey))
	if block == nil {
		return huaweiClient{}, errors.New("invalid Huawei service account private key")
	}
	var key *rsa.PrivateKey
	switch block.Type {
	case "RSA PRIVATE KEY":
		key, _ = x509.ParsePKCS1PrivateKey(block.Bytes)
	case "PRIVATE KEY":
		value, _ := x509.ParsePKCS8PrivateKey(block.Bytes)
		key, _ = value.(*rsa.PrivateKey)
	}
	if key == nil {
		return huaweiClient{}, errors.New("Huawei service account key must use RSA")
	}
	return huaweiClient{
		endpoint: "https://push-api.cloud.huawei.com/v3/" + url.PathEscape(projectID) + "/messages:send",
		key:      key,
		keyID:    account.KeyID,
		issuer:   account.SubAccount,
		httpClient: &http.Client{
			Timeout: 8 * time.Second,
			CheckRedirect: func(*http.Request, []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
	}, nil
}

func (client huaweiClient) authorization(now time.Time) (string, error) {
	header, _ := json.Marshal(map[string]string{"alg": "PS256", "typ": "JWT", "kid": client.keyID})
	claims, _ := json.Marshal(map[string]any{
		"aud": huaweiJWTAudience, "iss": client.issuer, "iat": now.Unix(), "exp": now.Add(time.Hour).Unix(),
	})
	encoding := base64.RawURLEncoding
	message := encoding.EncodeToString(header) + "." + encoding.EncodeToString(claims)
	hash := sha256.Sum256([]byte(message))
	signature, err := rsa.SignPSS(rand.Reader, client.key, crypto.SHA256, hash[:], &rsa.PSSOptions{
		SaltLength: rsa.PSSSaltLengthEqualsHash,
	})
	if err != nil {
		return "", errors.New("could not sign Huawei authorization")
	}
	return "Bearer " + message + "." + encoding.EncodeToString(signature), nil
}

func (client huaweiClient) send(ctx context.Context, value notification, now time.Time) (string, error) {
	seconds := int64(time.UnixMilli(value.ExpiresAt).Sub(now) / time.Second)
	if seconds < 1 {
		return "rejected", nil
	}
	const maxHuaweiTTL = 15 * 24 * 60 * 60
	payload, err := json.Marshal(map[string]any{
		"payload": map[string]any{"notification": map[string]any{
			"category":       "WORK",
			"title":          value.Title,
			"body":           value.Body,
			"appMessageId":   value.ID,
			"foregroundShow": false,
			"clickAction": map[string]any{"actionType": 0, "data": map[string]any{
				"t3AgentNotification": true, "environmentId": value.EnvironmentID, "threadId": value.ThreadID,
			}},
		}},
		"pushOptions": map[string]int64{"ttl": min(seconds, maxHuaweiTTL)},
		"target":      map[string][]string{"token": {value.Token}},
	})
	if err != nil {
		return "rejected", nil
	}
	auth, err := client.authorization(now)
	if err != nil {
		return "", err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, client.endpoint, bytes.NewReader(payload))
	if err != nil {
		return "", errors.New("could not create Huawei request")
	}
	request.Header.Set("Authorization", auth)
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("push-type", "0")
	response, err := client.httpClient.Do(request)
	if err != nil {
		return "", errors.New("Huawei Push Kit request failed")
	}
	defer response.Body.Close()
	return vendorResult(response.StatusCode, response.Body, value.Token)
}

func vendorResult(status int, body io.Reader, token string) (string, error) {
	if status != http.StatusOK && status != http.StatusBadRequest {
		return "", fmt.Errorf("Huawei Push Kit returned HTTP %d", status)
	}
	var result struct {
		Code string `json:"code"`
		Msg  string `json:"msg"`
	}
	if err := json.NewDecoder(io.LimitReader(body, 32<<10)).Decode(&result); err != nil || result.Code == "" {
		return "", errors.New("Huawei Push Kit returned an unreadable response")
	}
	switch result.Code {
	case "80000000":
		if status == http.StatusOK {
			return "sent", nil
		}
		return "", errors.New("Huawei Push Kit returned inconsistent success")
	case "80100000", "80300007":
		var outcome struct {
			IllegalTokens map[string][]string `json:"illegalTokens"`
		}
		if json.Unmarshal([]byte(result.Msg), &outcome) == nil && slices.Contains(outcome.IllegalTokens["tokenFormatError"], token) {
			return "invalid_token", nil
		}
	case "80200001", "80200005", "80300002", "80300029", "81000001":
		return "", fmt.Errorf("Huawei Push Kit returned code %s", result.Code)
	}
	return "rejected", nil
}
