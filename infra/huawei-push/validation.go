package main

import (
	"encoding/json"
	"errors"
	"io"
	"strings"
	"unicode"
)

type notification struct {
	ID            string
	Token         string
	Title         string
	Body          string
	EnvironmentID string
	ThreadID      string
	ExpiresAt     int64
}

func validHuaweiCredential(value string, maxLen int) bool {
	return len(value) > 0 && len(value) <= maxLen && strings.IndexFunc(value, func(r rune) bool {
		return r < 33 || r > 126 || r == ','
	}) < 0
}

func validPushIdentifier(value string, maxLen int) bool {
	return len(value) > 0 && len(value) <= maxLen && strings.TrimSpace(value) == value &&
		strings.IndexFunc(value, unicode.IsControl) < 0
}

func decodeSingleJSON(reader io.Reader, value any) error {
	decoder := json.NewDecoder(reader)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(value); err != nil {
		return err
	}
	if decoder.Decode(new(json.RawMessage)) != io.EOF {
		return errors.New("unexpected data after JSON value")
	}
	return nil
}
