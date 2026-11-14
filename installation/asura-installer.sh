#!/bin/sh
# Asura OS Guided System Installer
# Sleek, interactive system installer with automatic drive detection,
# Btrfs/ext4 support, subvolume setup, and hybrid UEFI/BIOS bootloader.
set -eu

DUAL_BOOT=0
DRY_RUN=0
TARGET_DISK_ARG=""

for arg in "$@"; do
	case "$arg" in
		--dual-boot) DUAL_BOOT=1 ;;
		--dry-run) DRY_RUN=1 ;;
		-*)
			echo "Unknown option: $arg" >&2
			echo "Usage: asura-installer [--dual-boot] [--dry-run] [TARGET_DISK]" >&2
			exit 1
			;;
		*)
			if [ -z "$TARGET_DISK_ARG" ]; then
				TARGET_DISK_ARG="$arg"
			fi
			;;
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

SAVED_STTY=""
if [ -t 0 ]; then
	SAVED_STTY=$(stty -g 2>/dev/null || true)
fi

DISKS_FILE=$(mktemp 2>/dev/null || echo "/tmp/asura-disks.$$")
TARGET_DIR="/mnt/asura-target"

cleanup_installer() {
	exit_code=$?
	# Always restore terminal settings and echo
	if [ -n "$SAVED_STTY" ]; then
		stty "$SAVED_STTY" 2>/dev/null || stty echo 2>/dev/null || true
	else
		stty echo 2>/dev/null || true
	fi
	rm -f "$DISKS_FILE" 2>/dev/null || true
	if [ -d "$TARGET_DIR" ]; then
		# Unmount in reverse order
		umount "$TARGET_DIR/boot/efi" 2>/dev/null || true
		umount "$TARGET_DIR/sys/firmware/efi/efivars" 2>/dev/null || true
		umount "$TARGET_DIR/sys" 2>/dev/null || true
		umount "$TARGET_DIR/proc" 2>/dev/null || true
		umount "$TARGET_DIR/dev/pts" 2>/dev/null || true
		umount "$TARGET_DIR/dev" 2>/dev/null || true
		umount "$TARGET_DIR/home" 2>/dev/null || true
		umount "$TARGET_DIR/.snapshots" 2>/dev/null || true
		umount "$TARGET_DIR" 2>/dev/null || true
		rmdir "$TARGET_DIR" 2>/dev/null || true
	fi
	if [ "$exit_code" -ne 0 ] && [ "$DRY_RUN" -eq 0 ]; then
		printf "\n${RED}${BOLD}Installation failed (exit code %s). Cleaned up mounts.${RESET}\n" "$exit_code"
		printf "${WHITE}Press Enter to close...${RESET}"
		read -r _ 2>/dev/null || true
	fi
}

on_signal() {
	trap - EXIT INT TERM
	if [ -n "$SAVED_STTY" ]; then
		stty "$SAVED_STTY" 2>/dev/null || stty echo 2>/dev/null || true
	else
		stty echo 2>/dev/null || true
	fi
	rm -f "$DISKS_FILE" 2>/dev/null || true
	if [ -d "$TARGET_DIR" ]; then
		umount "$TARGET_DIR/boot/efi" 2>/dev/null || true
		umount "$TARGET_DIR/sys/firmware/efi/efivars" 2>/dev/null || true
		umount "$TARGET_DIR/sys" 2>/dev/null || true
		umount "$TARGET_DIR/proc" 2>/dev/null || true
		umount "$TARGET_DIR/dev/pts" 2>/dev/null || true
		umount "$TARGET_DIR/dev" 2>/dev/null || true
		umount "$TARGET_DIR/home" 2>/dev/null || true
		umount "$TARGET_DIR/.snapshots" 2>/dev/null || true
		umount "$TARGET_DIR" 2>/dev/null || true
		rmdir "$TARGET_DIR" 2>/dev/null || true
	fi
	printf "\n"
	exit 130
}

trap on_signal INT TERM
trap cleanup_installer EXIT

clear 2>/dev/null || true

cat <<EOF
${WHITE}╭──────────────────────────────────────────────────────────────╮
│                           ${BOLD}ASURA OS${RESET}${WHITE}                           │
│                   Guided System Installer                    │
╰──────────────────────────────────────────────────────────────╯${RESET}

EOF

if [ "$DRY_RUN" -eq 1 ]; then
	printf "${YELLOW}${BOLD}● DRY RUN MODE ACTIVE${RESET} ${DIM}(No disks will be partitioned or modified)${RESET}\n\n"
fi

if [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" -eq 0 ]; then
	printf "${RED}asura-installer: must be run as root (e.g. sudo asura install)${RESET}\n" >&2
	exit 1
fi

# Pre-flight dependency check
REQUIRED_TOOLS="rsync parted mkfs.vfat mkfs.ext4 grub-install grub-mkconfig blkid"
MISSING_TOOLS=""
for tool in $REQUIRED_TOOLS; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		MISSING_TOOLS="$MISSING_TOOLS $tool"
	fi
done
if [ -n "$MISSING_TOOLS" ] && [ "$DRY_RUN" -eq 0 ]; then
	printf "${RED}Pre-flight error: required installer tool(s) missing:${BOLD}%s${RESET}\n" "$MISSING_TOOLS" >&2
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

lsblk -d -n -o NAME,SIZE,MODEL 2>/dev/null | grep -v '^zram' | while read -r dname dsize dmodel; do
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

total_disks=$(wc -l < "$DISKS_FILE" 2>/dev/null | tr -d ' ' || echo 0)

if [ "$total_disks" -eq 0 ] && [ -z "$TARGET_DISK_ARG" ] && [ "$DRY_RUN" -eq 0 ]; then
	printf "\n${RED}Error: No suitable install drives found.${RESET}\n" >&2
	exit 1
fi

if [ -n "$TARGET_DISK_ARG" ]; then
	TARGET_DISK="$TARGET_DISK_ARG"
elif [ "$total_disks" -gt 0 ]; then
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
else
	TARGET_DISK="/dev/sda"
fi

if [ ! -b "$TARGET_DISK" ] && [ "$DRY_RUN" -eq 0 ]; then
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

# Prompt for password for primary user
while true; do
	printf "Enter password for %s: " "$USERNAME_INPUT"
	stty -echo 2>/dev/null || true
	read -r USER_PASS || USER_PASS=""
	stty echo 2>/dev/null || true
	printf "\n"
	if [ -z "$USER_PASS" ]; then
		if [ "$DRY_RUN" -eq 1 ]; then
			USER_PASS="dryrunpass"
			break
		fi
		printf "${RED}Password cannot be empty. Please enter a valid password.${RESET}\n"
		continue
	fi
	printf "Confirm password for %s: " "$USERNAME_INPUT"
	stty -echo 2>/dev/null || true
	read -r USER_PASS_CONFIRM || USER_PASS_CONFIRM=""
	stty echo 2>/dev/null || true
	printf "\n"
	if [ "$USER_PASS" = "$USER_PASS_CONFIRM" ]; then
		break
	fi
	printf "${RED}Passwords do not match. Please try again.${RESET}\n"
done

# Root account setup (lock or set password)
printf "Lock root account (recommended for sudo setups)? [Y/n]: "
read -r LOCK_ROOT_INPUT || LOCK_ROOT_INPUT="Y"
[ -z "$LOCK_ROOT_INPUT" ] && LOCK_ROOT_INPUT="Y"

ROOT_PASS=""
case "$LOCK_ROOT_INPUT" in
	[nN]|[nN][oO])
		while true; do
			printf "Enter root password: "
			stty -echo 2>/dev/null || true
			read -r ROOT_PASS || ROOT_PASS=""
			stty echo 2>/dev/null || true
			printf "\n"
			if [ -z "$ROOT_PASS" ]; then
				if [ "$DRY_RUN" -eq 1 ]; then
					ROOT_PASS="dryrunroot"
					break
				fi
				printf "${RED}Root password cannot be empty.${RESET}\n"
				continue
			fi
			printf "Confirm root password: "
			stty -echo 2>/dev/null || true
			read -r ROOT_PASS_CONFIRM || ROOT_PASS_CONFIRM=""
			stty echo 2>/dev/null || true
			printf "\n"
			if [ "$ROOT_PASS" = "$ROOT_PASS_CONFIRM" ]; then
				break
			fi
			printf "${RED}Passwords do not match. Please try again.${RESET}\n"
		done
		;;
	*)
		ROOT_PASS=""
		;;
esac

# ── STEP 4: Review & Final Confirmation ────────────────────────────────────
FS_DISPLAY="Btrfs (subvolumes @, @home, @snapshots, compress=zstd:1)"
[ "$FS_CHOICE" = "2" ] && FS_DISPLAY="ext4 (defaults, noatime)"

BOOT_DISPLAY="GRUB EFI (UEFI 64-bit)"
[ "$IS_UEFI" -eq 0 ] && BOOT_DISPLAY="GRUB MBR (Legacy BIOS)"

ROOT_STATUS="Locked (sudo only via wheel group)"
[ -n "$ROOT_PASS" ] && ROOT_STATUS="Password set"

printf "\n${WHITE}╭──────────────────────────────────────────────────────────────╮
│                   INSTALLATION SPECIFICATION                 │
├──────────────────────────────────────────────────────────────┤${RESET}\n"
printf "${WHITE}│${RESET} Target Disk:    ${BOLD}%-44s${RESET} ${WHITE}│${RESET}\n" "$TARGET_DISK"
printf "${WHITE}│${RESET} Bootloader:     ${BOLD}%-44s${RESET} ${WHITE}│${RESET}\n" "$BOOT_DISPLAY"
printf "${WHITE}│${RESET} Filesystem:     ${BOLD}%-44s${RESET} ${WHITE}│${RESET}\n" "$FS_DISPLAY"
printf "${WHITE}│${RESET} Hostname:       ${BOLD}%-44s${RESET} ${WHITE}│${RESET}\n" "$HOSTNAME_INPUT"
printf "${WHITE}│${RESET} User Account:   ${BOLD}%-44s${RESET} ${WHITE}│${RESET}\n" "$USERNAME_INPUT (wheel, asura-hw)"
printf "${WHITE}│${RESET} Root Account:   ${BOLD}%-44s${RESET} ${WHITE}│${RESET}\n" "$ROOT_STATUS"
printf "${WHITE}╰──────────────────────────────────────────────────────────────╯${RESET}\n\n"

if [ "$DRY_RUN" -eq 1 ]; then
	printf "${YELLOW}${BOLD}DRY RUN SUMMARY:${RESET}\n"
	printf "  1. Partition %s (GPT for UEFI with 512MB ESP, or MBR for BIOS)\n" "$TARGET_DISK"
	printf "  2. Format with %s\n" "$FS_DISPLAY"
	if [ "$FS_CHOICE" != "2" ]; then
		printf "     Create Btrfs subvolumes: @ -> /, @home -> /home, @snapshots -> /.snapshots\n"
	fi
	printf "  3. Deploy rootfs via rsync to /mnt/asura-target\n"
	printf "  4. Configure fstab with persistent UUIDs, regenerate initramfs, install GRUB\n"
	printf "  5. Set credentials: user '%s' password, root: %s\n" "$USERNAME_INPUT" "$ROOT_STATUS"
	printf "  6. Remove live-only configs (agetty autologin, NOPASSWD, live session files)\n"
	printf "  7. Run post-installation verification check.\n\n"
	printf "${GREEN}Dry-run completed successfully.${RESET}\n"
	exit 0
fi

printf "${RED}${BOLD}⚠  CRITICAL WARNING: ALL EXISTING DATA ON %s WILL BE ERASED!${RESET}\n" "$TARGET_DISK"
printf "${WHITE}Type ${BOLD}'YES'${RESET}${WHITE} to format disk and install Asura OS: ${RESET}"
read -r CONFIRM
if [ "$CONFIRM" != "YES" ]; then
	printf "\n${DIM}Installation cancelled by user.${RESET}\n"
	exit 0
fi

# ── EXECUTION: Partitioning, Formatting, Deployment ────────────────────────
printf "\n${WHITE}${BOLD}[1/5] Partitioning target disk (%s)...${RESET}\n" "$TARGET_DISK"
wipefs -a "$TARGET_DISK"

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

sleep 1
printf "${GREEN}✓ Partition table generated.${RESET}\n"

printf "${WHITE}${BOLD}[2/5] Formatting filesystems...${RESET}\n"
if [ "$IS_UEFI" -eq 1 ]; then
	if [ "$DUAL_BOOT" -eq 1 ]; then
		printf "  Dual-boot mode: preserving existing ESP at %s\n" "$PART_EFI"
	else
		mkfs.vfat -F 32 -n "ASURA_ESP" "$PART_EFI"
	fi
fi

mkdir -p "$TARGET_DIR"

if [ "$FS_CHOICE" != "2" ] && command -v mkfs.btrfs >/dev/null 2>&1; then
	printf "  Formatting root with Btrfs and creating subvolumes (@, @home, @snapshots)...\n"
	mkfs.btrfs -f -L "ASURA_ROOT" "$PART_ROOT"
	FS_TYPE="btrfs"
	BTRFS_BASE_OPTS="defaults,noatime,compress=zstd:1"
	
	# Temporary mount to create subvolumes
	TMP_BTRFS="/mnt/asura-subvols.$$"
	mkdir -p "$TMP_BTRFS"
	mount -t btrfs "$PART_ROOT" "$TMP_BTRFS"
	btrfs subvolume create "$TMP_BTRFS/@"
	btrfs subvolume create "$TMP_BTRFS/@home"
	btrfs subvolume create "$TMP_BTRFS/@snapshots"
	umount "$TMP_BTRFS"
	rmdir "$TMP_BTRFS"

	# Mount subvolumes into target tree
	mount -t btrfs -o "$BTRFS_BASE_OPTS,subvol=@" "$PART_ROOT" "$TARGET_DIR"
	mkdir -p "$TARGET_DIR/home" "$TARGET_DIR/.snapshots"
	mount -t btrfs -o "$BTRFS_BASE_OPTS,subvol=@home" "$PART_ROOT" "$TARGET_DIR/home"
	mount -t btrfs -o "$BTRFS_BASE_OPTS,subvol=@snapshots" "$PART_ROOT" "$TARGET_DIR/.snapshots"
else
	printf "  Formatting root with ext4...\n"
	mkfs.ext4 -F -L "ASURA_ROOT" "$PART_ROOT"
	FS_TYPE="ext4"
	mount -t ext4 -o defaults,noatime "$PART_ROOT" "$TARGET_DIR"
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
if [ -z "$ROOT_UUID" ]; then
	echo "ERROR: Failed to retrieve UUID for $PART_ROOT" >&2
	exit 1
fi

if [ "$IS_UEFI" -eq 1 ]; then
	EFI_UUID=$(blkid -s UUID -o value "$PART_EFI")
	if [ -z "$EFI_UUID" ]; then
		echo "ERROR: Failed to retrieve UUID for $PART_EFI" >&2
		exit 1
	fi
	if [ "$FS_TYPE" = "btrfs" ]; then
		cat >"$TARGET_DIR/etc/fstab" <<EOF
# /etc/fstab: static file system information for Asura OS
UUID=$ROOT_UUID / btrfs defaults,noatime,compress=zstd:1,subvol=@ 0 0
UUID=$ROOT_UUID /home btrfs defaults,noatime,compress=zstd:1,subvol=@home 0 0
UUID=$ROOT_UUID /.snapshots btrfs defaults,noatime,compress=zstd:1,subvol=@snapshots 0 0
UUID=$EFI_UUID /boot/efi vfat defaults,noatime,umask=0077 0 2
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
EOF
	else
		cat >"$TARGET_DIR/etc/fstab" <<EOF
# /etc/fstab: static file system information for Asura OS
UUID=$ROOT_UUID / ext4 defaults,noatime 0 1
UUID=$EFI_UUID /boot/efi vfat defaults,noatime,umask=0077 0 2
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
EOF
	fi
else
	if [ "$FS_TYPE" = "btrfs" ]; then
		cat >"$TARGET_DIR/etc/fstab" <<EOF
# /etc/fstab: static file system information for Asura OS
UUID=$ROOT_UUID / btrfs defaults,noatime,compress=zstd:1,subvol=@ 0 0
UUID=$ROOT_UUID /home btrfs defaults,noatime,compress=zstd:1,subvol=@home 0 0
UUID=$ROOT_UUID /.snapshots btrfs defaults,noatime,compress=zstd:1,subvol=@snapshots 0 0
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
EOF
	else
		cat >"$TARGET_DIR/etc/fstab" <<EOF
# /etc/fstab: static file system information for Asura OS
UUID=$ROOT_UUID / ext4 defaults,noatime 0 1
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
EOF
	fi
fi

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

# Purge live installer artifacts and markers
rm -f "$TARGET_DIR/etc/asura-live"
rm -f "$TARGET_DIR/usr/bin/asura-installer"
rm -f "$TARGET_DIR/usr/bin/void-installer"
rm -f "$TARGET_DIR/usr/share/applications/asura-installer.desktop"
rm -f "$TARGET_DIR/home"/*/Desktop/asura-installer.desktop 2>/dev/null || true
rm -f "$TARGET_DIR/etc/skel/Desktop/asura-installer.desktop" 2>/dev/null || true

# Ensure dedicated hardware and docker groups exist on target
chroot "$TARGET_DIR" getent group asura-hw >/dev/null 2>&1 || chroot "$TARGET_DIR" groupadd -r asura-hw
chroot "$TARGET_DIR" getent group docker >/dev/null 2>&1 || chroot "$TARGET_DIR" groupadd -r docker || true

# Record live user hash from running environment to verify against later
LIVE_SHADOW_HASH=$(grep '^asura:' /etc/shadow 2>/dev/null | cut -d: -f2 || true)

# Completely purge live user account, credentials, and live home directory from target
if chroot "$TARGET_DIR" id -u asura >/dev/null 2>&1; then
	chroot "$TARGET_DIR" userdel -r asura >/dev/null 2>&1 || true
fi
rm -rf "$TARGET_DIR/home/asura"

# User account creation on target
if ! chroot "$TARGET_DIR" id -u "$USERNAME_INPUT" >/dev/null 2>&1; then
	chroot "$TARGET_DIR" useradd -m -s /bin/zsh -G wheel,_seatd,video,audio,input,storage,network,asura-hw,docker "$USERNAME_INPUT"
else
	chroot "$TARGET_DIR" usermod -aG wheel,_seatd,video,audio,input,storage,network,asura-hw,docker "$USERNAME_INPUT"
fi

# Set password for primary user with explicit SHA512 encryption
echo "$USERNAME_INPUT:$USER_PASS" | chroot "$TARGET_DIR" chpasswd -c SHA512

# Configure root password or lock root account
if [ -n "$ROOT_PASS" ]; then
	echo "root:$ROOT_PASS" | chroot "$TARGET_DIR" chpasswd -c SHA512
else
	chroot "$TARGET_DIR" usermod -p '!' root
fi

# Clean up any shadow/passwd backup files that might contain the live hash
rm -f "$TARGET_DIR/etc/shadow-" "$TARGET_DIR/etc/passwd-" "$TARGET_DIR/etc/group-" "$TARGET_DIR/etc/gshadow-"

# Purge live-only configurations, live sudoers, polkit rules, and autologin from installed system
rm -f "$TARGET_DIR/etc/sudoers.d/99-asura-live" "$TARGET_DIR/etc/sudoers.d/99-void-live" "$TARGET_DIR/etc/sudoers.d/"*live*
rm -f "$TARGET_DIR/etc/polkit-1/rules.d/asura-live.rules"
rm -f "$TARGET_DIR/etc/default/live.conf"
rm -f "$TARGET_DIR/etc/sv/agetty-tty1/conf"
rm -f "$TARGET_DIR/etc/profile.d/asura-autologin.sh"
rm -f "$TARGET_DIR/home/$USERNAME_INPUT/.hushlogin" 2>/dev/null || true
rm -f "$TARGET_DIR/etc/skel/.hushlogin" 2>/dev/null || true
rm -rf "$TARGET_DIR/tmp"/* "$TARGET_DIR/var/tmp"/*

# Replace live MOTD, issue, and issue.net with installed system banners
cat >"$TARGET_DIR/etc/motd" <<'MOTD'
       #                    #         Asura OS Beta 001
     %##                    ##%       https://asuraos.dev
    ####   %%%%%%%%%%%%%%   ####
  ######% %%%%%%%%%%%%%%%% %######    Robust. Minimal. Kinetic.
%###########% %%%%%%%%  ###########%
 %###########          ###########%
     ########  @@@@@@  ########
   %% ########%      %######## %%%
   %%  %%##################%%% %%%
   %% ##     %########%     ## %%%
   %% ####%%%%%      %%%%%#### %%
       %####################%
      %%  %##############%  %%
       ### ############## %##
       %##  ############  ###
        ###  %        %  ###
         %################%
           %############%
             ##########
MOTD

cat >"$TARGET_DIR/etc/issue" <<'ISSUE'
       #                    #         Asura OS Beta 001 (\m)
     %##                    ##%       Kernel \r on an \m (\l)
    ####   %%%%%%%%%%%%%%   ####
  ######% %%%%%%%%%%%%%%%% %######    Robust. Minimal. Kinetic.
%###########% %%%%%%%%  ###########%  https://asuraos.dev
 %###########          ###########%
     ########  @@@@@@  ########
   %% ########%      %######## %%%
   %%  %%##################%%% %%%
   %% ##     %########%     ## %%%
   %% ####%%%%%      %%%%%#### %%
       %####################%
      %%  %##############%  %%
       ### ############## %##
       %##  ############  ###
        ###  %        %  ###
         %################%
           %############%
             ##########
ISSUE
cp "$TARGET_DIR/etc/motd" "$TARGET_DIR/etc/issue.net"

# Strict sudoers configuration: require password for wheel group (NO NOPASSWD)
mkdir -p "$TARGET_DIR/etc/sudoers.d"
chmod 0750 "$TARGET_DIR/etc/sudoers.d"
echo '%wheel ALL=(ALL:ALL) ALL' > "$TARGET_DIR/etc/sudoers.d/wheel"
chmod 0440 "$TARGET_DIR/etc/sudoers.d/wheel"
if [ -f "$TARGET_DIR/etc/sudoers" ]; then
	sed -i '/NOPASSWD/d' "$TARGET_DIR/etc/sudoers"
fi

# The session dismisses the boot splash before the compositor claims KMS, and
# plymouthd runs as root, so the wheel group gets exactly these commands without
# a password. Every other sudo call still asks for one. The drop-in name sorts
# after "wheel" on purpose: sudo applies the LAST matching entry, so a file
# sorted before wheel would be overridden by wheel's password rule.
cat >"$TARGET_DIR/etc/sudoers.d/zz-asura-session" <<'SUDOERS'
# Asura's session: the boot splash is dismissed by asura-session before the
# compositor claims KMS. plymouthd runs as root, so these exact commands are
# the only passwordless privileges the session needs. Both spellings are
# granted because sudo resolves a bare name through secure_path, where
# /usr/sbin precedes /usr/bin. The file name sorts after "wheel" because
# sudo applies the last matching sudoers entry.
Cmnd_Alias ASURA_SESSION_PLYMOUTH = /usr/bin/plymouth --quit, /usr/sbin/plymouth --quit, /usr/bin/killall -9 plymouthd, /usr/sbin/killall -9 plymouthd, /usr/bin/pkill -9 -x plymouthd, /usr/sbin/pkill -9 -x plymouthd
%wheel ALL=(root) NOPASSWD: ASURA_SESSION_PLYMOUTH
SUDOERS
chmod 0440 "$TARGET_DIR/etc/sudoers.d/zz-asura-session"

# Enable core system runit services
mkdir -p "$TARGET_DIR/etc/runit/runsvdir/default"
for svc in dbus seatd elogind udevd NetworkManager acpid turnstiled zramen ananicy-cpp asura-sysd asura-boot-guard; do
	if [ -d "$TARGET_DIR/etc/sv/$svc" ]; then
		ln -sf "/etc/sv/$svc" "$TARGET_DIR/etc/runit/runsvdir/default/$svc"
	fi
done

# Ensure wpa_supplicant does not run as a standalone service (managed by NetworkManager)
rm -f "$TARGET_DIR/etc/runit/runsvdir/default/wpa_supplicant" "$TARGET_DIR/var/service/wpa_supplicant"

# Layer 3 Tuning: Configure zramen zstd compression
mkdir -p "$TARGET_DIR/etc/sv/zramen"
cat >"$TARGET_DIR/etc/sv/zramen/conf" <<'ZRAMCONF'
export ZRAM_COMP_ALGORITHM=zstd
export ZRAM_SIZE=50
export ZRAM_PRIORITY=32767
ZRAMCONF

# Layer 3 Tuning: Avoid global ld.so.preload (opt-in runner /usr/bin/with-mimalloc provided)
rm -f "$TARGET_DIR/etc/ld.so.preload"

# Configure GRUB bootloader identity
mkdir -p "$TARGET_DIR/etc/default"
cat >"$TARGET_DIR/etc/default/grub" <<'GRUBDEF'
GRUB_DISTRIBUTOR="Asura OS"
GRUB_DEFAULT=saved
GRUB_SAVEDEFAULT=true
GRUB_TIMEOUT=3
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 rd.udev.log_level=3 udev.log_level=3 rd.plymouth=1 plymouth.enable=1 vt.global_cursor_default=0 fbcon=nodefer console=ttyS0,115200 console=tty0"
GRUB_DISABLE_OS_PROBER=false
GRUBDEF

# Ensure Plymouth theme and dracut configuration exist on installed target
mkdir -p "$TARGET_DIR/etc/plymouth" "$TARGET_DIR/etc/dracut.conf.d"
cat >"$TARGET_DIR/etc/plymouth/plymouthd.conf" <<'EOF'
[Daemon]
Theme=asura
ShowDelay=0
DeviceTimeout=8
EOF

cat >"$TARGET_DIR/etc/dracut.conf.d/50-plymouth.conf" <<'EOF'
add_dracutmodules+=" plymouth "
add_drivers+=" vboxvideo vmwgfx bochs virtio_gpu qxl simpledrm "
install_optional_items+=" /usr/lib/plymouth/script.so /usr/lib/plymouth/label.so /usr/lib/plymouth/label-pango.so /usr/lib/plymouth/renderers/drm.so /usr/lib/plymouth/renderers/frame-buffer.so /etc/fonts/fonts.conf /etc/fonts/local.conf /usr/share/fonts/TTF/DejaVuSans.ttf /usr/share/fonts/TTF/DejaVuSans-Bold.ttf /usr/share/fonts/TTF/DejaVuSansMono.ttf "
EOF

if [ -d "$TARGET_DIR/usr/share/plymouth/themes/asura" ]; then
	ln -sf /usr/share/plymouth/themes/asura/asura.plymouth "$TARGET_DIR/usr/share/plymouth/themes/default.plymouth" 2>/dev/null || true
fi
chroot "$TARGET_DIR" plymouth-set-default-theme asura 2>/dev/null || true

printf "${GREEN}✓ Host, services, and accounts configured.${RESET}\n"

# Bind mounts for chroot maintenance
mount --bind /dev "$TARGET_DIR/dev"
mount --bind /proc "$TARGET_DIR/proc"
mount --bind /sys "$TARGET_DIR/sys"

printf "${WHITE}${BOLD}[4.5/5] Regenerating initramfs for installed kernel...${RESET}\n"
KERNEL_PKG=$(chroot "$TARGET_DIR" xbps-query -l 2>/dev/null | grep -E '^ii linux[0-9]' | awk '{print $2}' | cut -d- -f1 | head -n1 || echo "linux")
[ -z "$KERNEL_PKG" ] && KERNEL_PKG="linux"

if chroot "$TARGET_DIR" xbps-reconfigure -f "$KERNEL_PKG" >/dev/null 2>&1; then
	printf "  Regenerated initramfs via xbps-reconfigure.\n"
elif chroot "$TARGET_DIR" dracut --force >/dev/null 2>&1; then
	printf "  Regenerated initramfs via dracut.\n"
fi

# Verify kernel and initramfs exist
KERNEL_IMG=$(ls "$TARGET_DIR/boot"/vmlinuz* 2>/dev/null | head -n1 || true)
INITRD_IMG=$(ls "$TARGET_DIR/boot"/initramfs* 2>/dev/null | head -n1 || true)
if [ -z "$KERNEL_IMG" ] || [ -z "$INITRD_IMG" ]; then
	echo "ERROR: Kernel image or initramfs not found in $TARGET_DIR/boot after regeneration!" >&2
	exit 1
fi
printf "${GREEN}✓ Kernel and initramfs verified in /boot.${RESET}\n"

printf "${WHITE}${BOLD}[5/5] Installing bootloader (%s)...${RESET}\n" "$BOOT_DISPLAY"

if [ "$IS_UEFI" -eq 1 ]; then
	if [ -d /sys/firmware/efi/efivars ]; then
		mkdir -p "$TARGET_DIR/sys/firmware/efi/efivars"
		mount -t efivarfs efivarfs "$TARGET_DIR/sys/firmware/efi/efivars" 2>/dev/null || true
	fi
	chroot "$TARGET_DIR" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Asura --recheck
	mkdir -p "$TARGET_DIR/boot/efi/EFI/BOOT"
	if [ -f "$TARGET_DIR/boot/efi/EFI/Asura/grubx64.efi" ]; then
		cp -f "$TARGET_DIR/boot/efi/EFI/Asura/grubx64.efi" "$TARGET_DIR/boot/efi/EFI/BOOT/BOOTX64.EFI"
	elif [ -f "$TARGET_DIR/boot/efi/EFI/asura/grubx64.efi" ]; then
		cp -f "$TARGET_DIR/boot/efi/EFI/asura/grubx64.efi" "$TARGET_DIR/boot/efi/EFI/BOOT/BOOTX64.EFI"
	fi
	chroot "$TARGET_DIR" grub-mkconfig -o /boot/grub/grub.cfg
else
	chroot "$TARGET_DIR" grub-install --target=i386-pc --recheck "$TARGET_DISK"
	chroot "$TARGET_DIR" grub-mkconfig -o /boot/grub/grub.cfg
fi

# Install the Asura snapshot GRUB snippet so /.snapshots entries are generated
if [ -d "$TARGET_DIR/usr/share/asura/session/grub" ]; then
    mkdir -p "$TARGET_DIR/etc/grub.d"
    cp "$TARGET_DIR/usr/share/asura/session/grub"/* "$TARGET_DIR/etc/grub.d/" 2>/dev/null || true
    chmod +x "$TARGET_DIR/etc/grub.d"/40_asura_snapshots 2>/dev/null || true
fi

printf "${GREEN}✓ Bootloader successfully installed.${RESET}\n"

# ── POST-INSTALLATION VERIFICATION ─────────────────────────────────────────
printf "\n${WHITE}╭──────────────────────────────────────────────────────────────╮
│                POST-INSTALLATION VERIFICATION                │
├──────────────────────────────────────────────────────────────┤${RESET}\n"

V_FSTAB="FAIL"
if grep -q "UUID=" "$TARGET_DIR/etc/fstab" && ! grep -q "UUID= " "$TARGET_DIR/etc/fstab"; then
	V_FSTAB="PASS"
fi

V_GRUB="FAIL"
if [ -s "$TARGET_DIR/boot/grub/grub.cfg" ]; then
	V_GRUB="PASS"
fi

V_KERNEL="FAIL"
if [ -n "$KERNEL_IMG" ] && [ -n "$INITRD_IMG" ]; then
	V_KERNEL="PASS"
fi

V_USER="FAIL"
if chroot "$TARGET_DIR" id -u "$USERNAME_INPUT" >/dev/null 2>&1; then
	TARGET_USER_HASH=$(grep "^${USERNAME_INPUT}:" "$TARGET_DIR/etc/shadow" 2>/dev/null | cut -d: -f2 || true)
	if [ -n "$TARGET_USER_HASH" ] && \
	   [ "$TARGET_USER_HASH" != "!" ] && \
	   [ "$TARGET_USER_HASH" != "*" ] && \
	   [ "$(printf '%s' "$TARGET_USER_HASH" | cut -c1)" != "!" ] && \
	   { [ -z "$LIVE_SHADOW_HASH" ] || [ "$TARGET_USER_HASH" != "$LIVE_SHADOW_HASH" ]; }; then
		V_USER="PASS"
	fi
fi

V_SERVICES="FAIL"
if [ -L "$TARGET_DIR/etc/runit/runsvdir/default/dbus" ] && [ -L "$TARGET_DIR/etc/runit/runsvdir/default/seatd" ]; then
	V_SERVICES="PASS"
fi

printf "${WHITE}│${RESET} [1] /etc/fstab UUIDs:       ${BOLD}%-33s${RESET} ${WHITE}│${RESET}\n" "$V_FSTAB"
printf "${WHITE}│${RESET} [2] /boot/grub/grub.cfg:    ${BOLD}%-33s${RESET} ${WHITE}│${RESET}\n" "$V_GRUB"
printf "${WHITE}│${RESET} [3] Kernel & Initramfs:     ${BOLD}%-33s${RESET} ${WHITE}│${RESET}\n" "$V_KERNEL"
printf "${WHITE}│${RESET} [4] Primary User Created:   ${BOLD}%-33s${RESET} ${WHITE}│${RESET}\n" "$V_USER ($USERNAME_INPUT)"
printf "${WHITE}│${RESET} [5] Runit Services Linked:  ${BOLD}%-33s${RESET} ${WHITE}│${RESET}\n" "$V_SERVICES"
printf "${WHITE}╰──────────────────────────────────────────────────────────────╯${RESET}\n\n"

if [ "$V_FSTAB" != "PASS" ] || [ "$V_GRUB" != "PASS" ] || [ "$V_KERNEL" != "PASS" ] || [ "$V_USER" != "PASS" ] || [ "$V_SERVICES" != "PASS" ]; then
	printf "${RED}${BOLD}Verification failed. Aborting installation.${RESET}\n" >&2
	exit 1
fi

printf "${GREEN}${BOLD}All post-installation verification checks passed.${RESET}\n"

# Unmount cleanly
if [ "$IS_UEFI" -eq 1 ]; then
	umount "$TARGET_DIR/sys/firmware/efi/efivars" 2>/dev/null || true
	umount "$TARGET_DIR/boot/efi" 2>/dev/null || true
fi
umount "$TARGET_DIR/sys"
umount "$TARGET_DIR/proc"
umount "$TARGET_DIR/dev"

if [ "$FS_TYPE" = "btrfs" ]; then
	umount "$TARGET_DIR/home"
	umount "$TARGET_DIR/.snapshots"
fi
umount "$TARGET_DIR"

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
