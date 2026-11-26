package main

import (
	"context"
	"embed"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"sync"
	"time"

	"github.com/skip2/go-qrcode"
)

//go:embed setup.html setup.js setup.css
var setupAssets embed.FS

type setupPage struct {
	path    string
	client  pushClient
	pair    func(context.Context) (t3Connection, error)
	install func() error
	mu      sync.Mutex
}

func newSetupHandler(address, prefix, path, server string, pair func(context.Context) (t3Connection, error), install func() error) http.Handler {
	page := setupPage{path: path, client: pushClient{server}, pair: pair, install: install}
	mux := http.NewServeMux()
	for requestPath, asset := range map[string]string{"/{$}": "setup.html", "/setup.js": "setup.js", "/setup.css": "setup.css"} {
		mux.HandleFunc("GET "+requestPath, func(w http.ResponseWriter, r *http.Request) {
			http.ServeFileFS(w, r, setupAssets, asset)
		})
	}
	mux.HandleFunc("GET /state", page.state)
	mux.HandleFunc("POST /pair", page.connect)
	mux.HandleFunc("POST /login", page.login)
	mux.HandleFunc("POST /login/poll", page.poll)
	mux.HandleFunc("POST /logout", page.logout)
	mux.HandleFunc("POST /startup", page.startup)
	router := http.NewServeMux()
	router.Handle(prefix+"/", http.StripPrefix(prefix, mux))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Host != address || (r.Method != http.MethodGet && r.Header.Get("Origin") != "http://"+address) {
			http.Error(w, "Forbidden", http.StatusForbidden)
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Content-Security-Policy", "default-src 'none'; connect-src 'self'; img-src data:; style-src 'self'; script-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
		page.mu.Lock()
		defer page.mu.Unlock()
		router.ServeHTTP(w, r)
	})
}

type setupStatus struct {
	Paired        bool `json:"paired"`
	SignedIn      bool `json:"signedIn"`
	StartupActive bool `json:"startupActive"`
}

func (page *setupPage) config() (desktopConfig, error) {
	config, err := readConfig(page.path)
	if err != nil {
		return config, err
	}
	if config.PushURL != page.client.url {
		config.PushURL = page.client.url
		config.HuaweiToken = ""
		config.HuaweiExpiry = time.Time{}
	}
	return config, nil
}

func statusOf(config desktopConfig) setupStatus {
	return setupStatus{config.paired(), config.signedIn(time.Now()), config.StartupActive}
}

func (page *setupPage) state(w http.ResponseWriter, r *http.Request) {
	config, err := page.config()
	if err != nil {
		respondError(w, http.StatusInternalServerError, "无法读取本机设置。")
		return
	}
	if config.signedIn(time.Now()) {
		var session struct{ ExpiresAt time.Time }
		err = page.client.request(r.Context(), http.MethodGet, "/v1/session", config.HuaweiToken, nil, &session)
		if errors.Is(err, pushResponseError(http.StatusUnauthorized)) {
			config.HuaweiToken = ""
			config.HuaweiExpiry = time.Time{}
			if err := saveConfig(page.path, config); err != nil {
				respondError(w, http.StatusInternalServerError, "无法更新本机设置。")
				return
			}
		}
	}
	respondJSON(w, statusOf(config))
}

func (page *setupPage) connect(w http.ResponseWriter, r *http.Request) {
	config, err := page.config()
	if err != nil {
		respondError(w, http.StatusInternalServerError, "无法读取本机设置。")
		return
	}
	config.T3, err = page.pair(r.Context())
	if err != nil {
		respondError(w, http.StatusBadGateway, "连接失败。请打开官方 T3 Code 或启动它的后台服务，再重试。")
		return
	}
	if !page.save(w, &config) {
		return
	}
	respondJSON(w, statusOf(config))
}

func (page *setupPage) login(w http.ResponseWriter, r *http.Request) {
	var login deviceLogin
	if err := page.client.request(r.Context(), http.MethodPost, "/v1/desktop/login", "", struct{}{}, &login); err != nil {
		respondError(w, http.StatusBadGateway, "无法开始华为账号登录，请重试。")
		return
	}
	switch login.VerificationURL {
	case "https://oauth-login1.cloud.huawei.com/oauth2/v3/device", "https://oauth-login.cloud.huawei.com/oauth2/v3/device":
	default:
		respondError(w, http.StatusBadGateway, "华为授权地址无效。")
		return
	}
	if login.FlowToken == "" || login.UserCode == "" || len(login.UserCode) > 256 || login.IntervalSeconds <= 0 || login.ExpiresIn < login.IntervalSeconds || login.ExpiresIn > 1800 {
		respondError(w, http.StatusBadGateway, "华为授权信息无效，请重试。")
		return
	}
	query := url.Values{"user_code": {login.UserCode}, "lang": {"zh-cn"}}
	login.VerificationURL += "?" + query.Encode()
	image, err := qrcode.Encode(login.VerificationURL, qrcode.Medium, 228)
	if err != nil {
		respondError(w, http.StatusBadGateway, "无法生成授权二维码。")
		return
	}
	respondJSON(w, struct {
		deviceLogin
		QRImage string `json:"qrImage"`
	}{login, "data:image/png;base64," + base64.StdEncoding.EncodeToString(image)})
}

func (page *setupPage) poll(w http.ResponseWriter, r *http.Request) {
	var input struct {
		FlowToken string `json:"flowToken"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048)).Decode(&input); err != nil || input.FlowToken == "" || len(input.FlowToken) > 512 {
		respondError(w, http.StatusBadRequest, "授权请求无效。")
		return
	}
	var result devicePoll
	if err := page.client.request(r.Context(), http.MethodPost, "/v1/desktop/login/poll", "", input, &result); err != nil {
		respondError(w, http.StatusBadGateway, "等待华为授权时连接失败。")
		return
	}
	if result.Status == "signed_in" {
		if result.AccessToken == "" || !result.ExpiresAt.After(time.Now()) {
			respondError(w, http.StatusBadGateway, "华为登录状态无效。")
			return
		}
		config, err := page.config()
		if err != nil {
			respondError(w, http.StatusInternalServerError, "无法读取本机设置。")
			return
		}
		config.HuaweiToken = result.AccessToken
		config.HuaweiExpiry = result.ExpiresAt
		if !page.save(w, &config) {
			return
		}
		respondJSON(w, struct {
			Status string `json:"status"`
			setupStatus
		}{result.Status, statusOf(config)})
		return
	}
	respondJSON(w, struct {
		Status string `json:"status"`
	}{result.Status})
}

func (page *setupPage) logout(w http.ResponseWriter, r *http.Request) {
	config, err := page.config()
	if err != nil {
		respondError(w, http.StatusInternalServerError, "无法读取本机设置。")
		return
	}
	if config.HuaweiToken != "" {
		err = page.client.request(r.Context(), http.MethodDelete, "/v1/session", config.HuaweiToken, nil, nil)
		if err != nil && !errors.Is(err, pushResponseError(http.StatusUnauthorized)) {
			respondError(w, http.StatusBadGateway, "无法撤销华为登录，请重试。")
			return
		}
	}
	config.HuaweiToken = ""
	config.HuaweiExpiry = time.Time{}
	if page.save(w, &config) {
		respondJSON(w, statusOf(config))
	}
}

func (page *setupPage) startup(w http.ResponseWriter, r *http.Request) {
	config, err := page.config()
	if err != nil || !config.paired() || !config.signedIn(time.Now()) {
		respondError(w, http.StatusConflict, "请先连接 T3 Code 并登录华为账号。")
		return
	}
	if page.save(w, &config) {
		respondJSON(w, statusOf(config))
	}
}

func (page *setupPage) save(w http.ResponseWriter, config *desktopConfig) bool {
	if err := saveConfig(page.path, *config); err != nil {
		respondError(w, http.StatusInternalServerError, "无法保存本机设置。")
		return false
	}
	if !config.StartupActive && config.paired() && config.signedIn(time.Now()) {
		if err := page.install(); err == nil {
			config.StartupActive = true
			_ = saveConfig(page.path, *config)
		}
	}
	return true
}

func respondError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": message})
}

func respondJSON(w http.ResponseWriter, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_ = json.NewEncoder(w).Encode(data)
}
