#!/bin/sh
# Asura OS Guided System Installer
# Sleek, interactive system installer with automatic drive detection,
# Btrfs/ext4 support, and hybrid UEFI/BIOS bootloader setup.
set -eu

DUAL_BOOT=0
for arg in "$@"; do
	case "$arg" in
		--dual-boot) DUAL_BOOT=1 ;;
	esac
done

BOLD=$(printf '\033[1m')
DIM=$(printf '\033[2m')
WHITE=$(printf '\033[1;37m')
GREEN=$(printf '\033[1;32m')
YELLOW=$(printf '\033[1;33m')
RED=$(printf '\033[1;31m')
RESET=$(printf '\033[0m')
CYAN=$(printf '\033[1;36m')

DISKS_FILE=$(mktemp 2>/dev/null || echo "/tmp/asura-disks.$$")

cleanup_installer() {
	rm -f "$DISKS_FILE" 2>/dev/null || true
	code=$?
	if [ "$code" -ne 0 ]; then
		printf "\n${RED}${BOLD}Installation encountered an error (exit code %s).${RESET}\n" "$code"
		printf "${WHITE}Press Enter to close...${RESET}"
		read -r _ 2>/dev/null || true
	fi
}
trap cleanup_installer EXIT INT TERM

clear 2>/dev/null || true

cat <<EOF
${WHITE}╭──────────────────────────────────────────────────────────────╮
│                           ${BOLD}ASURA OS${RESET}${WHITE}                           │
│                   Guided System Installer                    │
╰──────────────────────────────────────────────────────────────╯${RESET}

EOF

if [ "$(id -u)" -ne 0 ]; then
	printf "${RED}asura-installer: must be run as root (e.g. sudo asura install)${RESET}\n" >&2
	exit 1
fi

# Pre-flight: Check UEFI firmware vs Legacy BIOS
if [ ! -d /sys/firmware/efi ]; then
	printf "${YELLOW}● Boot Mode:${RESET} ${BOLD}Legacy BIOS${RESET} ${DIM}(MBR/BIOS bootloader will be installed)${RESET}\n\n"
	IS_UEFI=0
else
	printf "${GREEN}● Boot Mode:${RESET} ${BOLD}UEFI (Verified)${RESET} ${DIM}(GRUB EFI 64-bit bootloader)${RESET}\n\n"
	IS_UEFI=1
fi

# ── STEP 1: Interactive Drive Selection ─────────────────────────────────────
printf "${WHITE}╭──────────────────────────────────────────────────────────────╮
│  ${BOLD}[ STEP 1/4 ]  Target Drive Selection${RESET}${WHITE}                        │
╰──────────────────────────────────────────────────────────────╯${RESET}\n"

rm -f "$DISKS_FILE"
touch "$DISKS_FILE"
idx=1

lsblk -d -n -o NAME,SIZE,MODEL | grep -v '^zram' | while read -r dname dsize dmodel; do
	[ -z "$dname" ] && continue
	case "$dname" in
		zram*|loop*|sr*|dm-*) continue ;;
	esac
	echo "/dev/$dname" >> "$DISKS_FILE"
	rec_tag=""
	[ "$idx" -eq 1 ] && rec_tag="${DIM}[Recommended]${RESET}"
	printf "  ${WHITE}[%d]${RESET} ${BOLD}/dev/%-10s${RESET} %-8s %-22s %s\n" "$idx" "$dname" "$dsize" "${dmodel:-Disk}" "$rec_tag"
	idx=$((idx + 1))
done

total_disks=$(wc -l < "$DISKS_FILE" | tr -d ' ')

if [ "$total_disks" -eq 0 ]; then
	printf "\n${RED}Error: No suitable install drives found.${RESET}\n" >&2
	exit 1
fi

if [ $# -ge 1 ]; then
	TARGET_DISK="$1"
else
	printf "\n${WHITE}Select target drive [1-%d, or type path] (default: 1): ${RESET}" "$total_disks"
	read -r DRIVE_CHOICE || DRIVE_CHOICE="1"
	[ -z "$DRIVE_CHOICE" ] && DRIVE_CHOICE="1"

	case "$DRIVE_CHOICE" in
		[0-9]*)
			if [ "$DRIVE_CHOICE" -ge 1 ] 2>/dev/null && [ "$DRIVE_CHOICE" -le "$total_disks" ] 2>/dev/null; then
				TARGET_DISK=$(sed -n "${DRIVE_CHOICE}p" "$DISKS_FILE")
			else
				TARGET_DISK="$DRIVE_CHOICE"
			fi
			;;
		*)
			TARGET_DISK="$DRIVE_CHOICE"
			;;
	esac
fi

if [ ! -b "$TARGET_DISK" ]; then
	printf "${RED}Error: %s is not a valid block device.${RESET}\n" "$TARGET_DISK" >&2
	exit 1
fi

printf "${GREEN}✓ Selected drive:${RESET} ${BOLD}%s${RESET}\n\n" "$TARGET_DISK"

# ── STEP 2: Filesystem Selection ───────────────────────────────────────────
printf "${WHITE}╭──────────────────────────────────────────────────────────────╮
│  ${BOLD}[ STEP 2/4 ]  Select Root Filesystem${RESET}${WHITE}                        │
╰──────────────────────────────────────────────────────────────╯${RESET}\n"
printf "  ${WHITE}[1]${RESET} ${BOLD}Btrfs${RESET} ${DIM}(Recommended: subvolumes @, @home, @snapshots, zstd:1 compression)${RESET}\n"
printf "  ${WHITE}[2]${RESET} ${BOLD}ext4${RESET}  ${DIM}(Standard Linux journaling filesystem)${RESET}\n\n"
printf "${WHITE}Choose filesystem [1/2] (default: 1): ${RESET}"
read -r FS_CHOICE || FS_CHOICE="1"
[ -z "$FS_CHOICE" ] && FS_CHOICE="1"

# ── STEP 3: Identity & Configuration ───────────────────────────────────────
printf "\n${WHITE}╭──────────────────────────────────────────────────────────────╮
│  ${BOLD}[ STEP 3/4 ]  System Identity & User Setup${RESET}${WHITE}                  │
╰──────────────────────────────────────────────────────────────╯${RESET}\n"
printf "Enter system hostname [default: asura-os]: "
read -r HOSTNAME_INPUT || HOSTNAME_INPUT="asura-os"
[ -z "$HOSTNAME_INPUT" ] && HOSTNAME_INPUT="asura-os"

printf "Enter primary username [default: asura]: "
read -r USERNAME_INPUT || USERNAME_INPUT="asura"
[ -z "$USERNAME_INPUT" ] && USERNAME_INPUT="asura"

# ── STEP 4: Review & Final Confirmation ────────────────────────────────────
FS_DISPLAY="Btrfs (compress=zstd:1, subvolumes)"
[ "$FS_CHOICE" = "2" ] && FS_DISPLAY="ext4 (defaults, noatime)"

BOOT_DISPLAY="GRUB EFI (UEFI 64-bit)"
[ "$IS_UEFI" -eq 0 ] && BOOT_DISPLAY="GRUB MBR (Legacy BIOS)"

printf "\n${WHITE}╭──────────────────────────────────────────────────────────────╮
│                   INSTALLATION SPECIFICATION                 │
├──────────────────────────────────────────────────────────────┤${RESET}\n"
printf "${WHITE}│${RESET} Target Disk:    ${BOLD}%-44s${RESET} ${WHITE}│${RESET}\n" "$TARGET_DISK"
printf "${WHITE}│${RESET} Bootloader:     ${BOLD}%-44s${RESET} ${WHITE}│${RESET}\n" "$BOOT_DISPLAY"
printf "${WHITE}│${RESET} Filesystem:     ${BOLD}%-44s${RESET} ${WHITE}│${RESET}\n" "$FS_DISPLAY"
printf "${WHITE}│${RESET} Hostname:       ${BOLD}%-44s${RESET} ${WHITE}│${RESET}\n" "$HOSTNAME_INPUT"
printf "${WHITE}│${RESET} User Account:   ${BOLD}%-44s${RESET} ${WHITE}│${RESET}\n" "$USERNAME_INPUT (wheel, seatd, sudo)"
printf "${WHITE}╰──────────────────────────────────────────────────────────────╯${RESET}\n\n"

printf "${RED}${BOLD}⚠  CRITICAL WARNING: ALL EXISTING DATA ON %s WILL BE ERASED!${RESET}\n" "$TARGET_DISK"
printf "${WHITE}Type ${BOLD}'YES'${RESET}${WHITE} to format disk and install Asura OS: ${RESET}"
read -r CONFIRM
if [ "$CONFIRM" != "YES" ]; then
	printf "\n${DIM}Installation cancelled by user.${RESET}\n"
	exit 0
fi

# ── EXECUTION: Partitioning, Formatting, Deployment ────────────────────────
printf "\n${WHITE}${BOLD}[1/5] Partitioning target disk (%s)...${RESET}\n" "$TARGET_DISK"
wipefs -a "$TARGET_DISK" >/dev/null 2>&1 || true

if [ "$IS_UEFI" -eq 1 ]; then
	parted -s "$TARGET_DISK" mklabel gpt
	parted -s "$TARGET_DISK" mkpart "ESP" fat32 1MiB 513MiB
	parted -s "$TARGET_DISK" set 1 esp on
	parted -s "$TARGET_DISK" mkpart "AsuraRoot" 513MiB 100%
else
	parted -s "$TARGET_DISK" mklabel msdos
	parted -s "$TARGET_DISK" mkpart primary 1MiB 100%
	parted -s "$TARGET_DISK" set 1 boot on
fi

# Resolve partition names
if [ "$IS_UEFI" -eq 1 ]; then
	if [ -b "${TARGET_DISK}p1" ]; then
		PART_EFI="${TARGET_DISK}p1"
		PART_ROOT="${TARGET_DISK}p2"
	else
		PART_EFI="${TARGET_DISK}1"
		PART_ROOT="${TARGET_DISK}2"
	fi
else
	if [ -b "${TARGET_DISK}p1" ]; then
		PART_ROOT="${TARGET_DISK}p1"
	else
		PART_ROOT="${TARGET_DISK}1"
	fi
	PART_EFI=""
fi

sleep 2
printf "${GREEN}✓ Partition table generated.${RESET}\n"

printf "${WHITE}${BOLD}[2/5] Formatting filesystems...${RESET}\n"
if [ "$IS_UEFI" -eq 1 ]; then
	if [ "$DUAL_BOOT" -eq 1 ]; then
		printf "  Dual-boot mode: preserving existing ESP at %s\n" "$PART_EFI"
	else
		mkfs.vfat -F 32 -n "ASURA_ESP" "$PART_EFI" >/dev/null
	fi
fi

TARGET_DIR="/mnt/asura-target"
mkdir -p "$TARGET_DIR"

if [ "$FS_CHOICE" != "2" ] && command -v mkfs.btrfs >/dev/null 2>&1; then
	printf "  Formatting root with Btrfs (zstd:1 compression)...\n"
	mkfs.btrfs -f -L "ASURA_ROOT" "$PART_ROOT" >/dev/null
	FS_TYPE="btrfs"
	FS_OPTS="defaults,noatime,compress=zstd:1"
	mount -o "$FS_OPTS" "$PART_ROOT" "$TARGET_DIR"
else
	printf "  Formatting root with ext4...\n"
	mkfs.ext4 -F -L "ASURA_ROOT" "$PART_ROOT" >/dev/null
	FS_TYPE="ext4"
	FS_OPTS="defaults,noatime"
	mount "$PART_ROOT" "$TARGET_DIR"
fi

if [ "$IS_UEFI" -eq 1 ]; then
	mkdir -p "$TARGET_DIR/boot/efi"
	mount "$PART_EFI" "$TARGET_DIR/boot/efi"
fi
printf "${GREEN}✓ Filesystems ready and mounted.${RESET}\n"

printf "${WHITE}${BOLD}[3/5] Deploying Asura OS system image (rootfs)...${RESET}\n"
rsync -aAX --info=progress2 \
	--exclude='/dev/*' \
	--exclude='/proc/*' \
	--exclude='/sys/*' \
	--exclude='/tmp/*' \
	--exclude='/run/*' \
	--exclude='/mnt/*' \
	--exclude='/media/*' \
	--exclude='/lost+found' \
	--exclude='/var/cache/*' \
	/ "$TARGET_DIR/"
printf "${GREEN}✓ System image copied.${RESET}\n"

printf "${WHITE}${BOLD}[4/5] Configuring system services, fstab, and identity...${RESET}\n"
ROOT_UUID=$(blkid -s UUID -o value "$PART_ROOT")

if [ "$IS_UEFI" -eq 1 ]; then
	EFI_UUID=$(blkid -s UUID -o value "$PART_EFI")
	cat >"$TARGET_DIR/etc/fstab" <<EOF
# /etc/fstab: static file system information for Asura OS
UUID=$ROOT_UUID / $FS_TYPE $FS_OPTS 0 0
UUID=$EFI_UUID /boot/efi vfat defaults,noatime,umask=0077 0 2
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
EOF
else
	cat >"$TARGET_DIR/etc/fstab" <<EOF
# /etc/fstab: static file system information for Asura OS
UUID=$ROOT_UUID / $FS_TYPE $FS_OPTS 0 0
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
EOF
fi

# Remove live session markers so first-boot welcome tour triggers
rm -f "$TARGET_DIR/etc/asura-live"

# Set hostname and OS identity
printf '%s\n' "$HOSTNAME_INPUT" > "$TARGET_DIR/etc/hostname"

cat >"$TARGET_DIR/etc/os-release" <<'EOF'
NAME="Asura OS"
PRETTY_NAME="Asura OS Beta 001"
ID=asura
ID_LIKE="linux"
VERSION_ID="0.1"
VERSION_CODENAME=beta-001
HOME_URL="https://asuraos.dev/"
SUPPORT_URL="https://asuraos.dev/support"
BUG_REPORT_URL="https://github.com/mohitjoer/ASURA-OS/issues"
EOF

# Automatically clean up installer artifacts on the installed drive
rm -f "$TARGET_DIR/etc/asura-live"
rm -f "$TARGET_DIR/usr/bin/asura-installer"
rm -f "$TARGET_DIR/usr/bin/void-installer"
rm -f "$TARGET_DIR/usr/share/applications/asura-installer.desktop"
rm -f "$TARGET_DIR/home"/*/Desktop/asura-installer.desktop 2>/dev/null || true
rm -f "$TARGET_DIR/etc/skel/Desktop/asura-installer.desktop" 2>/dev/null || true

# User account creation
if ! chroot "$TARGET_DIR" id -u "$USERNAME_INPUT" >/dev/null 2>&1; then
	chroot "$TARGET_DIR" useradd -m -s /bin/zsh -G wheel,_seatd,video,audio,input "$USERNAME_INPUT" || true
fi

# Enable core system runit services
mkdir -p "$TARGET_DIR/etc/runit/runsvdir/default"
for svc in dbus seatd udevd NetworkManager acpid turnstiled tlp zramen scx-lavd ananicy-cpp asura-sysd asura-boot-guard; do
	if [ -d "$TARGET_DIR/etc/sv/$svc" ]; then
		ln -sf "/etc/sv/$svc" "$TARGET_DIR/etc/runit/runsvdir/default/$svc"
	fi
done

# Layer 3 Tuning: Configure zramen zstd compression
mkdir -p "$TARGET_DIR/etc/sv/zramen"
cat >"$TARGET_DIR/etc/sv/zramen/conf" <<'ZRAMCONF'
export ZRAM_COMP_ALGORITHM=zstd
export ZRAM_SIZE=50
export ZRAM_PRIORITY=32767
ZRAMCONF

# Layer 3 Tuning: Configure global mimalloc lock-free allocator
if [ -f "$TARGET_DIR/usr/lib/libmimalloc.so.3" ]; then
	echo "/usr/lib/libmimalloc.so.3" > "$TARGET_DIR/etc/ld.so.preload"
fi

# Configure GRUB bootloader identity
mkdir -p "$TARGET_DIR/etc/default"
cat >"$TARGET_DIR/etc/default/grub" <<'GRUBDEF'
GRUB_DISTRIBUTOR="Asura OS"
GRUB_TIMEOUT=3
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 quiet splash"
GRUB_DISABLE_OS_PROBER=false
GRUBDEF

printf "${GREEN}✓ Host and services configured.${RESET}\n"

printf "${WHITE}${BOLD}[5/5] Installing bootloader (%s)...${RESET}\n" "$BOOT_DISPLAY"
mount --bind /dev "$TARGET_DIR/dev"
mount --bind /proc "$TARGET_DIR/proc"
mount --bind /sys "$TARGET_DIR/sys"

if [ "$IS_UEFI" -eq 1 ]; then
	chroot "$TARGET_DIR" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Asura --recheck >/dev/null 2>&1 || true
	chroot "$TARGET_DIR" grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
else
	# Legacy BIOS / MBR installation (supports VirtualBox BIOS boot)
	chroot "$TARGET_DIR" grub-install --target=i386-pc --recheck "$TARGET_DISK" >/dev/null 2>&1 || true
	chroot "$TARGET_DIR" grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
fi

umount "$TARGET_DIR/sys" || true
umount "$TARGET_DIR/proc" || true
umount "$TARGET_DIR/dev" || true

if [ "$IS_UEFI" -eq 1 ]; then
	umount "$TARGET_DIR/boot/efi" || true
fi
umount "$TARGET_DIR" || true

printf "${GREEN}✓ Bootloader successfully installed.${RESET}\n"

cat <<EOF

${GREEN}╭──────────────────────────────────────────────────────────────╮
│              ✓ ASURA OS Successfully Installed!              │
│                                                              │
│   Asura OS has been deployed to your storage drive.          │
│   The installer has been automatically deleted.              │
│   You can now safely reboot into your new installation.      │
╰──────────────────────────────────────────────────────────────╯${RESET}

EOF

printf "Would you like to reboot into Asura OS now? [Y/n]: "
read -r REBOOT_CHOICE || REBOOT_CHOICE="y"
[ -z "$REBOOT_CHOICE" ] && REBOOT_CHOICE="y"

case "$REBOOT_CHOICE" in
	[yY]|[yY][eE][sS])
		printf "\n${WHITE}Rebooting system...${RESET}\n"
		reboot
		;;
	*)
		printf "\n${DIM}Returning to live desktop environment. You may reboot anytime.${RESET}\n\n"
		printf "${WHITE}Press Enter to exit...${RESET}"
		read -r _ || true
		;;
esac
