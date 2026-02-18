#!/bin/bash
echo "📦 [3/9] Setting up Flatpaks..."

# 1. Setup Remotes (Allow failure if it already exists)
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true

FLATPAKS=(
    it.mijorus.gearlever
    com.github.tchx84.Flatseal
    com.google.Chrome
    com.discordapp.Discord
)

# 2. Install Loop (The Robust Version)
echo "   Installing applications..."

# Turn OFF 'Stop on Error' so a single Flatpak warning doesn't kill the whole OS install
set +e

for pkg in "${FLATPAKS[@]}"; do
    echo "   ⬇️  Installing $pkg..."
    # --assumeyes skips prompts, --noninteractive stops the "drunk terminal" characters
    flatpak install -y --noninteractive flathub "$pkg"
done

# Turn 'Stop on Error' back ON for the rest of the script
set -e

echo "   ✅ Flatpak setup complete."