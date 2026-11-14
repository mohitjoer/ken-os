package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGpuMuxNeedsSubcommand(t *testing.T) {
	err := runGpuMux(nil)
	if err == nil {
		t.Fatal("expected error with no arguments, got nil")
	}
}

func TestGpuMuxSetRequiresMode(t *testing.T) {
	err := runGpuMux([]string{"set"})
	if err == nil {
		t.Fatal("expected error with no mode, got nil")
	}
}

func TestGpuMuxMockGet(t *testing.T) {
	tmp := t.TempDir()
	bin := filepath.Join(tmp, "asura-gpu")
	script := `#!/bin/sh
if [ "$1" = "mux" ] && [ "$2" = "get" ]; then
    echo '{"capable":true,"mode":"hybrid","reboot_pending":false}'
    exit 0
fi
exit 1
`
	if err := os.WriteFile(bin, []byte(script), 0755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("ASURA_GPU_BIN", bin)
	t.Setenv("PATH", tmp+":"+os.Getenv("PATH"))

	if err := runGpuMux([]string{"get"}); err != nil {
		t.Fatalf("runGpuMux get failed: %v", err)
	}
}
