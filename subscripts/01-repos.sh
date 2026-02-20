#!/bin/bash
echo "📦 [1/9] Configuring Repositories..."

# 1. Enable Multilib
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "   Enabling multilib..."
    # Fixed the truncated sed command to properly uncomment the section
    sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman\.d\/mirrorlist/ s/^#//' /etc/pacman.conf
else
    echo "   Multilib already active."
fi

# 2. Set Local Mirror as Priority #1
echo "   Setting local mirror priority..."
if ! head -n 5 /etc/pacman.d/mirrorlist | grep -q "repo.zyphersystems.com"; then
    sudo sed -i '1i Server = https://repo.zyphersystems.com/mirror/$repo/os/$arch\n' /etc/pacman.d/mirrorlist
else
    echo "   Local mirror already at the top."
fi

# 3. Add Custom Zypher_OS Repository
if ! grep -q "^\[zypheros\]" /etc/pacman.conf; then
    echo "   Injecting [zypheros] custom repository..."
    # Using 'tee -a' so sudo permissions apply correctly when appending to the file
    cat << 'EOF' | sudo tee -a /etc/pacman.conf > /dev/null

[zypheros]
SigLevel = Optional TrustAll
Server = https://repo.zyphersystems.com/zypheros/$arch
EOF
else
    echo "   [zypheros] repository already configured."
fi

# 4. Refresh Package Databases
echo "   Synchronizing package databases..."
sudo pacman -Syy --noconfirm
