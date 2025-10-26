#!/usr/bin/env bash
#
# post_install.sh
#
# Post-install automation for DaedalusArch
#
# Usage:
#   ./post_install.sh [--yes] [--reboot]
#
# Options:
#   --yes     Run non-interactively where possible (will pass --noconfirm to pkg managers)
#   --reboot  Reboot automatically at the end (requires sudo)
#
# Notes:
# - This script is intended to be run after entering the installed system as the regular user
#   (i.e. after chroot and `su - <user>`). It will try to detect the invoking user automatically.
# - Some operations require root; the script uses `sudo` where appropriate.
# - Review before running. This automates network downloads and package installs.
set -euo pipefail

# ---------- Configuration ----------
PACMAN_OPTS=()
PARU_OPTS=()
YES=false
AUTO_REBOOT=false
DRY_RUN=false

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Timestamped logfile in the directory the script is run from
LOGFILE="$(pwd)/post_install-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOGFILE")"
# Create/empty the logfile and add a header
: > "$LOGFILE"
echo "Post-install run started at: $(date --iso-8601=seconds)" >> "$LOGFILE"

for arg in "$@"; do
  case "$arg" in
    --yes) YES=true ;;
    --reboot) AUTO_REBOOT=true ;;
    --dry-run|--dryrun) DRY_RUN=true ;;
    *) echo "Unknown arg: $arg"; exit 2 ;;
  esac
done

if [ "$YES" = true ]; then
  PACMAN_OPTS+=(--noconfirm --needed)
  PARU_OPTS+=(--noconfirm --needed)
fi

if [ "$DRY_RUN" = true ]; then
  printf '\n[+] %s\n' "Running in dry-run mode; commands will be printed but not executed."
  echo "[DRYRUN] Running in dry-run mode; commands will be printed but not executed." >> "$LOGFILE"
fi

log() { printf '\n[+] %s\n' "$*"; }
err() { printf '\n[!] %s\n' "$*" >&2; }

# Summary tracking
SUMMARY_INSTALLED=()
SUMMARY_SKIPPED=()
SUMMARY_ENABLED=()
SUMMARY_ACTIONS=()
SUMMARY_ERRORS=()

summary_add() {
  # summary_add <category> <message>
  local cat="$1"; shift
  local msg="$*"
  case "$cat" in
    installed) SUMMARY_INSTALLED+=("$msg") ;;
    skipped) SUMMARY_SKIPPED+=("$msg") ;;
    enabled) SUMMARY_ENABLED+=("$msg") ;;
    action) SUMMARY_ACTIONS+=("$msg") ;;
    error) SUMMARY_ERRORS+=("$msg") ;;
    *) SUMMARY_ACTIONS+=("$cat:$msg") ;;
  esac
}

summary_print() {
  log "Summary:"
  if [ ${#SUMMARY_INSTALLED[@]} -gt 0 ]; then
    printf '\nInstalled:\n'
    for i in "${SUMMARY_INSTALLED[@]}"; do printf '  - %s\n' "$i"; done
  fi
  if [ ${#SUMMARY_SKIPPED[@]} -gt 0 ]; then
    printf '\nSkipped (already present):\n'
    for i in "${SUMMARY_SKIPPED[@]}"; do printf '  - %s\n' "$i"; done
  fi
  if [ ${#SUMMARY_ENABLED[@]} -gt 0 ]; then
    printf '\nEnabled services:\n'
    for i in "${SUMMARY_ENABLED[@]}"; do printf '  - %s\n' "$i"; done
  fi
  if [ ${#SUMMARY_ACTIONS[@]} -gt 0 ]; then
    printf '\nOther actions:\n'
    for i in "${SUMMARY_ACTIONS[@]}"; do printf '  - %s\n' "$i"; done
  fi
  if [ ${#SUMMARY_ERRORS[@]} -gt 0 ]; then
    printf '\nErrors / Warnings:\n'
    for i in "${SUMMARY_ERRORS[@]}"; do printf '  - %s\n' "$i"; done
  fi
  printf '\n'
}

# Determine a sensible user to run per-user actions as.
# Prefer SUDO_USER (if invoked with sudo), otherwise $USER, otherwise id -un
if [ -n "${SUDO_USER-}" ]; then
  USERNAME="$SUDO_USER"
elif [ -n "${USER-}" ]; then
  USERNAME="$USER"
else
  USERNAME="$(id -un)"
fi

USER_HOME="$(eval echo "~$USERNAME")"

log "Detected user: $USERNAME (home: $USER_HOME)"

# Helper to run a command as the non-root user (preserve environment where useful)
# Captures command output to the logfile (appends). In dry-run we record the action.
run_as_user() {
  if [ "${DRY_RUN:-false}" = true ]; then
    printf '[DRYRUN] as %s: %s\n' "$USERNAME" "$*"
    record_dry_action "as $USERNAME: $*"
    echo "[DRYRUN] as $USERNAME: $*" >> "$LOGFILE"
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    # When running via sudo as another user, use bash -lc and tee to append output to logfile.
    sudo -Hu "$USERNAME" bash -lc "$* 2>&1 | tee -a '$LOGFILE'"
  else
    # already running as user; pipe output to tee to capture to logfile as well
    bash -lc "$* 2>&1 | tee -a '$LOGFILE'"
  fi
}

# Helper to run a command as root using sudo (will error if sudo not available)
# Command output is appended to the timestamped logfile.
# This helper prefers an interactive sudo prompt. If no TTY is available, and an
# askpass helper is provided via the SUDO_ASKPASS or ASKPASS environment
# variables, sudo will be invoked with -A to use that helper.
# To minimize repeated prompts we validate the sudo timestamp once per run.
SUDO_VALIDATED=false
run_root() {
  if [ "${DRY_RUN:-false}" = true ]; then
    printf '[DRYRUN] as root: %s\n' "$*"
    record_dry_action "as root: $*"
    echo "[DRYRUN] as root: $*" >> "$LOGFILE"
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    # Already root; run the command and tee output to logfile
    bash -lc "$* 2>&1 | tee -a '$LOGFILE'"
    return $?
  fi

  # Try to validate sudo credential cache once. If validation fails because no
  # TTY is present, fall back to using an askpass helper if one is configured.
  if [ "${SUDO_VALIDATED}" != "true" ]; then
    if sudo -v 2>/dev/null; then
      SUDO_VALIDATED=true
    else
      if [ -n "${SUDO_ASKPASS-}" ] || [ -n "${ASKPASS-}" ]; then
        # Prefer SUDO_ASKPASS if set, otherwise use ASKPASS
        ASK=${SUDO_ASKPASS:-$ASKPASS}
        export SUDO_ASKPASS="$ASK"
        # Mark validated so we attempt sudo -A below
        SUDO_VALIDATED=true
        echo "[+] Using askpass helper: $ASK" >> "$LOGFILE"
      else
        # No TTY and no askpass helper — let sudo try anyway (it may fail)
        echo "[!] sudo validation failed and no askpass helper configured; attempting sudo which may fail in non-interactive contexts" >> "$LOGFILE"
      fi
    fi
  fi

  # If an askpass helper is configured in the environment, use sudo -A so it
  # calls the helper to obtain a password. Otherwise use normal sudo which
  # will prompt on the controlling TTY.
  if [ -n "${SUDO_ASKPASS-}" ]; then
    sudo -A bash -lc "$* 2>&1 | tee -a '$LOGFILE'"
  else
    sudo bash -lc "$* 2>&1 | tee -a '$LOGFILE'"
  fi
}

# ---------- Step 1: Install CachyOS repos ----------
install_cachyos_repo() {
  log "Installing CachyOS repo (if not already installed)..."
  # Check for obvious signs the repo is already present
  if [ -f /etc/pacman.d/cachyos-mirrorlist ] || grep -q '^\[cachyos' /etc/pacman.conf 2>/dev/null; then
    log "CachyOS repo appears to be already installed; skipping."
    return 0
  fi

  TMPDIR="$(mktemp -d /tmp/cachyos-repo.XXXX)"
  #cleanup() { rm -rf "$TMPDIR"; }
  #trap cleanup EXIT

  cd "$TMPDIR"
  if curl -fsSLO "https://mirror.cachyos.org/cachyos-repo.tar.xz"; then
    tar xvf cachyos-repo.tar.xz
    if [ -f "./cachyos-repo.sh" ]; then
      run_root "./cachyos-repo.sh"
    else
      err "cachyos-repo.sh not found in archive; aborting cachyos repo install step"
    fi
  else
    err "Failed to download cachyos-repo.tar.xz; skipping CachyOS repo install"
  fi
}

# ---------- Step 2: Install CachyOS kernel ----------
install_cachyos_kernel() {
  log "Installing CachyOS kernel packages..."
  # If linux-cachyos is already installed, skip
  if pacman -Qi linux-cachyos >/dev/null 2>&1; then
    log "linux-cachyos already installed; skipping kernel install."
    return 0
  fi

  run_root "pacman -Syu ${PACMAN_OPTS[*]} linux-cachyos linux-cachyos-headers" || \
    err "Failed to install linux-cachyos packages (they may not be available on your system)"
}

# ---------- Step 3: Enable SSH ----------
enable_ssh() {
  log "Installing openssh and enabling sshd (will not start in chroot)..."
  # Install openssh package (skip if already installed)
  if pacman -Qi openssh >/dev/null 2>&1; then
    log "openssh already installed; skipping package install."
  else
    run_root "pacman -S ${PACMAN_OPTS[*]} openssh"
  fi

  # If systemd is present on the system (not a chroot), enable the unit.
  # We avoid attempting to start services inside a chroot environment.
  if [ -d /run/systemd/system ]; then
    # If the sshd unit exists, enable it if not already enabled.
    if run_root "systemctl list-unit-files --type=service | grep -q '^sshd\.service'"; then
      if run_root "systemctl is-enabled --quiet sshd"; then
        log "sshd already enabled"
      else
        run_root "systemctl enable sshd" || log "Failed to enable sshd"
      fi
    else
      log "sshd unit not present; skipping enable"
    fi
  else
    log "systemd not available (likely running in a chroot); skipping enable"
  fi

  # Start the service only if PID 1 is systemd (i.e. not in a chroot)
  if [ -r /proc/1/comm ] && grep -q '^systemd$' /proc/1/comm 2>/dev/null; then
    log "Starting sshd service"
    run_root "systemctl start sshd" || log "Failed to start sshd; you may need to start it after boot"
  else
    log "Detected chroot or non-systemd init; skipping starting sshd (enable only)"
  fi
}

# ---------- Step 4: Install Chaotic-AUR repo ----------
install_chaotic_aur() {
  log "Installing Chaotic-AUR repo keys and mirrorlist..."
  # Key import and pacman -U of chaotic packages (will create mirrorlist file)
  run_root "pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com"
  run_root "pacman-key --lsign-key 3056513887B78AEB"
  run_root "pacman -U ${PACMAN_OPTS[*]} 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'"

  # Add repo to /etc/pacman.conf if missing
  if ! grep -q "^\[chaotic-aur\]" /etc/pacman.conf; then
    log "Adding [chaotic-aur] to /etc/pacman.conf"
    run_root "bash -lc 'cat >> /etc/pacman.conf <<EOF

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF'"
  else
    log "chaotic-aur already present in /etc/pacman.conf"
  fi

  run_root "pacman -Syu ${PACMAN_OPTS[*]}"
}

# ---------- Step 5: Install paru ----------
install_paru() {
  if command -v paru >/dev/null 2>&1; then
    log "paru already installed"
    return
  fi

  log "Installing paru (AUR helper) via pacman..."
  # paru may be unavailable depending on repos; README suggests pacman -S paru
  run_root "pacman -S ${PACMAN_OPTS[*]} paru" || err "Failed to install paru. You may need to install it manually."
}

# ---------- Step 6: Install Dank Linux ----------
install_danklinux() {
  log "Installing Dank Linux (interactive installer)..."
  # This runs install script from the network; it's interactive.
  run_as_user "curl -fsSL https://install.danklinux.com | sh"
  log "If the Dank Linux installer required manual choices, please complete them."
}

# ---------- Step 7: Install greeter and enable greetd ----------
install_greeter_enable_greetd() {
  log "Installing greeter and enabling greetd (idempotent, chroot-safe)..."

  # If dms is not present, skip and inform the user.
  if ! command -v dms >/dev/null 2>&1; then
    log "dms not found; skipping greeter install. If you installed Dank Linux, ensure `dms` is in your PATH and try again."
    summary_add action "dms not found; skipped greeter install"
    return 0
  fi

  # If greetd is already enabled, skip installation/enablement.
  if run_root "systemctl list-unit-files --type=service 2>/dev/null | grep -q '^greetd\.service' 2>/dev/null" && run_root "systemctl is-enabled --quiet greetd 2>/dev/null"; then
    log "greetd already enabled; skipping greeter install."
    summary_add skipped "greetd (already enabled)"
    return 0
  fi

  # Run the greeter installer as the regular user. Allow it to return non-zero (may already be configured).
  if run_as_user "dms greeter install"; then
    summary_add action "dms greeter install ran"
  else
    log "dms greeter install returned non-zero (may already be configured or require manual steps)."
    summary_add action "dms greeter install returned non-zero"
  fi

  # ensure greetd package installed
  if pacman -Qi greetd >/dev/null 2>&1; then
    log "greetd package already installed"
    summary_add skipped "greetd package"
  else
    if run_root "pacman -S ${PACMAN_OPTS[*]} greetd"; then
      summary_add installed "greetd package"
    else
      summary_add error "greetd package install failed"
    fi
  fi

  # Enable the greetd unit if systemd is present (don't attempt to start services inside a chroot).
  if [ -d /run/systemd/system ]; then
    if run_root "systemctl list-unit-files --type=service 2>/dev/null | grep -q '^greetd\.service' 2>/dev/null"; then
      if run_root "systemctl is-enabled --quiet greetd 2>/dev/null"; then
        log "greetd already enabled"
        summary_add enabled "greetd"
      else
        if run_root "systemctl enable greetd"; then
          summary_add enabled "greetd"
        else
          log "Failed to enable greetd"
          summary_add error "failed to enable greetd"
        fi
      fi
    else
      log "greetd unit not present; skipping enable"
      summary_add action "greetd unit not present"
    fi
  else
    log "systemd not available (likely running in a chroot); skipping enable"
    summary_add action "skipped enabling greetd (chroot)"
  fi

  # Start greetd only if PID 1 is systemd (i.e. not in a chroot). Otherwise instruct the user to start after boot.
  if [ -r /proc/1/comm ] && grep -q '^systemd$' /proc/1/comm 2>/dev/null; then
    log "Starting greetd service"
    if run_root "systemctl start greetd"; then
      summary_add action "started greetd"
    else
      log "Failed to start greetd; you may need to start it after boot"
      summary_add error "failed to start greetd"
    fi
  else
    log "Detected chroot or non-systemd init; skipping starting greetd (enable only)"
    summary_add action "did not start greetd (chroot)"
    log "After exiting chroot, run: sudo systemctl enable --now greetd"
  fi
}

# ---------- Step 8: Install themes and extra packages ----------
install_extra_packages() {
  # Package lists from README (merged into fewer calls)
  THEME_PKGS=(sassc gtk-engine-murrine gnome-themes-extra colloid-gtk-theme colloid-icon-theme colloid-cursors qt6ct-kde breeze)
  EXTRA_PKGS=(brightnessctl wl-clipboard cava cliphist gammastep cosmic-edit-git cosmic-files-git ddcutil imagemagick fzf ttf-meslo-nerd zoxide ripgrep bash-completion multitail tree trash-cli wget firefox cachyos-firefox-settings xdg-user-dirs pipewire-audio python-pywalfox wireplumber pwvucontrol jq grim slurp cachyos-settings inxi spdlog fmt ananicy-cpp cachyos-ananicy-rules wlr-randr bind-tools tealdeer man-db bat eza yazi fd zed laygit github-cli parted e2fsprogs dostools ntfs-3g exfatprogs btrfs-progs xfsprogs smartmontools lshw lm_sensors disktui)

  install_packages() {
    local pkg
    for pkg in "$@"; do
      # Check whether package is already installed in the pacman DB
      if pacman -Qi "$pkg" >/dev/null 2>&1; then
        log "Package '$pkg' is already installed; skipping."
        summary_add skipped "$pkg"
        continue
      fi

      # If paru is available prefer it for AUR packages, otherwise use pacman
      if command -v paru >/dev/null 2>&1; then
        log "Installing '$pkg' via paru..."
        if run_root "paru -S ${PARU_OPTS[*]} --needed --noconfirm $pkg"; then
          summary_add installed "$pkg"
        else
          log "Installation of $pkg via paru failed"
          summary_add error "paru install failed: $pkg"
        fi
      else
        log "Installing '$pkg' via pacman..."
        if run_root "pacman -S ${PACMAN_OPTS[*]} $pkg"; then
          summary_add installed "$pkg"
        else
          log "Installation of $pkg via pacman failed"
          summary_add error "pacman install failed: $pkg"
        fi
      fi
    done
  }

  log "Installing theme packages..."
  install_packages "${THEME_PKGS[@]}"

  log "Installing extra packages..."
  install_packages "${EXTRA_PKGS[@]}"
}

# ---------- Step 9: Install dotfiles (Dotbot) ----------
install_dotfiles() {
  REPO_URL="https://github.com/thedaedalus/DaedalusArch.git"
  DEST="$USER_HOME/DaedalusArch"

  if [ -d "$DEST" ]; then
    log "Dotfiles repo already exists at $DEST; pulling latest changes"
    if run_as_user "git -C '$DEST' pull --ff-only || true"; then
      summary_add action "dotfiles:updated"
    else
      summary_add error "dotfiles pull may have failed"
    fi
  else
    log "Cloning dotfiles to $DEST"
    if run_as_user "git clone '$REPO_URL' '$DEST'"; then
      summary_add installed "dotfiles:cloned"
    else
      summary_add error "dotfiles clone failed"
    fi
  fi

  if [ -x "$DEST/install" ] || [ -f "$DEST/install" ]; then
    log "Running dotfiles install script"
    if run_as_user "cd '$DEST' && ./install"; then
      summary_add installed "dotfiles:installed"
    else
      summary_add error "dotfiles install script returned non-zero"
    fi
  else
    err "Dotfiles install script not found at $DEST/install"
    summary_add error "dotfiles install script missing"
  fi
}

# ---------- Step 10: Install Starship prompt ----------
install_starship() {
  log "Installing Starship prompt (per README)"
  run_as_user "curl -sS https://starship.rs/install.sh | sh -s -- -y"
}


# ---------- Step 11: Setup XDG dirs ----------
setup_xdg_dirs() {
  log "Updating XDG user directories"
  run_as_user "xdg-user-dirs-update"
}

# ---------- Step 13: Download Wallpapers ----------
download_wallpapers() {
  log "Cloning wallpapers repository into Pictures"
  run_as_user "mkdir -p '$USER_HOME/Pictures' && cd '$USER_HOME/Pictures' && git clone --depth 1 https://github.com/orangci/walls-catppuccin-mocha.git || true"
}

# ---------- Step 14: Install Firefox theme via pywalfox ----------
install_pywalfox() {
  log "Running pywalfox install (requires python-pywalfox package)"
  # README uses sudo pywalfox install; we'll attempt as user first then root fallback
  if command -v pywalfox >/dev/null 2>&1; then
    run_as_user "pywalfox install" || run_root "pywalfox install || true"
  else
    err "pywalfox not installed or not in PATH; ensure python-pywalfox package installed and run `pywalfox install` manually."
  fi
}

# ---------- Step 15: Restart DMS and add wal symlink ----------
restart_dms_and_symlink() {
  log "Restarting DMS (if installed) and linking wal colors"
  if command -v dms >/dev/null 2>&1; then
    run_as_user "dms restart || true"
  fi

  # create symlink for wal colors if file exists
  run_as_user "mkdir -p '$USER_HOME/.cache/wal' || true"
  SRC="$USER_HOME/.cache/wal/dank-pywalfox.json"
  DST="$USER_HOME/.cache/wal/colors.json"
  if [ -f "$SRC" ]; then
    run_as_user "ln -sf '$SRC' '$DST'"
  else
    log "pywalfox cache file not found at $SRC; skipping symlink. It may be created after first run of pywalfox."
  fi
}

# ---------- Step 16: Helper - report enabled but not running services ----------
report_enabled_not_running() {
  log "Checking for enabled services that are not running (useful when in a chroot)..."

  if can_manage_systemd; then
    # Collect enabled unit names
    mapfile -t enabled_units < <(systemctl list-unit-files --type=service 2>/dev/null | awk '/enabled/ {print $1}')
    not_running=()
    for u in "${enabled_units[@]}"; do
      # Skip empty entries
      [ -z "$u" ] && continue
      # Check active state
      if systemctl is-active --quiet "$u" 2>/dev/null; then
        : # active
      else
        not_running+=("$u")
      fi
    done

    if [ ${#not_running[@]} -eq 0 ]; then
      log "All enabled services are running."
    else
      log "Enabled but not running services:"
      for u in "${not_running[@]}"; do
        printf '  - %s\n' "$u"
      done
      log "You may need to start these services after leaving chroot (e.g. sudo systemctl start <unit>) or investigate failures."
    fi
  else
    # Fallback in chroot: list units referenced in /etc/systemd/system as a hint.
    if [ -d /etc/systemd/system ]; then
      log "Cannot query systemd state from chroot. Listing enabled unit symlinks under /etc/systemd/system (informational):"
      find /etc/systemd/system -maxdepth 3 -type l -printf '  - %p -> %l\n' 2>/dev/null || true
      log "To check which enabled services are not running, exit chroot and run: systemctl list-units --type=service --state=failed,inactive"
    else
      log "No systemd configuration found to inspect."
    fi
  fi
}

# ---------- Step 17: Gaming packages ----------
install_gaming_packages() {
  log "Installing gaming packages (cachyos-gaming-applications)"
  # Skip if already installed
  if pacman -Qi cachyos-gaming-applications >/dev/null 2>&1; then
    log "cachyos-gaming-applications already installed; skipping."
    return 0
  fi

  # In dry-run mode, print the intended command via run_root (which respects dry-run)
  if [ "${DRY_RUN:-false}" = true ]; then
    if command -v paru >/dev/null 2>&1; then
      run_root "paru -S ${PARU_OPTS[*]} cachyos-gaming-applications"
    else
      run_root "pacman -S ${PACMAN_OPTS[*]} cachyos-gaming-applications"
    fi
    return 0
  fi

  if command -v paru >/dev/null 2>&1; then
    run_root "paru -S ${PARU_OPTS[*]} cachyos-gaming-applications" || log "Failed to install cachyos-gaming-applications via paru"
  else
    run_root "pacman -S ${PACMAN_OPTS[*]} cachyos-gaming-applications" || log "Failed to install cachyos-gaming-applications via pacman"
  fi
}

# ---------- Execution ----------
main() {
  log "Starting install of DaedalusArch. Review console output for errors."

  install_cachyos_repo || log "CachyOS repo install step finished with errors or was skipped."
  install_cachyos_kernel || log "CachyOS kernel install step finished with errors or was skipped."
  enable_ssh
  install_chaotic_aur || log "Chaotic-AUR step finished with errors or was skipped."
  install_paru
  install_danklinux || log "Dank Linux installer step completed or was skipped."
  install_greeter_enable_greetd || log "Greeter/greetd step finished with warnings."
  install_extra_packages || log "Extra packages installation completed with some errors."
  install_dotfiles || log "Dotfiles install step finished with warnings."
  setup_xdg_dirs
  download_wallpapers
  install_pywalfox || log "pywalfox step finished with warnings."
  restart_dms_and_symlink
  install_gaming_packages || log "Gaming packages step completed with warnings."

  # Print short summary report
  summary_print

  # Report enabled-but-not-running services (helps catch services that should be started after leaving chroot)
  report_enabled_not_running

  log "All done. Manual verification recommended:
  - Check kernel installed and rebooted into linux-cachyos if you installed it.
  - Verify Chaotic-AUR repo is present in /etc/pacman.conf.
  - Confirm `paru` is installed for AUR packages.
  - Run `pywalfox install` if pywalfox did not run automatically.
  - If any step reported errors, re-run that step manually."

  if [ "$AUTO_REBOOT" = true ]; then
    log "Rebooting now..."
    run_root "reboot"
  else
    log "Reboot not requested. When ready, reboot the system with: sudo reboot now"
  fi
}

main "$@"
