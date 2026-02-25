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
# Read all valid drives into an array, ignoring loopbacks and cdroms
mapfile -t DRIVE_ARRAY < <(lsblk -d -p -n -l -o NAME,SIZE,MODEL | grep -v "loop" | grep -v "rom")

# Print the numbered list dynamically
for i in "${!DRIVE_ARRAY[@]}"; do
  echo "  $((i + 1))) ${DRIVE_ARRAY[$i]}"
done
echo ""

# Trap the user until they enter a valid number
while true; do
  read -p "Select the number of the target drive (1-${#DRIVE_ARRAY[@]}): " DRIVE_NUM </dev/tty
  if [[ "$DRIVE_NUM" =~ ^[0-9]+$ ]] && [ "$DRIVE_NUM" -ge 1 ] && [ "$DRIVE_NUM" -le "${#DRIVE_ARRAY[@]}" ]; then
    # Extract just the device path (e.g., /dev/sda) from the selection
    TARGET_DRIVE=$(echo "${DRIVE_ARRAY[$((DRIVE_NUM - 1))]}" | awk '{print $1}')
    echo "Selected target: $TARGET_DRIVE"
    break
  else
    echo "Invalid selection. Please pick a number from the list."
  fi
done

echo ""
read -p "Enter desired username: " USERNAME </dev/tty

# Trap the user until passwords match
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

# --- 2. Universal Partitioning (Supports UEFI & SeaBIOS) ---
echo "Wiping and partitioning $TARGET_DRIVE..."
sgdisk -Z "$TARGET_DRIVE"

# Part 1: 1MB BIOS Boot Partition (Required for Limine on Legacy BIOS with GPT)
sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS_BOOT" "$TARGET_DRIVE"
# Part 2: 1GB EFI System Partition (Required for UEFI)
sgdisk -n 2:0:+1024M -t 2:ef00 -c 2:"EFI" "$TARGET_DRIVE"
# Part 3: Remaining space for BTRFS Root
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

# Mount the EFI partition
mount "$EFI_PART" /mnt/boot

# --- 3.5. Configure Repositories (ZypherOS Sync) ---
echo "Configuring package repositories for synchronized install..."

# 1. Enable Multilib
sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman\.d\/mirrorlist/ s/^#//' /etc/pacman.conf

# 2. Set Local Mirror as Priority #1
if ! head -n 5 /etc/pacman.d/mirrorlist | grep -q "repo.zyphersystems.com"; then
  sed -i '1i Server = https://repo.zyphersystems.com/mirror/$repo/os/$arch\n' /etc/pacman.d/mirrorlist
fi

# 3. Add Custom Zypher_OS Repository
if ! grep -q "^\[zypheros\]" /etc/pacman.conf; then
  cat <<'EOF' >>/etc/pacman.conf

[zypheros]
SigLevel = Optional TrustAll
Server = https://repo.zyphersystems.com/zypheros/$arch
EOF
fi

# 4. Refresh Package Databases
echo "Synchronizing package databases with ZypherOS repos..."
pacman -Sy archlinux-keyring --noconfirm
pacman -Syy --noconfirm

# --- 4. The Pacstrap ---
echo "Preparing ZypherOS package lists..."

ZYPHER_PACKAGES=(
  # Base System & Hardware
  base base-devel linux linux-lts linux-firmware btrfs-progs sudo networkmanager
  $GPU_PKG

  # Bootloader & Snapshots
  limine snapper efibootmgr mtools

  # Desktop Environment & Audio/Bluetooth
  plasma sddm pipewire wireplumber pipewire-pulse bluez bluez-utils bluedevil

  # KDE Core Apps
  konsole dolphin ark spectacle kate gwenview okular partitionmanager

  # CLI Utilities & Core Tools
  git fastfetch fish neovim starship zoxide thefuck eza bat btop
  lazygit ripgrep fd unzip wget xclip wl-clipboard

  # Productivity & Creation Apps
  ghostty gimp blender inkscape libreoffice-fresh pika-backup
  obs-studio flatpak kdenlive thunderbird

  # Fonts
  ttf-meslo-nerd noto-fonts noto-fonts-emoji
)

echo "Installing base system and ZypherOS dependencies..."
pacstrap -K /mnt "${ZYPHER_PACKAGES[@]}"

echo "Generating fstab..."
genfstab -U /mnt >>/mnt/etc/fstab

# --- 5. The Chroot Handoff ---
echo "Generating internal configuration script..."

cat <<EOF >/mnt/zypher_chroot.sh
#!/bin/bash
# Set Hostname and Timezone
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Silence the mkinitcpio vconsole warning
echo "KEYMAP=us" > /etc/vconsole.conf

# Create User
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Enable Services
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable bluetooth

# Initialize Snapper
snapper -c root create-config /
snapper -c home create-config /home
chmod 750 /.snapshots
chmod 750 /home/.snapshots

# Configure Limine Bootloader
mkdir -p /boot/EFI/BOOT

# Copy both UEFI and BIOS Stage 3 payloads so the drive is fully hybrid
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/
cp /usr/share/limine/limine-bios.sys /boot/

# Write the custom Limine Config securely
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

# Detect Firmware and Install Bootloader Accordingly
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
  # Wait 1 second for a single keypress directly from the terminal
  if read -t 1 -n 1 -s </dev/tty; then
    CANCELED=true
    break
  fi
done

echo "" # Print a newline so the prompt doesn't overwrite the countdown

if [ "$CANCELED" = true ]; then
  echo "Auto-reboot canceled. You are still in the live environment."
  echo "Type 'reboot' when you are ready."
else
  echo "Rebooting now!"
  reboot
fi
