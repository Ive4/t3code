package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

type pushClient struct{ url string }

type pushResponseError int

func (code pushResponseError) Error() string { return fmt.Sprintf("push service HTTP %d", code) }

type deviceLogin struct {
	FlowToken       string `json:"flowToken"`
	VerificationURL string `json:"verificationUrl"`
	UserCode        string `json:"userCode"`
	IntervalSeconds int    `json:"intervalSeconds"`
	ExpiresIn       int    `json:"expiresIn"`
}

type devicePoll struct {
	Status      string    `json:"status"`
	AccessToken string    `json:"accessToken"`
	ExpiresAt   time.Time `json:"expiresAt"`
}

var pushHTTPClient = http.Client{
	Timeout:       12 * time.Second,
	CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
}

func (client pushClient) request(ctx context.Context, method, path, token string, payload, output any) error {
	var body io.Reader
	if payload != nil {
		encoded, err := json.Marshal(payload)
		if err != nil {
			return err
		}
		body = bytes.NewReader(encoded)
	}
	req, err := http.NewRequestWithContext(ctx, method, client.url+path, body)
	if err != nil {
		return err
	}
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("User-Agent", "T3-Huawei-Push/1")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	response, err := pushHTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusNoContent && output == nil {
		return nil
	}
	if response.StatusCode != http.StatusOK || output == nil {
		return pushResponseError(response.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(response.Body, 16<<10)).Decode(output)
}
