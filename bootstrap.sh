#!/bin/bash
set -e 

echo "========================================="
echo "   ZypherOS Installer - Alpha Release    "
echo "========================================="

# --- 1. The Interview ---
echo "Available Drives:"
lsblk -d -p -n -l -o NAME,SIZE,MODEL | grep -v "loop"
echo ""
read -p "Enter target drive (e.g., /dev/sda or /dev/nvme0n1): " TARGET_DRIVE < /dev/tty
read -p "Enter desired username: " USERNAME < /dev/tty
read -sp "Enter password for $USERNAME (and Root): " PASSWORD < /dev/tty
echo ""
read -p "Enter system hostname: " HOSTNAME < /dev/tty

echo ""
echo "Select Video Driver:"
echo "1) AMD (Open Source)"
echo "2) NVIDIA (Proprietary)"
echo "3) Intel"
echo "4) Virtual Machine (QEMU/VMware)"
read -p "Selection (1-4): " GPU_CHOICE < /dev/tty

case $GPU_CHOICE in
    1) GPU_PKG="mesa xf86-video-amdgpu vulkan-radeon amd-ucode" ;;
    2) GPU_PKG="nvidia nvidia-utils" ;;
    3) GPU_PKG="mesa xf86-video-intel vulkan-intel intel-ucode" ;;
    4) GPU_PKG="mesa" ;;
    *) echo "Invalid choice. Exiting."; exit 1 ;;
esac

echo ""
echo "WARNING: This will COMPLETELY WIPE $TARGET_DRIVE."
read -p "Are you sure you want to continue? (Type YES to proceed): " CONFIRM < /dev/tty
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

if [[ "$TARGET_DRIVE" == *"nvme"* ]]; then
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

# Mount the EFI partition (Limine uses this as the general boot directory)
mount "$EFI_PART" /mnt/boot

# --- 4. The Pacstrap ---
echo "Updating Arch Keyring to prevent package installation failures..."
pacman -Sy archlinux-keyring --noconfirm

echo "Installing base system and ZypherOS dependencies..."
pacstrap -K /mnt base base-devel linux linux-firmware btrfs-progs sudo networkmanager neovim git plasma sddm limine snapper efibootmgr mtools $GPU_PKG

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- 5. The Chroot Handoff ---
echo "Generating internal configuration script..."

cat <<EOF > /mnt/zypher_chroot.sh
#!/bin/bash
# Set Hostname and Timezone
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Create User
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Enable Services
systemctl enable NetworkManager
systemctl enable sddm

# Initialize Snapper (Nested matching your layout)
snapper -c root create-config /
snapper -c home create-config /home
chmod 750 /.snapshots
chmod 750 /home/.snapshots

# Write the custom Limine Config securely
echo "timeout: 5" > /boot/limine.conf
echo "" >> /boot/limine.conf
echo ":ZypherOS" >> /boot/limine.conf
echo "    protocol: linux" >> /boot/limine.conf
echo "    kernel_path: boot():/vmlinuz-linux" >> /boot/limine.conf
echo "    module_path: boot():/initramfs-linux.img" >> /boot/limine.conf
echo "    cmdline: root=UUID=\$(blkid -s UUID -o value $ROOT_PART) rootflags=subvol=@ rw" >> /boot/limine.conf

# Detect Firmware and Install Bootloader Accordingly
if [ -d "/sys/firmware/efi" ]; then
    echo "UEFI detected. Registering ZypherOS with efibootmgr..."
    mkdir -p /boot/EFI/BOOT
    cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/
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
echo " You can now type 'reboot'."
echo "========================================="
