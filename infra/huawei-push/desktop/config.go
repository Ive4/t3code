package main

import (
	"encoding/json"
	"errors"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type desktopConfig struct {
	PushURL       string       `json:"pushUrl"`
	T3            t3Connection `json:"t3"`
	HuaweiToken   string       `json:"huaweiToken"`
	HuaweiExpiry  time.Time    `json:"huaweiExpiry"`
	StartupActive bool         `json:"startupActive"`
}

func (config desktopConfig) paired() bool {
	return config.T3.BaseURL != "" && config.T3.EnvironmentID != "" && config.T3.AccessToken != ""
}

func (config desktopConfig) signedIn(now time.Time) bool {
	return config.HuaweiToken != "" && config.HuaweiExpiry.After(now)
}

func readConfig(path string) (desktopConfig, error) {
	var config desktopConfig
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return config, nil
	}
	if err != nil {
		return config, err
	}
	err = json.Unmarshal(data, &config)
	return config, err
}

func saveConfig(path string, config desktopConfig) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	file, err := os.CreateTemp(dir, ".config-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	writeErr := json.NewEncoder(file).Encode(config)
	if writeErr == nil {
		writeErr = file.Sync()
	}
	if err := errors.Join(writeErr, file.Close()); err != nil {
		return err
	}
	return os.Rename(file.Name(), path)
}

func pushServerURL(value string) (string, error) {
	parsed, err := url.Parse(strings.TrimSpace(value))
	if err != nil || parsed.Hostname() == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.ForceQuery || parsed.Fragment != "" || parsed.RawPath != "" ||
		(parsed.Path != "" && parsed.Path != "/") {
		return "", errors.New("推送服务地址必须是 HTTPS 地址")
	}
	if parsed.Scheme != "https" {
		ip := net.ParseIP(parsed.Hostname())
		if parsed.Scheme != "http" || (parsed.Hostname() != "localhost" && (ip == nil || !ip.IsLoopback())) {
			return "", errors.New("推送服务地址必须使用 HTTPS")
		}
	}
	parsed.Path = ""
	return parsed.String(), nil
}
