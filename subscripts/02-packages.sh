#!/bin/bash
echo "📦 [2/9] Installing Core Packages..."

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

    # Fonts
    ttf-meslo-nerd
    noto-fonts
)

sudo pacman -S --noconfirm --needed "${PACKAGES[@]}"