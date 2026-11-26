package main

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"strings"
	"syscall"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

func instanceLock(path string) (*os.File, error) {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	err = windows.LockFileEx(windows.Handle(file.Fd()), windows.LOCKFILE_EXCLUSIVE_LOCK|windows.LOCKFILE_FAIL_IMMEDIATELY, 0, 1, 0, &windows.Overlapped{})
	if err != nil {
		_ = file.Close()
		if errors.Is(err, windows.ERROR_LOCK_VIOLATION) {
			return nil, nil
		}
		return nil, err
	}
	return file, nil
}

func hideConsole(cmd *exec.Cmd) *exec.Cmd {
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: windows.CREATE_NO_WINDOW}
	return cmd
}

func pairingCommand(ctx context.Context, cli, home string) *exec.Cmd {
	if strings.HasSuffix(strings.ToLower(cli), ".cmd") {
		cmd := exec.CommandContext(ctx, "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", `
$pairArgs = @('pair','--scope','orchestration:read','--label','Huawei Push')
if ($env:T3_PUSH_PAIR_HOME) { $pairArgs += @('--base-dir', $env:T3_PUSH_PAIR_HOME) }
& $env:T3_PUSH_PAIR_CLI @pairArgs
exit $LASTEXITCODE
`)
		cmd.Env = append(os.Environ(), "T3_PUSH_PAIR_CLI="+cli, "T3_PUSH_PAIR_HOME="+home)
		return hideConsole(cmd)
	}
	args := []string{"pair", "--scope", "orchestration:read", "--label", "Huawei Push"}
	if home != "" {
		args = append(args, "--base-dir", home)
	}
	return hideConsole(exec.CommandContext(ctx, cli, args...))
}

func openBrowser(addr string) error {
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", `Start-Process -FilePath $env:T3_PUSH_SETUP_URL`)
	cmd.Env = append(os.Environ(), "T3_PUSH_SETUP_URL="+addr)
	return hideConsole(cmd).Run()
}

func startAtLogin(binary string) error {
	const run = `Software\Microsoft\Windows\CurrentVersion\Run`
	key, _, err := registry.CreateKey(registry.CURRENT_USER, run, registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer key.Close()
	if err := key.SetStringValue("T3HuaweiPush", `"`+binary+`" run`); err != nil {
		return err
	}
	cmd := hideConsole(exec.Command(binary, "run"))
	if err := cmd.Start(); err != nil {
		return err
	}
	return cmd.Process.Release()
}
