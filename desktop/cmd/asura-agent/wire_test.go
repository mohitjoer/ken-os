package main

import (
	"os"
	"path/filepath"
	"testing"
)

// setupTestEnv sets up an isolated temporary HOME and mock asura skills directory.
func setupTestEnv(t *testing.T) (string, string) {
	t.Helper()

	tempHome := t.TempDir()
	t.Setenv("HOME", tempHome)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(tempHome, ".config"))

	skillsDir := t.TempDir()
	asuraSkillDir := filepath.Join(skillsDir, "asura")
	if err := os.MkdirAll(asuraSkillDir, 0o755); err != nil {
		t.Fatal(err)
	}

	skillMD := `---
name: asura
description: Asura OS agent skill
---
# Asura
`
	if err := os.WriteFile(filepath.Join(asuraSkillDir, "SKILL.md"), []byte(skillMD), 0o644); err != nil {
		t.Fatal(err)
	}

	t.Setenv("ASURA_SKILLS_DIR", asuraSkillDir)
	return tempHome, asuraSkillDir
}

func assertSymlink(t *testing.T, linkPath, expectedTarget string) {
	t.Helper()
	fi, err := os.Lstat(linkPath)
	if err != nil {
		t.Fatalf("expected symlink at %s: %v", linkPath, err)
	}
	if fi.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("%s is not a symlink", linkPath)
	}
	target, err := os.Readlink(linkPath)
	if err != nil {
		t.Fatalf("failed to read symlink %s: %v", linkPath, err)
	}
	if filepath.Clean(target) != filepath.Clean(expectedTarget) {
		t.Fatalf("symlink %s points to %q, want %q", linkPath, target, expectedTarget)
	}
}

func TestWireAllAgents(t *testing.T) {
	h, skillDir := setupTestEnv(t)

	n, err := Wire("")
	if err != nil {
		t.Fatalf("Wire(\"\") failed: %v", err)
	}
	if n != 4 {
		t.Fatalf("Wire(\"\") wired %d agents, want 4", n)
	}

	assertSymlink(t, filepath.Join(h, ".config", "opencode", "skills", "asura"), skillDir)
	assertSymlink(t, filepath.Join(h, ".pi", "agent", "skills", "asura"), skillDir)
	assertSymlink(t, filepath.Join(h, ".claude", "skills", "asura"), skillDir)
	assertSymlink(t, filepath.Join(h, ".gemini", "skills", "asura"), skillDir)

	// Test idempotency: wiring again must succeed without error
	n2, err := Wire("")
	if err != nil {
		t.Fatalf("second Wire(\"\") failed: %v", err)
	}
	if n2 != 4 {
		t.Fatalf("second Wire(\"\") returned %d, want 4", n2)
	}
	assertSymlink(t, filepath.Join(h, ".claude", "skills", "asura"), skillDir)
}

func TestWireSingleAgent(t *testing.T) {
	h, skillDir := setupTestEnv(t)

	n, err := Wire("claude")
	if err != nil {
		t.Fatalf("Wire(\"claude\") failed: %v", err)
	}
	if n != 1 {
		t.Fatalf("Wire(\"claude\") wired %d, want 1", n)
	}

	assertSymlink(t, filepath.Join(h, ".claude", "skills", "asura"), skillDir)

	// Other agents should not be wired yet
	if _, err := os.Lstat(filepath.Join(h, ".config", "opencode", "skills", "asura")); !os.IsNotExist(err) {
		t.Fatalf("opencode skill should not exist yet")
	}
}

func TestUnwireAgents(t *testing.T) {
	h, _ := setupTestEnv(t)

	if _, err := Wire(""); err != nil {
		t.Fatalf("initial Wire failed: %v", err)
	}

	// Unwire single agent
	n, err := Unwire("opencode")
	if err != nil {
		t.Fatalf("Unwire(\"opencode\") failed: %v", err)
	}
	if n != 1 {
		t.Fatalf("Unwire(\"opencode\") unwired %d, want 1", n)
	}

	if _, err := os.Lstat(filepath.Join(h, ".config", "opencode", "skills", "asura")); !os.IsNotExist(err) {
		t.Fatalf("opencode skill was not removed")
	}

	// Claude should still be wired
	if _, err := os.Lstat(filepath.Join(h, ".claude", "skills", "asura")); err != nil {
		t.Fatalf("claude skill should still exist")
	}

	// Unwire all remaining
	if _, err := Unwire(""); err != nil {
		t.Fatalf("Unwire(\"\") failed: %v", err)
	}

	for _, d := range SupportedAgents() {
		if _, err := os.Lstat(d.SkillPath()); !os.IsNotExist(err) {
			t.Fatalf("skill for %s should be removed", d.ID)
		}
	}
}

func TestSymlinkSafetyWithForeignLink(t *testing.T) {
	h, skillDir := setupTestEnv(t)

	// Create a foreign directory and symlink
	foreignDir := t.TempDir()
	claudeSkill := filepath.Join(h, ".claude", "skills", "asura")
	if err := os.MkdirAll(filepath.Dir(claudeSkill), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(foreignDir, claudeSkill); err != nil {
		t.Fatal(err)
	}

	// Unwire should NOT remove foreign link
	if _, err := Unwire("claude"); err != nil {
		t.Fatalf("Unwire: %v", err)
	}
	if _, err := os.Lstat(claudeSkill); os.IsNotExist(err) {
		t.Fatalf("foreign symlink was unexpectedly removed")
	}

	// But Wire should replace it cleanly with ours
	if _, err := Wire("claude"); err != nil {
		t.Fatalf("Wire over foreign link failed: %v", err)
	}
	assertSymlink(t, claudeSkill, skillDir)
}

func TestSymlinkSafetyWithRealDir(t *testing.T) {
	h, _ := setupTestEnv(t)

	claudeSkill := filepath.Join(h, ".claude", "skills", "asura")
	if err := os.MkdirAll(claudeSkill, 0o755); err != nil {
		t.Fatal(err)
	}

	// If there's an actual directory there, symlinkForce should refuse to clobber
	_, err := Wire("claude")
	if err == nil {
		t.Fatalf("expected error when wiring over a real directory")
	}
}

func TestDetectAgents(t *testing.T) {
	_, _ = setupTestEnv(t)

	agents := DetectAgents()
	if len(agents) != 4 {
		t.Fatalf("DetectAgents returned %d, want 4", len(agents))
	}

	for _, a := range agents {
		if a.Wired {
			t.Fatalf("agent %s should not be wired initially", a.ID)
		}
	}

	if _, err := Wire("gemini"); err != nil {
		t.Fatal(err)
	}

	agentsAfter := DetectAgents()
	for _, a := range agentsAfter {
		if a.ID == "gemini" && !a.Wired {
			t.Fatalf("gemini should be wired after Wire(\"gemini\")")
		}
		if a.ID != "gemini" && a.Wired {
			t.Fatalf("agent %s should not be wired", a.ID)
		}
	}
}
