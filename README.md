# Install Arch with Dank Shell and CachyOS repos
This is my setup of Arch without needing to install the full CachyOS stuff 

## Links
- [Arch Linux](archlinux.org)
- [CahcyOS PKGBUILDS Repo](https://github.com/CachyOS/CachyOS-PKGBUILDS)
- [CachyOS Repo](https://github.com/CachyOS/linux-cachyos)
- [Chaotic-AUR](https://aur.chaotic.cx/docs)
- [Starship Prompt](https://starship.rs)
- [Dank Linux](https://github.com/AvengeMedia/danklinux)

## Download & Install base Arch
1. Download the latest [archiso](https://mirror.aarnet.edu.au/pub/archlinux/iso/2025.10.01/archlinux-2025.10.01-x86_64.iso)
2. run ```archinstall```
3. choose minimal install and netmanger
4. after install is finished enter chroot and follow the next steps an switch to the user you created
```bash
su - <user> #make sure you change this to your username
```
## Install CachyOS Repos
1. Download the script and run it
```bash
curl -O https://mirror.cachyos.org/cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz && cd cachyos-repo
sudo ./cachyos-repo.sh
```
2. Install the CachyOS kernel
```bash
pacman -S linux-cachyos linux-cachyos-headers
```
## Install Chaotic Aur
1. Install the repo
```bash
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
```
2. Add the repo to the ```/etc/pacman.conf```
```
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
```
3. Sync the Repos
```bash
sudo pacman -Syu
```

## Install Paru
```bash
sudo pacman -S paru
```

## Install Dank Linux
1. Run the script
```bash 
curl -fsSL https://install.danklinux.com | sh
```
2. Choose options (if in VM choose kitty as the terminal otherwise choose ghostty)
3. Install Greeter
```bash
dms greeter install
sudo systemctl enable greetd
```
## Customise the install
1. Install Theme
```bash
paru -S sassc gtk-engine-murrine gnome-themes-extra colloid-gtk-theme colloid-icon-theme colloid-cursors qt6ct-kde
```
2. Install extra packages
```bash 
paru -S brightnessctl  wl-clipboard cava cliphist gammastep cosmic-edit-git cosmic-files-git fastfetch ddcutil imagemagick fzf ttf-meslo-nerd zoxide ripgrep bash-completion multitail tree trash-cli wget firefox cachyos-firefox-settings xdg-user-dirs pipewire-audio python-pywalfox wireplumber pwvucontrol jq grim slurp
```
3. Install Starship prompt
```bash
curl -sS https://starship.rs/install.sh | sh
starship preset catppuccin-powerline -o ~/.config/starship.toml
```
4. Install Fastfetch theme
```bash
mkdir -p ~/.config/fastfetch && cd ~/.config/fastfetch
fastfetch --gen-config
rm config.jsonc
wget  https://raw.githubusercontent.com/thedaedalus/DaedalusArch/refs/heads/main/dotfiles/fastfetch/config.jsonc
```
5. Setup XDG Dirs
```bash
xdg-user-dirs-update
```  

6. Download Wallpapers
```bash
cd ~/Pictures
git clone https://github.com/orangci/walls-catppuccin-mocha.git 
```
7. Install Firefox theme
```bash
sudo pywalfox install
```
restart DMS then do below
```bash
dms restart
ln -sf ~/.cache/wal/dank-pywalfox.json ~/.cache/wal/colors.json
```

     
