#!/bin/bash
echo "⚙️  [8/9] Configuring KDE Plasma Settings..."

# --- 1. Enable NumLock on Login Screen (SDDM) ---
# This requires sudo because SDDM runs as a system user
echo "   Enabling NumLock for SDDM..."
if [ -d "/etc/sddm.conf.d" ]; then
    echo "[General]
Numlock=on" | sudo tee /etc/sddm.conf.d/numlock.conf > /dev/null
else
    # Fallback if directory doesn't exist (unlikely on Arch)
    sudo mkdir -p /etc/sddm.conf.d
    echo "[General]
Numlock=on" | sudo tee /etc/sddm.conf.d/numlock.conf > /dev/null
fi

# --- 2. Enable NumLock for User Session ---
# This sets the user preference file (~/.config/kcminputrc)
echo "   Enabling NumLock for Plasma Session..."
# "0" means ON in KDE config land
kwriteconfig6 --file kcminputrc --group Keyboard --key NumLock 0

echo "   ✅ NumLock Configured."