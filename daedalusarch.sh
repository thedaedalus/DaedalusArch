#!/usr/bin/env bash
set -euo pipefail

# DaedalusArch installer script
# - Fully scriptable via CLI flags
# - Optional LUKS+LVM encrypted root
# - Choose bootloader: grub or systemd-boot (systemd-boot requires UEFI)
# - Choose LV filesystem: ext4 (default), xfs, btrfs
# - Optional secure whole-disk wipe (dd)
# - Secure overwrite-before-delete of generated chroot helper
# - Logging to file with optional no-color output
#
# WARNING: This script is destructive. Test in a VM and run as root from an Arch live environment.

PROGNAME="$(basename "$0")"
DEFAULT_LOG="/tmp/daedalusarch.log"

# Defaults
DISK=""
HOSTNAME="archbox"
USERNAME="user"
BOOTLOADER="grub"          # grub or systemd-boot
USE_LUKS=false
LUKS_PASS=""
LUKS_PASS_FILE=""
VG_NAME="vg0"
LV_NAME="root"
LV_FS="ext4"               # ext4, xfs, btrfs
SECURE_WIPE="none"         # none or dd
LOG_FILE="$DEFAULT_LOG"
NO_COLOR=false
ASSUME_YES=false
AUTO_REBOOT=false
NO_CLEANUP=false

# Utilities: colored output unless NO_COLOR true; also log to file if LOG_FILE set
_log() {
  local lvl="$1"; shift
  local msg="$*"
  local now
  now="$(date --iso-8601=seconds 2>/dev/null || date +%s)"
  if [ "$NO_COLOR" = false ]; then
    case "$lvl" in
      INFO) printf '\033[0;34m[%s] INFO: %s\033[0m\n' "$now" "$msg" ;;
      OK)   printf '\033[0;32m[%s] OK:   %s\033[0m\n' "$now" "$msg" ;;
      WARN) printf '\033[0;33m[%s] WARN: %s\033[0m\n' "$now" "$msg" ;;
      ERR)  printf '\033[0;31m[%s] ERR:  %s\033[0m\n' "$now" "$msg" ;;
      *)    printf '[%s] %s: %s\n' "$now" "$lvl" "$msg" ;;
    esac
  else
    printf '[%s] %s: %s\n' "$now" "$lvl" "$msg"
  fi
  # Append to log file if writable
  if [ -n "$LOG_FILE" ]; then
    printf '[%s] %s: %s\n' "$now" "$lvl" "$msg" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

info()  { _log INFO "$*"; }
ok()    { _log OK "$*"; }
warn()  { _log WARN "$*"; }
err()   { _log ERR "$*"; }

usage() {
  cat <<EOF
Usage: $PROGNAME [options]

Options:
  --disk DISK                 Disk to partition (e.g. /dev/sda or /dev/nvme0n1) (required)
  --hostname NAME             Hostname (default: $HOSTNAME)
  --username NAME             Username to create (default: $USERNAME)
  --bootloader grub|systemd-boot  Bootloader to install (default: $BOOTLOADER)
  --luks                      Use LUKS+LVM for root
  --luks-pass PASS            LUKS passphrase (insecure on CLI)
  --luks-pass-file FILE       Read LUKS passphrase from file (recommended)
  --vg-name NAME              LVM VG name (default: $VG_NAME)
  --lv-name NAME              LVM LV name for root (default: $LV_NAME)
  --lv-fs ext4|xfs|btrfs      Filesystem for LV (default: $LV_FS)
  --secure-wipe none|dd       Secure wipe whole disk before partitioning (dd zeros) (default: none)
  --root-pass PASS            Root password (insecure on CLI)
  --root-pass-file FILE       Read root password from file (recommended)
  --user-pass PASS            User password (insecure on CLI)
  --user-pass-file FILE       Read user password from file (recommended)
  --log-file FILE             Append logs to FILE (default: $DEFAULT_LOG)
  --no-color                  Disable colored terminal output
  --no-cleanup                Preserve generated chroot helper for debugging
  --yes                       Non-interactive: assume confirmations
  --reboot                    Unmount and reboot at end (implies --yes)
  --help                      Show this help and exit

Notes:
  - Prefer *-file options for secrets to avoid exposing them in process listings.
  - This script will wipe the specified disk.
EOF
}

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --disk) DISK="$2"; shift 2;;
    --disk=*) DISK="${1#*=}"; shift;;
    --hostname) HOSTNAME="$2"; shift 2;;
    --hostname=*) HOSTNAME="${1#*=}"; shift;;
    --username) USERNAME="$2"; shift 2;;
    --username=*) USERNAME="${1#*=}"; shift;;
    --bootloader) BOOTLOADER="$2"; shift 2;;
    --bootloader=*) BOOTLOADER="${1#*=}"; shift;;
    --luks) USE_LUKS=true; shift;;
    --luks-pass) LUKS_PASS="$2"; shift 2;;
    --luks-pass=*) LUKS_PASS="${1#*=}"; shift;;
    --luks-pass-file) LUKS_PASS_FILE="$2"; shift 2;;
    --luks-pass-file=*) LUKS_PASS_FILE="${1#*=}"; shift;;
    --vg-name) VG_NAME="$2"; shift 2;;
    --vg-name=*) VG_NAME="${1#*=}"; shift;;
    --lv-name) LV_NAME="$2"; shift 2;;
    --lv-name=*) LV_NAME="${1#*=}"; shift;;
    --lv-fs) LV_FS="$2"; shift 2;;
    --lv-fs=*) LV_FS="${1#*=}"; shift;;
    --secure-wipe) SECURE_WIPE="$2"; shift 2;;
    --secure-wipe=*) SECURE_WIPE="${1#*=}"; shift;;
    --root-pass) ROOT_PASS="$2"; shift 2;;
    --root-pass=*) ROOT_PASS="${1#*=}"; shift;;
    --root-pass-file) ROOT_PASS_FILE="$2"; shift 2;;
    --root-pass-file=*) ROOT_PASS_FILE="${1#*=}"; shift;;
    --user-pass) USER_PASS="$2"; shift 2;;
    --user-pass=*) USER_PASS="${1#*=}"; shift;;
    --user-pass-file) USER_PASS_FILE="$2"; shift 2;;
    --user-pass-file=*) USER_PASS_FILE="${1#*=}"; shift;;
    --log-file) LOG_FILE="$2"; shift 2;;
    --log-file=*) LOG_FILE="${1#*=}"; shift;;
    --no-color) NO_COLOR=true; shift;;
    --no-cleanup) NO_CLEANUP=true; shift;;
    --yes) ASSUME_YES=true; shift;;
    --reboot) AUTO_REBOOT=true; ASSUME_YES=true; shift;;
    --help) usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 1;;
  esac
done

# Basic env checks
if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root from an Arch live environment."
  exit 1
fi
# Welcome banner
if [ "$NO_COLOR" = false ]; then
  printf '\033[0;32m'
  cat <<'BANNER'
  ____                 _       _              _             _
 |  _ \  __ _  ___  __| | __ _| |_   _ ___   / \   _ __ ___| |__
 | | | |/ _` |/ _ \/ _` |/ _` | | | | / __| / _ \ | '__/ __| '_ \
 | |_| | (_| |  __/ (_| | (_| | | |_| \__ \/ ___ \| | | (__| | | |
 |____/ \__,_|\___|\__,_|\__,_|_|\__,_|___/_/   \_\_|  \___|_| |_|
BANNER
  printf '\033[0m\n'
else
  cat <<'BANNER'
  ____                 _       _              _             _
 |  _ \  __ _  ___  __| | __ _| |_   _ ___   / \   _ __ ___| |__
 | | | |/ _` |/ _ \/ _` |/ _` | | | | / __| / _ \ | '__/ __| '_ \
 | |_| | (_| |  __/ (_| | (_| | | |_| \__ \/ ___ \| | | (__| | | |
 |____/ \__,_|\___|\__,_|\__,_|_|\__,_|___/_/   \_\_|  \___|_| |_|
BANNER
fi

# Validate some choices early
case "$BOOTLOADER" in
  grub|systemd-boot) ;;
  *)
    err "Invalid bootloader choice: '$BOOTLOADER'. Valid: grub or systemd-boot."
    exit 1
    ;;
esac

case "$LV_FS" in
  ext4|xfs|btrfs) ;;
  *)
    err "Invalid LV filesystem: '$LV_FS'. Valid: ext4, xfs, btrfs."
    exit 1
    ;;
esac

case "$SECURE_WIPE" in
  none|dd) ;;
  *)
    err "Invalid secure wipe option: '$SECURE_WIPE'. Valid: none, dd."
    exit 1
    ;;
esac

# Validate UEFI if systemd-boot chosen
if [ "$BOOTLOADER" = "systemd-boot" ] && [ ! -d /sys/firmware/efi ]; then
  err "systemd-boot requires UEFI. /sys/firmware/efi not present on this system."
  exit 1
fi

# If LUKS requested ensure cryptsetup and lvm tools exist on live
if [ "$USE_LUKS" = true ]; then
  for cmd in cryptsetup pvcreate vgcreate lvcreate; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      err "Required tool '$cmd' not found on live environment. Install and retry (or avoid --luks)."
      exit 1
    fi
  done
fi

# Ensure openssl for hashing
if ! command -v openssl >/dev/null 2>&1; then
  err "openssl not found on live environment. Required to hash passwords. Install openssl and retry."
  exit 1
fi

# dd required for secure wipe
if [ "$SECURE_WIPE" = "dd" ]; then
  if ! command -v dd >/dev/null 2>&1; then
    err "dd is required for --secure-wipe=dd but not found."
    exit 1
  fi
fi

# Read secret files if provided
if [ -n "${LUKS_PASS_FILE:-}" ]; then
  if [ ! -f "$LUKS_PASS_FILE" ]; then err "LUKS pass file not found: $LUKS_PASS_FILE"; exit 1; fi
  LUKS_PASS="$(<"$LUKS_PASS_FILE")"
fi
if [ -n "${ROOT_PASS_FILE:-}" ]; then
  if [ ! -f "$ROOT_PASS_FILE" ]; then err "Root pass file not found: $ROOT_PASS_FILE"; exit 1; fi
  ROOT_PASS="$(<"$ROOT_PASS_FILE")"
fi
if [ -n "${USER_PASS_FILE:-}" ]; then
  if [ ! -f "$USER_PASS_FILE" ]; then err "User pass file not found: $USER_PASS_FILE"; exit 1; fi
  USER_PASS="$(<"$USER_PASS_FILE")"
fi

# Prompt for missing minimal things if interactive
if [ -z "$DISK" ]; then
  if [ "$ASSUME_YES" = true ]; then
    err "--disk is required in non-interactive mode."
    exit 1
  fi
  info "Detected block devices:"
  lsblk -dno NAME,SIZE,MODEL | sed 's/^/  /' || true
  read -rp "Enter disk to partition (e.g. /dev/sda or /dev/nvme0n1): " DISK
fi
if [ -z "$HOSTNAME" ]; then read -rp "Hostname: " HOSTNAME; fi
if [ -z "$USERNAME" ]; then read -rp "Username: " USERNAME; fi

# Password prompts if needed (recommend files)
if [ -z "${ROOT_PASS:-}" ]; then
  if [ "$ASSUME_YES" = true ]; then err "Root password required in non-interactive mode (use --root-pass-file)"; exit 1; fi
  read -rsp "Root password: " ROOT_PASS; echo
fi
if [ -z "${USER_PASS:-}" ]; then
  if [ "$ASSUME_YES" = true ]; then err "User password required in non-interactive mode (use --user-pass-file)"; exit 1; fi
  read -rsp "User password: " USER_PASS; echo
fi
if [ "$USE_LUKS" = true ] && [ -z "${LUKS_PASS:-}" ]; then
  if [ "$ASSUME_YES" = true ]; then err "LUKS passphrase required in non-interactive mode (use --luks-pass-file)"; exit 1; fi
  read -rsp "LUKS passphrase: " LUKS_PASS; echo
fi

# Final destructive confirmation
if [ "$ASSUME_YES" = false ]; then
  warn "About to wipe and repartition disk: $DISK"
  read -rp "Type 'YES' to continue: " CONF
  if [ "$CONF" != "YES" ]; then err "Aborted."; exit 1; fi
else
  info "--yes specified: proceeding non-interactively."
fi

# Optional secure wipe whole disk
if [ "$SECURE_WIPE" = "dd" ]; then
  warn "Secure wiping $DISK with dd (zeros). This may take a long time."
  dd if=/dev/zero of="$DISK" bs=1M status=progress || warn "dd returned non-zero (continue anyway?)"
  sync
fi

# Partitioning and filesystems
set -x
wipefs -a "$DISK" || true
sgdisk --zap-all "$DISK" || true

PART_SUFFIX=""
if [[ "$DISK" =~ nvme ]]; then PART_SUFFIX="p"; fi
PART_EFI="${DISK}${PART_SUFFIX}1"
PART_ROOT="${DISK}${PART_SUFFIX}2"

parted --script "$DISK" mklabel gpt \
  mkpart primary fat32 1MiB 513MiB \
  mkpart primary 513MiB 100% \
  set 1 boot on \
  set 1 esp on

mkfs.fat -F32 "$PART_EFI"

# If LUKS is requested, leave PART_ROOT raw for LUKS; otherwise mkfs based on choice (ext4)
if [ "$USE_LUKS" = false ]; then
  case "$LV_FS" in
    ext4) mkfs.ext4 -F "$PART_ROOT" ;;
    xfs)  mkfs.xfs -f "$PART_ROOT" ;;
    btrfs) mkfs.btrfs -f "$PART_ROOT" ;;
  esac
fi

# Mount (if LUKS we'll remount later after LVM)
mount_point="/mnt"
mount "$PART_ROOT" "$mount_point" 2>/dev/null || mkdir -p "$mount_point" && mount "$PART_ROOT" "$mount_point"
mkdir -p "$mount_point/boot"
mount "$PART_EFI" "$mount_point/boot"

info "Pacstrap installing base system (may take a while)..."

# Build pacstrap package list
PKGS=(base linux linux-firmware sudo git networkmanager base-devel curl grub efibootmgr dosfstools)
if [ "$USE_LUKS" = true ]; then
  PKGS+=(cryptsetup lvm2)
fi

pacstrap /mnt "${PKGS[@]}" --noconfirm

info "Generating /etc/fstab..."
genfstab -U /mnt > /mnt/etc/fstab

# Hash passwords on live to avoid embedding plaintext
ROOT_PASS_HASH="$(openssl passwd -6 "$ROOT_PASS")"
USER_PASS_HASH="$(openssl passwd -6 "$USER_PASS")"

# If LUKS requested, perform LUKS+LVM setup now (we need /dev/mapper/cryptroot ready inside installed system)
LUKS_UUID=""
if [ "$USE_LUKS" = true ]; then
  info "Setting up LUKS on $PART_ROOT..."
  # LUKS format
  printf '%s' "$LUKS_PASS" | cryptsetup luksFormat --type luks2 "$PART_ROOT" -q --key-file=- || { err "luksFormat failed"; exit 1; }
  printf '%s' "$LUKS_PASS" | cryptsetup open --type luks "$PART_ROOT" cryptroot --key-file=- || { err "cryptsetup open failed"; exit 1; }
  # Create LVM on /dev/mapper/cryptroot
  pvcreate /dev/mapper/cryptroot
  vgcreate "$VG_NAME" /dev/mapper/cryptroot
  lvcreate -l 100%FREE -n "$LV_NAME" "$VG_NAME"
  LV_DEVICE="/dev/$VG_NAME/$LV_NAME"
  info "Formatting LV ($LV_DEVICE) with fs=$LV_FS..."
  case "$LV_FS" in
    ext4) mkfs.ext4 -F "$LV_DEVICE" ;;
    xfs)  mkfs.xfs -f "$LV_DEVICE" ;;
    btrfs) mkfs.btrfs -f "$LV_DEVICE" ;;
  esac
  # Remount LV as root
  umount /mnt || true
  mount "$LV_DEVICE" /mnt
  mkdir -p /mnt/boot
  mount "$PART_EFI" /mnt/boot
  LUKS_UUID="$(blkid -s UUID -o value "$PART_ROOT" 2>/dev/null || true)"
  if [ -z "$LUKS_UUID" ]; then warn "Could not determine LUKS partition UUID; crypttab will be incomplete"; fi
fi

info "Preparing chroot finish script (quoted heredoc with safe placeholder replacement)..."

# Write a quoted heredoc template (no expansion)
cat > /mnt/root/finish_chroot.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Minimal logging helpers (no color; the outer script controls color)
log() { printf '[%s] %s\n' "$(date --iso-8601=seconds 2>/dev/null || date +%s)" "$*"; }

# Placeholders
HOSTNAME="__HOSTNAME__"
USERNAME="__USERNAME__"
BOOTLOADER="__BOOTLOADER__"
USE_LUKS="__USE_LUKS__"
LUKS_UUID="__LUKS_UUID__"
VG_NAME="__VG_NAME__"
LV_NAME="__LV_NAME__"
LV_FS="__LV_FS__"
ROOT_PASS_HASH='__ROOT_PASS_HASH__'
USER_PASS_HASH='__USER_PASS_HASH__'
POST_INSTALL_URL='__POST_INSTALL_URL__'
REMOVE_FINISH='__REMOVE_FINISH__'
DISK_PLACEHOLDER='__DISK__'

log "Configuring basic system settings..."
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<HOSTS
127.0.0.1	localhost
::1		localhost
127.0.1.1	$HOSTNAME.localdomain $HOSTNAME
HOSTS

log "Creating user and setting hashed passwords..."
useradd -m -G wheel -s /bin/bash "$USERNAME" || true
echo "root:$ROOT_PASS_HASH" | chpasswd -e || true
echo "$USERNAME:$USER_PASS_HASH" | chpasswd -e || true

log "Enabling NetworkManager..."
systemctl enable NetworkManager

# If LUKS was used; configure crypttab and mkinitcpio hooks
if [ "$USE_LUKS" = "true" ]; then
  log "Configuring crypttab for LUKS root..."
  if [ -n "$LUKS_UUID" ]; then
    printf 'cryptroot UUID=%s none luks\n' "$LUKS_UUID" > /etc/crypttab
  else
    log "WARNING: LUKS UUID not provided; /etc/crypttab may need manual edits"
  fi
  # Ensure hooks contain encrypt and lvm2
  if [ -f /etc/mkinitcpio.conf ]; then
    sed -i '/^HOOKS=/ s/filesystems/ encrypt lvm2 filesystems/' /etc/mkinitcpio.conf || true
    pacman -S --noconfirm --needed lvm2 cryptsetup || true
    mkinitcpio -P || true
  fi
fi

log "Installing/configuring bootloader: $BOOTLOADER"
if [ -d /sys/firmware/efi ]; then
  if [ "$BOOTLOADER" = "grub" ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck --no-floppy || true
    if command -v grub-mkconfig >/dev/null 2>&1; then
      grub-mkconfig -o /boot/grub/grub.cfg || true
    fi
  elif [ "$BOOTLOADER" = "systemd-boot" ]; then
    if command -v bootctl >/dev/null 2>&1; then
      bootctl --path=/boot install || true
      mkdir -p /boot/loader/entries
      # If LUKS, use cryptdevice and LV root; otherwise use PARTUUID
      if [ "$USE_LUKS" = "true" ]; then
        ROOT_OPT="root=/dev/mapper/${VG_NAME}-${LV_NAME} rw"
        CRYPT_OPT="cryptdevice=UUID=${LUKS_UUID}:cryptroot"
      else
        PARTUUID=$(blkid -s PARTUUID -o value /dev/disk/by-partuuid/$(basename "$DISK_PLACEHOLDER") 2>/dev/null || true)
        ROOT_OPT="root=PARTUUID=${PARTUUID} rw"
        CRYPT_OPT=""
      fi
      cat > /boot/loader/loader.conf <<LOADER
default arch
timeout 3
editor 0
LOADER
      cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options ${CRYPT_OPT} ${ROOT_OPT}
ENTRY
    else
      log "WARNING: bootctl not found; cannot install systemd-boot"
    fi
  fi
else
  # BIOS - try grub
  if [ "$BOOTLOADER" = "grub" ]; then
    grub-install --target=i386-pc "$DISK_PLACEHOLDER" || true
    if command -v grub-mkconfig >/dev/null 2>&1; then
      grub-mkconfig -o /boot/grub/grub.cfg || true
    fi
  else
    log "WARNING: systemd-boot requested on non-UEFI system; bootloader not installed"
  fi
fi

log "Fetching post-install script..."
su - "$USERNAME" -c "curl -fsSLo ~/post_install.sh $POST_INSTALL_URL || true"
chown "$USERNAME:$USERNAME" /home/"$USERNAME"/post_install.sh || true
chmod +x /home/"$USERNAME"/post_install.sh || true

log "Running post-install script as $USERNAME..."
su - "$USERNAME" -c "/home/$USERNAME/post_install.sh --yes || true"

# Secure removal if requested
secure_remove() {
  f="$1"
  if command -v shred >/dev/null 2>&1; then
    shred -u "$f" || rm -f "$f" || true
  elif command -v dd >/dev/null 2>&1 && command -v stat >/dev/null 2>&1; then
    sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
    if [ "$sz" -gt 0 ]; then
      dd if=/dev/zero of="$f" bs=4096 count=$(( (sz+4095)/4096 )) conv=notrunc 2>/dev/null || true
      sync
    fi
    rm -f "$f" || true
  else
    rm -f "$f" || true
  fi
}

if [ "$REMOVE_FINISH" = "true" ]; then
  unset ROOT_PASS_HASH USER_PASS_HASH HOSTNAME USERNAME BOOTLOADER LV_NAME VG_NAME 2>/dev/null || true
  secure_remove /root/finish_chroot.sh || true
  log "Chroot finish script removed securely."
else
  log "Chroot finish script preserved for debugging."
fi

exit 0
EOF

# Helper to escape for sed
escape_for_sed() {
  printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'
}

# Prepare replacement values
esc_HOSTNAME=$(escape_for_sed "$HOSTNAME")
esc_USERNAME=$(escape_for_sed "$USERNAME")
esc_BOOTLOADER=$(escape_for_sed "$BOOTLOADER")
esc_USE_LUKS=$(escape_for_sed "$USE_LUKS")
esc_LUKS_UUID=$(escape_for_sed "${LUKS_UUID:-}")
esc_VG_NAME=$(escape_for_sed "$VG_NAME")
esc_LV_NAME=$(escape_for_sed "$LV_NAME")
esc_LV_FS=$(escape_for_sed "$LV_FS")
esc_ROOT_PASS_HASH=$(escape_for_sed "$ROOT_PASS_HASH")
esc_USER_PASS_HASH=$(escape_for_sed "$USER_PASS_HASH")
esc_POST_INSTALL_URL=$(escape_for_sed "$POST_INSTALL_URL")
esc_REMOVE_FINISH=$(escape_for_sed "$([ "$NO_CLEANUP" = true ] && echo "false" || echo "true")")
esc_DISK=$(escape_for_sed "$DISK")

# Replace placeholders
sed -i "s#__HOSTNAME__#${esc_HOSTNAME}#g" /mnt/root/finish_chroot.sh
sed -i "s#__USERNAME__#${esc_USERNAME}#g" /mnt/root/finish_chroot.sh
sed -i "s#__BOOTLOADER__#${esc_BOOTLOADER}#g" /mnt/root/finish_chroot.sh
sed -i "s#__USE_LUKS__#${esc_USE_LUKS}#g" /mnt/root/finish_chroot.sh
sed -i "s#__LUKS_UUID__#${esc_LUKS_UUID}#g" /mnt/root/finish_chroot.sh
sed -i "s#__VG_NAME__#${esc_VG_NAME}#g" /mnt/root/finish_chroot.sh
sed -i "s#__LV_NAME__#${esc_LV_NAME}#g" /mnt/root/finish_chroot.sh
sed -i "s#__LV_FS__#${esc_LV_FS}#g" /mnt/root/finish_chroot.sh
sed -i "s#__ROOT_PASS_HASH__#${esc_ROOT_PASS_HASH}#g" /mnt/root/finish_chroot.sh
sed -i "s#__USER_PASS_HASH__#${esc_USER_PASS_HASH}#g" /mnt/root/finish_chroot.sh
sed -i "s#__POST_INSTALL_URL__#${esc_POST_INSTALL_URL}#g" /mnt/root/finish_chroot.sh
sed -i "s#__REMOVE_FINISH__#${esc_REMOVE_FINISH}#g" /mnt/root/finish_chroot.sh
sed -i "s#__DISK__#${esc_DISK}#g" /mnt/root/finish_chroot.sh

chmod +x /mnt/root/finish_chroot.sh

info "Copied resolv.conf for chroot networking..."
cp -L /etc/resolv.conf /mnt/etc/resolv.conf || warn "Could not copy resolv.conf; chroot may lack networking"

info "Running the chroot helper..."
arch-chroot /mnt /root/finish_chroot.sh || warn "arch-chroot returned non-zero"

# Securely remove the chroot helper on live environment unless NO_CLEANUP
secure_remove_live() {
  f="/mnt/root/finish_chroot.sh"
  if [ "$NO_CLEANUP" = true ]; then
    warn "Preserving $f (--no-cleanup)"
    return 0
  fi
  if [ ! -f "$f" ]; then return 0; fi
  if command -v shred >/dev/null 2>&1; then
    shred -u "$f" || rm -f "$f" || true
  elif command -v dd >/dev/null 2>&1 && command -v stat >/dev/null 2>&1; then
    size=$(stat -c%s "$f" 2>/dev/null || echo 0)
    if [ "$size" -gt 0 ]; then
      dd if=/dev/zero of="$f" bs=4096 count=$(( (size+4095)/4096 )) conv=notrunc 2>/dev/null || true
      sync
    fi
    rm -f "$f" || true
  else
    rm -f "$f" || true
  fi
}

secure_remove_live

# Unset sensitive variables on live environment
unset ROOT_PASS USER_PASS ROOT_PASS_HASH USER_PASS_HASH LUKS_PASS LUKS_PASS_FILE 2>/dev/null || true

ok "Installation complete."

# Final unmount / reboot behavior
if [ "$AUTO_REBOOT" = true ]; then
  info "Auto-reboot requested: unmounting /mnt and rebooting..."
  umount -R /mnt || warn "umount failed; unmount manually"
  reboot || warn "reboot failed; please reboot manually"
  exit 0
fi

if [ "$ASSUME_YES" = true ]; then
  info "Non-interactive mode; not rebooting. Please unmount /mnt and reboot manually when ready."
  echo "  umount -R /mnt"
  echo "  reboot"
  exit 0
fi

read -rp "Unmount /mnt and reboot now? Type YES to unmount & reboot: " FINAL
if [ "$FINAL" = "YES" ]; then
  info "Unmounting /mnt..."
  umount -R /mnt || warn "umount failed; unmount manually"
  info "Rebooting..."
  reboot || warn "reboot failed; reboot manually"
else
  info "Done. You can unmount and reboot later:"
  echo "  umount -R /mnt"
  echo "  reboot"
fi

exit 0
