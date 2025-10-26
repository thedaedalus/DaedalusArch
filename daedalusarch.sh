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
# - Support multiple locales, vconsole keymap validation, vconsole font/font_map
#
# WARNING: This script is destructive. Test in a VM and run as root from an Arch live environment.

PROGNAME="$(basename "$0")"
DEFAULT_LOG="/tmp/daedalusarch.log"
VERSION="0.5"

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
TIMEZONE="UTC"
LOCALES="en_US.UTF-8"      # comma-separated list of locales to generate
VCONSOLE_KEYMAP="us"
VCONSOLE_FONT=""
VCONSOLE_FONT_MAP=""
DRY_RUN=false
LOG_FILE="$DEFAULT_LOG"
NO_COLOR=false
ASSUME_YES=false
AUTO_REBOOT=false
NO_CLEANUP=false

POST_INSTALL_URL="https://raw.githubusercontent.com/thedaedalus/DaedalusArch/main/post_install.sh"

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
  --timezone TZ               Timezone (e.g. 'UTC' or 'America/New_York'; default: $TIMEZONE)
  --locales LOCALES           Comma-separated locales to generate (default: $LOCALES)
  --vconsole-keymap MAP       Console keymap for /etc/vconsole.conf (default: $VCONSOLE_KEYMAP)
  --vconsole-font FONT        Console font for /etc/vconsole.conf (optional)
  --vconsole-font-map MAP     Console FONT_MAP for /etc/vconsole.conf (optional)
  --dry-run                   Print planned actions and exit (no destructive changes)
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
    --timezone) TIMEZONE="$2"; shift 2;;
    --timezone=*) TIMEZONE="${1#*=}"; shift;;
    --locales) LOCALES="$2"; shift 2;;
    --locales=*) LOCALES="${1#*=}"; shift;;
    --vconsole-keymap) VCONSOLE_KEYMAP="$2"; shift 2;;
    --vconsole-keymap=*) VCONSOLE_KEYMAP="${1#*=}"; shift;;
    --vconsole-font) VCONSOLE_FONT="$2"; shift 2;;
    --vconsole-font=*) VCONSOLE_FONT="${1#*=}"; shift;;
    --vconsole-font-map) VCONSOLE_FONT_MAP="$2"; shift 2;;
    --vconsole-font-map=*) VCONSOLE_FONT_MAP="${1#*=}"; shift;;
    --dry-run) DRY_RUN=true; shift;;
    --dry-run=*) DRY_RUN=true; shift;;
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

# Welcome banner (interactive-only)
print_banner() {
  # Skip banner in non-interactive mode
  if [ "$ASSUME_YES" = true ]; then
    return 0
  fi

  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local disk_disp
  if [ -n "$DISK" ]; then disk_disp="$DISK"; else disk_disp="(not specified yet)"; fi

  if [ "$NO_COLOR" = false ]; then
    printf '\033[0;36m'
  fi

  cat <<'BANNER'
  ____                 _       _              _             _
 |  _ \  __ _  ___  __| | __ _| |_   _ ___   / \   _ __ ___| |__
 | | | |/ _` |/ _ \/ _` |/ _` | | | | / __| / _ \ | '__/ __| '_ \
 | |_| | (_| |  __/ (_| | (_| | | |_| \__ \/ ___ \| | | (__| | | |
 |____/ \__,_|\___|\__,_|\__,_|_|\__,_|___/_/   \_\_|  \___|_| |_|
BANNER

  if [ "$NO_COLOR" = false ]; then
    printf '\033[0m'
  fi

  printf 'Version: %s  Date: %s  Target disk: %s  TZ: %s  Locales: %s  Keymap: %s  Font: %s  FontMap: %s\n' \
    "$VERSION" "$now" "$disk_disp" "$TIMEZONE" "$LOCALES" "$VCONSOLE_KEYMAP" "${VCONSOLE_FONT:-(none)}" "${VCONSOLE_FONT_MAP:-(none)}"
}

# Print banner now (after parsing so --no-color is effective)
print_banner

# Basic env checks
if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root from an Arch live environment."
  exit 1
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

# Validate timezone availability
if [ -n "${TIMEZONE:-}" ]; then
  if [ ! -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
    if [ "$ASSUME_YES" = true ]; then
      err "Timezone '/usr/share/zoneinfo/${TIMEZONE}' not found on live system. In non-interactive mode provide a valid --timezone."
      exit 1
    else
      warn "Timezone '/usr/share/zoneinfo/${TIMEZONE}' not found on live system."
      read -rp "Continue with '$TIMEZONE' anyway? [y/N]: " _tzreply < /dev/tty
      if [[ ! "$_tzreply" =~ ^[Yy]$ ]]; then
        read -rp "Enter an alternative timezone (or press Enter to keep '$TIMEZONE'): " _alt_tz < /dev/tty
        if [ -n "$_alt_tz" ]; then
          TIMEZONE="$_alt_tz"
          if [ ! -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
            warn "Alternate timezone '/usr/share/zoneinfo/${TIMEZONE}' not found; will default to UTC in installed system."
          fi
        fi
      fi
    fi
  fi
fi

# Validate vconsole keymap against /usr/share/kbd/keymaps (warn or fail)
if [ -n "${VCONSOLE_KEYMAP:-}" ]; then
  # Try to find a keymap file that matches the keymap name
  found_keymap=false
  if [ -d /usr/share/kbd/keymaps ]; then
    # Many distributions store keymaps under subdirectories; search for a matching filename
    # We do a simple file name match (keymap.map.gz or keymap.map), or directory name containing the keymap
    while IFS= read -r -d '' f; do
      fname="$(basename "$f")"
      case "$fname" in
        "$VCONSOLE_KEYMAP" | "$VCONSOLE_KEYMAP".map | "$VCONSOLE_KEYMAP".map.gz) found_keymap=true; break ;;
      esac
    done < <(find /usr/share/kbd/keymaps -type f -print0 2>/dev/null || true)
  fi

  if [ "$found_keymap" = false ]; then
    if [ "$ASSUME_YES" = true ]; then
      err "vconsole keymap '$VCONSOLE_KEYMAP' not found under /usr/share/kbd/keymaps. Exiting (non-interactive mode)."
      exit 1
    else
      warn "vconsole keymap '$VCONSOLE_KEYMAP' not found under /usr/share/kbd/keymaps. You may get a wrong keymap in the installed system."
      read -rp "Continue anyway? [y/N]: " _reply < /dev/tty
      if [[ ! "$_reply" =~ ^[Yy]$ ]]; then
        err "Aborted by user due to missing keymap."
        exit 1
      fi
    fi
  else
    info "vconsole keymap '$VCONSOLE_KEYMAP' found."
  fi
fi

# Validate vconsole font exists under /usr/share/kbd/consolefonts (if provided)
if [ -n "${VCONSOLE_FONT:-}" ]; then
  found_font=false
  if [ -d /usr/share/kbd/consolefonts ]; then
    if ls /usr/share/kbd/consolefonts/"${VCONSOLE_FONT}"* >/dev/null 2>&1; then found_font=true; fi
  fi

  if [ "$found_font" = false ]; then
    if [ "$ASSUME_YES" = true ]; then
      err "vconsole font '${VCONSOLE_FONT}' not found under /usr/share/kbd/consolefonts. Provide a valid --vconsole-font in non-interactive mode."
      exit 1
    else
      warn "vconsole font '${VCONSOLE_FONT}' not found under /usr/share/kbd/consolefonts."
      read -rp "Continue without setting font? [y/N]: " _freply < /dev/tty
      if [[ ! \"$_freply\" =~ ^[Yy]$ ]]; then
        read -rp "Enter alternative vconsole font (or leave empty to skip): " _alt_font < /dev/tty
        if [ -n \"$_alt_font\" ]; then
          VCONSOLE_FONT=\"$_alt_font\"
          # quick check
          if ! ls /usr/share/kbd/consolefonts/\"${VCONSOLE_FONT}\"* >/dev/null 2>&1; then
            warn "Alternate font not found; continuing without font."
            VCONSOLE_FONT=\"\"
          fi
        fi
      fi
    fi
  else
    info "vconsole font '${VCONSOLE_FONT}' found."
  fi
fi

# Basic locale sanity check for first provided locale (warn only)
IFS=',' read -r -a _LOCALES_ARR <<< "$LOCALES"
first_locale="${_LOCALES_ARR[0]}"
case "$first_locale" in
  *.*) ;; # looks like LANG.CHARSET
  *) warn "First locale '$first_locale' does not match expected pattern like en_US.UTF-8." ;;
esac

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

# Prompt for minimal things and allow overriding defaults in interactive mode
if [ -z "$DISK" ]; then
  if [ "$ASSUME_YES" = true ]; then
    err "--disk is required in non-interactive mode."
    exit 1
  fi
  info "Detected block devices:"
  lsblk -dno NAME,SIZE,MODEL | sed 's/^/  /' || true
  read -rp "Enter disk to partition (e.g. /dev/sda or /dev/nvme0n1): " DISK < /dev/tty
else
  # If a disk was provided but we're interactive, give the user a chance to override it
  if [ "$ASSUME_YES" = false ]; then
    read -rp "Target disk [$DISK] (leave empty to keep): " _tmp < /dev/tty
    if [ -n "$_tmp" ]; then DISK="$_tmp"; fi
  fi
fi

# Prompt interactively for common options even when defaults exist (only in interactive mode)
if [ "$ASSUME_YES" = false ]; then
  read -rp "Hostname [$HOSTNAME]: " _tmp < /dev/tty
  if [ -n "$_tmp" ]; then HOSTNAME="$_tmp"; fi

  read -rp "Username [$USERNAME]: " _tmp < /dev/tty
  if [ -n "$_tmp" ]; then USERNAME="$_tmp"; fi

  # Password prompts if needed (recommend files)
  if [ -z "${ROOT_PASS:-}" ]; then
    if [ "$ASSUME_YES" = true ]; then err "Root password required in non-interactive mode (use --root-pass-file)"; exit 1; fi
    read -rsp "Root password: " ROOT_PASS < /dev/tty; echo
  fi
  if [ -z "${USER_PASS:-}" ]; then
    if [ "$ASSUME_YES" = true ]; then err "User password required in non-interactive mode (use --user-pass-file)"; exit 1; fi
    read -rsp "User password: " USER_PASS < /dev/tty; echo
  fi

  read -rp "Bootloader (grub|systemd-boot) [$BOOTLOADER]: " _tmp < /dev/tty
  if [ -n "$_tmp" ]; then BOOTLOADER="$_tmp"; fi

  # Ask whether to use LUKS+LVM (default reflects current value)
  read -rp "Use LUKS+LVM for root? [y/N] " _tmp < /dev/tty
  case "$_tmp" in
    [Yy]*)
      USE_LUKS=true
      ;;
    [Nn]|'')
      USE_LUKS=false
      ;;
    *)
      USE_LUKS=false
      ;;
  esac


  # If LUKS is selected and no passphrase provided via CLI/files, prompt for one
  if [ "$USE_LUKS" = true ] && [ -z "${LUKS_PASS:-}" ]; then
    read -rsp "LUKS passphrase: " LUKS_PASS < /dev/tty
    echo
  fi

  if [ "$USE_LUKS" = true ] && [ -z "${LUKS_PASS:-}" ]; then
    if [ "$ASSUME_YES" = true ]; then err "LUKS passphrase required in non-interactive mode (use --luks-pass-file)"; exit 1; fi
    read -rsp "LUKS passphrase: " LUKS_PASS < /dev/tty; echo
  fi
  read -rp "LV filesystem (ext4|xfs|btrfs) [$LV_FS]: " _tmp < /dev/tty
  if [ -n "$_tmp" ]; then LV_FS="$_tmp"; fi

  read -rp "Secure wipe whole disk? (none|dd) [$SECURE_WIPE]: " _tmp < /dev/tty
  if [ -n "$_tmp" ]; then SECURE_WIPE="$_tmp"; fi

  read -rp "Timezone [$TIMEZONE]: " _tmp < /dev/tty
  if [ -n "$_tmp" ]; then TIMEZONE="$_tmp"; fi

  read -rp "Locales (comma-separated) [$LOCALES]: " _tmp < /dev/tty
  if [ -n "$_tmp" ]; then LOCALES="$_tmp"; fi

  read -rp "vconsole keymap [$VCONSOLE_KEYMAP]: " _tmp < /dev/tty
  if [ -n "$_tmp" ]; then VCONSOLE_KEYMAP="$_tmp"; fi

  read -rp "vconsole font (optional) [$VCONSOLE_FONT]: " _tmp < /dev/tty
  if [ -n "$_tmp" ]; then VCONSOLE_FONT="$_tmp"; fi

  read -rp "vconsole font map (optional) [$VCONSOLE_FONT_MAP]: " _tmp < /dev/tty
  if [ -n "$_tmp" ]; then VCONSOLE_FONT_MAP="$_tmp"; fi
fi



# Final destructive confirmation
if [ "$ASSUME_YES" = false ]; then
  warn "About to wipe and repartition disk: $DISK"
  read -rp "Type 'YES' to continue: " CONF < /dev/tty
  if [ "$CONF" != "YES" ]; then err "Aborted."; exit 1; fi
else
  info "--yes specified: proceeding non-interactively."
fi

# Dry-run mode: print planned actions and exit without making changes
if [ "$DRY_RUN" = true ]; then
  info "DRY-RUN: planned actions (no changes will be made):"
  echo "  Target disk: $DISK"
  echo "  Secure wipe: $SECURE_WIPE"
  echo "  Use LUKS+LVM: $USE_LUKS"
  echo "  VG: $VG_NAME  LV: $LV_NAME  LV FS: $LV_FS"
  echo "  Bootloader: $BOOTLOADER"
  echo "  Timezone: $TIMEZONE"
  echo "  Locales: $LOCALES"
  echo "  vconsole keymap: $VCONSOLE_KEYMAP  font: ${VCONSOLE_FONT:-}(none)  font_map: ${VCONSOLE_FONT_MAP:-}(none)"
  echo "  Will install packages: base linux linux-firmware sudo git networkmanager base-devel curl grub efibootmgr dosfstools terminus-font"
  echo "Dry-run complete."
  exit 0
fi

# Optional secure wipe whole disk
if [ "$SECURE_WIPE" = "dd" ]; then
  warn "Secure wiping $DISK with dd (zeros). This may take a long time."
  dd if=/dev/zero of="$DISK" bs=1M status=progress || warn "dd returned non-zero (continue anyway?)"
  sync
fi

# Partitioning and filesystems
set -x

# Attempt to free the device before wipefs/sgdisk: unmount mounts, swapoff, deactivate LVM, close crypt mappings
DISK_BASENAME="$(basename "$DISK" 2>/dev/null || true)"
if [ -n "$DISK_BASENAME" ]; then
  info "Attempting to unmount partitions and deactivate mappings on $DISK..."
  # Unmount any mounted partitions belonging to the disk
  while IFS= read -r part; do
    dev="/dev/${part}"
    # If mounted, try lazy unmount then regular unmount
    mnt="$(lsblk -n -o MOUNTPOINT "$dev" 2>/dev/null || true)"
    if [ -n "$mnt" ]; then
      warn "Unmounting $dev (mounted at $mnt)..."
      umount -l "$dev" 2>/dev/null || umount "$dev" 2>/dev/null || true
    fi
    # Disable swap on partition if it's used as swap
    if awk '{print $1}' /proc/swaps 2>/dev/null | grep -qx "$dev"; then
      warn "Turning off swap on $dev..."
      swapoff "$dev" 2>/dev/null || true
    fi
  done < <(lsblk -ln -o NAME "${DISK}" 2>/dev/null | tail -n +2 || true)

  # Deactivate LVM volumes and VGs if any PVs are on this disk
  if command -v pvs >/dev/null 2>&1 && command -v vgchange >/dev/null 2>&1; then
    # Find PVs that reference the disk basename
    for pv in $(pvs --noheadings -o pv_name 2>/dev/null | awk '{print $1}' | grep "${DISK_BASENAME}" || true); do
      # Try to find VG and deactivate
      vg=$(pvs --noheadings -o vg_name "$pv" 2>/dev/null | awk '{print $1}' || true)
      if [ -n "$vg" ]; then
        warn "Deactivating VG $vg ..."
        lvchange -an "/dev/$vg" 2>/dev/null || true
        vgchange -an "$vg" 2>/dev/null || true
      fi
    done
    # Best-effort: deactivate all VGs to release devices
    vgchange -an 2>/dev/null || true
  fi

  # Close cryptsetup mappings whose underlying device lives on this disk
  if command -v cryptsetup >/dev/null 2>&1 && [ -d /dev/mapper ]; then
    for map in $(ls /dev/mapper 2>/dev/null || true); do
      if cryptsetup status "$map" >/dev/null 2>&1; then
        # attempt to extract the backing device path from status output
        backing="$(cryptsetup status "$map" 2>/dev/null | awk '/device:/ {print $2}' || true)"
        if [ -n "$backing" ] && echo "$backing" | grep -q "${DISK_BASENAME}"; then
          warn "Closing crypt mapping $map which references $backing ..."
          cryptsetup close "$map" 2>/dev/null || true
        fi
      fi
    done
  fi
fi

# Give the kernel a moment to release resources
sleep 1

# Now attempt wipefs/sgdisk
wipefs -a "$DISK" || warn "wipefs returned non-zero; continuing"
sgdisk --zap-all "$DISK" || warn "sgdisk --zap-all returned non-zero; continuing"

PART_SUFFIX=""
if [[ "$DISK" =~ nvme ]]; then PART_SUFFIX="p"; fi

# Create GPT partitions if they don't already exist:
#  - partition 1: EFI System (512M)
#  - partition 2: root (remaining space)
info "Creating GPT partitions on $DISK: 1=EFI 2GB, 2=ROOT (rest)"
if ! sgdisk -n1:0:+512M -t1:ef00 -c1:"EFI System" "$DISK" >/dev/null 2>&1; then
  warn "sgdisk: could not create EFI partition (it may already exist or sgdisk failed). Attempting to continue."
fi
if ! sgdisk -n2:0:0 -t2:8300 -c2:"Linux Root" "$DISK" >/dev/null 2>&1; then
  warn "sgdisk: could not create root partition (it may already exist or sgdisk failed). Attempting to continue."
fi

# Ask kernel to re-read partition table / ensure device nodes exist
if command -v partprobe >/dev/null 2>&1; then
  partprobe "$DISK" 2>/dev/null || true
fi
sleep 1

PART_EFI="${DISK}${PART_SUFFIX}1"
PART_ROOT="${DISK}${PART_SUFFIX}2"

# Wait briefly for partition device nodes to appear (best-effort)
for i in 1 2 3 4 5; do
  if [ -b "$PART_EFI" ] && [ -b "$PART_ROOT" ]; then
    break
  fi
  sleep 1
done

# Create EFI filesystem
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
PKGS=(base linux linux-firmware sudo git networkmanager base-devel curl grub efibootmgr dosfstools terminus-font)
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
TIMEZONE='__TIMEZONE__'
LOCALES='__LOCALES__'
VCONSOLE_KEYMAP='__VCONSOLE__'
VCONSOLE_FONT='__VCONSOLE_FONT__'
VCONSOLE_FONT_MAP='__VCONSOLE_FONT_MAP__'

log "Configuring basic system settings..."
# Timezone
if [ -n "__TIMEZONE__" ] && [ -f "/usr/share/zoneinfo/__TIMEZONE__" ]; then
  ln -sf /usr/share/zoneinfo/__TIMEZONE__ /etc/localtime
else
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
  log "WARNING: requested timezone not available; UTC applied"
fi
hwclock --systohc

# Locales: generate one or more locales
if [ -n "__LOCALES__" ]; then
  IFS=',' read -ra LOCALES_ARR <<< "__LOCALES__"
  : > /etc/locale.gen
  for L in "${LOCALES_ARR[@]}"; do
    L_TRIM=$(echo "$L" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$L_TRIM" ]; then
      echo "$L_TRIM UTF-8" >> /etc/locale.gen
    fi
  done
else
  echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
fi
locale-gen
# Set LANG to first locale
if [ -n "__LOCALES__" ]; then
  FIRST_LOCALE=$(echo "__LOCALES__" | cut -d',' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  echo "LANG=$FIRST_LOCALE" > /etc/locale.conf
else
  echo "LANG=en_US.UTF-8" > /etc/locale.conf
fi

# vconsole keymap, font, font map
if [ -n "__VCONSOLE__" ]; then
  echo "KEYMAP=__VCONSOLE__" > /etc/vconsole.conf
fi
if [ -n "__VCONSOLE_FONT__" ] && [ "__VCONSOLE_FONT__" != "''" ]; then
  echo "FONT=__VCONSOLE_FONT__" >> /etc/vconsole.conf
fi
if [ -n "__VCONSOLE_FONT_MAP__" ] && [ "__VCONSOLE_FONT_MAP__" != "''" ]; then
  echo "FONT_MAP=__VCONSOLE_FONT_MAP__" >> /etc/vconsole.conf
fi

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
esc_TIMEZONE=$(escape_for_sed "$TIMEZONE")
esc_LOCALES=$(escape_for_sed "$LOCALES")
esc_VCONSOLE=$(escape_for_sed "$VCONSOLE_KEYMAP")
esc_VCONSOLE_FONT=$(escape_for_sed "${VCONSOLE_FONT:-}")
esc_VCONSOLE_FONT_MAP=$(escape_for_sed "${VCONSOLE_FONT_MAP:-}")

# Replace placeholders in the chroot helper
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
sed -i "s#__TIMEZONE__#${esc_TIMEZONE}#g" /mnt/root/finish_chroot.sh
sed -i "s#__LOCALES__#${esc_LOCALES}#g" /mnt/root/finish_chroot.sh
sed -i "s#__VCONSOLE__#${esc_VCONSOLE}#g" /mnt/root/finish_chroot.sh
sed -i "s#__VCONSOLE_FONT__#${esc_VCONSOLE_FONT}#g" /mnt/root/finish_chroot.sh
sed -i "s#__VCONSOLE_FONT_MAP__#${esc_VCONSOLE_FONT_MAP}#g" /mnt/root/finish_chroot.sh

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

ok "Installation flow complete."

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

read -rp "Unmount /mnt and reboot now? Type YES to unmount & reboot: " FINAL < /dev/tty
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
