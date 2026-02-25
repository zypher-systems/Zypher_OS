#!/bin/bash
set -e

# --- 0. Firmware Check for User Awareness ---
if [ ! -d "/sys/firmware/efi" ]; then
  FIRMWARE_MSG="Notice: Booted in Legacy BIOS (SeaBIOS) mode. Proceeding with hybrid MBR/GPT install."
else
  FIRMWARE_MSG="Notice: Booted in UEFI mode. Proceeding with standard EFI install."
fi

whiptail --title "ZypherOS Installer - Alpha Release" --msgbox "Welcome to the ZypherOS Installer.\n\n$FIRMWARE_MSG\n\nPress Enter to begin the setup process." 12 60

# --- 1. The Interview (TUI) ---

# Drive Selection
DRIVE_OPTIONS=()
while read -r name size model; do
    DRIVE_OPTIONS+=("$name" "$model ($size)")
done < <(lsblk -d -p -n -l -o NAME,SIZE,MODEL | grep -v "loop" | grep -v "rom")

TARGET_DRIVE=$(whiptail --title "Target Drive Configuration" --menu "Choose the drive to install ZypherOS on:\nWARNING: ALL DATA ON THIS DRIVE WILL BE WIPED!" 15 65 5 "${DRIVE_OPTIONS[@]}" 3>&1 1>&2 2>&3)
if [ -z "$TARGET_DRIVE" ]; then clear; echo "Installation canceled."; exit 1; fi

# User Setup
USERNAME=$(whiptail --title "User Account Setup" --inputbox "Enter the desired username for the primary account:" 10 60 "Dusty" 3>&1 1>&2 2>&3)
if [ -z "$USERNAME" ]; then clear; echo "Installation canceled."; exit 1; fi

# Password Setup
while true; do
  PASSWORD=$(whiptail --title "Security Setup" --passwordbox "Enter the password for $USERNAME (This will also be the Root password):" 10 60 3>&1 1>&2 2>&3)
  PASSWORD_CONFIRM=$(whiptail --title "Security Setup" --passwordbox "Confirm your password:" 10 60 3>&1 1>&2 2>&3)
  
  if [ "$PASSWORD" == "$PASSWORD_CONFIRM" ] && [ -n "$PASSWORD" ]; then 
      break
  else 
      whiptail --title "Error" --msgbox "Passwords do not match or are empty. Please try again." 10 60
  fi
done

# Hostname Setup
HOSTNAME=$(whiptail --title "Network Setup" --inputbox "Enter the system hostname (Computer Name):" 10 60 "zypheros" 3>&1 1>&2 2>&3)
if [ -z "$HOSTNAME" ]; then clear; echo "Installation canceled."; exit 1; fi

# Smart GPU Auto-Detect
GPU_VENDOR=$(lspci -vnn | grep -iE 'VGA|3D' | grep -iE 'NVIDIA|AMD|Advanced Micro Devices|Intel' | head -n 1)
if echo "$GPU_VENDOR" | grep -iq "NVIDIA"; then DETECTED="NVIDIA"; DEFAULT="2";
elif echo "$GPU_VENDOR" | grep -iqE "AMD|Advanced Micro Devices"; then DETECTED="AMD"; DEFAULT="1";
elif echo "$GPU_VENDOR" | grep -iq "Intel"; then DETECTED="Intel"; DEFAULT="3";
else DETECTED="Virtual Machine / Generic"; DEFAULT="4"; fi

GPU_CHOICE=$(whiptail --title "Graphics Drivers" --menu "Hardware Scan detected: $DETECTED\n\nPlease verify your graphics driver deployment:" 15 65 4 \
"1" "AMD (Open Source) - Recommended" \
"2" "NVIDIA (Proprietary)" \
"3" "Intel" \
"4" "Virtual Machine (QEMU/VMware/VirtIO)" \
--default-item "$DEFAULT" 3>&1 1>&2 2>&3)

if [ -z "$GPU_CHOICE" ]; then clear; echo "Installation canceled."; exit 1; fi

case $GPU_CHOICE in
  1) GPU_PKG="mesa xf86-video-amdgpu vulkan-radeon amd-ucode" ;;
  2) GPU_PKG="nvidia nvidia-utils" ;;
  3) GPU_PKG="mesa xf86-video-intel vulkan-intel intel-ucode" ;;
  4) GPU_PKG="mesa" ;;
esac

# Final Point of No Return
if ! whiptail --title "WARNING: DATA DESTRUCTION" --yesno "You are about to COMPLETELY WIPE the following drive:\n\n$TARGET_DRIVE\n\nAre you absolutely sure you want to proceed?" 12 60; then
    clear
    echo "Installation aborted by user."
    exit 1
fi

clear
echo "========================================="
echo "   Initiating ZypherOS Deployment...     "
echo "========================================="
sleep 2

# --- 2. Universal Partitioning ---
echo "Wiping and partitioning $TARGET_DRIVE..."
sgdisk -Z "$TARGET_DRIVE"
sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS_BOOT" "$TARGET_DRIVE"
sgdisk -n 2:0:+1024M -t 2:ef00 -c 2:"EFI" "$TARGET_DRIVE"
sgdisk -n 3:0:0 -t 3:8300 -c 3:"ROOT" "$TARGET_DRIVE"

if [[ "$TARGET_DRIVE" == *"nvme"* ]] || [[ "$TARGET_DRIVE" == *"mmcblk"* ]]; then
  EFI_PART="${TARGET_DRIVE}p2"
  ROOT_PART="${TARGET_DRIVE}p3"
else
  EFI_PART="${TARGET_DRIVE}2"
  ROOT_PART="${TARGET_DRIVE}3"
fi

echo "Formatting partitions..."
mkfs.vfat -F32 "$EFI_PART"
mkfs.btrfs -f "$ROOT_PART"

# --- 3. ZypherOS BTRFS Subvolume Architecture ---
echo "Building BTRFS subvolumes..."
mount "$ROOT_PART" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
umount /mnt

echo "Mounting subvolumes..."
MNT_OPTS="noatime,compress=zstd,space_cache=v2"
mount -o "$MNT_OPTS,subvol=@" "$ROOT_PART" /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,boot}

mount -o "$MNT_OPTS,subvol=@home" "$ROOT_PART" /mnt/home
mount -o "$MNT_OPTS,subvol=@log" "$ROOT_PART" /mnt/var/log
mount -o "$MNT_OPTS,subvol=@pkg" "$ROOT_PART" /mnt/var/cache/pacman/pkg
mount "$EFI_PART" /mnt/boot

# --- 3.5. Optimize Live Environment for Speed ---
echo "Optimizing Live Environment for maximum download speeds..."

sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman\.d\/mirrorlist/ s/^#//' /etc/pacman.conf

echo "Fetching Arch Linux Global CDN..."
echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' > /etc/pacman.d/mirrorlist

echo "Synchronizing package databases..."
pacman -Sy archlinux-keyring --noconfirm
pacman -Syy --noconfirm

# --- 3.8. Pre-Pacstrap System Config ---
mkdir -p /mnt/etc
echo "KEYMAP=us" > /mnt/etc/vconsole.conf

# --- 4. The Pacstrap ---
echo "Preparing ZypherOS package lists..."
ZYPHER_PACKAGES=(
  base base-devel linux linux-lts linux-firmware btrfs-progs sudo networkmanager
  $GPU_PKG limine snapper efibootmgr mtools
  plasma sddm pipewire wireplumber pipewire-pulse bluez bluez-utils bluedevil
  konsole dolphin ark spectacle kate gwenview okular partitionmanager
  git fastfetch fish neovim starship zoxide thefuck eza bat btop
  lazygit ripgrep fd unzip wget xclip wl-clipboard ghostty gimp blender 
  inkscape libreoffice-fresh pika-backup obs-studio kdenlive thunderbird discord
  ttf-meslo-nerd noto-fonts noto-fonts-emoji
)

echo "Installing base system and ZypherOS dependencies..."
pacstrap -K /mnt "${ZYPHER_PACKAGES[@]}"
genfstab -U /mnt >>/mnt/etc/fstab


# --- 4.5. Stage Skeleton Directory & System Configs ---
echo "Staging system configurations and user dotfiles (/etc/skel)..."

mkdir -p /mnt/etc/skel/.config/{ghostty/themes,fish,fastfetch,nvim,discord}

cat <<'SKEL' > /mnt/etc/skel/.config/discord/settings.json
{
  "SKIP_HOST_UPDATE": true
}
SKEL

cat <<'SKEL' > /mnt/etc/skel/.config/ghostty/themes/carbonfox
palette = 0=#282828
palette = 1=#ee5396
palette = 2=#25be6a
palette = 3=#08bdba
palette = 4=#78a9ff
palette = 5=#be95ff
palette = 6=#33b1ff
palette = 7=#dfdfe0
palette = 8=#484848
palette = 9=#f16da6
palette = 10=#46c880
palette = 11=#2dc7c4
palette = 12=#8cb6ff
palette = 13=#c8a5ff
palette = 14=#52bdff
palette = 15=#e4e4e5
background = 161616
foreground = f2f4f8
cursor-color = e4e4e5
selection-background = 2a2a2a
selection-foreground = f2f4f8
SKEL

cat <<'SKEL' > /mnt/etc/skel/.config/ghostty/config
command = /usr/bin/fish
font-family = MesloLGS Nerd Font Mono
font-family-bold = MesloLGS Nerd Font Mono Bold
font-family-italic = MesloLGS Nerd Font Mono Italic
font-size = 14
background-opacity = 0.9
theme = carbonfox
shell-integration = fish
SKEL

cat <<'SKEL' > /mnt/etc/skel/.config/fish/config.fish
if status is-interactive
    set -gx EDITOR nvim
    set -gx BROWSER firefox
    set -gx PAGER less
    set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"
    set -gx TERM xterm-256color
    set -gx COLORTERM truecolor
    set -gx CLICOLOR 1

    fish_vi_key_bindings
    set fish_greeting

    set fish_color_normal normal
    set fish_color_command 00d7ff
    set fish_color_quote a8cc8c
    set fish_color_redirection ff6b9d
    set fish_color_end ff6b9d
    set fish_color_error ff5555
    set fish_color_param d7d7d7
    set fish_color_comment 6272a4
    set fish_color_match --background=brblue
    set fish_color_selection white --bold --background=brblack
    set fish_color_search_match bryellow --background=brblack
    set fish_color_history_current --bold
    set fish_color_operator ff79c6
    set fish_color_escape 8be9fd
    set fish_color_cwd green
    set fish_color_cwd_root red
    set fish_color_valid_path --underline
    set fish_color_autosuggestion 6272a4
    set fish_color_user brgreen
    set fish_color_host normal

    alias ls 'eza --color=always --group-directories-first --icons'
    alias ll 'eza -alF --color=always --group-directories-first --icons'
    alias la 'eza -a --color=always --group-directories-first --icons'
    alias lt 'eza -aT --color=always --group-directories-first --icons'
    alias l. 'eza -a | grep -E "^\."'
    alias g 'git'
    alias gs 'git status -sb'
    alias gl 'git log --oneline --graph --decorate --all'
    alias gd 'git diff --color=always'
    alias sysinfo 'fastfetch'
    alias weather 'curl -s "wttr.in?format=3"'
    alias myip 'curl -s ifconfig.me'
    alias ports 'netstat -tuln'
    alias cat 'bat --style=numbers,changes,header'
    alias less 'bat --paging=always'
    alias .. 'cd ..'
    alias ... 'cd ../..'
    alias .... 'cd ../../..'
    alias htop 'btop'
    alias df 'df -h'
    alias du 'du -h'
    alias free 'free -h'
    alias grep 'grep --color=auto'
    alias mkdir 'mkdir -pv'
    alias wget 'wget -c'
    alias reload 'source ~/.config/fish/config.fish'

    function cd
        builtin cd $argv
        and ls
    end

    function extract
        switch $argv[1]
            case '*.tar.bz2'; tar xjf $argv[1] ;;
            case '*.tar.gz'; tar xzf $argv[1] ;;
            case '*.bz2'; bunzip2 $argv[1] ;;
            case '*.rar'; unrar x $argv[1] ;;
            case '*.gz'; gunzip $argv[1] ;;
            case '*.tar'; tar xf $argv[1] ;;
            case '*.tbz2'; tar xjf $argv[1] ;;
            case '*.tgz'; tar xzf $argv[1] ;;
            case '*.zip'; unzip $argv[1] ;;
            case '*.7z'; 7z x $argv[1] ;;
            case '*'; echo "Unknown archive format" ;;
        end
    end

    function update
        echo "🔄 Updating system packages..."
        if command -v pacman >/dev/null
            sudo pacman -Syu
        else
            echo "Package manager not recognized"
        end
    end

    function netinfo
        echo "🌐 Network Information:"
        echo "External IP: "(curl -s ifconfig.me)
        echo "Local IP: "(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
        echo "DNS: "(grep nameserver /etc/resolv.conf | awk '{print $2}' | head -1)
    end

    if command -v starship >/dev/null
        starship init fish | source
    end

    function fish_greeting
        set_color cyan
        echo "╭────────────────────────────────────────────────────────────╮"
        set_color normal
        set_color --bold blue
        printf "│ 🚀 %-55s │\n" "Zypher Terminal - Enhanced Experience"
        set_color normal
        set_color yellow
        printf "│ 📅 %-55s │\n" (date "+%A, %B %d, %Y at %I:%M %p")
        set_color normal
        set_color green
        set -l uptime_info (cat /proc/uptime | cut -d' ' -f1)
        set -l uptime_hours (math "floor($uptime_info / 3600)")
        set -l uptime_minutes (math "floor(($uptime_info % 3600) / 60)")
        printf "│ 💾 %-55s │\n" "Uptime: $uptime_hours hours, $uptime_minutes minutes"
        set_color normal
        set_color magenta
        set -l host_name (cat /etc/hostname 2>/dev/null || echo "Unknown")
        printf "│ 🖥️ %-55s │\n" "Host: $host_name"
        set_color normal
        set_color red
        printf "│ 👤 %-55s │\n" "User: $USER"
        set_color normal
        set_color blue
        printf "│ 🐚 %-55s │\n" "Shell: Fish "(fish --version | string match -r '\d+\.\d+\.\d+')
        set_color normal
        set_color cyan
        echo "╰────────────────────────────────────────────────────────────╯"
        set_color normal
        echo
        set_color --dim white
        echo "💡 Tips: Use 'sysinfo' for detailed system info (Fastfetch)"
        set_color normal
        echo
    end

    set -gx PATH $HOME/.local/bin $PATH

    if command -v zoxide >/dev/null
        zoxide init fish | source
    end

    if command -v thefuck >/dev/null
        thefuck --alias | source
    end
end
SKEL

cat <<'SKEL' > /mnt/etc/skel/.config/fastfetch/config.jsonc
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "file",
        "source": "/usr/share/zypheros/branding/logo.txt",
        "padding": {
            "top": 1,
            "left": 2,
            "right": 2
        }
    },
    "modules": [
        "break",
        {
            "type": "custom",
            "format": "\u001b[1;32m╭──────────────────────── \u001b[1;97mHardware\u001b[1;32m ────────────────────────╮"
        },
        { "type": "host", "key": "\u001b[1;32m│ \u001b[1;97m \u001b[1;32mPC", "keyColor": "bright_green" },
        { "type": "cpu", "key": "\u001b[1;32m│ \u001b[1;97m \u001b[1;32mCPU", "keyColor": "bright_green" },
        { "type": "gpu", "key": "\u001b[1;32m│ \u001b[1;97m \u001b[1;32mGPU", "keyColor": "bright_green" },
        { "type": "memory", "key": "\u001b[1;32m│ \u001b[1;97m \u001b[1;32mRAM", "keyColor": "bright_green" },
        { "type": "disk", "key": "\u001b[1;32m│ \u001b[1;97m \u001b[1;32mStorage", "keyColor": "bright_green" },
        {
            "type": "custom",
            "format": "\u001b[1;32m╰──────────────────────────────────────────────────────────╯"
        },
        "break",
        {
            "type": "custom",
            "format": "\u001b[1;33m╭──────────────────────── \u001b[1;97mSoftware\u001b[1;33m ────────────────────────╮"
        },
        { "type": "os", "key": "\u001b[1;33m│ \u001b[1;97m \u001b[1;33mOS", "keyColor": "bright_yellow" },
        { "type": "kernel", "key": "\u001b[1;33m│ \u001b[1;97m \u001b[1;33mKernel", "keyColor": "bright_yellow" },
        { "type": "bios", "key": "\u001b[1;33m│ \u001b[1;97m \u001b[1;33mBIOS", "keyColor": "bright_yellow" },
        { "type": "packages", "key": "\u001b[1;33m│ \u001b[1;97m \u001b[1;33mPackages", "keyColor": "bright_yellow" },
        { "type": "shell", "key": "\u001b[1;33m│ \u001b[1;97m \u001b[1;33mShell", "keyColor": "bright_yellow" },
        {
            "type": "custom",
            "format": "\u001b[1;33m╰──────────────────────────────────────────────────────────╯"
        },
        "break",
        {
            "type": "custom",
            "format": "\u001b[1;34m╭─────────────────── \u001b[1;97mDesktop Environment\u001b[1;34m ──────────────────╮"
        },
        { "type": "de", "key": "\u001b[1;34m│ \u001b[1;97m \u001b[1;34mDE", "keyColor": "bright_blue" },
        { "type": "lm", "key": "\u001b[1;34m│ \u001b[1;97m \u001b[1;34mLogin Manager", "keyColor": "bright_blue" },
        { "type": "wm", "key": "\u001b[1;34m│ \u001b[1;97m \u001b[1;34mWindow Manager", "keyColor": "bright_blue" },
        { "type": "wmtheme", "key": "\u001b[1;34m│ \u001b[1;97m \u001b[1;34mTheme", "keyColor": "bright_blue" },
        { "type": "terminal", "key": "\u001b[1;34m│ \u001b[1;97m \u001b[1;34mTerminal", "keyColor": "bright_blue" },
        {
            "type": "custom",
            "format": "\u001b[1;34m╰──────────────────────────────────────────────────────────╯"
        },
        "break",
        {
            "type": "custom",
            "format": "\u001b[1;35m╭─────────────────── \u001b[1;97mNetwork & System\u001b[1;35m ───────────────────╮"
        },
        { "type": "localip", "key": "\u001b[1;35m│ \u001b[1;97m \u001b[1;35mLocal IP", "keyColor": "bright_magenta" },
        { "type": "wifi", "key": "\u001b[1;35m│ \u001b[1;97m \u001b[1;35mWiFi", "keyColor": "bright_magenta" },
        {
            "type": "command",
            "key": "\u001b[1;35m│ \u001b[1;97m \u001b[1;35mOS Age",
            "keyColor": "bright_magenta",
            "text": "birth_install=$(stat -c %W /); current=$(date +%s); time_progression=$((current - birth_install)); days_difference=$((time_progression / 86400)); echo $days_difference days"
        },
        { "type": "uptime", "key": "\u001b[1;35m│ \u001b[1;97m \u001b[1;35mUptime", "keyColor": "bright_magenta" },
        { "type": "datetime", "key": "\u001b[1;35m│ \u001b[1;97m \u001b[1;35mDateTime", "keyColor": "bright_magenta" },
        {
            "type": "custom",
            "format": "\u001b[1;35m╰────────────────────────────────────────────────────────╯"
        },
        "break",
        {
            "type": "custom",
            "format": "\u001b[1;90m                    ╭─ \u001b[1;97mPowered by Zypher Systems\u001b[1;90m ─╮"
        },
        {
            "type": "custom",
            "format": "\u001b[1;90m                    ╰─ \u001b[1;97mCustom Fastfetch Config\u001b[1;90m ───╯"
        }
    ]
}
SKEL

cat <<'SKEL' > /mnt/etc/skel/.config/kdeglobals
[General]
ColorScheme=BreezeDark
Name=Breeze Dark
TerminalApplication=ghostty
SKEL

cat <<'SKEL' > /mnt/etc/skel/.config/kcminputrc
[Keyboard]
NumLock=0
SKEL

echo "TERMINAL=ghostty" >> /mnt/etc/environment

# --- 5. The Chroot Handoff ---
echo "Generating internal configuration script..."

cat <<EOF >/mnt/zypher_chroot.sh
#!/bin/bash
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# --- ZypherOS Repo Pivot (Injecting Custom Repos) ---
echo "Pivoting system to ZypherOS Custom Repositories..."
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman\.d\/mirrorlist/ s/^#//' /etc/pacman.conf

if ! head -n 5 /etc/pacman.d/mirrorlist | grep -q "repo.zyphersystems.com"; then
  sed -i '1i Server = https://repo.zyphersystems.com/mirror/\$repo/os/\$arch\n' /etc/pacman.d/mirrorlist
fi

if ! grep -q "^\[zypheros\]" /etc/pacman.conf; then
  cat <<'REPOEOF' >> /etc/pacman.conf

[zypheros]
SigLevel = Optional TrustAll
Server = https://repo.zyphersystems.com/zypheros/\$arch
REPOEOF
fi

# Do a quick sync so the new OS registers the ZypherOS repo
pacman -Sy
# ----------------------------------------------------

# --- BRANDING ASSET DEPLOYMENT ---
echo "Cloning ZypherOS repository for branding assets..."
mkdir -p /usr/share/zypheros/branding
git clone https://github.com/zypher-systems/Zypher_OS.git /tmp/zypher_os_repo
cp /tmp/zypher_os_repo/images/zypher_os_wallpaper.png /usr/share/zypheros/branding/wallpaper.png
cp /tmp/zypher_os_repo/images/zypher_os_launcher_icon.png /usr/share/zypheros/branding/icon.png
rm -rf /tmp/zypher_os_repo

echo "Generating Dynamic ASCII Fastfetch Logo..."
echo -e "\033[1;36m@@@@@@@@@@@@@@@@@@@" > /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;36m@:::::::::::::::::@" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;36m@:::::::::::::::::@" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;36m@:::@@@@@@@@:::::@" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;36m@@@@@    Z:::::S" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;36m        Y:::::Y" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;36m       P:::::S" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;36m      H:::::T\033[1;35m" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;35m     E:::::E" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;35m    R:::::M" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;35m   @:::::S" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;35m@@@:::::@     @@@@@" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;35m@::::::@@@@@@@@:::@" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;35m@:::::::::::::::::@" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;35m@:::::::::::::::::@" >> /usr/share/zypheros/branding/logo.txt
echo -e "\033[1;35m@@@@@@@@@@@@@@@@@@@\033[0m" >> /usr/share/zypheros/branding/logo.txt

echo "Configuring SDDM Login Screen background and themes..."
mkdir -p /etc/sddm.conf.d
echo -e "[General]\nNumlock=on" > /etc/sddm.conf.d/numlock.conf
echo -e "[Theme]\nCurrent=breeze" > /etc/sddm.conf.d/10-theme.conf

mkdir -p /usr/share/sddm/themes/breeze
cat <<'THEME' > /usr/share/sddm/themes/breeze/theme.conf.user
[General]
background=/usr/share/zypheros/branding/wallpaper.png
THEME

echo "Staging Personal User Branding Assets (.local)..."
mkdir -p /etc/skel/.local/share/zypher/branding
cp /usr/share/zypheros/branding/wallpaper.png /etc/skel/.local/share/zypher/branding/wallpaper.png
cp /usr/share/zypheros/branding/icon.png /etc/skel/.local/share/zypher/branding/icon.png

echo "Cloning LazyVim profile..."
git clone https://github.com/zypher-systems/nvim-config.git /etc/skel/.config/nvim
rm -rf /etc/skel/.config/nvim/.git

# ==========================================
# Create User
# ==========================================
useradd -m -G wheel -s /usr/bin/fish $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# --- POST-USERADD ABSOLUTE SCRIPT INJECTION ---
echo "Staging bulletproof hardcoded DBus script for first login..."
mkdir -p /home/$USERNAME/.local/bin
mkdir -p /home/$USERNAME/.config/autostart

# Write the script using a placeholder (ZYPHERUSER)
cat <<'BRANDSCRIPT' > /home/$USERNAME/.local/bin/zypher-branding.sh
#!/bin/bash
exec > "/home/ZYPHERUSER/zypher-branding.log" 2>&1
echo "Waiting for Plasma DBus to initialize..."

until qdbus6 org.kde.plasmashell /PlasmaShell >/dev/null 2>&1; do
    sleep 2
done

echo "DBus found. Waiting 5s for Wayland desktop rendering..."
sleep 5

echo "Applying Wallpaper..."
plasma-apply-wallpaperimage "/home/ZYPHERUSER/.local/share/zypher/branding/wallpaper.png"

echo "Applying Launcher Icon..."
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
    var p = panels();
    for (var i=0; i<p.length; ++i) {
        var w = p[i].widgets();
        for (var j=0; j<w.length; ++j) {
            if (w[j].type === 'org.kde.plasma.kickoff') {
                w[j].currentConfigGroup = ['General'];
                w[j].writeConfig('icon', '/home/ZYPHERUSER/.local/share/zypher/branding/icon.png');
            }
        }
    }
"

echo "Success! Cleaning up autostart script and self-destructing..."
rm -f "/home/ZYPHERUSER/.config/autostart/zypher-branding.desktop"
rm -f "/home/ZYPHERUSER/zypher-branding.log"
rm -f "/home/ZYPHERUSER/.local/bin/zypher-branding.sh"
BRANDSCRIPT

# Swap placeholder for the real username
sed -i "s/ZYPHERUSER/$USERNAME/g" /home/$USERNAME/.local/bin/zypher-branding.sh
chmod +x /home/$USERNAME/.local/bin/zypher-branding.sh

cat <<'BRANDAUTO' > /home/$USERNAME/.config/autostart/zypher-branding.desktop
[Desktop Entry]
Type=Application
Name=ZypherOS Branding Apply
Exec=/home/ZYPHERUSER/.local/bin/zypher-branding.sh
X-KDE-autostart-condition=
BRANDAUTO

sed -i "s/ZYPHERUSER/$USERNAME/g" /home/$USERNAME/.config/autostart/zypher-branding.desktop

# Fix directory and file permissions
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config
chown -R $USERNAME:$USERNAME /home/$USERNAME/.local
# ==========================================

# Map the global KDE theme file so the SDDM user matches the desktop theme
mkdir -p /var/lib/sddm/.config
cp /etc/skel/.config/kdeglobals /var/lib/sddm/.config/kdeglobals
chown -R sddm:sddm /var/lib/sddm/.config

echo "Bootstrapping Neovim plugins for \$USERNAME..."
sudo -u "\$USERNAME" nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || true

# --- Install yay (AUR Helper) & Native Packages ---
echo "Installing yay and AUR packages..."
useradd -m -s /bin/bash builduser
echo 'builduser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builduser
chmod 440 /etc/sudoers.d/builduser

# Install yay
sudo -u builduser git clone https://aur.archlinux.org/yay-bin.git /home/builduser/yay-bin
sudo -u builduser bash -c "cd /home/builduser/yay-bin && makepkg -si --noconfirm"

# Install Google Chrome via yay
sudo -u builduser bash -c "yay -S --noconfirm google-chrome"

rm /etc/sudoers.d/builduser
userdel -r builduser
# ------------------------------------------------

systemctl enable NetworkManager
systemctl enable sddm
systemctl enable bluetooth

snapper -c root create-config /
snapper -c home create-config /home
chmod 750 /.snapshots
chmod 750 /home/.snapshots

mkdir -p /boot/EFI/BOOT
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/
cp /usr/share/limine/limine-bios.sys /boot/

echo "timeout: 5" > /boot/limine.conf
echo "" >> /boot/limine.conf
echo "/ZypherOS" >> /boot/limine.conf
echo "    protocol: linux" >> /boot/limine.conf
echo "    kernel_path: boot():/vmlinuz-linux" >> /boot/limine.conf
echo "    module_path: boot():/initramfs-linux.img" >> /boot/limine.conf
echo "    cmdline: root=UUID=\$(blkid -s UUID -o value $ROOT_PART) rootflags=subvol=@ rw" >> /boot/limine.conf
echo "" >> /boot/limine.conf
echo "/ZypherOS (LTS Kernel)" >> /boot/limine.conf
echo "    protocol: linux" >> /boot/limine.conf
echo "    kernel_path: boot():/vmlinuz-linux-lts" >> /boot/limine.conf
echo "    module_path: boot():/initramfs-linux-lts.img" >> /boot/limine.conf
echo "    cmdline: root=UUID=\$(blkid -s UUID -o value $ROOT_PART) rootflags=subvol=@ rw" >> /boot/limine.conf

if [ -d "/sys/firmware/efi" ]; then
    echo "UEFI detected. Registering ZypherOS with efibootmgr..."
    efibootmgr --create --disk "$TARGET_DRIVE" --part 2 --loader '\EFI\BOOT\BOOTX64.EFI' --label "ZypherOS" --unicode
else
    echo "Legacy BIOS detected. Deploying Limine to the MBR and BIOS Boot Partition..."
    limine bios-install "$TARGET_DRIVE"
fi
EOF

chmod +x /mnt/zypher_chroot.sh
echo "Entering Chroot to finalize system..."
arch-chroot /mnt /zypher_chroot.sh

# --- 6. Clean Up ---
rm /mnt/zypher_chroot.sh
umount -R /mnt

whiptail --title "Installation Complete" --msgbox "ZypherOS has been successfully installed!\n\nPress Enter to exit the installer and reboot." 10 60
clear

echo "========================================="
echo " ZypherOS Base Installation Complete! "
echo "========================================="
echo "The system will reboot automatically."
echo "Press any key to cancel..."

CANCELED=false
for i in {5..1}; do
  echo -ne "\rRebooting in $i seconds... "
  if read -t 1 -n 1 -s </dev/tty; then
    CANCELED=true
    break
  fi
done

echo ""
if [ "$CANCELED" = true ]; then
  echo "Auto-reboot canceled. You are still in the live environment."
  echo "Type 'reboot' when you are ready."
else
  echo "Rebooting now!"
  reboot
fi
