#!/usr/bin/env bash

# ▓█████▄  ▄▄▄      ▓█████ ▓█████▄  ▄▄▄       ██▓     █    ██   ██████  ▄▄▄       ██▀███   ▄████▄   ██░ ██
#▒██▀ ██▌▒████▄    ▓█   ▀ ▒██▀ ██▌▒████▄    ▓██▒     ██  ▓██▒▒██    ▒ ▒████▄    ▓██ ▒ ██▒▒██▀ ▀█  ▓██░ ██▒
#░██   █▌▒██  ▀█▄  ▒███   ░██   █▌▒██  ▀█▄  ▒██░    ▓██  ▒██░░ ▓██▄   ▒██  ▀█▄  ▓██ ░▄█ ▒▒▓█    ▄ ▒██▀▀██░
#░▓█▄   ▌░██▄▄▄▄██ ▒▓█  ▄ ░▓█▄   ▌░██▄▄▄▄██ ▒██░    ▓▓█  ░██░  ▒   ██▒░██▄▄▄▄██ ▒██▀▀█▄  ▒▓▓▄ ▄██▒░▓█ ░██
#░▒████▓  ▓█   ▓██▒░▒████▒░▒████▓  ▓█   ▓██▒░██████▒▒▒█████▓ ▒██████▒▒ ▓█   ▓██▒░██▓ ▒██▒▒ ▓███▀ ░░▓█▒░██▓
# ▒▒▓  ▒  ▒▒   ▓▒█░░░ ▒░ ░ ▒▒▓  ▒  ▒▒   ▓▒█░░ ▒░▓  ░░▒▓▒ ▒ ▒ ▒ ▒▓▒ ▒ ░ ▒▒   ▓▒█░░ ▒▓ ░▒▓░░ ░▒ ▒  ░ ▒ ░░▒░▒
# ░ ▒  ▒   ▒   ▒▒ ░ ░ ░  ░ ░ ▒  ▒   ▒   ▒▒ ░░ ░ ▒  ░░░▒░ ░ ░ ░ ░▒  ░ ░  ▒   ▒▒ ░  ░▒ ░ ▒░  ░  ▒    ▒ ░▒░ ░
# ░ ░  ░   ░   ▒      ░    ░ ░  ░   ░   ▒     ░ ░    ░░░ ░ ░ ░  ░  ░    ░   ▒     ░░   ░ ░         ░  ░░ ░
#   ░          ░  ░   ░  ░   ░          ░  ░    ░  ░   ░           ░        ░  ░   ░     ░ ░       ░  ░  ░
# ░                        ░                                                             ░
#Automate install of packages and dotfiles on a new Arch Linux system
set -euo pipefail
IFS=$'\n\t'
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with root privileges (sudo). You will be prompted for sudo when needed."
fi
logo() {
    echo -ne "
          =========================================================================================================
          ▓█████▄  ▄▄▄      ▓█████ ▓█████▄  ▄▄▄       ██▓     █    ██   ██████  ▄▄▄       ██▀███   ▄████▄   ██░ ██
          ▒██▀ ██▌▒████▄    ▓█   ▀ ▒██▀ ██▌▒████▄    ▓██▒     ██  ▓██▒▒██    ▒ ▒████▄    ▓██ ▒ ██▒▒██▀ ▀█  ▓██░ ██▒
          ░██   █▌▒██  ▀█▄  ▒███   ░██   █▌▒██  ▀█▄  ▒██░    ▓██  ▒██░░ ▓██▄   ▒██  ▀█▄  ▓██ ░▄█ ▒▒▓█    ▄ ▒██▀▀██░
          ░▓█▄   ▌░██▄▄▄▄██ ▒▓█  ▄ ░▓█▄   ▌░██▄▄▄▄██ ▒██░    ▓▓█  ░██░  ▒   ██▒░██▄▄▄▄██ ▒██▀▀█▄  ▒▓▓▄ ▄██▒░▓█ ░██
          ░▒████▓  ▓█   ▓██▒░▒████▒░▒████▓  ▓█   ▓██▒░██████▒▒▒█████▓ ▒██████▒▒ ▓█   ▓██▒░██▓ ▒██▒▒ ▓███▀ ░░▓█▒░██▓
           ▒▒▓  ▒  ▒▒   ▓▒█░░░ ▒░ ░ ▒▒▓  ▒  ▒▒   ▓▒█░░ ▒░▓  ░░▒▓▒ ▒ ▒ ▒ ▒▓▒ ▒ ░ ▒▒   ▓▒█░░ ▒▓ ░▒▓░░ ░▒ ▒  ░ ▒ ░░▒░▒
           ░ ▒  ▒   ▒   ▒▒ ░ ░ ░  ░ ░ ▒  ▒   ▒   ▒▒ ░░ ░ ▒  ░░░▒░ ░ ░ ░ ░▒  ░ ░  ▒   ▒▒ ░  ░▒ ░ ▒░  ░  ▒    ▒ ░▒░ ░
           ░ ░  ░   ░   ▒      ░    ░ ░  ░   ░   ▒     ░ ░    ░░░ ░ ░ ░  ░  ░    ░   ▒     ░░   ░ ░         ░  ░░ ░
             ░          ░  ░   ░  ░   ░          ░  ░    ░  ░   ░           ░        ░  ░   ░     ░ ░       ░  ░  ░
           ░                        ░                                                             ░

                                                Post install script for Arch Linux
          ==========================================================================================================
    "
}

_tmpfiles=()
cleanup() {
    #  Cleanup function for temporary files and helpful trap on exit
    for f in "${_tmpfiles[@]:-}"; do
        [[ -e "$f" ]] && rm -rf -- "$f"
    done
}
trap cleanup EXIT

require_cmd() {
    # helper: ensure commands exist
    command -v "$1" >/dev/null 2>&1 || { echo "Required command '$1' not found. Please install it and re-run."; exit 1; }
}
print_message() {
    echo "======================================"
    echo "$1"
    echo "======================================"
}

update_system() {
    # Update system and install essential packages
    print_message "Updating system..."
    sudo pacman -Syu --noconfirm
    if [ $? -ne 0 ]; then
        echo "System update failed. Exiting."
        exit 1
    fi
}

install_repos() {
    print_message "Setting up CachyOS & Chaotic AUR repositories..."
    require_cmd curl
    require_cmd tar
    require_cmd find
    require_cmd grep

    tmpdir="$(mktemp -d)"
    _tmpfiles+=("$tmpdir")
    pushd "$tmpdir" >/dev/null

    repo_url="https://mirror.cachyos.org/cachyos-repo.tar.xz"
    echo "Downloading ${repo_url}..."
    if ! curl -fLO "$repo_url"; then
        echo "Failed to download CachyOS repo archive from $repo_url"
        popd >/dev/null
        return 1
    fi

    echo "Listing archive contents (tar -tf):"
    tar -tf cachyos-repo.tar.xz | sed -n '1,200p'

    echo "Extracting archive..."
    if ! tar -xf cachyos-repo.tar.xz; then
        echo "Failed to extract cachyos-repo.tar.xz"
        popd >/dev/null
        return 1
    fi

    echo "Files extracted (showing up to depth 5):"
    find . -maxdepth 5 -print

    # Look for common install script names
    SCRIPT_PATH="$(find . -type f \( -iname 'cachyos-repo.sh' -o -iname 'install.sh' -o -iname '*cachyos*' -o -iname 'setup.sh' \) | head -n1 || true)"

    # If nothing found by name, search file contents for 'cachyos'
    if [[ -z "$SCRIPT_PATH" ]]; then
        echo "No common script name found; searching files that mention 'cachyos'..."
        SCRIPT_PATH="$(grep -RIl 'cachyos' . | head -n1 || true)"
    fi

    if [[ -z "$SCRIPT_PATH" ]]; then
        echo "No installer script located. Please inspect the extracted files above."
        popd >/dev/null
        return 1
    fi

    echo "Candidate installer script: $SCRIPT_PATH"
    echo "First 80 lines of the candidate (for quick inspection):"
    sed -n '1,80p' "$SCRIPT_PATH" || true

    # Ask user to confirm execution
    read -r -p "Execute this candidate script? [y/N] " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
        echo "Execution cancelled. Inspect $tmpdir to decide which file should be run."
        popd >/dev/null
        return 1
    fi

    chmod +x "$SCRIPT_PATH"
    if ! sudo "$SCRIPT_PATH"; then
        echo "Execution of $SCRIPT_PATH failed"
        popd >/dev/null
        return 1
    fi

    popd >/dev/null
    echo "Repository installer executed (if present)."
}




install_packages() {
    print_message "Installing essential packages..."
    ESSENTIAL_PACKAGES=(
        linux-cachyos
        linux-cachyos-headers
        linux-firmware
        base-devel
        git
        wget
        paru
        terminus-font
    )
    for package in "${ESSENTIAL_PACKAGES[@]}"; do
        sudo pacman -S --noconfirm --needed "$package"
    done

    # Ensure paru exists: prefer pacman if paru available in configured repos, else build it if AUR helper needed.
    if ! command -v paru >/dev/null 2>&1; then
        print_message "paru not found. Attempting to build paru from AUR (requires base-devel and git)."
        tmpdir="$(mktemp -d)"
        _tmpfiles+=("$tmpdir")
        pushd "$tmpdir" >/dev/null
        git clone https://aur.archlinux.org/paru.git
        cd paru || { popd >/dev/null; return 1; }
        makepkg -si --noconfirm
        popd >/dev/null
    fi
}


install_extra_packages() {
    print_message "Installing packages..."
    EXTRA_PACKAGES=(
            brightnessctl
            wl-clipboard
            cava
            cliphist
            gammastep
            cosmic-edit-git
            cosmic-files-git
            fastfetch
            ddcutil
            imagemagick
            fzf
            ttf-meslo-nerd
            ttf-jetbrains-mono-nerd
            ttf-caskaydia-nerd
            zoxide
            ripgrep
            bash-completion
            multitail
            tree
            trash-cli
            wget
            firefox
            cachyos-firefox-settings
            xdg-user-dirs
            pipewire-audio
            python-pywalfox
            wireplumber
            pwvucontrol
            jq
            grim
            slurp
            cachyos-settings
            inxi
            spdlog
            fmt
            ananicy-cpp
            cachyos-ananicy-rules
            wlr-randr
            bind-tools
            tealdeer
            man-db
            bat
            eza
            yazi
            fd
            zed
            laygit
            github-cli
            sassc
            gtk-engine-murrine
            gnome-themes-extra
            colloid-gtk-theme
            colloid-icon-theme
            colloid-cursors
            qt6ct-kde
            breeze-icons
            breeze
            starship
            cachyos-gaming-applications
            kitty
            ghostty
    )

    for package in "${EXTRA_PACKAGES[@]}"; do
        paru -S --noconfirm --needed "$package"
    done
}

install_wallpapers() {
    print_message "Installing wallpapers..."
    target_dir="$HOME/Pictures"
    mkdir -p "$target_dir"
    pushd "$target_dir" >/dev/null
    if [[ -d "walls-catppuccin-mocha" ]]; then
        echo "Wallpaper repo already present, pulling latest..."
        git -C walls-catppuccin-mocha pull --rebase
    else
        git clone https://github.com/orangci/walls-catppuccin-mocha.git
    fi
    popd >/dev/null
}

setup_dotfiles() {
    print_message "Setting up dotfiles..."
    REPO_URL="https://github.com/thedaedalus/DaedalusArch.git"
    CLONE_DIR="$HOME/DaedalusArch"
    if [[ -d "$CLONE_DIR" ]]; then
        echo "Directory $CLONE_DIR already exists, updating..."
        git -C "$CLONE_DIR" pull --rebase
    else
        git clone "$REPO_URL" "$CLONE_DIR"
    fi

    CONFIG="install.conf.yaml"
    DOTBOT_DIR="$CLONE_DIR/dotbot"
    DOTBOT_BIN="$DOTBOT_DIR/bin/dotbot"

    if [[ ! -d "$DOTBOT_DIR" ]]; then
        echo "dotbot submodule not present; attempting submodule init/update..."
    fi
    pushd "$CLONE_DIR" >/dev/null
    git submodule sync --quiet --recursive
    git submodule update --init --recursive -- "$DOTBOT_DIR"

    if [[ -x "$DOTBOT_BIN" ]]; then
        "$DOTBOT_BIN" -d "$CLONE_DIR" -c "$CONFIG" "${@:-}"
    else
        echo "Dotbot binary not found at $DOTBOT_BIN; please check the repository layout."
    fi
    popd >/dev/null
}


setup_pacman() {
    print_message "Configuring Pacman conf tweaks..."
    conf=/etc/pacman.conf
    sudo cp -n "$conf" "${conf}.bak" || true   # keep a backup if none exists

    # Parallel Downloads: add or uncomment an option
    if grep -q "^[#[:space:]]*ParallelDownloads" "$conf"; then
        sudo sed -i 's/^[#[:space:]]*ParallelDownloads.*/ParallelDownloads = 15/' "$conf"
    else
        # add default ParallelDownloads if not present
        echo "ParallelDownloads = 15" | sudo tee -a "$conf"
    fi

    # Color and ILoveCandy: ensure Color is enabled and ILoveCandy is present once
    sudo sed -i 's/^[#[:space:]]*Color/Color/' "$conf"
    if ! grep -q '^ILoveCandy' "$conf"; then
        # append ILoveCandy after the Color line if possible otherwise to end
        sudo awk '/^Color/{print; if(!x++){print "ILoveCandy"; next}}1' "$conf" | sudo tee "${conf}.tmp" >/dev/null && sudo mv "${conf}.tmp" "$conf"
    fi

    # Enable multilib section (uncomment bracket and include line)
    if ! grep -q "^\[multilib\]" "$conf"; then
        sudo sed -i '/^\s*#\s*\[multilib\]/s/^\s*#\s*//' "$conf"
        sudo sed -i '/^\s*#\s*Include = \/etc\/pacman.d\/mirrorlist/s/^\s*#\s*//' "$conf"
    fi
}

install_danklinux() {
    print_message "Installing DankLinux installer (https://install.danklinux.com)..."

    require_cmd curl
    require_cmd sh
    require_cmd mktemp

    if [ "$(id -u)" -eq 0 ]; then
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            RUN_AS_USER="$SUDO_USER"
        else
            echo "Refusing to run the DankLinux installer as root and cannot detect a non-root user to switch to."
            echo "Run the wrapper script as a normal user (it will use sudo internally when needed), or export SUDO_USER."
            return 1
        fi
    else
        RUN_AS_USER="$(id -un)"
    fi

    tmpfile="$(mktemp -t dankinstaller.XXXXXX.sh)"
    _tmpfiles+=("$tmpfile")
    if ! curl -fsSL "https://install.danklinux.com" -o "$tmpfile"; then
        echo "Failed to download https://install.danklinux.com"
        return 1
    fi
    chmod +x "$tmpfile"

    if [ "$(id -u)" -eq 0 ]; then
        echo "Running DankLinux installer as user: $RUN_AS_USER"
        if ! sudo -u "$RUN_AS_USER" -- sh "$tmpfile"; then
            echo "DankLinux installer failed when run as $RUN_AS_USER"
            return 1
        fi
    else
        echo "Running DankLinux installer as current user: $RUN_AS_USER"
        if ! sh "$tmpfile"; then
            echo "DankLinux installer failed"
            return 1
        fi
    fi

    echo "DankLinux installer finished successfully (or returned control)."
    return 0
}


logo
setup_pacman
install_repos
update_system
install_packages
install_extra_packages
install_danklinux
xdg-user-dirs-update
install_wallpapers
setup_dotfiles
print_message "Post-installation script completed successfully!"
echo "Please reboot your system to apply all changes."
echo "Reboot now? (y/n)"
read -r REBOOT_CHOICE
if [[ "$REBOOT_CHOICE" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "Reboot skipped. Please remember to reboot later."
fi
