#!/bin/bash
echo "📦 [1/9] Configuring Repositories..."

if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "   Enabling multilib..."
    sudo sed -i '/^\#\[multilib\]/,/^\#Include = \/etc\/pacman\.d\/mirrorlist/ s/^\#//' /etc/pacman.conf
    sudo pacman -Syu --noconfirm
else
    echo "   Multilib already active."
fi