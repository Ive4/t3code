package main

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"time"
)

const hostedSessionTTL = 30 * 24 * time.Hour

type hostedSession struct {
	Account        string    `json:"account"`
	Role           string    `json:"role"`
	ExpiresAt      time.Time `json:"expiresAt"`
	PushToken      string    `json:"pushToken,omitempty"`
	RegistrationID string    `json:"registrationId,omitempty"`
	EnvironmentIDs []string  `json:"environmentIds,omitempty"`
	Phases         []string  `json:"phases,omitempty"`
}

func (session hostedSession) matches(account, environmentID, phase string, now time.Time) bool {
	return session.Role == "mobile" && session.Account == account && session.ExpiresAt.After(now) &&
		session.RegistrationID != "" && slices.Contains(session.EnvironmentIDs, environmentID) &&
		slices.Contains(session.Phases, phase)
}

type hostedFlow struct {
	DeviceCode string        `json:"deviceCode"`
	ExpiresAt  time.Time     `json:"expiresAt"`
	NextPollAt time.Time     `json:"nextPollAt"`
	Interval   time.Duration `json:"interval"`
}

type hostedState struct {
	Sessions map[string]hostedSession `json:"sessions"`
	Flows    map[string]hostedFlow    `json:"flows"`
	Events   map[string]hostedEvent   `json:"events"`
}

const maxHostedStateSize = 64 << 20

func loadHostedState(path string) (hostedState, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return hostedState{}.snapshot(time.Time{}), nil
	}
	if err != nil {
		return hostedState{}, err
	}
	if !info.Mode().IsRegular() || (runtime.GOOS != "windows" && info.Mode().Perm()&0077 != 0) {
		return hostedState{}, errors.New("push state must be a regular file with owner-only permissions")
	}
	if info.Size() > maxHostedStateSize {
		return hostedState{}, errors.New("push state is too large")
	}
	file, err := os.Open(path)
	if err != nil {
		return hostedState{}, err
	}
	defer file.Close()
	var state hostedState
	if err := decodeSingleJSON(io.LimitReader(file, maxHostedStateSize+1), &state); err != nil {
		return hostedState{}, errors.New("invalid push state")
	}
	if state.Sessions == nil || state.Flows == nil || state.Events == nil {
		return hostedState{}, errors.New("incomplete push state")
	}
	return state, nil
}

func (state hostedState) snapshot(now time.Time) hostedState {
	next := hostedState{
		Sessions: make(map[string]hostedSession, len(state.Sessions)),
		Flows:    make(map[string]hostedFlow, len(state.Flows)),
		Events:   make(map[string]hostedEvent, len(state.Events)),
	}
	for id, session := range state.Sessions {
		if session.ExpiresAt.After(now) {
			next.Sessions[id] = session
		}
	}
	for id, flow := range state.Flows {
		if flow.ExpiresAt.After(now) {
			next.Flows[id] = flow
		}
	}
	for id, event := range state.Events {
		if event.ExpiresAt.After(now) {
			if !event.Deadline.After(now) {
				event = hostedEvent{ExpiresAt: event.ExpiresAt}
			}
			next.Events[id] = event
		}
	}
	return next
}

func writeHostedState(path string, state hostedState) error {
	var data bytes.Buffer
	encoder := json.NewEncoder(&data)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(state); err != nil {
		return err
	}
	if data.Len() > maxHostedStateSize {
		return errors.New("push state is too large")
	}
	dir := filepath.Dir(path)
	file, err := os.CreateTemp(dir, ".huawei-push-*")
	if err != nil {
		return err
	}
	name := file.Name()
	defer os.Remove(name)
	if _, err := data.WriteTo(file); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if err := os.Rename(name, path); err != nil {
		return err
	}
	if directory, err := os.Open(dir); err == nil {
		_ = directory.Sync()
		_ = directory.Close()
	}
	return nil
}

func hostedHash(value string) string {
	digest := sha256.Sum256([]byte(value))
	return hex.EncodeToString(digest[:])
}

func hostedToken() string {
	var raw [32]byte
	_, _ = rand.Read(raw[:])
	return base64.RawURLEncoding.EncodeToString(raw[:])
}

func validHostedToken(token string) bool {
	if len(token) != base64.RawURLEncoding.EncodedLen(32) {
		return false
	}
	_, err := base64.RawURLEncoding.Strict().DecodeString(token)
	return err == nil
}
