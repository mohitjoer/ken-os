#!/bin/sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$REPO_ROOT/installation/build-iso-void.sh"
MANIFEST="$REPO_ROOT/system/packages-void.yaml"

if [ ! -x "$SCRIPT" ]; then
	echo "build-iso-void_test: build-iso-void.sh is not executable" >&2
	exit 1
fi

if ! sh -n "$SCRIPT"; then
	echo "build-iso-void_test: shell syntax check failed on build-iso-void.sh" >&2
	exit 1
fi

if ! sh -n "$REPO_ROOT/session/runit/asura-user-services"; then
	echo "build-iso-void_test: shell syntax check failed on asura-user-services" >&2
	exit 1
fi

for run_script in "$REPO_ROOT/system/runit/user-services"/*/run "$REPO_ROOT/system/runit/services"/*/run "$REPO_ROOT/installation/asura-installer.sh"; do
	if ! sh -n "$run_script"; then
		echo "build-iso-void_test: shell syntax check failed on $run_script" >&2
		exit 1
	fi
done

if [ ! -f "$MANIFEST" ]; then
	echo "build-iso-void_test: system/packages-void.yaml missing" >&2
	exit 1
fi

grep -Fq 'system/packages-void.yaml' "$SCRIPT"
grep -Fq 'void-linux' "$SCRIPT"
grep -Fq 'asura-os-x86_64' "$SCRIPT"
grep -Fq -- '-k linux' "$SCRIPT"
grep -Fq 'LIBSEAT_BACKEND=seatd' "$SCRIPT"
grep -Fq 'void-mklive' "$SCRIPT"
grep -Fq 'asura-user-services' "$SCRIPT"
grep -Fq 'asura-sysd' "$SCRIPT"
grep -Fq 'asura-userd' "$SCRIPT"
grep -Fq 'etc/sv/asura-sysd' "$SCRIPT"
! grep -Fq 'NVreg_DynamicPowerManagement=0x02' "$SCRIPT"
grep -Fq '99-asura-power.rules' "$SCRIPT"
grep -Fq '99-asura-performance.conf' "$SCRIPT"
grep -Fq 'turnstile.conf' "$SCRIPT"
grep -Fq 'pam_elogind.so' "$SCRIPT"
grep -Fq '90-asura-powerkey.conf' "$SCRIPT"
grep -Fq 'system/xbps.d/asura.conf' "$SCRIPT"
grep -Fq 'boot-splash.png' "$SCRIPT"
grep -Fq 'Welcome to Asura OS!' "$SCRIPT"
grep -Fq 'nowatchdog mitigations=off preempt=full' "$SCRIPT"
grep -Fq 'os-ctl' "$SCRIPT"
grep -Fq 'etc/issue' "$SCRIPT"
grep -Fq 'etc/motd' "$SCRIPT"
grep -Fq 'DejaVuSans.ttf' "$SCRIPT"
grep -Fq 'plymouth --quit' "$SCRIPT"
grep -Fq 'asura-store' "$SCRIPT"
grep -Fq 'asura-store.desktop' "$SCRIPT"
grep -Fq 'asura-store' "$REPO_ROOT/shell/Services/Dock.qml"
test -s "$REPO_ROOT/session/applications/asura-store.desktop"

# Verify boot splash asset exists
if [ ! -f "$REPO_ROOT/public/branding/boot-splash.png" ]; then
	echo "build-iso-void_test: public/branding/boot-splash.png missing" >&2
	exit 1
fi

# Verify Plymouth splash theme assets exist and are valid non-empty files
for asset in logo.png window.png progress_box.png progress_bar.png asura.plymouth asura.script; do
	if [ ! -s "$REPO_ROOT/system/plymouth/asura/$asset" ]; then
		echo "build-iso-void_test: system/plymouth/asura/$asset missing or empty" >&2
		exit 1
	fi
done

# Verify udev power rules exist
if [ ! -s "$REPO_ROOT/system/udev/99-asura-power.rules" ]; then
	echo "build-iso-void_test: system/udev/99-asura-power.rules missing or empty" >&2
	exit 1
fi

# Verify packages in packages-void.yaml
grep -Fq 'base-system' "$MANIFEST"
grep -Fq 'linux' "$MANIFEST"
grep -Fq 'flatpak' "$MANIFEST"
grep -Fq 'hyprland' "$MANIFEST"
grep -Fq 'qt6-declarative' "$MANIFEST"
grep -Fq 'ghostty' "$MANIFEST"
grep -Fq 'pipewire' "$MANIFEST"
grep -Fq 'wireplumber' "$MANIFEST"
grep -Fq 'seatd' "$MANIFEST"
grep -Fq 'turnstile' "$MANIFEST"
! grep -Fq 'tlp' "$MANIFEST"
grep -Fq 'btrfs-progs' "$MANIFEST"
! grep -Fq 'gamemode' "$MANIFEST"
grep -Fq 'zramen' "$MANIFEST"
! grep -Fq 'scx' "$MANIFEST"
! grep -Fq 'scx-loader' "$MANIFEST"
grep -Fq 'mimalloc' "$MANIFEST"
grep -Fq 'podman' "$MANIFEST"
grep -Fq 'docker' "$MANIFEST"
test -x "$REPO_ROOT/system/helpers/systemctl"
test -x "$REPO_ROOT/system/helpers/journalctl"
grep -Fq 'systemctl' "$SCRIPT"

# LAYER 2: Verify Compiler, Kernel & Direct Hardware sysfs/udev
grep -Fq 'CONFIG_SCHED_BORE=y' "$REPO_ROOT/system/kernel/x86_64-dotconfig-asura"
grep -Fq 'CONFIG_HZ=1000' "$REPO_ROOT/system/kernel/x86_64-dotconfig-asura"
grep -Fq 'CONFIG_PREEMPT=y' "$REPO_ROOT/system/kernel/x86_64-dotconfig-asura"
grep -Fq 'CONFIG_SCHED_CLASS_EXT=y' "$REPO_ROOT/system/kernel/x86_64-dotconfig-asura"
grep -Fq 'cachyos-bore' "$REPO_ROOT/system/kernel/fleet.yaml"
grep -Fq 'march=x86-64-v3' "$REPO_ROOT/packaging/xbps/conf/xbps-v3.conf"
grep -Fq 'flto=auto' "$REPO_ROOT/packaging/xbps/conf/xbps-v3.conf"
grep -Fq -- '--emit-relocs' "$REPO_ROOT/packaging/xbps/conf/xbps-v3.conf"
grep -Fq 'profile-use' "$REPO_ROOT/packaging/xbps/conf/xbps-v3.conf"
test -s "$REPO_ROOT/system/udev/80-nvidia-pm.rules"
grep -Fq 'NVreg_DynamicPowerManagement=0x02' "$REPO_ROOT/system/modprobe.d/nvidia-optimus.conf"
grep -Fq 'charge_control_end_threshold' "$REPO_ROOT/system/udev/99-battery-threshold.rules"
grep -Fq 'pwm' "$REPO_ROOT/system/udev/70-pwm-fan.rules"

# LAYER 3: Verify Process, Memory & Storage Tuning
grep -Fq 'scx_lavd' "$REPO_ROOT/system/runit/services/scx-lavd/run"
grep -Fq 'scx-lavd' "$SCRIPT"
grep -Fq 'ananicy-cpp' "$REPO_ROOT/system/runit/services/ananicy-cpp/run"
grep -Fq 'ananicy-cpp' "$SCRIPT"
grep -Fq 'compiler' "$REPO_ROOT/system/ananicy/00-asura-rules.rules"
grep -Fq 'scanner' "$REPO_ROOT/system/ananicy/00-asura-rules.rules"
test -x "$REPO_ROOT/system/helpers/with-mimalloc"
! grep -Fq 'echo "/usr/lib/libmimalloc.so.3" > "$INCLUDE_DIR/etc/ld.so.preload"' "$SCRIPT"
! grep -Fq 'echo "/usr/lib/libmimalloc.so.3" > "$TARGET_DIR/etc/ld.so.preload"' "$REPO_ROOT/installation/asura-installer.sh"
grep -Fq 'ZRAM_COMP_ALGORITHM=zstd' "$SCRIPT"
grep -Fq 'ZRAM_COMP_ALGORITHM=zstd' "$REPO_ROOT/installation/asura-installer.sh"
grep -Fq 'compress=zstd:1' "$REPO_ROOT/installation/asura-installer.sh"
grep -Fq 'kyber' "$REPO_ROOT/system/udev/60-io-schedulers.rules"
grep -Fq 'bfq' "$REPO_ROOT/system/udev/60-io-schedulers.rules"

# STAGE 1: Security Verifications
test -s "$REPO_ROOT/installation/binary-checksums.txt"
grep -Fq 'verify_checksum' "$SCRIPT"
grep -Fq 'asura-hw' "$REPO_ROOT/system/udev/70-pwm-fan.rules"
if grep -Fq '0666' "$REPO_ROOT/system/udev/70-pwm-fan.rules"; then
	echo "build-iso-void_test: 0666 found in 70-pwm-fan.rules" >&2
	exit 1
fi
grep -Fq 'asura-hw' "$SCRIPT"
grep -Fq 'asura-hw' "$REPO_ROOT/installation/asura-installer.sh"
grep -Fq 'chpasswd' "$REPO_ROOT/installation/asura-installer.sh"
grep -Fq '%wheel ALL=(ALL:ALL) ALL' "$REPO_ROOT/installation/asura-installer.sh"

# STAGE 2: Installer Reliability Verifications
grep -Fq 'subvol=@' "$REPO_ROOT/installation/asura-installer.sh"
grep -Fq 'subvol=@home' "$REPO_ROOT/installation/asura-installer.sh"
grep -Fq 'POST-INSTALLATION VERIFICATION' "$REPO_ROOT/installation/asura-installer.sh"
grep -Fq -- '--dry-run' "$REPO_ROOT/installation/asura-installer.sh"
grep -Fq 'parted' "$MANIFEST"
grep -Fq 'dosfstools' "$MANIFEST"
grep -Fq 'e2fsprogs' "$MANIFEST"
grep -Fq 'rsync' "$MANIFEST"
grep -Fq 'grub' "$MANIFEST"
grep -Fq 'grub-x86_64-efi' "$MANIFEST"
printf "\n\n\n\n" | sh "$REPO_ROOT/installation/asura-installer.sh" --dry-run /dev/sda >/dev/null

# STAGE 3: Packaging Integrity & Developer OS Verifications
grep -Fq 'xbps-rindex -a' "$SCRIPT"
grep -Fq 'pkgdb-0.38.plist' "$SCRIPT"
grep -Fq 'tar -xf "$HYPR_CACHE' "$SCRIPT"
test -e "$REPO_ROOT/system/xbps.d/00-repository-main.conf"
if grep -Fq 'vm.max_map_count' "$REPO_ROOT/system/sysctl.d/99-asura-performance.conf"; then
	echo "build-iso-void_test: gaming vm.max_map_count found in 99-asura-performance.conf" >&2
	exit 1
fi
if grep -Fq 'steam' "$REPO_ROOT/system/ananicy/00-asura-rules.rules"; then
	echo "build-iso-void_test: gaming steam rule found in 00-asura-rules.rules" >&2
	exit 1
fi

# STAGE 4: Config Bug Fixes Verifications
grep -Fq 'NVreg_DynamicPowerManagement=0x02' "$REPO_ROOT/system/modprobe.d/nvidia.conf"
grep -Fq 'tcp_bbr' "$REPO_ROOT/system/modules-load.d/bbr.conf"
grep -Fq 'system/modules-load.d' "$SCRIPT"
grep -Fq 'performable:copy_to_clipboard' "$REPO_ROOT/apps/ghostty/config"
grep -Fq 'ATTR{type}=="Mains"' "$REPO_ROOT/system/udev/99-asura-power.rules"
test -x "$REPO_ROOT/system/runit/services/asura-sysd/log/run"
grep -Fq 'svlogd' "$REPO_ROOT/system/runit/services/asura-sysd/log/run"
grep -Fq 'sddm' "$MANIFEST"
if grep -Fq 'greetd' "$MANIFEST"; then
	echo "build-iso-void_test: greetd found in manifest" >&2
	exit 1
fi
grep -Fq 'zoxide' "$MANIFEST"
grep -Fq 'fzf' "$MANIFEST"
grep -Fq 'neovim' "$MANIFEST"
grep -Fq 'zsh-autosuggestions' "$MANIFEST"
grep -Fq 'zsh-syntax-highlighting' "$MANIFEST"
grep -Fq 'eza' "$MANIFEST"
grep -Fq 'atuin' "$MANIFEST"
grep -Fq 'mise' "$MANIFEST"
grep -Fq 'gcc' "$MANIFEST"
grep -Fq 'make' "$MANIFEST"
grep -Fq 'cmake' "$MANIFEST"
grep -Fq 'zed --wait' "$REPO_ROOT/apps/zsh/asura.zsh"

# STAGE 5: Performance & Light Cleanup Verifications
if grep -Fq 'xdg-desktop-portal-lxqt' "$MANIFEST"; then
	echo "build-iso-void_test: lxqt portal found in manifest" >&2
	exit 1
fi
grep -Fq 'xdg-desktop-portal-hyprland' "$MANIFEST"
grep -Fq 'xdg-desktop-portal-gtk' "$MANIFEST"
grep -Fq 'elogind' "$MANIFEST"
grep -Fq 'seatd' "$MANIFEST"
grep -Fq 'turnstile' "$MANIFEST"
if grep -Fq 'swayidle' "$MANIFEST" || grep -Fq 'swaylock' "$MANIFEST"; then
	echo "build-iso-void_test: swayidle/swaylock found in manifest" >&2
	exit 1
fi
grep -Fq 'hypridle' "$MANIFEST"
grep -Fq 'hyprlock' "$MANIFEST"
if grep -Fq '"name": "git"' "$REPO_ROOT/system/ananicy/00-asura-rules.rules" || \
   grep -Fq '"name": "fzf"' "$REPO_ROOT/system/ananicy/00-asura-rules.rules" || \
   grep -Fq '"name": "rg"' "$REPO_ROOT/system/ananicy/00-asura-rules.rules"; then
	echo "build-iso-void_test: interactive tools still in ananicy scanner class" >&2
	exit 1
fi
grep -Fq '"nice": 10' "$REPO_ROOT/system/ananicy/00-asura-types.types"
grep -Fq 'compinit -C' "$REPO_ROOT/apps/zsh/asura.zsh"
grep -Fq '_asura_cache_eval' "$REPO_ROOT/apps/zsh/asura.zsh"

# STAGE 6: Kernel and CI Verifications
grep -Fq 'grub-reboot' "$REPO_ROOT/system/runit/services/asura-boot-guard/run"
grep -Fq 'rollback-requested' "$REPO_ROOT/system/runit/services/asura-boot-guard/run"
grep -Fq 'qemu64' "$REPO_ROOT/.github/workflows/ci.yml"

echo "build-iso-void_test: ok"


