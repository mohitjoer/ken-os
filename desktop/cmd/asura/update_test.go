package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestIsAsuraRepo(t *testing.T) {
	tmp := t.TempDir()
	if isAsuraRepo(tmp) {
		t.Fatal("expected empty directory to not be Asura repo")
	}

	if err := os.Mkdir(filepath.Join(tmp, ".git"), 0o755); err != nil {
		t.Fatal(err)
	}
	if isAsuraRepo(tmp) {
		t.Fatal("expected .git without shell/hub to not be Asura repo")
	}

	if err := os.MkdirAll(filepath.Join(tmp, "shell", "hub"), 0o755); err != nil {
		t.Fatal(err)
	}
	if !isAsuraRepo(tmp) {
		t.Fatal("expected directory with .git and shell/hub to be Asura repo")
	}
}

func TestFindOrCloneRepoFromEnv(t *testing.T) {
	tmp := t.TempDir()
	if err := os.Mkdir(filepath.Join(tmp, ".git"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(tmp, "shell", "hub"), 0o755); err != nil {
		t.Fatal(err)
	}

	t.Setenv("ASURA_SRC_DIR", tmp)
	repo, err := findOrCloneRepo("dev-unstable")
	if err != nil {
		t.Fatalf("findOrCloneRepo failed: %v", err)
	}
	if repo != tmp {
		t.Fatalf("got %s, want %s", repo, tmp)
	}
}

func TestAsuraUpdateDryRunUnprivileged(t *testing.T) {
	tmp := t.TempDir()
	// Set up fixture paths
	configDir := filepath.Join(tmp, "home", ".config", "asura")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatal(err)
	}
	baseDir := filepath.Join(tmp, "usr", "share", "asura")
	if err := os.MkdirAll(baseDir, 0o755); err != nil {
		t.Fatal(err)
	}

	code := asuraUpdate([]string{"--root", tmp, "--dry-run", "--no-snapshot"})
	if code != exitOK {
		t.Fatalf("asura update unprivileged dry-run returned %d, want %d", code, exitOK)
	}
}
