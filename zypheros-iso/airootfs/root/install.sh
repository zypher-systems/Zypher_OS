#!/bin/bash
set -e
set -o pipefail # CRITICAL FIX: Ensures pipeline errors trigger the failsafe trap

# --- 0. Pre-Flight Cleanup & Failsafes ---
umount -R /mnt/boot 2>/dev/null || true
umount -R /mnt/home 2>/dev/null || true
umount -R /mnt/var/log 2>/dev/null || true
umount -R /mnt/var/cache/pacman/pkg 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true
cryptsetup close cryptroot 2>/dev/null || true

cleanup_on_fail() {
  if mountpoint -q /mnt; then
    echo -e "\n[!] Installer interrupted or failed. Cleaning up mounted drives..."
    umount -R /mnt/boot 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
    swapoff -a 2>/dev/null || true
    cryptsetup close cryptroot 2>/dev/null || true
    echo "Cleanup complete. You can safely restart the installer by running ./install.sh"
  fi
}
trap cleanup_on_fail ERR INT TERM

# --- TUI MODULES ---
BACKTITLE="ZypherOS Installer - 0.2.0 Alpha"

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
    if [ -f "$file" ]; then CITY_OPTIONS+=("$(basename "$file")" ""); fi
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

  while true; do
    USERNAME=$(whiptail --backtitle "$BACKTITLE" --title "Account Setup" \
      --inputbox "Confirm or edit your username:\n(Lowercase letters, numbers, hyphens only.)" 10 60 "$DEFAULT_USER" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
      clear
      echo "Installation canceled."
      exit 1
    fi
    USERNAME=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')

    if [ -z "$USERNAME" ]; then
      whiptail --backtitle "$BACKTITLE" --title "Invalid Username" --msgbox "Username cannot be empty. Please try again." 8 50
      continue
    fi
    if [ "$USERNAME" == "root" ]; then
      whiptail --backtitle "$BACKTITLE" --title "Invalid Username" --msgbox "Security Error: You cannot use 'root' as your daily driver account." 10 60
      DEFAULT_USER=""
      continue
    fi
    if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
      whiptail --backtitle "$BACKTITLE" --title "Invalid Username" --msgbox "Invalid format. Use only lowercase letters, numbers, hyphens." 8 60
      continue
    fi
    break
  done

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

# --- 1. Firmware Check ---
if [ ! -d "/sys/firmware/efi" ]; then
  FIRMWARE_MSG="Notice: Booted in Legacy BIOS (SeaBIOS) mode. Proceeding with hybrid MBR/GPT install."
else
  FIRMWARE_MSG="Notice: Booted in UEFI mode. Proceeding with standard EFI install."
fi
whiptail --backtitle "$BACKTITLE" --title "ZypherOS Installer" --msgbox "Welcome to the ZypherOS Installer.\n\n$FIRMWARE_MSG\n\nPress Enter to begin the setup process." 12 60

# --- 2. Dynamic Network Setup ---
NET_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n 1 || true)
while true; do
  if ping -c 1 -W 2 archlinux.org >/dev/null 2>&1; then
    NET_STATUS="Connected"
    CONNECTED=true
  else
    NET_STATUS="Disconnected"
    CONNECTED=false
  fi

  NET_CHOICE=$(whiptail --backtitle "$BACKTITLE" --title "Network Configuration" --menu "Interface: $NET_IFACE\nStatus: $NET_STATUS\n\nSelect network setup:" 16 65 2 \
    "1" "DHCP (Automatic - Recommended)" "2" "Static IP (Datacenter / Manual)" 3>&1 1>&2 2>&3)

  if [ -z "$NET_CHOICE" ]; then
    clear
    exit 1
  fi

  if [ "$NET_CHOICE" == "2" ]; then
    STATIC_IP=$(whiptail --backtitle "$BACKTITLE" --title "Static IP Setup" --inputbox "Enter IP Address with CIDR (e.g., 192.168.1.50/24):" 10 60 3>&1 1>&2 2>&3)
    STATIC_GW=$(whiptail --backtitle "$BACKTITLE" --title "Static IP Setup" --inputbox "Enter Default Gateway (e.g., 192.168.1.1):" 10 60 3>&1 1>&2 2>&3)
    STATIC_DNS=$(whiptail --backtitle "$BACKTITLE" --title "Static IP Setup" --inputbox "Enter DNS Server:" 10 60 "1.1.1.1" 3>&1 1>&2 2>&3)

    ip addr flush dev "$NET_IFACE"
    ip addr add "$STATIC_IP" dev "$NET_IFACE"
    ip route add default via "$STATIC_GW"
    echo "nameserver $STATIC_DNS" >/etc/resolv.conf
    sleep 2
    if ping -c 1 -W 3 archlinux.org >/dev/null 2>&1; then break; else continue; fi
  else
    if [ "$CONNECTED" = true ]; then break; else
      nmtui
      continue
    fi
  fi
done

# --- 3. Disk & Filesystem Selection ---
DRIVE_OPTIONS=()
while read -r name size model; do DRIVE_OPTIONS+=("$name" "$model ($size)"); done < <(lsblk -d -p -n -l -o NAME,SIZE,MODEL | grep -v "loop" | grep -v "rom")
TARGET_DRIVE=$(whiptail --backtitle "$BACKTITLE" --title "Target Drive" --menu "Choose the drive to install ZypherOS on:" 15 65 5 "${DRIVE_OPTIONS[@]}" 3>&1 1>&2 2>&3)
if [ -z "$TARGET_DRIVE" ]; then
  clear
  exit 1
fi

FS_CHOICE=$(whiptail --backtitle "$BACKTITLE" --title "Filesystem Selection" --menu "Choose your root filesystem format:" 15 65 3 \
  "btrfs" "BTRFS (Recommended - Enables Snapper Rollbacks)" \
  "ext4" "Ext4 (Traditional, Rock Solid, No snapshots)" \
  "xfs" "XFS (High Performance, No Snapshots)" 3>&1 1>&2 2>&3)
if [ -z "$FS_CHOICE" ]; then
  clear
  exit 1
fi

if whiptail --backtitle "$BACKTITLE" --title "Full Disk Encryption" --yesno "Would you like to encrypt your root partition with LUKS2?\n\n(Requires entering a password on every boot)" 10 60; then
  ENCRYPT_CHOICE="true"
  while true; do
    LUKS_PASS=$(whiptail --backtitle "$BACKTITLE" --title "LUKS Encryption" --passwordbox "Enter the encryption password:" 10 60 3>&1 1>&2 2>&3)
    LUKS_CONF=$(whiptail --backtitle "$BACKTITLE" --title "LUKS Encryption" --passwordbox "Confirm encryption password:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$LUKS_PASS" ]; then
      whiptail --msgbox "Password cannot be empty." 8 40
      continue
    fi
    if [ "$LUKS_PASS" != "$LUKS_CONF" ]; then
      whiptail --msgbox "Passwords do not match." 8 40
      continue
    fi
    break
  done
else
  ENCRYPT_CHOICE="false"
fi

# Unified Memory Management Menu
MEM_CHOICE=$(whiptail --backtitle "$BACKTITLE" --title "Memory Management" --menu "Select your Swap / ZRAM configuration:\n(ZRAM is highly recommended unless you specifically need Hibernation)" 16 65 4 \
  "1" "ZRAM - 50% of RAM (Recommended)" \
  "2" "ZRAM - 100% of RAM (Heavy Compiling)" \
  "3" "Physical Swap Partition (Enables Hibernation)" \
  "4" "None (Not recommended)" 3>&1 1>&2 2>&3)

if [ "$MEM_CHOICE" == "3" ]; then
  SWAP_CHOICE=$(whiptail --backtitle "$BACKTITLE" --title "Physical Swap" --inputbox "Enter Swap Partition size in GB (e.g., 16):" 10 60 "16" 3>&1 1>&2 2>&3)
  if [ -z "$SWAP_CHOICE" ] || ! [[ "$SWAP_CHOICE" =~ ^[0-9]+$ ]]; then SWAP_CHOICE="16"; fi
  ZRAM_SIZE="none"
else
  SWAP_CHOICE="0"
  case $MEM_CHOICE in
  1) ZRAM_SIZE="ram / 2" ;;
  2) ZRAM_SIZE="ram" ;;
  4) ZRAM_SIZE="none" ;;
  *) ZRAM_SIZE="ram / 2" ;;
  esac
fi

PARTITION_METHOD=$(whiptail --backtitle "$BACKTITLE" --title "Partitioning Method" --menu "How would you like to partition $TARGET_DRIVE?" 15 65 2 \
  "1" "Auto-Partition (Wipe entire drive - Recommended)" \
  "2" "Manual Partition (Custom layout via cfdisk)" 3>&1 1>&2 2>&3)

if [ "$PARTITION_METHOD" == "2" ]; then
  whiptail --backtitle "$BACKTITLE" --title "Manual Partitioning" --msgbox "You chose Manual.\n\nPlease create:\n1. EFI System Partition\n2. Swap Partition (Optional)\n3. Root Partition" 12 60
  cfdisk "$TARGET_DRIVE"
  partprobe "$TARGET_DRIVE"
  udevadm settle
  sleep 2
  PARTITIONS=()
  while read -r name size; do PARTITIONS+=("$name" "$size"); done < <(lsblk -r -n -p -o NAME,SIZE "$TARGET_DRIVE" | grep -v "^${TARGET_DRIVE} ")

  EFI_PART=$(whiptail --backtitle "$BACKTITLE" --title "Assignment" --menu "Select your EFI (Boot) Partition:" 15 65 6 "${PARTITIONS[@]}" 3>&1 1>&2 2>&3)
  ROOT_PART=$(whiptail --backtitle "$BACKTITLE" --title "Assignment" --menu "Select your Root (/) Partition:" 15 65 6 "${PARTITIONS[@]}" 3>&1 1>&2 2>&3)

  if [ "$SWAP_CHOICE" -gt 0 ]; then
    SWAP_PART=$(whiptail --backtitle "$BACKTITLE" --title "Assignment" --menu "Select your Physical Swap Partition:" 15 65 6 "${PARTITIONS[@]}" 3>&1 1>&2 2>&3)
  fi
fi

# --- 4. System Preferences ---
setup_timezone
setup_user_account

while true; do
  HOSTNAME=$(whiptail --backtitle "$BACKTITLE" --title "Hostname" --inputbox "Enter the system hostname:" 10 60 "zypheros" 3>&1 1>&2 2>&3)
  if [[ "$HOSTNAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] || [[ "$HOSTNAME" =~ ^[a-z0-9]$ ]]; then break; fi
done

if whiptail --backtitle "$BACKTITLE" --title "Remote Access" --yesno "Enable the SSH Server (sshd) on boot?" 10 60; then ENABLE_SSH="true"; else ENABLE_SSH="false"; fi

# Smart Hardware Detection
CPU_VENDOR=$(grep vendor_id /proc/cpuinfo | head -n 1 | awk '{print $3}')
if [ "$CPU_VENDOR" == "AuthenticAMD" ]; then
  UCODE_PKG="amd-ucode"
  UCODE_IMG="amd-ucode.img"
elif [ "$CPU_VENDOR" == "GenuineIntel" ]; then
  UCODE_PKG="intel-ucode"
  UCODE_IMG="intel-ucode.img"
else
  UCODE_PKG=""
  UCODE_IMG=""
fi

# THE FIX: Added || true so grep doesn't crash the script when run inside a VM
GPU_VENDOR=$(lspci -vnn | grep -iE 'VGA|3D' | grep -iE 'NVIDIA|AMD|Intel' | head -n 1 || true)
if echo "$GPU_VENDOR" | grep -iq "NVIDIA"; then
  DEFAULT="2"
elif echo "$GPU_VENDOR" | grep -iq "AMD"; then
  DEFAULT="1"
elif echo "$GPU_VENDOR" | grep -iq "Intel"; then
  DEFAULT="3"
else DEFAULT="4"; fi

GPU_CHOICE=$(whiptail --backtitle "$BACKTITLE" --title "Graphics" --menu "Verify graphics drivers:" 15 65 4 "1" "AMD" "2" "NVIDIA" "3" "Intel" "4" "Virtual Machine" --default-item "$DEFAULT" 3>&1 1>&2 2>&3)
case $GPU_CHOICE in
1) GPU_PKG="mesa xf86-video-amdgpu vulkan-radeon" ;;
2) GPU_PKG="nvidia nvidia-utils" ;;
3) GPU_PKG="mesa xf86-video-intel vulkan-intel" ;;
4) GPU_PKG="mesa" ;;
esac

KERNEL_CHOICE=$(whiptail --backtitle "$BACKTITLE" --title "Primary Kernel" --menu "Select your primary Linux kernel:\n(The LTS kernel will automatically be installed as a failsafe boot option)" 15 65 2 \
  "1" "Mainline (Latest features and hardware support)" \
  "2" "Zen (Tuned for desktop responsiveness and gaming)" 3>&1 1>&2 2>&3)

case $KERNEL_CHOICE in
1)
  KERNEL_PKG="linux linux-headers"
  KERNEL_NAME="linux"
  ;;
2)
  KERNEL_PKG="linux-zen linux-zen-headers"
  KERNEL_NAME="linux-zen"
  ;;
*)
  KERNEL_PKG="linux linux-headers"
  KERNEL_NAME="linux"
  ;;
esac

if ! whiptail --backtitle "$BACKTITLE" --title "WARNING" --yesno "READY TO INSTALL.\n\nAre you absolutely sure you want to proceed?" 10 60; then
  clear
  exit 1
fi

# --- 6. Execution: Formatting & Deployment ---
clear
LOG_FILE="/tmp/zypheros-install.log"
>"$LOG_FILE" # Clear any previous logs

{
  echo 5
  echo "XXX"
  echo "Preparing drives and clearing signatures..."
  echo "XXX"

  if [ "$PARTITION_METHOD" == "1" ]; then
    sgdisk -Z "$TARGET_DRIVE" >>"$LOG_FILE" 2>&1
    sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS_BOOT" "$TARGET_DRIVE" >>"$LOG_FILE" 2>&1
    sgdisk -n 2:0:+1024M -t 2:ef00 -c 2:"EFI" "$TARGET_DRIVE" >>"$LOG_FILE" 2>&1

    if [ "$SWAP_CHOICE" -gt 0 ]; then
      sgdisk -n 3:0:+${SWAP_CHOICE}G -t 3:8200 -c 3:"SWAP" "$TARGET_DRIVE" >>"$LOG_FILE" 2>&1
      sgdisk -n 4:0:0 -t 4:8300 -c 4:"ROOT" "$TARGET_DRIVE" >>"$LOG_FILE" 2>&1
    else
      sgdisk -n 3:0:0 -t 3:8300 -c 3:"ROOT" "$TARGET_DRIVE" >>"$LOG_FILE" 2>&1
    fi

    partprobe "$TARGET_DRIVE" >>"$LOG_FILE" 2>&1
    udevadm settle
    sleep 2
    if [[ "$TARGET_DRIVE" == *"nvme"* ]] || [[ "$TARGET_DRIVE" == *"mmcblk"* ]]; then
      EFI_PART="${TARGET_DRIVE}p2"
      if [ "$SWAP_CHOICE" -gt 0 ]; then
        SWAP_PART="${TARGET_DRIVE}p3"
        ROOT_PART="${TARGET_DRIVE}p4"
      else ROOT_PART="${TARGET_DRIVE}p3"; fi
    else
      EFI_PART="${TARGET_DRIVE}2"
      if [ "$SWAP_CHOICE" -gt 0 ]; then
        SWAP_PART="${TARGET_DRIVE}3"
        ROOT_PART="${TARGET_DRIVE}4"
      else ROOT_PART="${TARGET_DRIVE}3"; fi
    fi
  fi

  # Scrub old filesystem signatures (Ghost LUKS/Ext4 headers)
  wipefs -af "$EFI_PART" >>"$LOG_FILE" 2>&1 || true
  if [ "$SWAP_CHOICE" -gt 0 ] && [ -n "$SWAP_PART" ]; then wipefs -af "$SWAP_PART" >>"$LOG_FILE" 2>&1 || true; fi
  wipefs -af "$ROOT_PART" >>"$LOG_FILE" 2>&1 || true

  echo 15
  echo "XXX"
  echo "Formatting filesystems ($FS_CHOICE)..."
  echo "XXX"

  if [ "$SWAP_CHOICE" -gt 0 ] && [ -n "$SWAP_PART" ]; then
    mkswap "$SWAP_PART" >>"$LOG_FILE" 2>&1
    swapon "$SWAP_PART" >>"$LOG_FILE" 2>&1
  fi

  mkfs.vfat -F32 "$EFI_PART" >>"$LOG_FILE" 2>&1

  if [ "$ENCRYPT_CHOICE" == "true" ]; then
    echo 20
    echo "XXX"
    echo "Securing drive with LUKS2 Encryption..."
    echo "XXX"
    echo -n "$LUKS_PASS" | cryptsetup -q luksFormat "$ROOT_PART" - >>"$LOG_FILE" 2>&1
    echo -n "$LUKS_PASS" | cryptsetup open "$ROOT_PART" cryptroot - >>"$LOG_FILE" 2>&1
    ACTUAL_ROOT="/dev/mapper/cryptroot"
    CRYPT_PKG="cryptsetup"
  else
    ACTUAL_ROOT="$ROOT_PART"
    CRYPT_PKG=""
  fi

  if [ "$FS_CHOICE" == "btrfs" ]; then
    mkfs.btrfs -f "$ACTUAL_ROOT" >>"$LOG_FILE" 2>&1
    mount "$ACTUAL_ROOT" /mnt
    btrfs subvolume create /mnt/@ >>"$LOG_FILE" 2>&1
    btrfs subvolume create /mnt/@home >>"$LOG_FILE" 2>&1
    btrfs subvolume create /mnt/@log >>"$LOG_FILE" 2>&1
    btrfs subvolume create /mnt/@pkg >>"$LOG_FILE" 2>&1
    umount /mnt
    MNT_OPTS="noatime,compress=zstd,space_cache=v2"
    mount -o "$MNT_OPTS,subvol=@" "$ACTUAL_ROOT" /mnt
    mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,boot}
    mount -o "$MNT_OPTS,subvol=@home" "$ACTUAL_ROOT" /mnt/home
    mount -o "$MNT_OPTS,subvol=@log" "$ACTUAL_ROOT" /mnt/var/log
    mount -o "$MNT_OPTS,subvol=@pkg" "$ACTUAL_ROOT" /mnt/var/cache/pacman/pkg
    FS_PKG="btrfs-progs snapper"
  elif [ "$FS_CHOICE" == "ext4" ]; then
    mkfs.ext4 -F "$ACTUAL_ROOT" >>"$LOG_FILE" 2>&1
    mount "$ACTUAL_ROOT" /mnt
    mkdir -p /mnt/boot
    FS_PKG="e2fsprogs"
  elif [ "$FS_CHOICE" == "xfs" ]; then
    mkfs.xfs -f "$ACTUAL_ROOT" >>"$LOG_FILE" 2>&1
    mount "$ACTUAL_ROOT" /mnt
    mkdir -p /mnt/boot
    FS_PKG="xfsprogs"
  fi

  mount "$EFI_PART" /mnt/boot

  echo 30
  echo "XXX"
  echo "Optimizing download mirrors..."
  echo "XXX"
  reflector --country US --latest 5 --sort rate --save /etc/pacman.d/mirrorlist >>"$LOG_FILE" 2>&1
  pacman -Sy archlinux-keyring --noconfirm >>"$LOG_FILE" 2>&1
  pacman -Syy --noconfirm >>"$LOG_FILE" 2>&1

  mkdir -p /mnt/etc
  echo "KEYMAP=us" >/mnt/etc/vconsole.conf

  # We break the massive payload into logical chunks so the progress bar actually moves.
  CORE_PKGS=(
    base base-devel $KERNEL_PKG linux-lts linux-lts-headers linux-firmware sudo networkmanager
    $FS_PKG $CRYPT_PKG $GPU_PKG $UCODE_PKG limine efibootmgr mtools zram-generator openssh reflector
  )

  DESKTOP_PKGS=(
    plasma-meta sddm pipewire wireplumber pipewire-pulse bluez bluez-utils bluedevil
    dolphin ark spectacle kate gwenview okular partitionmanager
  )

  TOOL_PKGS=(
    git neovim zoxide thefuck eza bat btop nano fzf yazi fish
    lazygit ripgrep fd unzip wget xclip wl-clipboard firefox
    libreoffice-fresh pika-backup thunderbird ttf-meslo-nerd noto-fonts noto-fonts-emoji
  )

  echo 40
  echo "XXX"
  echo "Installing Core Linux System & Drivers..."
  echo "XXX"
  pacstrap -K /mnt "${CORE_PKGS[@]}" >>"$LOG_FILE" 2>&1

  # Generate fstab immediately after the core filesystem packages are installed
  genfstab -U /mnt >>/mnt/etc/fstab

  echo 48
  echo "XXX"
  echo "Downloading KDE Plasma & Wayland Compositor..."
  echo "XXX"
  pacstrap -K /mnt "${DESKTOP_PKGS[@]}" >>"$LOG_FILE" 2>&1

  echo 58
  echo "XXX"
  echo "Installing ZypherOS Developer Tools..."
  echo "XXX"
  pacstrap -K /mnt "${TOOL_PKGS[@]}" >>"$LOG_FILE" 2>&1

  if [ "$NET_CHOICE" == "2" ] && [ -n "$STATIC_IP" ]; then
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

  # Prepare initramfs HOOKS logic for chroot
  HOOK_STR="base udev autodetect modconf kms keyboard keymap consolefont block"
  if [ "$ENCRYPT_CHOICE" == "true" ]; then HOOK_STR="$HOOK_STR encrypt"; fi
  HOOK_STR="$HOOK_STR filesystems"
  if [ "$SWAP_CHOICE" -gt 0 ]; then HOOK_STR="$HOOK_STR resume"; fi
  HOOK_STR="$HOOK_STR fsck"

  echo 65
  echo "XXX"
  echo "Configuring boot parameters and user accounts..."
  echo "XXX"

  # Generating internal configuration script
  cat <<EOF >/mnt/zypher_chroot.sh
#!/bin/bash
set -e # CRITICAL FIX: Ensure inner chroot environment dies on failures

echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/$SELECTED_TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen >> /var/log/zypheros-install.log 2>&1
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "Rebuilding Initramfs with new Storage/Encryption Hooks..." >> /var/log/zypheros-install.log
sed -i "s/^HOOKS=.*/HOOKS=($HOOK_STR)/" /etc/mkinitcpio.conf
mkinitcpio -P >> /var/log/zypheros-install.log 2>&1

if [ "$ZRAM_SIZE" != "none" ]; then
    mkdir -p /etc/systemd/
    cat <<ZRAMEOF > /etc/systemd/zram-generator.conf
[zram0]
zram-size = $ZRAM_SIZE
ZRAMEOF
fi

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
# CRITICAL FIX: Removed the rogue backslash on $arch
Server = https://repo.zyphersystems.com/zypheros/$arch
REPOEOF
fi

pacman -Sy >> /var/log/zypheros-install.log 2>&1
pacman -S --noconfirm --overwrite="*" zypheros-release zypheros-desktop-env >> /var/log/zypheros-install.log 2>&1

useradd -m -c "$FULL_NAME" -G wheel -s /usr/bin/fish $USERNAME
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

sudo -u "$USERNAME" nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || true

useradd -m -s /bin/bash builduser
echo 'builduser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builduser
chmod 440 /etc/sudoers.d/builduser

sudo -u builduser git clone https://aur.archlinux.org/yay-bin.git /home/builduser/yay-bin >> /var/log/zypheros-install.log 2>&1
sudo -u builduser bash -c "cd /home/builduser/yay-bin && makepkg -si --noconfirm" >> /var/log/zypheros-install.log 2>&1

rm /etc/sudoers.d/builduser
userdel -r builduser

systemctl enable NetworkManager >> /var/log/zypheros-install.log 2>&1
systemctl enable sddm >> /var/log/zypheros-install.log 2>&1
systemctl enable bluetooth >> /var/log/zypheros-install.log 2>&1
if [ "$ENABLE_SSH" == "true" ]; then systemctl enable sshd >> /var/log/zypheros-install.log 2>&1; fi

if [ "$FS_CHOICE" == "btrfs" ]; then
    umount /.snapshots 2>/dev/null || true
    rm -rf /.snapshots
    snapper -c root create-config / >> /var/log/zypheros-install.log 2>&1
    btrfs subvolume delete /.snapshots 2>/dev/null || true
    mkdir /.snapshots
    mount -a
    snapper -c home create-config /home >> /var/log/zypheros-install.log 2>&1
    chmod 750 /.snapshots
    chmod 750 /home/.snapshots
fi

mkdir -p /boot/EFI/BOOT
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/
cp /usr/share/limine/limine-bios.sys /boot/

LIMINE_CMD=""
if [ "$ENCRYPT_CHOICE" == "true" ]; then
    PHYS_UUID=\$(blkid -s UUID -o value $ROOT_PART)
    LIMINE_CMD="cryptdevice=UUID=\${PHYS_UUID}:cryptroot root=/dev/mapper/cryptroot"
else
    LIMINE_CMD="root=UUID=\$(blkid -s UUID -o value $ROOT_PART)"
fi

if [ "$FS_CHOICE" == "btrfs" ]; then LIMINE_CMD="\$LIMINE_CMD rootflags=subvol=@"; fi
if [ "$SWAP_CHOICE" -gt 0 ]; then
    SWAP_UUID=\$(blkid -s UUID -o value $SWAP_PART)
    LIMINE_CMD="\$LIMINE_CMD resume=UUID=\${SWAP_UUID}"
fi
LIMINE_CMD="\$LIMINE_CMD rw"

echo "timeout: 5" > /boot/limine.conf
echo "" >> /boot/limine.conf
echo "/ZypherOS ($KERNEL_NAME)" >> /boot/limine.conf
echo "    protocol: linux" >> /boot/limine.conf
echo "    kernel_path: boot():/vmlinuz-$KERNEL_NAME" >> /boot/limine.conf
if [ -n "$UCODE_IMG" ]; then echo "    module_path: boot():/$UCODE_IMG" >> /boot/limine.conf; fi
echo "    module_path: boot():/initramfs-$KERNEL_NAME.img" >> /boot/limine.conf
echo "    cmdline: \$LIMINE_CMD" >> /boot/limine.conf

echo "" >> /boot/limine.conf
echo "/ZypherOS Failsafe (linux-lts)" >> /boot/limine.conf
echo "    protocol: linux" >> /boot/limine.conf
echo "    kernel_path: boot():/vmlinuz-linux-lts" >> /boot/limine.conf
if [ -n "$UCODE_IMG" ]; then echo "    module_path: boot():/$UCODE_IMG" >> /boot/limine.conf; fi
echo "    module_path: boot():/initramfs-linux-lts.img" >> /boot/limine.conf
echo "    cmdline: \$LIMINE_CMD" >> /boot/limine.conf

if [ -d "/sys/firmware/efi" ]; then
    efibootmgr --create --disk "$TARGET_DRIVE" --part 2 --loader '\EFI\BOOT\BOOTX64.EFI' --label "ZypherOS" --unicode >> /var/log/zypheros-install.log 2>&1
else
    limine bios-install "$TARGET_DRIVE" >> /var/log/zypheros-install.log 2>&1
fi
EOF

  chmod +x /mnt/zypher_chroot.sh
  arch-chroot /mnt /zypher_chroot.sh >>"$LOG_FILE" 2>&1

  echo 90
  echo "XXX"
  echo "Securing user passwords..."
  echo "XXX"
  echo "$USERNAME:$PASSWORD" | arch-chroot /mnt chpasswd >>"$LOG_FILE" 2>&1
  echo "root:$PASSWORD" | arch-chroot /mnt chpasswd >>"$LOG_FILE" 2>&1

  echo 95
  echo "XXX"
  echo "Cleaning up deployment environment..."
  echo "XXX"
  rm /mnt/zypher_chroot.sh
  # Copy the installation log into the new system so the user can review it later
  cp "$LOG_FILE" /mnt/var/log/zypheros-install.log
  umount -R /mnt
  swapoff -a 2>/dev/null || true
  cryptsetup close cryptroot 2>/dev/null || true

  echo 100
  echo "XXX"
  echo "Deployment Complete!"
  echo "XXX"
  sleep 1

} | whiptail --backtitle "$BACKTITLE" --title "System Deployment" --gauge "Initializing..." 8 70 0

whiptail --backtitle "$BACKTITLE" --title "Installation Complete" --msgbox "ZypherOS has been successfully deployed to $TARGET_DRIVE!\n\nAn installation log has been saved to /var/log/zypheros-install.log on the new system.\n\nPress Enter to exit the installer and reboot." 12 60
clear
echo "Rebooting in 5 seconds..."
sleep 5
reboot
