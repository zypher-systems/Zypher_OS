#!/bin/bash
echo "🎨 [5/10] Configuring Ghostty..."

mkdir -p "$HOME/.config/ghostty/themes"
GHOSTTY_CONFIG="$HOME/.config/ghostty/config"
CARBONFOX_THEME="$HOME/.config/ghostty/themes/carbonfox"

# Create Carbonfox Theme
cat >"$CARBONFOX_THEME" <<'EOF'
palette = 0=#282828
palette = 1=#ee5396
palette = 2=#25be6a
palette = 3=#08bdba
palette = 4=#78a9ff
palette = 5=#be95ff
palette = 6=#33b1ff
palette = 7=#dfdfe0
palette = 8=#484848
palette = 9=#f16da6
palette = 10=#46c880
palette = 11=#2dc7c4
palette = 12=#8cb6ff
palette = 13=#c8a5ff
palette = 14=#52bdff
palette = 15=#e4e4e5
background = 161616
foreground = f2f4f8
cursor-color = e4e4e5
selection-background = 2a2a2a
selection-foreground = f2f4f8
EOF

# Write Ghostty Config
if ! grep -q "shell-integration = fish" "$GHOSTTY_CONFIG" 2>/dev/null; then
  cat >>"$GHOSTTY_CONFIG" <<EOF
command = /usr/bin/fish
font-family = MesloLGS Nerd Font Mono
font-family-bold = MesloLGS Nerd Font Mono Bold
font-family-italic = MesloLGS Nerd Font Mono Italic
font-size = 14
background-opacity = 0.9
theme = carbonfox
shell-integration = fish
EOF
fi

