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
LOGFILE="$HOME/daedalusarch-post-install.log"
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
    \n"

}
is_sourced() {
    # If ${BASH_SOURCE[0]} != $0 then script is being sourced
    [ "${BASH_SOURCE[0]}" != "$0" ]
}

handle_fatal() {
    local msg="$1"
    echo "$msg" | tee -a "$LOGFILE" >&2
    if is_sourced; then
        return 1
    else
        exit 1
    fi
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
    echo -ne "
          ======================================
                $1
          ======================================
    \n"
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

check_supported_isa_level() {
    /lib/ld-linux-x86-64.so.2 --help | grep "$1 (supported, searched)" > /dev/null
    echo $?
}

check_supported_znver45() {
    gcc -march=native -Q --help=target 2>&1 | grep 'march' | grep -E '(znver4|znver5)' > /dev/null
    echo $?
}

check_if_repo_was_added() {
    cat /etc/pacman.conf | grep "(cachyos\|cachyos-v3\|cachyos-core-v3\|cachyos-extra-v3\|cachyos-testing-v3\|cachyos-v4\|cachyos-core-v4\|cachyos-extra-v4\|cachyos-znver4\|cachyos-core-znver4\|cachyos-extra-znver4)" > /dev/null
    echo $?
}

check_if_repo_was_commented() {
    cat /etc/pacman.conf | grep "cachyos\|cachyos-v3\|cachyos-core-v3\|cachyos-extra-v3\|cachyos-testing-v3\|cachyos-v4\|cachyos-core-v4\|cachyos-extra-v4\|cachyos-znver4\|cachyos-core-znver4\|cachyos-extra-znver4" | grep -v "#\[" | grep "\[" > /dev/null
    echo $?
}

add_specific_repo() {
    local isa_level="$1"
    local gawk_script="$2"
    local repo_name="$3"
    local cmd_check="check_supported_isa_level ${isa_level}"

    local pacman_conf="/etc/pacman.conf"
    local pacman_conf_cachyos="./pacman.conf"
    local pacman_conf_path_backup="/etc/pacman.conf.bak"

    local is_isa_supported="$(eval ${cmd_check})"
    if [ $is_isa_supported -eq 0 ]; then
        echo "${isa_level} is supported"

        sudo cp $pacman_conf $pacman_conf_cachyos
        sudo gawk -i inplace -f $gawk_script $pacman_conf_cachyos || true

        echo "Backup old config"
        sudo mv $pacman_conf $pacman_conf_path_backup

        echo "CachyOS ${repo_name} Repo changed"
        sudo mv $pacman_conf_cachyos $pacman_conf
    else
        echo "${isa_level} is not supported"
    fi
}

install_repos() {
    print_message "Setting up CachyOS & Chaotic AUR repositories..."
    require_cmd curl
    require_cmd tar
    require_cmd find

    repo_url="https://mirror.cachyos.org/cachyos-repo.tar.xz"
    echo "Downloading ${repo_url}..."
    if ! curl -fLO "$repo_url"; then
        echo "Failed to download CachyOS repo archive from $repo_url"
        return 1
    fi

    if ! tar -xf cachyos-repo.tar.xz; then
        echo "Failed to extract cachyos-repo.tar.xz"
        return 1
    fi

    sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key F3B607488DB35A47

    local mirror_url="https://mirror.cachyos.org/repo/x86_64/cachyos"

    sudo pacman -U --noconfirm "${mirror_url}/cachyos-keyring-20240331-1-any.pkg.tar.zst" \
              "${mirror_url}/cachyos-mirrorlist-22-1-any.pkg.tar.zst"    \
              "${mirror_url}/cachyos-v3-mirrorlist-22-1-any.pkg.tar.zst" \
              "${mirror_url}/cachyos-v4-mirrorlist-22-1-any.pkg.tar.zst"  \
              "${mirror_url}/pacman-7.0.0.r7.g1f38429-1-x86_64.pkg.tar.zst"

    local is_repo_added="$(check_if_repo_was_added)"
    local is_repo_commented="$(check_if_repo_was_commented)"
    local is_isa_v4_supported="$(check_supported_isa_level x86-64-v4)"
    local is_znver_supported="$(check_supported_znver45)"
    if [ $is_repo_added -ne 0 ] || [ $is_repo_commented -ne 0 ]; then
        if [ $is_znver_supported -eq 0 ]; then
            cd cachyos-repo
            add_specific_repo x86-64-v4 ./install-znver4-repo.awk cachyos-znver4
        elif [ $is_isa_v4_supported -eq 0 ]; then
            cd cachyos-repo
            add_specific_repo x86-64-v4 ./install-v4-repo.awk cachyos-v4
        else
            cd cachyos-repo
            add_specific_repo x86-64-v3 ./install-repo.awk cachyos-v3
        fi
    else
        echo "Repo is already added!"
    fi

    sudo pacman-key --keyserver hkps://keyserver.ubuntu.com --recv-keys 3056513887B78AEB
    sudo pacman-key --lsign-key 3056513887B78AEB

    sudo pacman -U --noconfirm "https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst"
    sudo pacman -U --noconfirm "https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst"

    if ! grep -q "^\[chaotic-aur\]" /etc/pacman.conf; then
        echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
    else
        echo "chaotic-aur already configured in /etc/pacman.conf"
    fi


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

    if ! command -v paru >/dev/null 2>&1; then
        echo "paru not found. Attempting to build paru from AUR (requires base-devel and git)."
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
            ttf-cascadia-mono-nerd
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
            lazygit
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
            kitty
            ghostty
            nano
    )

    for package in "${EXTRA_PACKAGES[@]}"; do
            paru -S --noconfirm --needed --skipreview --sudoloop "$package"
    done
}

install_gamining_applications() {
    print_message "Installing gaming tools..."
    GAMING_PACKAGES=(
        cachyos-gaming-applications
    )

    for package in "${GAMING_PACKAGES[@]}"; do
        paru -S --noconfirm --needed --skipreview --sudoloop "$package"
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
    CLONE_DIR="${HOME}/DaedalusArch"
    LOG_DIR="${HOME}/.daedalus"
    LOGFILE="${LOG_DIR}/dotbot.log"

    mkdir -p "${LOG_DIR}"

    # Backup existing files
    mv ~/.bashrc ~/.bashrc_backup_$(date +%s)
    mv ~/.config/kitty/kitty.conf ~/.config/kitty/kitty.conf_backup_$(date +%s)
    mv ~/.config/eza/theme.yml ~/.config/eza/theme_backup_$(date +%s)
    mv ~/.config/fastfetch/config.jsonc ~/.config/fastfetch/config.jsonc_backup_$(date +%s)
    mv ~/.config/niri/config.kdl ~/.config/niri/config.kdl_backup_$(date +%s)
    mv ~/.config/starship.toml ~/.config/starship.toml_backup_$(date +%s)
    mv ~/.config/tealdeer/config.toml ~/.config/tealdeer/config.toml_backup_$(date +%s)

    if [[ -d "${CLONE_DIR}" ]]; then
        echo "Directory ${CLONE_DIR} already exists, updating..."
        if ! git -C "${CLONE_DIR}" pull --rebase --quiet 2>&1 | tee -a "${LOGFILE}"; then
            echo "Warning: failed to update ${CLONE_DIR}; continuing with existing checkout (see ${LOGFILE})" >&2
        fi
    else
        echo "Cloning ${REPO_URL} into ${CLONE_DIR}..."
        if ! git clone --quiet "${REPO_URL}" "${CLONE_DIR}" 2>&1 | tee -a "${LOGFILE}"; then
            echo "Error: failed to clone ${REPO_URL} into ${CLONE_DIR}. Aborting dotfiles setup." >&2
            return 1
        fi
    fi
    cd "${CLONE_DIR}" || { echo "Error: failed to change directory to ${CLONE_DIR}. Aborting dotfiles setup." >&2; return 1; }
    if ! bash install 2>&1 | tee -a "${LOGFILE}"; then
        echo "Error: dotfiles installation script failed. See ${LOGFILE} for details." >&2
        return 1
    fi
    echo "Dotfiles setup completed successfully." | tee -a "${LOGFILE}"
    cd ~ >/dev/null
    return 0
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
        sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' "$conf"
    fi
}

install_danklinux() {
    print_message "Installing Dank Material Shell..."

    require_cmd curl
    require_cmd sh
    require_cmd mktemp
    require_cmd sha256sum
    require_cmd gunzip

    # Colors for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m' # No Color

    # Check if running on Linux
    if [ "$(uname)" != "Linux" ]; then
        printf "%bError: This installer only supports Linux systems%b\n" "$RED" "$NC"
        exit 1
    fi

    # Detect architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        *)
            printf "%bError: Unsupported architecture: %s%b\n" "$RED" "$ARCH" "$NC"
            printf "This installer only supports x86_64 (amd64) and aarch64 (arm64) architectures\n"
            exit 1
            ;;
    esac

    # Get the latest release version
    LATEST_VERSION=$(curl -s https://api.github.com/repos/AvengeMedia/danklinux/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$LATEST_VERSION" ]; then
        printf "%bError: Could not fetch latest version%b\n" "$RED" "$NC"
        exit 1
    fi

    printf "%bInstalling Dankinstall %s for %s...%b\n" "$GREEN" "$LATEST_VERSION" "$ARCH" "$NC"

    # Download and install
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1

    # Download the gzipped binary and its checksum
    printf "%bDownloading installer...%b\n" "$GREEN" "$NC"
    curl -L "https://github.com/AvengeMedia/danklinux/releases/download/$LATEST_VERSION/dankinstall-$ARCH.gz" -o "installer.gz"
    curl -L "https://github.com/AvengeMedia/danklinux/releases/download/$LATEST_VERSION/dankinstall-$ARCH.gz.sha256" -o "expected.sha256"

    # Get the expected checksum
    EXPECTED_CHECKSUM=$(cat expected.sha256 | awk '{print $1}')

    # Calculate actual checksum
    printf "%bVerifying checksum...%b\n" "$GREEN" "$NC"
    ACTUAL_CHECKSUM=$(sha256sum installer.gz | awk '{print $1}')

    # Compare checksums
    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
        printf "%bError: Checksum verification failed%b\n" "$RED" "$NC"
        printf "Expected: %s\n" "$EXPECTED_CHECKSUM"
        printf "Got:      %s\n" "$ACTUAL_CHECKSUM"
        printf "The downloaded file may be corrupted or tampered with\n"
        cd - > /dev/null
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Decompress the binary
    printf "%bDecompressing installer...%b\n" "$GREEN" "$NC"
    gunzip installer.gz
    chmod +x installer

    # Execute the installer
    printf "%bRunning installer...%b\n" "$GREEN" "$NC"
    ./installer

    # Cleanup
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    return 0
}

check_virtual_system() {
    # Preferred: systemd-detect-virt
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        vm="$(systemd-detect-virt 2>/dev/null || true)"
        # systemd-detect-virt may print "none" for no virtualization
        if [ -n "$vm" ] && [ "$vm" != "none" ]; then
            case "$vm" in
                kvm|qemu) echo "kvm"; return 0 ;;
                virtualbox|oracle) echo "virtualbox"; return 0 ;;
                vmware) echo "vmware"; return 0 ;;
                *) echo "$vm"; return 0 ;;
            esac
        fi
    fi

    # Fallback: dmidecode
    if command -v dmidecode >/dev/null 2>&1; then
        prod="$(dmidecode -s system-product-name 2>/dev/null || true)"
        case "$prod" in
            *VirtualBox*) echo "virtualbox"; return 0 ;;
            *KVM*|*QEMU*) echo "kvm"; return 0 ;;
            *VMware*) echo "vmware"; return 0 ;;
        esac
    fi

    if command -v lspci >/dev/null 2>&1; then
        if lspci 2>/dev/null | grep -qi virtualbox; then
            echo "virtualbox"; return 0
        fi
        if lspci 2>/dev/null | grep -qi vmware; then
            echo "vmware"; return 0
        fi
    fi

    # Nothing detected
    return 1
}

install_qemu_guest_tools() {
    echo  "Installing QEMU Guest Tools..."
    sudo pacman -S --noconfirm --needed qemu-guest-agent spice-vdagent vulkan-virtio lib32-vulkan-virtio
}

install_virtualbox_guest_additions() {
    echo "Installing VirtualBox Guest Additions..."
    sudo pacman -S --noconfirm --needed virtualbox-guest-utils virtualbox-guest-dkms linux-headers
    sudo systemctl enable vboxservice.service
}
install_vmware_tools() {
    echo "Installing VMware Tools..."
    sudo pacman -S --noconfirm --needed open-vm-tools
    sudo systemctl enable vmtoolsd.service
    sudo systemctl enable vmware-vmblock-fuse.service
}

logo
setup_pacman
install_repos
update_system


vm_type="$(check_virtual_system 2>/dev/null || true)"

if [ -n "$vm_type" ]; then
    echo "Running in VM: $vm_type"

    case "$vm_type" in
        kvm|qemu)
            # Run installer and pipe output to tee; capture installer's exit status
            install_qemu_guest_tools 2>&1 | tee -a "$LOGFILE"
            rc=${PIPESTATUS[0]:-1}
            if [ $rc -ne 0 ]; then
                handle_fatal "Error: install_qemu_guest_tools failed (exit $rc). See $LOGFILE"
            fi
            ;;
        virtualbox)
            install_virtualbox_guest_additions 2>&1 | tee -a "$LOGFILE"
            rc=${PIPESTATUS[0]:-1}
            if [ $rc -ne 0 ]; then
                handle_fatal "Error: install_virtualbox_guest_additions failed (exit $rc). See $LOGFILE"
            fi
            ;;
        vmware)
            install_vmware_tools 2>&1 | tee -a "$LOGFILE"
            rc=${PIPESTATUS[0]:-1}
            if [ $rc -ne 0 ]; then
                handle_fatal "Error: install_vmware_tools failed (exit $rc). See $LOGFILE"
            fi
            ;;
        *)
            echo "Unknown VM type: $vm_type; skipping guest tools" | tee -a "$LOGFILE"
            ;;
    esac
else
    echo "No virtual machine detected; skipping guest tools."
fi
install_packages
install_danklinux
install_extra_packages
read -r -p "Do you want to install gaming applications? (y/n): " GAMING_CHOICE
if [[ "$GAMING_CHOICE" =~ ^[Yy]$ ]]; then
    install_gamining_applications
else
    echo "Skipping gaming applications installation."
fi
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
