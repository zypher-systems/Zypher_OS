#!/bin/bash
echo "🎨 [9/10] Applying ZypherOS Branding..."

# --- Variables ---
SOURCE_DIR="../images"
DEST_DIR="$HOME/.local/share/zypher/branding"
WALLPAPER="zypher_os_wallpaper.png"
ICON="zypher_os_launcher_icon.png"

# The system's default widget location
SYSTEM_WIDGET="/usr/share/plasma/plasmoids/org.kde.plasma.kickoff"
# Where we will create our local override
LOCAL_WIDGET="$HOME/.local/share/plasma/plasmoids/org.kde.plasma.kickoff"

# --- 1. Setup Storage ---
echo "   Creating permanent asset storage..."
mkdir -p "$DEST_DIR"
cp "$SOURCE_DIR/$WALLPAPER" "$DEST_DIR/"
cp "$SOURCE_DIR/$ICON" "$DEST_DIR/"

# --- 2. Apply Wallpaper ---
echo "   Setting Wallpaper..."
plasma-apply-wallpaperimage "$DEST_DIR/$WALLPAPER"

# --- 3. The "Developer Override" Icon Fix ---
echo "   Creating Local Widget Override..."

if [ -d "$SYSTEM_WIDGET" ]; then
  # 1. Copy the system widget to the user's local directory
  mkdir -p "$(dirname "$LOCAL_WIDGET")"
  cp -r "$SYSTEM_WIDGET" "$LOCAL_WIDGET"

  # 2. Find the metadata file (It's usually metadata.json or metadata.desktop)
  if [ -f "$LOCAL_WIDGET/metadata.json" ]; then
    # Use sed to replace the "Icon": "start-here-kde" line with our path
    # We look for "Icon": "something", and replace it.
    sed -i 's|"Icon": ".*"|"Icon": "'"$DEST_DIR/$ICON"'"|' "$LOCAL_WIDGET/metadata.json"
    echo "   ✅ Metadata.json patched."

  elif [ -f "$LOCAL_WIDGET/metadata.desktop" ]; then
    # Older format fallback
    sed -i "s|^Icon=.*|Icon=$DEST_DIR/$ICON|" "$LOCAL_WIDGET/metadata.desktop"
    echo "   ✅ Metadata.desktop patched."
  else
    echo "   ⚠️  Could not find metadata file in widget."
  fi

  # 3. Reload Plasma to pick up the new "plugin"
  echo "   Restarting Plasma to load override..."

  if systemctl --user list-units | grep -q "plasma-plasmashell.service"; then
    systemctl --user restart plasma-plasmashell
  else
    # Fallback for non-systemd (VMs/Containers)
    kquitapp6 plasmashell || true
    # Wait for it to die
    while pgrep -u "$USER" -x plasmashell >/dev/null; do sleep 1; done
    nohup kstart6 plasmashell >/dev/null 2>&1 &
  fi

else
  echo "   ⚠️  System widget not found at $SYSTEM_WIDGET. Is plasma-desktop installed?"
fi

echo "✅ Branding Applied."
