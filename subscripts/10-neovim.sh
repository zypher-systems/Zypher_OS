#!/bin/bash
echo "📝 [10/10] Configuring Neovim & LazyVim..."

NVIM_CONFIG_DIR="$HOME/.config/nvim"
# Replace this with your actual GitHub repo URL!
MY_NVIM_REPO="https://github.com/zypher-systems/nvim-config.git"

# --- 1. Install Dependencies ---
echo "   Installing Neovim dependencies (ripgrep, fd, lazygit, clipboard)..."
sudo pacman -S --noconfirm --needed neovim ripgrep fd lazygit unzip wget base-devel xclip wl-clipboard

# --- 2. Setup Config ---
if [ -d "$NVIM_CONFIG_DIR" ]; then
  echo "   ⚠️  Neovim configuration already exists in ~/.config/nvim."
  echo "   Skipping clone to prevent overwriting your local files."
else
  echo "   Cloning custom LazyVim configuration..."

  # We use HTTPS here so the automated installer doesn't need an SSH key
  git clone "$MY_NVIM_REPO" "$NVIM_CONFIG_DIR"

  echo "   ✅ Custom LazyVim installed successfully."
fi

# --- 3. First Run (Optional but nice) ---
# This forces Neovim to download all its plugins silently in the background
# so it's instantly ready the first time you type 'nvim'
echo "   Bootstrapping plugins in the background..."
nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1

echo "✅ Neovim setup complete."
