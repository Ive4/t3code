//go:build darwin || linux

package main

import (
	"bytes"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"syscall"
)

func instanceLock(path string) (*os.File, error) {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = file.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, nil
		}
		return nil, err
	}
	return file, nil
}

func pairingCommand(ctx context.Context, cli, home string) *exec.Cmd {
	args := []string{"pair", "--scope", "orchestration:read", "--label", "Huawei Push"}
	if home != "" {
		args = append(args, "--base-dir", home)
	}
	return exec.CommandContext(ctx, cli, args...)
}

func openBrowser(addr string) error {
	if runtime.GOOS == "darwin" {
		return exec.Command("/usr/bin/open", addr).Run()
	}
	return exec.Command("xdg-open", addr).Run()
}

func startAtLogin(binary string) error {
	if runtime.GOOS != "darwin" {
		return errors.New("desktop login startup is supported on macOS and Windows")
	}
	const label = "com.t3code.huawei-push"
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	agents := filepath.Join(home, "Library", "LaunchAgents")
	if err := os.MkdirAll(agents, 0700); err != nil {
		return err
	}
	var escaped bytes.Buffer
	if err := xml.EscapeText(&escaped, []byte(binary)); err != nil {
		return err
	}
	plist := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>%s</string>
<key>ProgramArguments</key><array><string>%s</string><string>run</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
</dict></plist>
`, label, escaped.String())
	path := filepath.Join(agents, label+".plist")
	if err := os.WriteFile(path, []byte(plist), 0600); err != nil {
		return err
	}
	domain := fmt.Sprintf("gui/%d", os.Getuid())
	if exec.Command("/bin/launchctl", "print", domain+"/"+label).Run() == nil {
		return nil
	}
	return exec.Command("/bin/launchctl", "bootstrap", domain, path).Run()
}
