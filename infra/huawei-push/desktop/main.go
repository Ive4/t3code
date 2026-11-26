package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
)

const desktopName = "T3 Huawei Push"

var defaultPushURL string

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if err := desktop(ctx, os.Args[1:]); err != nil {
		log.Fatal(err)
	}
}

func desktop(ctx context.Context, args []string) error {
	dir, err := os.UserConfigDir()
	if err != nil {
		return err
	}
	dir = filepath.Join(dir, desktopName)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	path := filepath.Join(dir, "config.json")
	if len(args) == 1 && args[0] == "run" {
		return runBackground(ctx, dir, path)
	}
	flags := flag.NewFlagSet("t3-huawei-push", flag.ContinueOnError)
	serverFlag := flags.String("server", "", "HTTPS origin of the push service")
	t3Home := flags.String("t3-home", "", "T3 home of an isolated or non-default local environment")
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected argument")
	}
	return openSetup(ctx, dir, path, *serverFlag, *t3Home)
}

func openSetup(ctx context.Context, dir, path, serverFlag, t3Home string) error {
	config, err := readConfig(path)
	if err != nil {
		return err
	}
	serverURL := serverFlag
	if serverURL == "" {
		serverURL = config.PushURL
	}
	if serverURL == "" {
		serverURL = defaultPushURL
	}
	serverURL, err = pushServerURL(serverURL)
	if err != nil {
		return err
	}
	lock, err := instanceLock(filepath.Join(dir, "setup.lock"))
	if err != nil {
		return err
	}
	location := filepath.Join(dir, ".setup-url")
	if lock == nil {
		if state, err := os.ReadFile(location); err == nil && strings.HasPrefix(string(state), "http://127.0.0.1:") {
			return openBrowser(string(state))
		}
		return errors.New("华为推送设置已打开")
	}
	defer lock.Close()
	defer os.Remove(location)
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return err
	}
	defer listener.Close()
	address := listener.Addr().String()
	var secret [24]byte
	if _, err := rand.Read(secret[:]); err != nil {
		return err
	}
	prefix := "/" + base64.RawURLEncoding.EncodeToString(secret[:])
	setupURL := "http://" + address + prefix + "/"
	if err := os.WriteFile(location, []byte(setupURL), 0600); err != nil {
		return err
	}
	server := &http.Server{
		Handler: newSetupHandler(address, prefix, path, serverURL, func(ctx context.Context) (t3Connection, error) {
			return pairLocalT3(ctx, t3Home)
		}, func() error {
			return installBackground(dir)
		}),
		ReadTimeout: 5 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 25 * time.Second,
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Minute)
	defer cancel()
	go func() {
		<-ctx.Done()
		_ = server.Close()
	}()
	if err := openBrowser(setupURL); err != nil {
		fmt.Println(setupURL)
	}
	if err := server.Serve(listener); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

func pairLocalT3(ctx context.Context, t3Home string) (t3Connection, error) {
	if t3Home != "" && !filepath.IsAbs(t3Home) {
		return t3Connection{}, errors.New("T3 home must be absolute")
	}
	cli, err := findT3(t3Home)
	if err != nil {
		return t3Connection{}, err
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	output, err := pairingCommand(ctx, cli, t3Home).Output()
	if err != nil {
		return t3Connection{}, errors.New("official T3 Code could not issue a read-only pairing link")
	}
	link, err := readPairingLink(bytes.NewReader(output))
	if err != nil {
		return t3Connection{}, err
	}
	return pairT3(ctx, link)
}

func findT3(t3Home string) (string, error) {
	if executable, err := exec.LookPath("t3"); err == nil {
		return executable, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	if t3Home == "" {
		t3Home = filepath.Join(home, ".t3")
	}
	names := []string{"t3"}
	if runtime.GOOS == "windows" {
		names = []string{"t3.cmd", "t3.exe"}
	}
	for _, dir := range []string{filepath.Join(t3Home, "bin"), filepath.Join(home, ".local", "bin")} {
		for _, name := range names {
			path := filepath.Join(dir, name)
			if info, err := os.Stat(path); err == nil && info.Mode().IsRegular() {
				return path, nil
			}
		}
	}
	return "", errors.New("official t3 launcher is unavailable")
}

func readPairingLink(reader io.Reader) (string, error) {
	scan := bufio.NewScanner(reader)
	for scan.Scan() {
		if _, link, ok := strings.Cut(scan.Text(), "Pairing URL: "); ok {
			return strings.TrimSpace(link), nil
		}
	}
	return "", errors.New("official T3 pairing link missing from CLI output")
}

func runBackground(ctx context.Context, dir, path string) error {
	lock, err := instanceLock(filepath.Join(dir, "background.lock"))
	if err != nil || lock == nil {
		return err
	}
	defer lock.Close()
	logFile, err := os.OpenFile(filepath.Join(dir, "activity.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer logFile.Close()
	logger := log.New(logFile, "", log.LstdFlags)
	tick := time.NewTicker(3 * time.Second)
	defer tick.Stop()
	var previous desktopConfig
	stop := func() {}
	defer func() { stop() }()
	for {
		config, err := readConfig(path)
		if err != nil {
			config = desktopConfig{}
		}
		config.StartupActive = false
		if !config.signedIn(time.Now()) {
			config.HuaweiToken = ""
		}
		if previous != config {
			stop()
			previous = config
			if config.paired() && config.HuaweiToken != "" {
				stop = startRelay(ctx, config, logger)
			}
		}
		select {
		case <-ctx.Done():
			return nil
		case <-tick.C:
		}
	}
}

func startRelay(ctx context.Context, config desktopConfig, logger *log.Logger) context.CancelFunc {
	worker, cancel := context.WithCancel(ctx)
	go relayEvents(worker, config, logger)
	return cancel
}

func relayEvents(ctx context.Context, config desktopConfig, logger *log.Logger) {
	serverURL, err := pushServerURL(config.PushURL)
	if err != nil {
		return
	}
	client := pushClient{serverURL}
	ctx, cancel := context.WithDeadline(ctx, config.HuaweiExpiry)
	defer cancel()
	var session struct{ ExpiresAt time.Time }
	err = client.request(ctx, http.MethodGet, "/v1/session", config.HuaweiToken, nil, &session)
	if errors.Is(err, pushResponseError(http.StatusUnauthorized)) || errors.Is(err, pushResponseError(http.StatusForbidden)) {
		logger.Print("Huawei session expired. Reopen setup to sign in again.")
		return
	}
	err = watchT3(ctx, config.T3, func(eventContext context.Context, event pushEvent) error {
		err := client.request(eventContext, http.MethodPost, "/v1/desktop/events", config.HuaweiToken, event, nil)
		var status pushResponseError
		if errors.As(err, &status) && status < 500 && status != http.StatusTooManyRequests {
			logger.Printf("push request rejected (HTTP %d)", status)
			if status == http.StatusUnauthorized || status == http.StatusForbidden {
				cancel()
			}
			return nil
		}
		return err
	})
	if err != nil && ctx.Err() == nil {
		logger.Print("T3 connection stopped. Reopen setup to check the pairing.")
	}
}
