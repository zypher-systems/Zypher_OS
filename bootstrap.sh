#!/bin/bash
set -e

echo "========================================="
echo "   ZypherOS Installer - Alpha Release    "
echo "========================================="

# --- 0. Firmware Check for User Awareness ---
if [ ! -d "/sys/firmware/efi" ]; then
  echo "Notice: Booted in Legacy BIOS (SeaBIOS) mode. Proceeding with hybrid MBR/GPT install."
else
  echo "Notice: Booted in UEFI mode. Proceeding with standard EFI install."
fi
echo ""

# --- 1. The Interview ---
echo "Available Drives:"
mapfile -t DRIVE_ARRAY < <(lsblk -d -p -n -l -o NAME,SIZE,MODEL | grep -v "loop" | grep -v "rom")

for i in "${!DRIVE_ARRAY[@]}"; do
  echo "  $((i + 1))) ${DRIVE_ARRAY[$i]}"
done
echo ""

while true; do
  read -p "Select the number of the target drive (1-${#DRIVE_ARRAY[@]}): " DRIVE_NUM </dev/tty
  if [[ "$DRIVE_NUM" =~ ^[0-9]+$ ]] && [ "$DRIVE_NUM" -ge 1 ] && [ "$DRIVE_NUM" -le "${#DRIVE_ARRAY[@]}" ]; then
    TARGET_DRIVE=$(echo "${DRIVE_ARRAY[$((DRIVE_NUM - 1))]}" | awk '{print $1}')
    echo "Selected target: $TARGET_DRIVE"
    break
  else
    echo "Invalid selection. Please pick a number from the list."
  fi
done

echo ""
read -p "Enter desired username: " USERNAME </dev/tty

while true; do
  read -sp "Enter password for $USERNAME (and Root): " PASSWORD </dev/tty
  echo ""
  read -sp "Confirm password: " PASSWORD_CONFIRM </dev/tty
  echo ""
  if [ "$PASSWORD" == "$PASSWORD_CONFIRM" ]; then
    echo "Passwords match."
    break
  else
    echo "Error: Passwords do not match. Please try again."
  fi
done

echo ""
read -p "Enter system hostname: " HOSTNAME </dev/tty

echo ""
echo "Select Video Driver:"
echo "  1) AMD (Open Source)"
echo "  2) NVIDIA (Proprietary)"
echo "  3) Intel"
echo "  4) Virtual Machine (QEMU/VMware)"
read -p "Selection (1-4): " GPU_CHOICE </dev/tty

case $GPU_CHOICE in
1) GPU_PKG="mesa xf86-video-amdgpu vulkan-radeon amd-ucode" ;;
2) GPU_PKG="nvidia nvidia-utils" ;;
3) GPU_PKG="mesa xf86-video-intel vulkan-intel intel-ucode" ;;
4) GPU_PKG="mesa" ;;
*)
  echo "Invalid choice. Exiting."
  exit 1
  ;;
esac

echo ""
echo "WARNING: This will COMPLETELY WIPE $TARGET_DRIVE."
read -p "Are you sure you want to continue? (Type YES to proceed): " CONFIRM </dev/tty
if [ "$CONFIRM" != "YES" ]; then
  echo "Aborting installation."
  exit 1
fi

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

# --- 3.5. Configure Repositories ---
echo "Configuring package repositories for synchronized install..."
sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman\.d\/mirrorlist/ s/^#//' /etc/pacman.conf
if ! head -n 5 /etc/pacman.d/mirrorlist | grep -q "repo.zyphersystems.com"; then
  sed -i '1i Server = https://repo.zyphersystems.com/mirror/$repo/os/$arch\n' /etc/pacman.d/mirrorlist
fi
if ! grep -q "^\[zypheros\]" /etc/pacman.conf; then
  cat <<'EOF' >>/etc/pacman.conf

[zypheros]
SigLevel = Optional TrustAll
Server = https://repo.zyphersystems.com/zypheros/$arch
EOF
fi

echo "Synchronizing package databases with ZypherOS repos..."
pacman -Sy archlinux-keyring --noconfirm
pacman -Syy --noconfirm

# --- 4. The Pacstrap ---
echo "Preparing ZypherOS package lists..."
ZYPHER_PACKAGES=(
  base base-devel linux linux-lts linux-firmware btrfs-progs sudo networkmanager
  $GPU_PKG limine snapper efibootmgr mtools
  plasma sddm pipewire wireplumber pipewire-pulse bluez bluez-utils bluedevil
  konsole dolphin ark spectacle kate gwenview okular partitionmanager
  git fastfetch fish neovim starship zoxide thefuck eza bat btop
  lazygit ripgrep fd unzip wget xclip wl-clipboard ghostty gimp blender 
  inkscape libreoffice-fresh pika-backup obs-studio flatpak kdenlive thunderbird
  ttf-meslo-nerd noto-fonts noto-fonts-emoji
)

echo "Installing base system and ZypherOS dependencies..."
pacstrap -K /mnt "${ZYPHER_PACKAGES[@]}"
genfstab -U /mnt >>/mnt/etc/fstab


# --- 4.5. Stage Skeleton Directory & System Configs ---
echo "Staging system configurations and user dotfiles (/etc/skel)..."

mkdir -p /mnt/etc/skel/.config/{ghostty/themes,fish,fastfetch,nvim}

# Ghostty Theme & Config
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

# Fish Config
# We use 'SKEL' in quotes so $USER and $PATH don't evaluate during the install phase
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

# Fastfetch Config
cat <<'SKEL' > /mnt/etc/skel/.config/fastfetch/config.jsonc
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "builtin",
        "height": 15,
        "width": 30,
        "padding": {
            "top": 5,
            "left": 3
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

# KDE Globals (Breeze Dark + Ghostty Default)
cat <<'SKEL' > /mnt/etc/skel/.config/kdeglobals
[General]
ColorScheme=BreezeDark
Name=Breeze Dark
TerminalApplication=ghostty
SKEL

# KDE NumLock Preference
cat <<'SKEL' > /mnt/etc/skel/.config/kcminputrc
[Keyboard]
NumLock=0
SKEL

# LazyVim Clone
git clone https://github.com/zypher-systems/nvim-config.git /mnt/etc/skel/.config/nvim
rm -rf /mnt/etc/skel/.config/nvim/.git

# System-wide Terminal Default
echo "TERMINAL=ghostty" >> /mnt/etc/environment

# SDDM NumLock & Breeze Theme Configurations
mkdir -p /mnt/etc/sddm.conf.d
echo -e "[General]\nNumlock=on" > /mnt/etc/sddm.conf.d/numlock.conf
echo -e "[Theme]\nCurrent=breeze" > /mnt/etc/sddm.conf.d/10-theme.conf

# Stage the global dark mode config for the SDDM background user
mkdir -p /mnt/var/lib/sddm/.config
cp /mnt/etc/skel/.config/kdeglobals /mnt/var/lib/sddm/.config/kdeglobals


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
echo "KEYMAP=us" > /etc/vconsole.conf

# Create User (Automatically pulls everything from /etc/skel!)
# Shell changed from bash to fish
useradd -m -G wheel -s /usr/bin/fish $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Fix permissions for the SDDM theme background
chown -R sddm:sddm /var/lib/sddm/.config

# Bootstrap Neovim Plugins as the new user cleanly in the background
echo "Bootstrapping Neovim plugins for \$USERNAME..."
su - "\$USERNAME" -c "nvim --headless '+Lazy! sync' +qa >/dev/null 2>&1" || true

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
