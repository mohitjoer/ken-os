package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"asura/desktop/internal/overlay"
	"asura/desktop/internal/runner"
)

// asuraUpdate runs the complete Void Linux system update lifecycle.
//
// Lifecycle sequence:
//  1. Snapshot ~/.config to git AND create an atomic Btrfs root snapshot
//     (/.snapshots/pre-update-<timestamp>) if / is on Btrfs.
//  2. Run system package updates via xbps-install -Su -y (routing through
//     asura-sysd socket /run/asura/sysd.sock or sudo xbps-install -Su -y).
//  3. Update installed Flatpaks via flatpak update -y (if flatpak is present).
//  4. Re-materialize the /usr/share/asura/ base overlay with ~/.config/asura/user_edits/
//     and trigger a live shell/daemon reload.
func asuraUpdate(args []string) int {
	set := newFlags("update", updateUsage)
	var (
		root       = set.String("root", "", "operate on a tree under this directory")
		dryRun     = set.Bool("dry-run", false, "do the snapshot and preserve steps, fetch nothing")
		noSnapshot = set.Bool("no-snapshot", false, "skip the config snapshot")
		unstable   = set.Bool("unstable", false, "pull the latest code from the dev-unstable branch")
		branch     = set.String("branch", "", "git branch to pull code updates from (default: dev-unstable)")
		channel    = set.String("channel", "", "channel to update from (stable, unstable, dev-unstable)")
		system     = set.Bool("system", false, "force update of all system packages (XBPS)")
		asuraOnly  = set.Bool("asura-only", false, "only update ASURA packages and desktop components")
	)
	if err := set.Parse(args); err != nil {
		return exitUsage
	}

	targetBranch := ""
	if *unstable {
		targetBranch = "dev-unstable"
	} else if *branch != "" {
		targetBranch = *branch
	} else if *channel == "unstable" || *channel == "dev-unstable" {
		targetBranch = "dev-unstable"
	} else {
		if ch, err := xbpsChannel(*root); err == nil {
			if ch == "unstable" || ch == "dev-unstable" {
				targetBranch = "dev-unstable"
			}
		}
	}

	paths, err := overlayPaths(*root)
	if err != nil {
		fmt.Fprintln(os.Stderr, "asura update:", err)
		return exitFail
	}

	isRoot := os.Geteuid() == 0
	updateSystemPkgs := (isRoot || *system) && !*asuraOnly

	var snapshot func(overlay.Paths) error
	if !*noSnapshot {
		snapshot = func(p overlay.Paths) error {
			if err := gitSnapshot(p); err != nil {
				return err
			}
			if !*dryRun && updateSystemPkgs {
				if snap, err := createBtrfsSnapshot(); err != nil {
					fmt.Fprintf(os.Stderr, "asura update: btrfs snapshot: %v\n", err)
				} else if snap != "" {
					fmt.Printf("created system Btrfs snapshot: %s\n", snap)
				}
			}
			return nil
		}
	}

	var fetch func() error
	if !*dryRun {
		fetch = func() error {
			// Step: Update ASURA git code and packages
			if targetBranch != "" {
				fmt.Printf("==> Updating ASURA packages from '%s' branch...\n", targetBranch)
				if err := pullGitUpdates(targetBranch, *root); err != nil {
					fmt.Fprintf(os.Stderr, "asura update: git pull warning: %v\n", err)
				} else {
					fmt.Printf("==> Successfully updated ASURA packages from '%s'\n", targetBranch)
				}
			} else {
				// If a local source repo exists, pull and sync updates
				if repo, err := findOrCloneRepo("dev-unstable"); err == nil && repo != "" {
					fmt.Printf("==> Updating ASURA components from local repository (%s)...\n", repo)
					_ = pullGitUpdates("dev-unstable", *root)
				}
			}

			// Full system package update via XBPS (only when root or --system)
			if updateSystemPkgs {
				return voidFetch()
			}
			return nil
		}
	} else {
		fetch = nil
	}

	// Step 1 & 2 & 4: snapshot, package update, and re-materialization
	if err := overlay.Update(paths, snapshot, fetch); err != nil {
		fmt.Fprintln(os.Stderr, "asura update:", err)
		return exitFail
	}

	// Step 3: Flatpak updates (if flatpak is present)
	if !*dryRun {
		updateFlatpaks()
	}

	// Regenerate GRUB so the new Btrfs snapshot gets a boot entry (only on system updates)
	if !*dryRun && updateSystemPkgs && isBtrfsRoot() {
		if _, err := exec.LookPath("grub-mkconfig"); err == nil {
			fmt.Println("==> Regenerating GRUB boot menu (snapshot entries)...")
			cmd := exec.Command("grub-mkconfig", "-o", "/boot/grub/grub.cfg")
			cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
			if err := cmd.Run(); err != nil {
				fmt.Fprintf(os.Stderr, "asura update: grub-mkconfig: %v\n", err)
			}
		}
	}

	status, err := overlay.StatusOf(paths)
	if err != nil {
		fmt.Fprintln(os.Stderr, "asura update:", err)
		return exitFail
	}
	fmt.Printf("updated to revision %s\n", status.Revision)
	fmt.Printf("config materialized; %d user edit(s), %d stale, %d missing\n",
		status.Edits, status.Stale, status.Missing)

	// Step 4b: Reconcile shell config and trigger live reload
	if msg, err := reconcileShellConfig(filepath.Join(paths.Config, "shell.json"), true); err != nil {
		fmt.Fprintln(os.Stderr, "asura update:", err)
	} else if msg != "" {
		fmt.Println(msg)
	}

	if !*dryRun {
		fmt.Println("triggering live shell and service reload...")
		reloadMain(nil, os.Stdout, os.Stderr, runner.Exec(15*time.Second))
	}

	if !updateSystemPkgs {
		fmt.Println("\n--------------------------------------------------------------------------------")
		fmt.Println("==> ASURA packages and desktop components are up to date.")
		fmt.Println("==> Recommendation: To update all base system packages (XBPS) and OS, run:")
		fmt.Println("    sudo asura update")
		fmt.Println("--------------------------------------------------------------------------------")
	} else {
		fmt.Println("\n==> Full system and ASURA update complete.")
	}

	return exitOK
}

// voidFetch executes the system package update via Void Linux XBPS.
// It first attempts to route through the privileged asura-sysd socket.
// If the daemon is not active, it falls back to direct xbps-install.
func voidFetch() error {
	fmt.Println("==> Step 2/4: Updating system packages (XBPS)...")

	// Try sysd socket first
	if err := runSysdPkgUpdate(); err == nil {
		fmt.Println("system packages updated via asura-sysd")
		return nil
	}

	// Fallback to local xbps-install command
	return runLocalXbpsUpdate()
}

// runSysdPkgUpdate communicates with asura-sysd over /run/asura/sysd.sock.
func runSysdPkgUpdate() error {
	conn, err := net.DialTimeout("unix", "/run/asura/sysd.sock", 2*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()

	req := struct {
		Action string `json:"action"`
	}{
		Action: "pkg_update",
	}
	data, err := json.Marshal(req)
	if err != nil {
		return err
	}
	if _, err := conn.Write(append(data, '\n')); err != nil {
		return err
	}

	scanner := bufio.NewScanner(conn)
	if scanner.Scan() {
		var res struct {
			Status  string `json:"status"`
			Message string `json:"message"`
		}
		if err := json.Unmarshal(scanner.Bytes(), &res); err != nil {
			return err
		}
		if res.Status != "ok" {
			return fmt.Errorf("sysd returned error: %s", res.Message)
		}
		return nil
	}
	return fmt.Errorf("no response from asura-sysd")
}

// runLocalXbpsUpdate executes xbps-install -Su -y locally with privilege elevation.
func runLocalXbpsUpdate() error {
	sudo := "sudo"
	if os.Geteuid() == 0 {
		sudo = ""
	}

	execCommand := func(prog string, args ...string) *exec.Cmd {
		if sudo != "" {
			fullArgs := append([]string{prog}, args...)
			return exec.Command(sudo, fullArgs...)
		}
		return exec.Command(prog, args...)
	}

	syncCmd := execCommand("xbps-install", "-Su", "-y")
	syncCmd.Stdout, syncCmd.Stderr, syncCmd.Stdin = os.Stdout, os.Stderr, os.Stdin
	if err := syncCmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 8 {
			fmt.Fprintf(os.Stderr, "\n==> XBPS Warning: package transaction aborted due to unresolved shared libraries.\n")
			fmt.Fprintf(os.Stderr, "==> Third-party repository (hyprland-void) has packages awaiting base system library rebuilds.\n")
			fmt.Fprintf(os.Stderr, "==> Attempting fallback: holding mismatched third-party packages to update remaining system packages...\n")

			holdCmd := execCommand("xbps-pkgdb", "-m", "hold", "aquamarine", "hyprgraphics", "hyprland")
			_ = holdCmd.Run()

			retryCmd := execCommand("xbps-install", "-Su", "-y")
			retryCmd.Stdout, retryCmd.Stderr, retryCmd.Stdin = os.Stdout, os.Stderr, os.Stdin
			if retryErr := retryCmd.Run(); retryErr == nil {
				fmt.Println("==> System packages updated successfully (mismatched third-party packages held).")
				return nil
			}

			fmt.Fprintf(os.Stderr, "\n==> Note: Base system update deferred until upstream library transitions complete.\n")
			fmt.Fprintf(os.Stderr, "==> Continuing ASURA desktop update...\n\n")
			return nil
		}
		return fmt.Errorf("xbps-install: %w", err)
	}
	return nil
}

// updateFlatpaks executes flatpak update -y if Flatpak is installed.
func updateFlatpaks() {
	if _, err := exec.LookPath("flatpak"); err != nil {
		return
	}
	fmt.Println("==> Step 3/4: Updating installed Flatpak applications & runtimes...")
	cmd := exec.Command("flatpak", "update", "-y")
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	_ = cmd.Run()
}

// isBtrfsRoot checks if the root filesystem is Btrfs.
func isBtrfsRoot() bool {
	data, err := os.ReadFile("/proc/mounts")
	if err != nil {
		out, err := exec.Command("stat", "-f", "-c", "%T", "/").Output()
		return err == nil && strings.TrimSpace(string(out)) == "btrfs"
	}
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 3 && fields[1] == "/" && fields[2] == "btrfs" {
			return true
		}
	}
	return false
}

// createBtrfsSnapshot creates an atomic read-only snapshot of root in /.snapshots/.
func createBtrfsSnapshot() (string, error) {
	if !isBtrfsRoot() {
		return "", nil
	}
	if _, err := exec.LookPath("btrfs"); err != nil {
		return "", nil
	}

	snapDir := "/.snapshots"
	timestamp := time.Now().Format("20060102-150405")
	snapName := "pre-update-" + timestamp
	snapPath := filepath.Join(snapDir, snapName)

	sudo := "sudo"
	if os.Geteuid() == 0 {
		sudo = ""
	}

	// Ensure /.snapshots directory exists
	var mkdirCmd *exec.Cmd
	if sudo != "" {
		mkdirCmd = exec.Command(sudo, "mkdir", "-p", snapDir)
	} else {
		mkdirCmd = exec.Command("mkdir", "-p", snapDir)
	}
	_ = mkdirCmd.Run()

	var snapCmd *exec.Cmd
	if sudo != "" {
		snapCmd = exec.Command(sudo, "btrfs", "subvolume", "snapshot", "-r", "/", snapPath)
	} else {
		snapCmd = exec.Command("btrfs", "subvolume", "snapshot", "-r", "/", snapPath)
	}

	out, err := snapCmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%s (%s)", err, strings.TrimSpace(string(out)))
	}
	return snapPath, nil
}

const defaultGitRepoURL = "https://github.com/mohitjoer/ASURA-OS.git"

// pullGitUpdates fetches the latest changes from the specified branch and updates base files.
func pullGitUpdates(branch string, root string) error {
	repoDir, err := findOrCloneRepo(branch)
	if err != nil {
		return fmt.Errorf("locating Asura repository: %w", err)
	}

	fmt.Printf("==> Pulling latest changes from branch '%s' in %s...\n", branch, repoDir)

	fetchCmd := exec.Command("git", "-c", "safe.directory=*", "-C", repoDir, "fetch", "origin", branch)
	fetchCmd.Stdout, fetchCmd.Stderr = os.Stdout, os.Stderr
	if err := fetchCmd.Run(); err != nil {
		return fmt.Errorf("git fetch: %w", err)
	}

	checkoutCmd := exec.Command("git", "-c", "safe.directory=*", "-C", repoDir, "checkout", branch)
	checkoutCmd.Stdout, checkoutCmd.Stderr = os.Stdout, os.Stderr
	_ = checkoutCmd.Run()

	pullCmd := exec.Command("git", "-c", "safe.directory=*", "-C", repoDir, "pull", "--ff-only", "origin", branch)
	pullCmd.Stdout, pullCmd.Stderr = os.Stdout, os.Stderr
	if err := pullCmd.Run(); err != nil {
		return fmt.Errorf("git pull: %w", err)
	}

	// Update base files in /usr/share/asura/
	baseDir := filepath.Join(root, "/usr/share/asura")
	if _, err := os.Stat(baseDir); err == nil {
		fmt.Println("==> Syncing updated code into /usr/share/asura/...")
		for _, sub := range []string{"shell", "hyprland", "apps", "session"} {
			src := filepath.Join(repoDir, sub)
			dst := filepath.Join(baseDir, sub)
			_ = sudoCopyDir(src, dst)
		}
		// Also sync helpers
		helperSrc := filepath.Join(repoDir, "system", "helpers", "asura-gpu")
		if _, err := os.Stat(helperSrc); err == nil {
			dstHelper := filepath.Join(root, "/usr/bin/asura-gpu")
			sudo := "sudo"
			if os.Geteuid() == 0 {
				sudo = ""
			}
			if sudo != "" {
				_ = exec.Command(sudo, "cp", helperSrc, dstHelper).Run()
				_ = exec.Command(sudo, "chmod", "755", dstHelper).Run()
			} else {
				_ = exec.Command("cp", helperSrc, dstHelper).Run()
				_ = exec.Command("chmod", "755", dstHelper).Run()
			}
		}
	}

	return nil
}

func findOrCloneRepo(branch string) (string, error) {
	// 1. Check ASURA_SRC_DIR environment variable override
	if env := os.Getenv("ASURA_SRC_DIR"); env != "" && isAsuraRepo(env) {
		return env, nil
	}

	// 2. Check current directory or git root
	if out, err := exec.Command("git", "rev-parse", "--show-toplevel").Output(); err == nil {
		top := strings.TrimSpace(string(out))
		if isAsuraRepo(top) {
			return top, nil
		}
	}

	// 3. Check well-known local paths
	home := os.Getenv("HOME")
	candidates := []string{
		filepath.Join(home, "code", "ASURA-OS"),
		filepath.Join(home, "code", "asura", "ASURA-OS"),
		filepath.Join(home, "ASURA-OS"),
		"/usr/src/asura",
		"/usr/share/asura",
		"/var/cache/asura/source",
	}
	if sudoUser := os.Getenv("SUDO_USER"); sudoUser != "" && sudoUser != "root" {
		userHome := filepath.Join("/home", sudoUser)
		candidates = append([]string{
			filepath.Join(userHome, "code", "ASURA-OS"),
			filepath.Join(userHome, "code", "asura", "ASURA-OS"),
			filepath.Join(userHome, "ASURA-OS"),
		}, candidates...)
	}
	for _, c := range candidates {
		if isAsuraRepo(c) {
			return c, nil
		}
	}

	// 4. Clone to cache directory if not found locally
	cacheDir := filepath.Join(home, ".cache", "asura", "source")
	if os.Geteuid() == 0 {
		cacheDir = "/var/cache/asura/source"
	}
	if err := os.MkdirAll(filepath.Dir(cacheDir), 0o755); err != nil {
		return "", err
	}

	if _, err := os.Stat(filepath.Join(cacheDir, ".git")); os.IsNotExist(err) {
		fmt.Printf("==> Cloning Asura OS repository (%s) into %s...\n", branch, cacheDir)
		cmd := exec.Command("git", "clone", "--depth", "1", "--branch", branch, defaultGitRepoURL, cacheDir)
		cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
		if err := cmd.Run(); err != nil {
			return "", fmt.Errorf("git clone failed: %w", err)
		}
		return cacheDir, nil
	}

	return cacheDir, nil
}

func isAsuraRepo(path string) bool {
	if path == "" {
		return false
	}
	if _, err := os.Stat(filepath.Join(path, ".git")); err != nil {
		return false
	}
	if _, err := os.Stat(filepath.Join(path, "shell", "hub")); err == nil {
		return true
	}
	return false
}

func sudoCopyDir(src, dst string) error {
	if _, err := os.Stat(src); err != nil {
		return nil
	}
	sudo := "sudo"
	if os.Geteuid() == 0 {
		sudo = ""
	}
	var mkdirCmd *exec.Cmd
	if sudo != "" {
		mkdirCmd = exec.Command(sudo, "mkdir", "-p", dst)
	} else {
		mkdirCmd = exec.Command("mkdir", "-p", dst)
	}
	_ = mkdirCmd.Run()

	var cpCmd *exec.Cmd
	if sudo != "" {
		cpCmd = exec.Command(sudo, "cp", "-a", src+"/.", dst+"/")
	} else {
		cpCmd = exec.Command("cp", "-a", src+"/.", dst+"/")
	}
	return cpCmd.Run()
}
