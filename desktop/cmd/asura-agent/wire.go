package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// AgentInfo describes a supported local coding agent harness.
type AgentInfo struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Binaries  []string `json:"binaries"`
	InPath    bool     `json:"inPath"`
	SkillPath string   `json:"skillPath"`
	Wired     bool     `json:"wired"`
}

// AgentDef defines how to resolve an agent's paths and detect its presence.
type AgentDef struct {
	ID        string
	Name      string
	Binaries  []string
	SkillPath func() string
}

func getHome() string {
	if h := os.Getenv("HOME"); h != "" {
		return h
	}
	return "/root"
}

func getConfigHome() string {
	if c := os.Getenv("XDG_CONFIG_HOME"); c != "" {
		return c
	}
	return filepath.Join(getHome(), ".config")
}

// SupportedAgents returns the definitions for all recognized local coding agents.
func SupportedAgents() []AgentDef {
	return []AgentDef{
		{
			ID:       "opencode",
			Name:     "OpenCode CLI",
			Binaries: []string{"opencode"},
			SkillPath: func() string {
				return filepath.Join(getConfigHome(), "opencode", "skills", "asura")
			},
		},
		{
			ID:       "pi",
			Name:     "Pi coding agent",
			Binaries: []string{"pi"},
			SkillPath: func() string {
				return filepath.Join(getHome(), ".pi", "agent", "skills", "asura")
			},
		},
		{
			ID:       "claude",
			Name:     "Claude Code",
			Binaries: []string{"claude"},
			SkillPath: func() string {
				return filepath.Join(getHome(), ".claude", "skills", "asura")
			},
		},
		{
			ID:       "gemini",
			Name:     "Gemini CLI / Antigravity",
			Binaries: []string{"gemini", "antigravity", "agy"},
			SkillPath: func() string {
				return filepath.Join(getHome(), ".gemini", "skills", "asura")
			},
		},
	}
}

// ResolveSkillSource locates the asura skill directory.
// Priority:
// 1. ASURA_SKILLS_DIR environment override
// 2. Packaged system skill at /usr/share/asura/shell/agent/skills/asura
// 3. Repository checkout fallback (shell/agent/skills/asura)
func ResolveSkillSource() (string, error) {
	if env := os.Getenv("ASURA_SKILLS_DIR"); env != "" {
		p := filepath.Join(env, "asura")
		if isValidSkillDir(p) {
			return p, nil
		}
		if isValidSkillDir(env) {
			return env, nil
		}
	}

	sysDir := "/usr/share/asura/shell/agent/skills/asura"
	if isValidSkillDir(sysDir) {
		return sysDir, nil
	}

	candidates := []string{
		"shell/agent/skills/asura",
		"../shell/agent/skills/asura",
		"../../shell/agent/skills/asura",
	}

	if pwd, err := os.Getwd(); err == nil {
		candidates = append(candidates,
			filepath.Join(pwd, "shell", "agent", "skills", "asura"),
			filepath.Join(pwd, "..", "shell", "agent", "skills", "asura"),
			filepath.Join(pwd, "..", "..", "shell", "agent", "skills", "asura"),
		)
	}

	if exe, err := os.Executable(); err == nil {
		exeDir := filepath.Dir(exe)
		candidates = append(candidates,
			filepath.Join(exeDir, "..", "shell", "agent", "skills", "asura"),
			filepath.Join(exeDir, "..", "..", "shell", "agent", "skills", "asura"),
			filepath.Join(exeDir, "..", "..", "..", "shell", "agent", "skills", "asura"),
		)
	}

	for _, c := range candidates {
		clean := filepath.Clean(c)
		if isValidSkillDir(clean) {
			if abs, err := filepath.Abs(clean); err == nil {
				return abs, nil
			}
			return clean, nil
		}
	}

	return "", fmt.Errorf("could not locate Asura skill directory (checked %s and repo fallbacks)", sysDir)
}

func isValidSkillDir(dir string) bool {
	skillFile := filepath.Join(dir, "SKILL.md")
	f, err := os.Open(skillFile)
	if err != nil {
		return false
	}
	defer f.Close()

	buf := make([]byte, 512)
	n, _ := f.Read(buf)
	content := string(buf[:n])
	for _, line := range strings.Split(content, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "name: asura" {
			return true
		}
	}
	return false
}

// isOurSkillLink checks if a link points to a valid asura skill directory.
func isOurSkillLink(link string) bool {
	fi, err := os.Lstat(link)
	if err != nil || fi.Mode()&os.ModeSymlink == 0 {
		return false
	}
	dest, err := os.Readlink(link)
	if err != nil {
		return false
	}
	if !filepath.IsAbs(dest) {
		dest = filepath.Join(filepath.Dir(link), dest)
	}
	return isValidSkillDir(filepath.Clean(dest))
}

// symlinkForce idempotently points link to target.
// Returns (createdOrUpdated, error).
func symlinkForce(link, target string) (bool, error) {
	fi, err := os.Lstat(link)
	if err == nil {
		if fi.Mode()&os.ModeSymlink == 0 {
			return false, fmt.Errorf("%s exists and is a regular file/directory, refusing to overwrite", link)
		}
		dest, readErr := os.Readlink(link)
		if readErr == nil {
			absDest := dest
			if !filepath.IsAbs(absDest) {
				absDest = filepath.Join(filepath.Dir(link), absDest)
			}
			if filepath.Clean(absDest) == filepath.Clean(target) {
				return false, nil // Already wired identically
			}
		}
		// If existing symlink is ours or broken, remove and replace
		if isOurSkillLink(link) || readErr != nil {
			if rmErr := os.Remove(link); rmErr != nil {
				return false, rmErr
			}
		} else {
			// Foreign symlink - replace only if pointing to non-existent or foreign
			if rmErr := os.Remove(link); rmErr != nil {
				return false, rmErr
			}
		}
	} else if !os.IsNotExist(err) {
		return false, err
	}

	if err := os.MkdirAll(filepath.Dir(link), 0o755); err != nil {
		return false, err
	}
	if err := os.Symlink(target, link); err != nil {
		return false, err
	}
	return true, nil
}

// DetectAgents inspects the system for each supported agent and its wiring status.
func DetectAgents() []AgentInfo {
	defs := SupportedAgents()
	out := make([]AgentInfo, 0, len(defs))

	for _, d := range defs {
		inPath := false
		for _, bin := range d.Binaries {
			if _, err := exec.LookPath(bin); err == nil {
				inPath = true
				break
			}
		}

		skillPath := d.SkillPath()
		wired := isOurSkillLink(skillPath)

		out = append(out, AgentInfo{
			ID:        d.ID,
			Name:      d.Name,
			Binaries:  d.Binaries,
			InPath:    inPath,
			SkillPath: skillPath,
			Wired:     wired,
		})
	}

	return out
}

// Wire links the Asura skill directory into one agent or all agents.
func Wire(agentID string) (int, error) {
	src, err := ResolveSkillSource()
	if err != nil {
		return 0, err
	}

	defs := SupportedAgents()
	count := 0

	for _, d := range defs {
		if agentID != "" && d.ID != agentID {
			continue
		}
		link := d.SkillPath()
		created, err := symlinkForce(link, src)
		if err != nil {
			return count, fmt.Errorf("wiring %s (%s): %w", d.ID, link, err)
		}
		if created {
			fmt.Printf("wired %s -> %s\n", d.ID, tildeAbbrev(link))
		} else {
			fmt.Printf("already wired %s -> %s\n", d.ID, tildeAbbrev(link))
		}
		count++
	}

	if agentID != "" && count == 0 {
		return 0, fmt.Errorf("unknown agent %q (supported: opencode, pi, claude, gemini)", agentID)
	}

	return count, nil
}

// Unwire removes the Asura skill symlink for one agent or all agents.
func Unwire(agentID string) (int, error) {
	defs := SupportedAgents()
	count := 0

	for _, d := range defs {
		if agentID != "" && d.ID != agentID {
			continue
		}
		link := d.SkillPath()
		if isOurSkillLink(link) {
			if err := os.Remove(link); err != nil {
				return count, fmt.Errorf("unwiring %s (%s): %w", d.ID, link, err)
			}
			fmt.Printf("unwired %s (removed %s)\n", d.ID, tildeAbbrev(link))
			count++
		} else {
			fmt.Printf("not wired %s (%s)\n", d.ID, tildeAbbrev(link))
		}
	}

	if agentID != "" && count == 0 && !isValidAgentID(agentID) {
		return 0, fmt.Errorf("unknown agent %q (supported: opencode, pi, claude, gemini)", agentID)
	}

	return count, nil
}

func isValidAgentID(id string) bool {
	for _, d := range SupportedAgents() {
		if d.ID == id {
			return true
		}
	}
	return false
}

func tildeAbbrev(path string) string {
	h := getHome()
	if strings.HasPrefix(path, h) {
		return "~" + path[len(h):]
	}
	return path
}

// Status prints the detection and wiring status of all agents.
func Status(asJSON bool) error {
	agents := DetectAgents()
	if asJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(agents)
	}

	fmt.Printf("%-10s %-25s %-9s %-7s %s\n", "AGENT", "NAME", "IN PATH", "WIRED", "SKILL PATH")
	for _, a := range agents {
		inPathStr := "no"
		if a.InPath {
			inPathStr = "yes"
		}
		wiredStr := "no"
		if a.Wired {
			wiredStr = "yes"
		}
		fmt.Printf("%-10s %-25s %-9s %-7s %s\n", a.ID, a.Name, inPathStr, wiredStr, tildeAbbrev(a.SkillPath))
	}
	return nil
}
