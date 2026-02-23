#!/bin/bash
echo "📦 [4/10] Configuring AUR..."

# Install yay if missing
if ! command -v yay &>/dev/null; then
  echo "   Installing yay..."
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay && makepkg -si --noconfirm
  cd ~ && rm -rf /tmp/yay
fi

echo "   Installing AUR Packages..."
yay -S --noconfirm visual-studio-code-bin limine-snapper-sync-git
