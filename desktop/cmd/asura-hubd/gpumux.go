package main

import (
	"fmt"
	"os"
	"os/exec"
)

// runGpuMux routes `asura-hubd gpu mux get|set` to the asura-gpu helper.
// The Hub GPU page polls `gpu mux get` to detect if the laptop has a
// hardware display-routing switch (e.g. ASUS ROG / TUF WMI mux, Lenovo Legion,
// apple-gmux, or vga_switcheroo), and displays the Hybrid/Discrete switch if capable.
func runGpuMux(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("gpu mux needs get|set")
	}
	bin := asuraGpuBin()
	switch args[0] {
	case "get":
		cmd := exec.Command(bin, "mux", "get")
		out, err := cmd.Output()
		if err != nil {
			return printJSON(map[string]any{"capable": false, "mode": "hybrid", "reboot_pending": false})
		}
		os.Stdout.Write(out)
		return nil
	case "set":
		if len(args) < 2 {
			return fmt.Errorf("gpu mux set needs hybrid|discrete")
		}
		cmd := exec.Command(bin, "mux", "set", args[1])
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	default:
		return fmt.Errorf("unknown gpu mux command: %s", args[0])
	}
}
