//go:build windows

package main

import (
	"io"
	"os/exec"
	"strconv"
)

func configureChildCommand(cmd *exec.Cmd) {}

func stopChildCommand(cmd *exec.Cmd) {
	if cmd.Process == nil {
		return
	}
	if taskkill, err := exec.LookPath("taskkill.exe"); err == nil {
		kill := exec.Command(taskkill, "/T", "/F", "/PID", strconv.Itoa(cmd.Process.Pid))
		kill.Stdout = io.Discard
		kill.Stderr = io.Discard
		if kill.Run() == nil {
			return
		}
	}
	_ = cmd.Process.Kill()
}
