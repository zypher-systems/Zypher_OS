#!/bin/bash
echo "⚙️  [8/11] Configuring KDE Plasma Settings..."

# --- 1. Enable NumLock on Login Screen (SDDM) ---
# This requires sudo because SDDM runs as a system user
echo "   Enabling NumLock for SDDM..."
if [ -d "/etc/sddm.conf.d" ]; then
  echo "[General]
Numlock=on" | sudo tee /etc/sddm.conf.d/numlock.conf >/dev/null
else
  # Fallback if directory doesn't exist (unlikely on Arch)
  sudo mkdir -p /etc/sddm.conf.d
  echo "[General]
Numlock=on" | sudo tee /etc/sddm.conf.d/numlock.conf >/dev/null
fi

# --- 2. Enable NumLock for User Session ---
# This sets the user preference file (~/.config/kcminputrc)
echo "   Enabling NumLock for Plasma Session..."
# "0" means ON in KDE config land
kwriteconfig6 --file kcminputrc --group Keyboard --key NumLock 0

echo "   ✅ NumLock Configured."

# ----------TEST CODE----------

# --- 3. Apply the Breeze Dark global theme to the current user (Headless Mode)
QT_QPA_PLATFORM=offscreen plasma-apply-lookandfeel -a org.kde.breezedark.desktop

# --- 4. Tell SDDM to use the standard Breeze theme
sudo mkdir -p /etc/sddm.conf.d
echo -e "[Theme]\nCurrent=breeze" | sudo tee /etc/sddm.conf.d/10-theme.conf

# Sync the user's new dark color scheme over to the SDDM background user
sudo mkdir -p /var/lib/sddm/.config
sudo cp ~/.config/kdeglobals /var/lib/sddm/.config/kdeglobals

# Fix the file permissions so the SDDM user can actually read it
sudo chown -R sddm:sddm /var/lib/sddm/.config

# ----------END TEST CODE----------
