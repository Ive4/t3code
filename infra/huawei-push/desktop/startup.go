package main

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"runtime"
)

func installBackground(dir string) error {
	source, err := os.Executable()
	if err != nil {
		return err
	}
	name := "t3-huawei-push"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	binary := filepath.Join(dir, name)
	if source != binary {
		if err := copyExecutable(source, binary); err != nil {
			return err
		}
	}
	return startAtLogin(binary)
}

func copyExecutable(source, dest string) error {
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	if current, err := os.Stat(dest); err == nil {
		if original, err := input.Stat(); err == nil && os.SameFile(current, original) {
			return nil
		}
	}
	output, err := os.CreateTemp(filepath.Dir(dest), ".install-*")
	if err != nil {
		return err
	}
	defer os.Remove(output.Name())
	_, copyErr := io.Copy(output, input)
	modeErr := output.Chmod(0700)
	if err := errors.Join(copyErr, modeErr, output.Close()); err != nil {
		return err
	}
	return os.Rename(output.Name(), dest)
}
