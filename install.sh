#!/bin/bash
set -e

# --- Configuration ---
REPO_URL="https://github.com/zypher-systems/Zypher_OS.git"
BRANCH="main"
TEMP_DIR="/tmp/zypheros-installer"

# --- Pre-flight Checks ---
if [ "$EUID" -eq 0 ]; then
    echo "❌ Error: Please do NOT run this script as root."
    echo "   Run it as your regular user. The script will ask for sudo password when needed."
    exit 1
fi

echo "🚀 Starting ZypherOS Network Installer..."

# --- Bootstrap Git ---
if ! command -v git &> /dev/null; then
    echo "📦 Installing Git for bootstrapping..."
    sudo pacman -S --noconfirm git
fi

# --- Clone the Repo ---
echo "⬇️  Downloading installer scripts..."
rm -rf "$TEMP_DIR"
git clone -b "$BRANCH" "$REPO_URL" "$TEMP_DIR" --quiet

# --- Execute Subscripts ---
echo "⚙️  Executing modules..."
cd "$TEMP_DIR/subscripts"

# Make executable
chmod +x *.sh

# Run in order
./01-repos.sh
./02-packages.sh
./03-flatpak.sh
./04-aur.sh
./05-ghostty.sh
./06-fish.sh
./07-fastfetch.sh
./08-plasma.sh
./09-branding.sh

# --- Cleanup ---
echo "🧹 Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo "✅ ZypherOS Installation Complete! Please reboot."