package main

import (
	"fmt"
	"os"
)

const usage = `asura-agent: Asura OS local coding agent harness integration

Usage:
  asura-agent wire [agent]      Symlink the Asura skill suite into all or specified agent
  asura-agent unwire [agent]    Remove the Asura skill symlink from all or specified agent
  asura-agent status [--json]   Report detection in PATH and wiring status of local agents

Supported agents:
  opencode    OpenCode CLI (~/.config/opencode/skills/asura)
  pi          Pi coding agent (~/.pi/agent/skills/asura)
  claude      Claude Code (~/.claude/skills/asura)
  gemini      Gemini CLI / Antigravity (~/.gemini/skills/asura)
`

func main() {
	if len(os.Args) < 2 {
		fmt.Print(usage)
		os.Exit(2)
	}

	switch os.Args[1] {
	case "wire":
		agent := ""
		if len(os.Args) > 2 {
			agent = os.Args[2]
		}
		if _, err := Wire(agent); err != nil {
			fmt.Fprintf(os.Stderr, "asura-agent wire: %v\n", err)
			os.Exit(1)
		}
	case "unwire":
		agent := ""
		if len(os.Args) > 2 {
			agent = os.Args[2]
		}
		if _, err := Unwire(agent); err != nil {
			fmt.Fprintf(os.Stderr, "asura-agent unwire: %v\n", err)
			os.Exit(1)
		}
	case "status":
		asJSON := false
		for _, arg := range os.Args[2:] {
			if arg == "--json" {
				asJSON = true
			}
		}
		if err := Status(asJSON); err != nil {
			fmt.Fprintf(os.Stderr, "asura-agent status: %v\n", err)
			os.Exit(1)
		}
	case "-h", "--help", "help":
		fmt.Print(usage)
		os.Exit(0)
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n\n", os.Args[1])
		fmt.Print(usage)
		os.Exit(2)
	}
}
