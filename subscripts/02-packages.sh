#!/bin/bash
echo "📦 [2/11] Installing Core Packages..."

PACKAGES=(
  # Core Tools
  base-devel
  git
  fastfetch
  fish
  neovim
  starship
  zoxide
  thefuck
  eza
  bat
  btop
  lazygit
  ripgrep
  fd
  unzip
  wget
  xclip
  wl-clipboard
  partitionmanager

  # Apps
  ghostty
  gwenview
  okular
  gimp
  blender
  inkscape
  libreoffice-fresh
  pika-backup
  obs-studio
  flatpak
  kdenlive
  thunderbird

  # Fonts
  ttf-meslo-nerd
  noto-fonts
)

sudo pacman -S --noconfirm --needed "${PACKAGES[@]}"
