#!/bin/bash
set -e

# --- 0. Pre-Flight Cleanup & Failsafes ---
umount -R /mnt 2>/dev/null || true

cleanup_on_fail() {
  if mountpoint -q /mnt; then
    echo -e "\n[!] Installer interrupted or failed. Cleaning up mounted drives..."
    umount -R /mnt 2>/dev/null || true
    echo "Cleanup complete. You can safely restart the installer by running ./install.sh"
  fi
}
trap cleanup_on_fail ERR INT TERM

# --- TUI MODULES ---
BACKTITLE="ZypherOS Installer - v0.1.3 Alpha"

setup_timezone() {
  REGION=$(whiptail --backtitle "$BACKTITLE" --title "Timezone Selection" --menu "Select your region:" 15 50 8 \
    "America" "" "Europe" "" "Asia" "" "Africa" "" "Australia" "" "Pacific" "" "US" "" 3>&1 1>&2 2>&3)

  if [ -z "$REGION" ]; then
    clear
    echo "Installation canceled."
    exit 1
  fi

  CITY_OPTIONS=()
  for file in /usr/share/zoneinfo/"$REGION"/*; do
    if [ -f "$file" ]; then
      CITY_OPTIONS+=("$(basename "$file")" "")
    fi
  done

  CITY=$(whiptail --backtitle "$BACKTITLE" --title "Timezone Selection" --menu "Select your city:" 20 50 12 "${CITY_OPTIONS[@]}" 3>&1 1>&2 2>&3)

  if [ -z "$CITY" ]; then
    clear
    echo "Installation canceled."
    exit 1
  fi

  SELECTED_TIMEZONE="$REGION/$CITY"
}

setup_user_account() {
  FULL_NAME=$(whiptail --backtitle "$BACKTITLE" --title "Account Setup" \
    --inputbox "Enter the user's Full Name:\n(This will be shown on the login screen.)" 10 60 3>&1 1>&2 2>&3)
  if [ -z "$FULL_NAME" ]; then
    clear
    echo "Installation canceled."
    exit 1
  fi

  DEFAULT_USER=$(echo "$FULL_NAME" | awk '{if (NF==1) print $1; else print substr($1,1,1) $NF}' | tr '[:upper:]' '[:lower:]')

  # --- USERNAME VALIDATION LOOP ---
  while true; do
    USERNAME=$(whiptail --backtitle "$BACKTITLE" --title "Account Setup" \
      --inputbox "Confirm or edit your username:\n(Lowercase letters, numbers, hyphens only.)" 10 60 "$DEFAULT_USER" 3>&1 1>&2 2>&3)

    # Catch if they hit 'Cancel' or 'ESC'
    if [ $? -ne 0 ]; then
      clear
      echo "Installation canceled."
      exit 1
    fi

    # Convert to lowercase to catch 'Root', 'ROOT', etc.
    USERNAME=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')

    # 1. Check if empty
    if [ -z "$USERNAME" ]; then
      whiptail --backtitle "$BACKTITLE" --title "Invalid Username" --msgbox "Username cannot be empty. Please try again." 8 50
      continue
    fi

    # 2. Check if trying to be root
    if [ "$USERNAME" == "root" ]; then
      whiptail --backtitle "$BACKTITLE" --title "Invalid Username" --msgbox "Security Error: You cannot use 'root' as your daily driver account. Please choose a standard username." 10 60
      DEFAULT_USER="" # Clears the default so they have to type something else
      continue
    fi

    # 3. Enforce standard Linux username rules
    if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
      whiptail --backtitle "$BACKTITLE" --title "Invalid Username" --msgbox "Invalid format. Use only lowercase letters, numbers, hyphens, and underscores." 8 60
      continue
    fi

    # If all checks pass, break the loop
    break
  done
  # --------------------------------

  while true; do
    PASSWORD=$(whiptail --backtitle "$BACKTITLE" --title "Security Setup" \
      --passwordbox "Enter the password for user '$USERNAME':\n(This will also be the Root password)" 10 60 3>&1 1>&2 2>&3)
    PASSWORD_CONFIRM=$(whiptail --backtitle "$BACKTITLE" --title "Security Setup" \
      --passwordbox "Confirm your password:" 10 60 3>&1 1>&2 2>&3)

    if [ -z "$PASSWORD" ]; then
      whiptail --backtitle "$BACKTITLE" --title "Error" --msgbox "Password cannot be empty." 8 50
    elif [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
      whiptail --backtitle "$BACKTITLE" --title "Error" --msgbox "Passwords do not match." 8 50
    else
      break
    fi
  done
}

# --- 1. Firmware Check for User Awareness ---
if [ ! -d "/sys/firmware/efi" ]; then
  FIRMWARE_MSG="Notice: Booted in Legacy BIOS (SeaBIOS) mode. Proceeding with hybrid MBR/GPT install."
else
  FIRMWARE_MSG="Notice: Booted in UEFI mode. Proceeding with standard EFI install."
fi

whiptail --backtitle "$BACKTITLE" --title "ZypherOS Installer" --msgbox "Welcome to the ZypherOS Installer.\n\n$FIRMWARE_MSG\n\nPress Enter to begin the setup process." 12 60

# --- 2. Dynamic Network Setup ---
NET_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n 1)

while true; do
  if ping -c 1 -W 2 archlinux.org >/dev/null 2>&1; then
    NET_STATUS="Connected (Internet Accessible)"
    CONNECTED=true
  else
    NET_STATUS="Disconnected (No Internet Access)"
    CONNECTED=false
  fi

  NET_CHOICE=$(whiptail --backtitle "$BACKTITLE" --title "Network Configuration" --menu "Interface: $NET_IFACE\nStatus: $NET_STATUS\n\nSelect network setup for this installation AND the final system:" 16 65 2 \
    "1" "DHCP (Automatic - Recommended)" \
    "2" "Static IP (Datacenter / Manual)" 3>&1 1>&2 2>&3)

  if [ -z "$NET_CHOICE" ]; then
    clear
    echo "Installation canceled."
    exit 1
  fi

  if [ "$NET_CHOICE" == "2" ]; then
    STATIC_IP=$(whiptail --backtitle "$BACKTITLE" --title "Static IP Setup" --inputbox "Enter IP Address with CIDR\n(e.g., 192.168.1.50/24):" 10 60 3>&1 1>&2 2>&3)
    STATIC_GW=$(whiptail --backtitle "$BACKTITLE" --title "Static IP Setup" --inputbox "Enter Default Gateway\n(e.g., 192.168.1.1):" 10 60 3>&1 1>&2 2>&3)
    STATIC_DNS=$(whiptail --backtitle "$BACKTITLE" --title "Static IP Setup" --inputbox "Enter DNS Server\n(e.g., 1.1.1.1 or 8.8.8.8):" 10 60 "1.1.1.1" 3>&1 1>&2 2>&3)

    whiptail --backtitle "$BACKTITLE" --title "Applying Network" --infobox "Applying Static IP to $NET_IFACE..." 8 50
    ip addr flush dev "$NET_IFACE"
    ip addr add "$STATIC_IP" dev "$NET_IFACE"
    ip route add default via "$STATIC_GW"
    echo "nameserver $STATIC_DNS" >/etc/resolv.conf
    sleep 2

    if ping -c 1 -W 3 archlinux.org >/dev/null 2>&1; then
      whiptail --backtitle "$BACKTITLE" --title "Network Connected" --msgbox "Static IP successfully established internet connectivity!" 8 50
      break
    else
      if whiptail --backtitle "$BACKTITLE" --title "Network Failed" --yesno "Could not reach the internet with those settings.\n\nWould you like to try again?" 10 50; then
        continue
      else
        clear
        echo "Installation requires an internet connection. Aborting."
        exit 1
      fi
    fi
  else
    if [ "$CONNECTED" = true ]; then
      whiptail --backtitle "$BACKTITLE" --title "Network Connected" --msgbox "Internet connection confirmed via DHCP! Proceeding with setup." 8 50
      break
    else
      if whiptail --backtitle "$BACKTITLE" --title "Network Disconnected" --yesno "DHCP did not establish a connection.\n\nWould you like to open Network Manager (nmtui) to connect to Wi-Fi?" 10 60; then
        clear
        nmtui
        continue
      else
        clear
        echo "Installation requires an internet connection. Aborting."
        exit 1
      fi
    fi
  fi
done

# --- 3. Disk Selection & Partitioning Setup ---
DRIVE_OPTIONS=()
while read -r name size model; do
  DRIVE_OPTIONS+=("$name" "$model ($size)")
done < <(lsblk -d -p -n -l -o NAME,SIZE,MODEL | grep -v "loop" | grep -v "rom")

TARGET_DRIVE=$(whiptail --backtitle "$BACKTITLE" --title "Target Drive Configuration" --menu "Choose the drive to install ZypherOS on:" 15 65 5 "${DRIVE_OPTIONS[@]}" 3>&1 1>&2 2>&3)

if [ -z "$TARGET_DRIVE" ]; then
  clear
  echo "Installation canceled."
  exit 1
fi

PARTITION_METHOD=$(whiptail --backtitle "$BACKTITLE" --title "Partitioning Method" --menu "How would you like to partition $TARGET_DRIVE?" 15 65 2 \
  "1" "Auto-Partition (Wipe entire drive - Recommended)" \
  "2" "Manual Partition (Custom layout via cfdisk)" 3>&1 1>&2 2>&3)

if [ -z "$PARTITION_METHOD" ]; then
  clear
  echo "Installation aborted."
  exit 1
fi

if [ "$PARTITION_METHOD" == "2" ]; then
  whiptail --backtitle "$BACKTITLE" --title "Manual Partitioning" --msgbox "You will now enter cfdisk to partition $TARGET_DRIVE.\n\nPlease create at least:\n1. An EFI System Partition (min 512MB, Type: EFI System)\n2. A Linux Root Partition (Type: Linux filesystem)\n\nRemember to select 'Write' before quitting." 12 60
  while true; do
    cfdisk "$TARGET_DRIVE"

    echo "Validating partition table..."
    partprobe "$TARGET_DRIVE"
    udevadm settle
    sleep 2

    PARTITIONS=()
    while read -r name size; do
      PARTITIONS+=("$name" "$size")
    done < <(lsblk -r -n -p -o NAME,SIZE "$TARGET_DRIVE" | grep -v "^${TARGET_DRIVE} ")

    if [ ${#PARTITIONS[@]} -lt 4 ]; then
      if ! whiptail --backtitle "$BACKTITLE" --title "Validation Error" --yesno "You must create at least two partitions (EFI and Root).\n\nReturn to cfdisk?" 10 50; then
        clear
        echo "Installation aborted."
        exit 1
      fi
      continue
    fi

    EFI_PART=$(whiptail --backtitle "$BACKTITLE" --title "Partition Assignment" --menu "Select your EFI (Boot) Partition:\n(This will be formatted as FAT32)" 15 65 6 "${PARTITIONS[@]}" 3>&1 1>&2 2>&3)
    if [ -z "$EFI_PART" ]; then continue; fi

    ROOT_PART=$(whiptail --backtitle "$BACKTITLE" --title "Partition Assignment" --menu "Select your Linux Root (/) Partition:\n(This will be formatted as BTRFS)" 15 65 6 "${PARTITIONS[@]}" 3>&1 1>&2 2>&3)
    if [ -z "$ROOT_PART" ]; then continue; fi

    if [ "$EFI_PART" == "$ROOT_PART" ]; then
      whiptail --backtitle "$BACKTITLE" --title "Validation Error" --msgbox "EFI and Root cannot be the same partition!" 8 50
      continue
    fi

    break
  done
fi

# --- 4. System Preferences ---
setup_timezone
setup_user_account

while true; do
  HOSTNAME=$(whiptail --backtitle "$BACKTITLE" --title "Network Setup" --inputbox "Enter the system hostname (Computer Name):\n(Lowercase letters, numbers, and hyphens only. No spaces.)" 10 60 "zypheros" 3>&1 1>&2 2>&3)

  if [ -z "$HOSTNAME" ]; then
    clear
    echo "Installation canceled."
    exit 1
  fi

  if [[ "$HOSTNAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] || [[ "$HOSTNAME" =~ ^[a-z0-9]$ ]]; then
    break
  else
    whiptail --backtitle "$BACKTITLE" --title "Invalid Hostname" --msgbox "Hostname '$HOSTNAME' is invalid.\n\nHostnames must:\n- Contain only lowercase letters, numbers, and hyphens\n- Contain NO spaces or underscores\n- Not start or end with a hyphen" 12 60
  fi
done

# --- ZRAM SWAP CONFIGURATION ---
ZRAM_CHOICE=$(whiptail --backtitle "$BACKTITLE" --title "ZRAM Swap Configuration" --menu "Select your ZRAM (Compressed Swap) size:\n(Dynamically scales based on total system physical RAM)" 16 65 4 \
  "1" "50% of RAM (Recommended for most workloads)" \
  "2" "25% of RAM (For machines with 32GB+ RAM)" \
  "3" "100% of RAM (For low-RAM or heavy compiling)" \
  "4" "Disable ZRAM (No swap space)" 3>&1 1>&2 2>&3)

case $ZRAM_CHOICE in
1) ZRAM_SIZE="ram / 2" ;;
2) ZRAM_SIZE="ram / 4" ;;
3) ZRAM_SIZE="ram" ;;
4) ZRAM_SIZE="none" ;;
*) ZRAM_SIZE="ram / 2" ;; # Failsafe
esac

# --- SSH SERVER CONFIGURATION ---
if whiptail --backtitle "$BACKTITLE" --title "Remote Access" --yesno "Would you like to enable the SSH Server (sshd) on boot?\n\n(Recommended if you plan to remotely manage this machine)" 10 60; then
  ENABLE_SSH="true"
else
  ENABLE_SSH="false"
fi

# --- SMART CPU AUTO-DETECT (MICROCODE) ---
echo -e "\nDetecting CPU Architecture for Microcode..."
CPU_VENDOR=$(grep vendor_id /proc/cpuinfo | head -n 1 | awk '{print $3}')

if [ "$CPU_VENDOR" == "AuthenticAMD" ]; then
  UCODE_PKG="amd-ucode"
  UCODE_IMG="amd-ucode.img"
  echo "Detected AMD CPU. Queuing amd-ucode."
elif [ "$CPU_VENDOR" == "GenuineIntel" ]; then
  UCODE_PKG="intel-ucode"
  UCODE_IMG="intel-ucode.img"
  echo "Detected Intel CPU. Queuing intel-ucode."
else
  UCODE_PKG=""
  UCODE_IMG=""
  echo "Virtual/Unknown CPU detected. Skipping microcode."
fi

# Smart GPU Auto-Detect
GPU_VENDOR=$(lspci -vnn | grep -iE 'VGA|3D' | grep -iE 'NVIDIA|AMD|Advanced Micro Devices|Intel' | head -n 1)
if echo "$GPU_VENDOR" | grep -iq "NVIDIA"; then
  DETECTED="NVIDIA"
  DEFAULT="2"
elif echo "$GPU_VENDOR" | grep -iqE "AMD|Advanced Micro Devices"; then
  DETECTED="AMD"
  DEFAULT="1"
elif echo "$GPU_VENDOR" | grep -iq "Intel"; then
  DETECTED="Intel"
  DEFAULT="3"
else
  DETECTED="Virtual Machine / Generic"
  DEFAULT="4"
fi

GPU_CHOICE=$(whiptail --backtitle "$BACKTITLE" --title "Graphics Drivers" --menu "Hardware Scan detected: $DETECTED\n\nPlease verify your graphics driver deployment:" 15 65 4 \
  "1" "AMD (Open Source) - Recommended" \
  "2" "NVIDIA (Proprietary)" \
  "3" "Intel" \
  "4" "Virtual Machine (QEMU/VMware/VirtIO)" \
  --default-item "$DEFAULT" 3>&1 1>&2 2>&3)

if [ -z "$GPU_CHOICE" ]; then
  clear
  echo "Installation canceled."
  exit 1
fi

case $GPU_CHOICE in
1) GPU_PKG="mesa xf86-video-amdgpu vulkan-radeon" ;;
2) GPU_PKG="nvidia nvidia-utils" ;;
3) GPU_PKG="mesa xf86-video-intel vulkan-intel" ;;
4) GPU_PKG="mesa" ;;
esac

# --- 5. Final Point of No Return ---
if ! whiptail --backtitle "$BACKTITLE" --title "WARNING: READY TO INSTALL" --yesno "All configuration is complete.\n\nIf you chose Auto-Partitioning, $TARGET_DRIVE will now be wiped.\nIf you chose Manual, your selected partitions will be formatted.\n\nAre you absolutely sure you want to proceed with the installation?" 14 60; then
  clear
  echo "Installation aborted by user."
  exit 1
fi

# --- 6. Execution: Formatting & Deployment ---
clear
echo "========================================="
echo "   Initiating ZypherOS Deployment...     "
echo "========================================="
sleep 2

if [ "$PARTITION_METHOD" == "1" ]; then
  echo "Wiping and auto-partitioning $TARGET_DRIVE..."
  sgdisk -Z "$TARGET_DRIVE"
  sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS_BOOT" "$TARGET_DRIVE"
  sgdisk -n 2:0:+1024M -t 2:ef00 -c 2:"EFI" "$TARGET_DRIVE"
  sgdisk -n 3:0:0 -t 3:8300 -c 3:"ROOT" "$TARGET_DRIVE"

  partprobe "$TARGET_DRIVE"
  udevadm settle
  sleep 2

  if [[ "$TARGET_DRIVE" == *"nvme"* ]] || [[ "$TARGET_DRIVE" == *"mmcblk"* ]]; then
    EFI_PART="${TARGET_DRIVE}p2"
    ROOT_PART="${TARGET_DRIVE}p3"
  else
    EFI_PART="${TARGET_DRIVE}2"
    ROOT_PART="${TARGET_DRIVE}3"
  fi
fi

echo "Formatting partitions..."
mkfs.vfat -F32 "$EFI_PART"
mkfs.btrfs -f "$ROOT_PART"

sync
udevadm settle
sleep 2

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

echo "Optimizing Live Environment for maximum download speeds..."
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman\.d\/mirrorlist/ s/^#//' /etc/pacman.conf

echo "Hunting for the fastest Arch mirrors..."
reflector --country US --latest 5 --sort rate --save /etc/pacman.d/mirrorlist

echo "Synchronizing package databases..."
pacman -Sy archlinux-keyring --noconfirm
pacman -Syy --noconfirm

mkdir -p /mnt/etc
echo "KEYMAP=us" >/mnt/etc/vconsole.conf

echo "Preparing ZypherOS package lists..."
ZYPHER_PACKAGES=(
  base base-devel linux linux-lts linux-firmware btrfs-progs sudo networkmanager
  $GPU_PKG $UCODE_PKG limine snapper efibootmgr mtools zram-generator openssh reflector
  plasma sddm pipewire wireplumber pipewire-pulse bluez bluez-utils bluedevil
  dolphin ark spectacle kate gwenview okular partitionmanager
  git neovim zoxide thefuck eza bat btop nano fzf yazi
  lazygit ripgrep fd unzip wget xclip wl-clipboard firefox
  libreoffice-fresh pika-backup thunderbird
  ttf-meslo-nerd noto-fonts noto-fonts-emoji
)

echo "Installing base system and ZypherOS dependencies..."
pacstrap -K /mnt "${ZYPHER_PACKAGES[@]}"
genfstab -U /mnt >>/mnt/etc/fstab

if [ "$NET_CHOICE" == "2" ] && [ -n "$STATIC_IP" ]; then
  echo "Configuring NetworkManager Static IP Profile..."
  mkdir -p /mnt/etc/NetworkManager/system-connections/
  cat <<NMEOF >/mnt/etc/NetworkManager/system-connections/Wired_Static.nmconnection
[connection]
id=Zypher_Static
type=ethernet
match-device=type:ethernet

[ipv4]
method=manual
address1=$STATIC_IP,$STATIC_GW
dns=$STATIC_DNS;

[ipv6]
method=auto
NMEOF
  chmod 600 /mnt/etc/NetworkManager/system-connections/Wired_Static.nmconnection
fi

echo "Staging system configurations and user dotfiles (/etc/skel)..."
mkdir -p /mnt/etc/skel/.config/{nvim,discord}

cat <<'SKEL' >/mnt/etc/skel/.config/discord/settings.json
{
  "SKIP_HOST_UPDATE": true
}
SKEL

cat <<'SKEL' >/mnt/etc/skel/.config/kdeglobals
[General]
ColorScheme=BreezeDark
Name=Breeze Dark
TerminalApplication=ghostty
SKEL

cat <<'SKEL' >/mnt/etc/skel/.config/kcminputrc
[Keyboard]
NumLock=0
SKEL

echo "TERMINAL=ghostty" >>/mnt/etc/environment

echo "Generating internal configuration script..."
cat <<EOF >/mnt/zypher_chroot.sh
#!/bin/bash
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/$SELECTED_TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "Configuring ZRAM"
if [ "$ZRAM_SIZE" != "none" ]; then
    echo "Configuring ZRAM for performance..."
    mkdir -p /etc/systemd/
    cat <<ZRAMEOF > /etc/systemd/zram-generator.conf
[zram0]
zram-size = $ZRAM_SIZE
ZRAMEOF
fi

echo "Pivoting system to ZypherOS Custom Repositories..."
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman\.d\/mirrorlist/ s/^#//' /etc/pacman.conf
echo "NoExtract = etc/os-release etc/issue etc/issue.net" >> /etc/pacman.conf

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

pacman -Sy
pacman -S --noconfirm --overwrite="*" zypheros-release zypheros-ghostty zypheros-fastfetch

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

useradd -m -c "$FULL_NAME" -G wheel -s /usr/bin/fish $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "Staging bulletproof hardcoded DBus script for first login..."
mkdir -p /home/$USERNAME/.local/bin
mkdir -p /home/$USERNAME/.config/autostart

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

chown -R $USERNAME:$USERNAME /home/$USERNAME/.config
chown -R $USERNAME:$USERNAME /home/$USERNAME/.local

mkdir -p /var/lib/sddm/.config
cp /etc/skel/.config/kdeglobals /var/lib/sddm/.config/kdeglobals
chown -R sddm:sddm /var/lib/sddm/.config

echo "Bootstrapping Neovim plugins for $USERNAME..."
sudo -u "$USERNAME" nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || true

echo "Installing yay and AUR packages..."
useradd -m -s /bin/bash builduser
echo 'builduser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builduser
chmod 440 /etc/sudoers.d/builduser

sudo -u builduser git clone https://aur.archlinux.org/yay-bin.git /home/builduser/yay-bin
sudo -u builduser bash -c "cd /home/builduser/yay-bin && makepkg -si --noconfirm"

rm /etc/sudoers.d/builduser
userdel -r builduser

systemctl enable NetworkManager
systemctl enable sddm
systemctl enable bluetooth
if [ "$ENABLE_SSH" == "true" ]; then
    systemctl enable sshd
fi

echo "Initializing Snapper Architecture..."
umount /.snapshots 2>/dev/null || true
rm -rf /.snapshots
snapper -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount -a
snapper -c home create-config /home

chmod 750 /.snapshots
chmod 750 /home/.snapshots

mkdir -p /boot/EFI/BOOT
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/
cp /usr/share/limine/limine-bios.sys /boot/

echo "timeout: 5" > /boot/limine.conf
echo "" >> /boot/limine.conf
echo "/ZypherOS (linux)" >> /boot/limine.conf
echo "    protocol: linux" >> /boot/limine.conf
echo "    kernel_path: boot():/vmlinuz-linux" >> /boot/limine.conf
if [ -n "$UCODE_IMG" ]; then
    echo "    module_path: boot():/$UCODE_IMG" >> /boot/limine.conf
fi
echo "    module_path: boot():/initramfs-linux.img" >> /boot/limine.conf
echo "    cmdline: root=UUID=\$(blkid -s UUID -o value $ROOT_PART) rootflags=subvol=@ rw" >> /boot/limine.conf

echo "" >> /boot/limine.conf
echo "/ZypherOS (linux-lts)" >> /boot/limine.conf
echo "    protocol: linux" >> /boot/limine.conf
echo "    kernel_path: boot():/vmlinuz-linux-lts" >> /boot/limine.conf
if [ -n "$UCODE_IMG" ]; then
    echo "    module_path: boot():/$UCODE_IMG" >> /boot/limine.conf
fi
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

rm /mnt/zypher_chroot.sh
umount -R /mnt

whiptail --backtitle "$BACKTITLE" --title "Installation Complete" --msgbox "ZypherOS has been successfully installed!\n\nPress Enter to exit the installer and reboot." 10 60
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
