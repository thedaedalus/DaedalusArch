#!/usr/bin/env bash
# Automated Arch Linux Installer - updated to read prompts from /dev/tty so interactive prompts work when piped.
# NOTE: This script is interactive and destructive. Review before running.

set -euo pipefail
IFS=$'\n\t'

# Redirect stdout and stderr to archsetup.txt and still output to console
exec > >(tee -i archsetup.txt)
exec 2>&1

echo -ne "
-------------------------------------------------------------------------
  ____                 _       _              _             _
 |  _ \\  __ _  ___  __| | __ _| |_   _ ___   / \\   _ __ ___| |__
 | | | |/ _\` |/ _ \\/ _\` |/ _\` | | | | / __| / _ \\ | '__/ __| '_ \\
 | |_| | (_| |  __/ (_| | (_| | | |_| \\__ \\/ ___ \\| | | (__| | | |
 |____/ \\__,_|\\___|\\__,_|\\__,_|_|\\__,_|___/_/   \\_\\_|  \\___|_| |_|
-------------------------------------------------------------------------
                    Automated Arch Linux Installer
-------------------------------------------------------------------------
Verifying Arch Linux ISO is Booted
"

if [ ! -f /usr/bin/pacstrap ]; then
    echo "This script must be run from an Arch Linux ISO environment."
    exit 1
fi

root_check() {
    if [[ "$(id -u)" != "0" ]]; then
        echo -ne "ERROR! This script must be run under the 'root' user!\n"
        exit 1
    fi
}

docker_check() {
    # Try to detect docker via cgroup or /.dockerenv
    if awk -F/ '$2 == "docker"' /proc/self/cgroup | read -r; then
        echo -ne "ERROR! Docker container is not supported (at the moment)\n"
        exit 1
    elif [[ -f /.dockerenv ]]; then
        echo -ne "ERROR! Docker container is not supported (at the moment)\n"
        exit 1
    fi
}

arch_check() {
    if [[ ! -e /etc/arch-release ]]; then
        echo -ne "ERROR! This script must be run in Arch Linux!\n"
        exit 1
    fi
}

pacman_check() {
    if [[ -f /var/lib/pacman/db.lck ]]; then
        echo "ERROR! Pacman is blocked."
        echo -ne "If not running remove /var/lib/pacman/db.lck.\n"
        exit 1
    fi
}

background_checks() {
    root_check
    arch_check
    pacman_check
    docker_check
}

# Read arrow-key menu and return index as function return
# All reads on menus are redirected from /dev/tty so the script works when piped.
select_option() {
    local options=("$@")
    local num_options=${#options[@]}
    local selected=0
    local last_selected=-1
    local key esc_seq

    while true; do
        # Move cursor up to the start of the menu
        if [ $last_selected -ne -1 ]; then
            echo -ne "\033[${num_options}A"
        fi

        if [ $last_selected -eq -1 ]; then
            echo "Please select an option using the arrow keys and Enter:"
        fi
        for i in "${!options[@]}"; do
            if [ "$i" -eq $selected ]; then
                echo "> ${options[$i]}"
            else
                echo "  ${options[$i]}"
            fi
        done

        last_selected=$selected

        # Read a single byte/char from the controlling terminal so the script works over SSH and when piped.
        # If read fails, key will be empty; guard against set -e by using || true.
        read -rsn1 key < /dev/tty || key=''

        # If we received an ESC, read the rest of the escape sequence (longer timeout, don't overwrite 'key')
        if [[ "$key" == $'\x1b' ]]; then
            # read up to 3 additional bytes (most terminal sequences are short) with a slightly longer timeout for SSH latency
            read -rsn3 -t 0.25 esc_seq < /dev/tty || esc_seq=''
            case "$esc_seq" in
                '[A'*) # Up arrow
                    ((selected--))
                    if [ $selected -lt 0 ]; then
                        selected=$((num_options - 1))
                    fi
                    ;;
                '[B'*) # Down arrow
                    ((selected++))
                    if [ $selected -ge $num_options ]; then
                        selected=0
                    fi
                    ;;
                *)
                    # Unrecognized escape sequence: ignore
                    ;;
            esac
            # Loop to redraw menu after handling arrow
            continue
        fi

        # Detect Enter (newline or carriage return) or empty key (fallback)
        if [[ "$key" == $'\n' || "$key" == $'\r' || -z "$key" ]]; then
            break
        fi

        # Allow vi-like shortcuts over SSH: 'k' = up, 'j' = down
        case "$key" in
            'k')
                ((selected--))
                if [ $selected -lt 0 ]; then
                    selected=$((num_options - 1))
                fi
                ;;
            'j')
                ((selected++))
                if [ $selected -ge $num_options ]; then
                    selected=0
                fi
                ;;
            *)
                # ignore other keys
                ;;
        esac
    done

    return $selected
}

# helper: prompt for a password and export to variable name given
# read from /dev/tty so piping the script doesn't break prompts
set_password() {
    local varname="$1"
    while true; do
        read -rs -p "Please enter password for ${varname}: " pass1 < /dev/tty || true
        echo
        read -rs -p "Please re-enter password for ${varname}: " pass2 < /dev/tty || true
        echo
        if [[ "$pass1" == "$pass2" && -n "$pass1" ]]; then
            # Use declare -x to set environment variable by name
            declare -x "$varname=$pass1"
            break
        fi
        echo "Passwords don't match or are empty. Try again."
    done
}

# @description Displays logo
logo () {
echo -ne "
-------------------------------------------------------------------------
  ____                 _       _              _             _
 |  _ \\  __ _  ___  __| | __ _| |_   _ ___   / \\   _ __ ___| |__
 | | | |/ _\` |/ _ \\/ _\` |/ _\` | | | | / __| / _ \\ | '__/ __| '_ \\
 | |_| | (_| |  __/ (_| | (_| | | |_| \\__ \\/ ___ \\| | | (__| | | |
 |____/ \\__,_|\\___|\\__,_\\__,_|_|\\__,_|___/_/   \\_\\_|  \\___|_| |_|
------------------------------------------------------------------------
            Please select presetup settings for your system
------------------------------------------------------------------------
"
}

filesystem () {
    echo -ne "
    Please select your file system for root
    "
    options=("btrfs" "ext4" "luks" "exit")
    select_option "${options[@]}"
    choice=$?
    case $choice in
        0) export FS=btrfs;;
        1) export FS=ext4;;
        2)
            set_password "LUKS_PASSWORD"
            export FS=luks
            ;;
        3) echo "Exiting."; exit 0;;
        *) echo "Wrong option please select again"; filesystem;;
    esac
}

timezone () {
    # attempt to detect timezone
    local time_zone
    if time_zone="$(curl --fail --silent https://ipapi.co/timezone)"; then
        echo -ne "
    System detected your timezone to be '$time_zone'\n"
    else
        time_zone=""
        echo -ne "
    Could not auto-detect timezone.\n"
    fi

    echo -ne "Is this correct?\n"
    options=("Yes" "No")
    select_option "${options[@]}"
    choice=$?
    case $choice in
        0)
            if [[ -n "$time_zone" ]]; then
                echo "${time_zone} set as timezone"
                export TIMEZONE="$time_zone"
            else
                echo "No detected timezone. Please enter manually."
                read -r new_timezone < /dev/tty || true
                export TIMEZONE="$new_timezone"
            fi
            ;;
        1)
            read -r -p "Please enter your desired timezone (e.g. Europe/London): " new_timezone < /dev/tty || true
            export TIMEZONE="$new_timezone"
            echo "${TIMEZONE} set as timezone"
            ;;
        *)
            echo "Wrong option. Try again"
            timezone
            ;;
    esac
}

keymap () {
    echo -ne "
    Please select key board layout from this list
    "
    options=(us by ca cf cz de dk es et fa fi fr gr hu il it lt lv mk nl no pl ro ru se sg ua uk)
    select_option "${options[@]}"
    choice=$?
    keymap=${options[$choice]}
    echo -ne "Your key boards layout: ${keymap} \n"
    export KEYMAP=$keymap
}

drivessd () {
    echo -ne "
    Is this a solid state, flash, or hard drive?
    "
    options=("SSD" "MMC" "HDD")
    select_option "${options[@]}"
    choice=$?
    case $choice in
        0)
            export MOUNT_OPTIONS="noatime,compress=zstd,ssd,commit=120";;
        1)
            export MOUNT_OPTIONS="noatime,compress=zstd:5,ssd,commit=120";;
        2)
            export MOUNT_OPTIONS="noatime,compress=zstd,commit=120";;
        *)
            echo "Wrong option. Try again"; drivessd;;
    esac
}

diskpart () {
echo -ne "
------------------------------------------------------------------------
    THIS WILL FORMAT AND DELETE ALL DATA ON THE DISK
    Please make sure you know what you are doing because
    after formatting your disk there is no way to get data back
    *****BACKUP YOUR DATA BEFORE CONTINUING*****
    ***I AM NOT RESPONSIBLE FOR ANY DATA LOSS***
------------------------------------------------------------------------

"

    while true; do
        mapfile -t options < <(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "/dev/"$2"|"$3}')
        select_option "${options[@]}"
        choice=$?
        disk_entry="${options[$choice]}"
        disk="${disk_entry%%|*}"

        if [[ -b "$disk" ]]; then
            echo -e "\n${disk} selected \n"
            export DISK="$disk"
            break
        else
            echo "Invalid disk selected. Try again."
        fi
    done

    drivessd
}

userinfo () {
    # username
    while true; do
        read -r -p "Please enter username: " username < /dev/tty || true
        if [[ "${username,,}" =~ ^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$ ]]; then
            break
        fi
        echo "Incorrect username."
    done
    export USERNAME=$username

    # password - uses set_password which reads from /dev/tty
    set_password "PASSWORD"

    # hostname
    while true; do
        read -r -p "Please name your machine: " name_of_machine < /dev/tty || true
        if [[ "${name_of_machine,,}" =~ ^[a-z][a-z0-9_.-]{0,62}[a-z0-9]$ ]]; then
            break
        fi
        read -r -p "Hostname doesn't seem correct. Do you still want to save it? (y/n) " force < /dev/tty || true
        if [[ "${force,,}" = "y" ]]; then
            break
        fi
    done
    export NAME_OF_MACHINE=$name_of_machine
}

locale_select () {
    echo -ne "
    Please select your locale setting from this list
    "
    options=("en_AU.UTF-8" "en_US.UTF-8" "en_GB.UTF-8" "es_ES.UTF-8" "fr_FR.UTF-8" "de_DE.UTF-8" "it_IT.UTF-8" "pt_PT.UTF-8" "ja_JP.UTF-8" "exit")
    select_option "${options[@]}"
    choice=$?
    if [[ "${options[$choice]}" == "exit" ]]; then
        echo "Exiting."
        exit 0
    fi
    export LOCALE="${options[$choice]}"
    echo -ne "Your locale: ${LOCALE} \n"
}

# Starting functions
background_checks
clear
logo
userinfo
clear
logo
diskpart
clear
logo
filesystem
clear
logo
timezone
clear
logo
keymap
clear
logo
locale_select

echo "Setting up mirrors for optimal download"
iso=$(curl -4 --silent ifconfig.io/country_code || echo "")
timedatectl set-ntp true
pacman -Sy --noconfirm
pacman -S --noconfirm archlinux-keyring # update keyrings
pacman -S --noconfirm --needed pacman-contrib terminus-font
setfont ter-v18b || true
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
pacman -S --noconfirm --needed reflector rsync grub
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup || true

echo -ne "
-------------------------------------------------------------------------
                    Setting up ${iso:-all} mirrors for faster downloads
-------------------------------------------------------------------------
"
if [[ -n "$iso" ]]; then
    reflector -a 48 -c "$iso" --score 5 -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist || true
fi

if [[ $(grep -c "Server =" /etc/pacman.d/mirrorlist || true) -lt 5 ]]; then
    cp /etc/pacman.d/mirrorlist.backup /etc/pacman.d/mirrorlist || true
fi

mkdir -p /mnt
echo -ne "
-------------------------------------------------------------------------
                    Installing Prerequisites
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed gptfdisk btrfs-progs glibc

echo -ne "
-------------------------------------------------------------------------
                    Formatting Disk
-------------------------------------------------------------------------
"
umount -A --recursive /mnt || true
sgdisk -Z "${DISK}" # zap all on disk
sgdisk -a 2048 -o "${DISK}" # new gpt disk 2048 alignment

# create partitions
sgdisk -n 1::+1M --typecode=1:ef02 --change-name=1:'BIOSBOOT' "${DISK}"
sgdisk -n 2::+1GiB --typecode=2:ef00 --change-name=2:'EFIBOOT' "${DISK}"
sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' "${DISK}"
if [[ ! -d "/sys/firmware/efi" ]]; then
    sgdisk -A 1:set:2 "${DISK}"
fi
partprobe "${DISK}"

# helper: detect correct partition paths for device naming
if [[ "${DISK}" =~ (nvme|mmcblk) ]]; then
    partition2="${DISK}p2"
    partition3="${DISK}p3"
else
    partition2="${DISK}2"
    partition3="${DISK}3"
fi

# We'll use ROOT_DEVICE for formatting/mounting; it may be partition3 or /dev/mapper/ROOT
ROOT_DEVICE="${partition3}"

# btrfs subvolume helpers (use ROOT_DEVICE variable)
createsubvolumes () {
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
}

mountallsubvol () {
    mount -o "${MOUNT_OPTIONS}",subvol=@home "${ROOT_DEVICE}" /mnt/home
}

subvolumesetup () {
    createsubvolumes
    umount /mnt
    mount -o "${MOUNT_OPTIONS}",subvol=@ "${ROOT_DEVICE}" /mnt
    mkdir -p /mnt/home
    mountallsubvol
}

if [[ "${FS}" == "btrfs" ]]; then
    mkfs.fat -F32 -n "EFIBOOT" "${partition2}"
    mkfs.btrfs -f "${partition3}"
    ROOT_DEVICE="${partition3}"
    mount -t btrfs "${ROOT_DEVICE}" /mnt
    subvolumesetup
elif [[ "${FS}" == "ext4" ]]; then
    mkfs.fat -F32 -n "EFIBOOT" "${partition2}"
    mkfs.ext4 "${partition3}"
    ROOT_DEVICE="${partition3}"
    mount -t ext4 "${ROOT_DEVICE}" /mnt
elif [[ "${FS}" == "luks" ]]; then
    mkfs.fat -F32 -n "EFIBOOT" "${partition2}"

    # Capture outer partition UUID before opening the container
    ENCRYPTED_PARTITION_UUID=$(blkid -s UUID -o value "${partition3}" || true)

    # Format LUKS and open it; mapped device will be /dev/mapper/ROOT
    echo -n "${LUKS_PASSWORD}" | cryptsetup -q luksFormat "${partition3}" -
    echo -n "${LUKS_PASSWORD}" | cryptsetup open "${partition3}" ROOT -

    # Set ROOT_DEVICE to the mapped device
    ROOT_DEVICE="/dev/mapper/ROOT"

    # Format the mapped device and create subvolumes
    mkfs.btrfs -f "${ROOT_DEVICE}"
    mount -t btrfs "${ROOT_DEVICE}" /mnt
    subvolumesetup

    # if we didn't get the UUID earlier, try reading again from the partition
    ENCRYPTED_PARTITION_UUID="${ENCRYPTED_PARTITION_UUID:-$(blkid -s UUID -o value "${partition3}" || true)}"
fi

BOOT_UUID=$(blkid -s UUID -o value "${partition2}" || true)

sync
if ! mountpoint -q /mnt; then
    echo "ERROR! Failed to mount root device to /mnt after attempts."
    exit 1
fi
mkdir -p /mnt/boot
if [[ -n "${BOOT_UUID}" ]]; then
    mount -U "${BOOT_UUID}" /mnt/boot/
else
    mount "${partition2}" /mnt/boot || true
fi

if ! grep -qs '/mnt' /proc/mounts; then
    echo "Drive is not mounted can not continue"
    echo "Rebooting in 3 Seconds ..." && sleep 1
    echo "Rebooting in 2 Seconds ..." && sleep 1
    echo "Rebooting in 1 Second ..." && sleep 1
    reboot now
fi

echo -ne "
-------------------------------------------------------------------------
                    Arch Install on Main Drive
-------------------------------------------------------------------------
"
if [[ ! -d "/sys/firmware/efi" ]]; then
    pacstrap /mnt base base-devel linux linux-firmware --noconfirm --needed
else
    pacstrap /mnt base base-devel linux linux-firmware efibootmgr --noconfirm --needed
fi

echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

genfstab -U /mnt > /mnt/etc/fstab

echo "
  Generated /etc/fstab:
"
cat /mnt/etc/fstab

echo -ne "
-------------------------------------------------------------------------
                    GRUB BIOS Bootloader Install & Check
-------------------------------------------------------------------------
"
if [[ ! -d "/sys/firmware/efi" ]]; then
    grub-install --boot-directory=/mnt/boot "${DISK}"
fi

echo -ne "
-------------------------------------------------------------------------
                    Checking for low memory systems <8G
-------------------------------------------------------------------------
"
TOTAL_MEM=$(awk '/MemTotal/ {print $2}' /proc/meminfo || echo 0)
if [[  $TOTAL_MEM -lt 8000000 ]]; then
    mkdir -p /mnt/opt/swap
    if findmnt -n -o FSTYPE /mnt | grep -q btrfs; then
        chattr +C /mnt/opt/swap || true
    fi
    dd if=/dev/zero of=/mnt/opt/swap/swapfile bs=1M count=2048 status=progress || true
    chmod 600 /mnt/opt/swap/swapfile
    chown root /mnt/opt/swap/swapfile
    mkswap /mnt/opt/swap/swapfile
    swapon /mnt/opt/swap/swapfile || true
    echo "/opt/swap/swapfile    none    swap    sw    0    0" >> /mnt/etc/fstab
fi

gpu_type=$(lspci | grep -E "VGA|3D|Display" || true)

# Use arch-chroot and pass environment variables explicitly; use a single-quoted heredoc so outer shell doesn't expand variables.
arch-chroot /mnt /usr/bin/env KEYMAP="${KEYMAP:-}" TIMEZONE="${TIMEZONE:-}" LOCALE="${LOCALE:-}" /bin/bash -s <<'EOF_CHROOT'
set -euo pipefail
IFS=$'\n\t'

echo -ne "
-------------------------------------------------------------------------
                    Network Setup
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed networkmanager
systemctl enable NetworkManager

echo -ne "
-------------------------------------------------------------------------
                    Setting up mirrors for optimal download (chroot)
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed pacman-contrib curl terminus-font
pacman -S --noconfirm --needed reflector rsync grub arch-install-scripts git ntp wget
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak || true

nc=$(grep -c ^"cpu cores" /proc/cpuinfo || echo 1)
echo -ne "
-------------------------------------------------------------------------
                    You have ${nc} cores. Adjusting makepkg settings.
-------------------------------------------------------------------------
"
TOTAL_MEM=$(awk '/MemTotal/ {print $2}' /proc/meminfo || echo 0)
if [[  $TOTAL_MEM -gt 8000000 ]]; then
    sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j${nc}\"/g" /etc/makepkg.conf || true
    sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T ${nc} -z -)/g" /etc/makepkg.conf || true
fi

echo -ne "
-------------------------------------------------------------------------
                    Setup Language and set locale
-------------------------------------------------------------------------
"
# Use LOCALE variable passed via env
if [[ -n "${LOCALE:-}" ]]; then
    sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen || true
    locale-gen || true
    timedatectl --no-ask-password set-timezone "${TIMEZONE:-UTC}" || true
    timedatectl --no-ask-password set-ntp 1 || true
    localectl --no-ask-password set-locale LANG="${LOCALE}" LC_TIME="${LOCALE}" || true
    ln -sf /usr/share/zoneinfo/"${TIMEZONE:-UTC}" /etc/localtime || true
fi

# Set keymaps
if [[ -n "${KEYMAP:-}" ]]; then
    echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
fi

# Add sudo no password rights temporarily
sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers || true
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers || true

# Add parallel downloading and ILoveCandy for pacman
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf || true
sed -i 's/^#Color/Color\nILoveCandy/' /etc/pacman.conf || true
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf || true
pacman -Sy --noconfirm --needed || true

echo -ne "
-------------------------------------------------------------------------
                    Installing Microcode
-------------------------------------------------------------------------
"
if grep -q "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
    pacman -S --noconfirm --needed intel-ucode || true
elif grep -q "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
    pacman -S --noconfirm --needed amd-ucode || true
else
    echo "Unable to determine CPU vendor. Skipping microcode installation."
fi

echo -ne "
-------------------------------------------------------------------------
                    Installing Graphics Drivers
-------------------------------------------------------------------------
"
# gpu_type from outer environment is not available here; do best-effort detection
gpu_type_local=$(lspci | grep -E "VGA|3D|Display" || true)
if echo "${gpu_type_local}" | grep -E "NVIDIA|GeForce" >/dev/null 2>&1; then
    pacman -S --noconfirm --needed nvidia nvidia-utils || true
elif echo "${gpu_type_local}" | grep -E "Radeon|AMD" >/dev/null 2>&1; then
    pacman -S --noconfirm --needed xf86-video-amdgpu || true
else
    pacman -S --noconfirm --needed mesa || true
fi

echo "Done chroot configuration steps."
EOF_CHROOT

echo -ne "
-------------------------------------------------------------------------
                    Adding User on target root
-------------------------------------------------------------------------
"
# Add user and set password in the new system
arch-chroot /mnt /bin/bash -c "
groupadd -f libvirt || true
useradd -m -G wheel,libvirt -s /bin/bash '${USERNAME}' || true
echo '${USERNAME}:${PASSWORD}' | chpasswd
echo '${NAME_OF_MACHINE}' > /etc/hostname
"

if [[ ${FS} == "luks" ]]; then
    # Ensure initramfs includes encrypt hook and regenerate
    arch-chroot /mnt /bin/bash -c "sed -i 's/filesystems/encrypt filesystems/g' /etc/mkinitcpio.conf || true; mkinitcpio -P || true"
else
    arch-chroot /mnt /bin/bash -c "mkinitcpio -P || true"
fi

echo -ne "
-------------------------------------------------------------------------
                    GRUB EFI Bootloader Install & Check
-------------------------------------------------------------------------
"
if [[ -d "/sys/firmware/efi" ]]; then
    arch-chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB || true"
fi

# Configure grub for LUKS (if used) and add splash
if [[ "${FS:-}" == "luks" && -n "${ENCRYPTED_PARTITION_UUID:-}" ]]; then
    arch-chroot /mnt /bin/bash -c "sed -i 's%GRUB_CMDLINE_LINUX_DEFAULT=\"%GRUB_CMDLINE_LINUX_DEFAULT=\"cryptdevice=UUID=${ENCRYPTED_PARTITION_UUID}:ROOT root=/dev/mapper/ROOT %g' /etc/default/grub || true"
fi
arch-chroot /mnt /bin/bash -c "sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"[^\\\"]*/& splash /' /etc/default/grub || true"
arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg || true"

echo -ne "
-------------------------------------------------------------------------
                    Enabling Essential Services
-------------------------------------------------------------------------
"
arch-chroot /mnt /bin/bash -c "ntpd -qg || true"
arch-chroot /mnt /bin/bash -c "systemctl enable ntpd.service || true"
arch-chroot /mnt /bin/bash -c "systemctl disable dhcpcd.service || true"
arch-chroot /mnt /bin/bash -c "systemctl enable NetworkManager.service || true"
arch-chroot /mnt /bin/bash -c "systemctl enable reflector.timer || true"

echo -ne "
-------------------------------------------------------------------------
                    Cleaning / Finalizing
-------------------------------------------------------------------------
"
# Remove nopass sudo and enable normal wheel rights
arch-chroot /mnt /bin/bash -c "sed -i 's/^%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers || true"
arch-chroot /mnt /bin/bash -c "sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers || true"
arch-chroot /mnt /bin/bash -c "sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers || true"
arch-chroot /mnt /bin/bash -c "sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers || true"

echo -ne "
-------------------------------------------------------------------------
                    Installation complete
-------------------------------------------------------------------------
"
echo "You can now reboot into your new system."
