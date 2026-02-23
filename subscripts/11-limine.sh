#!/bin/bash
echo "Configuring Limine Bootloader for ZypherOS..."

# 1. Dynamically find the Limine config file
if [ -f /boot/limine.conf ]; then
  CONF_PATH="/boot/limine.conf"
elif [ -f /boot/limine/limine.conf ]; then
  CONF_PATH="/boot/limine/limine.conf"
elif [ -f /efi/limine.conf ]; then
  CONF_PATH="/efi/limine.conf"
else
  echo "Error: Could not find limine.conf."
  exit 1
fi

# 2. Rename the main OS entry to "ZypherOS"
sudo sed -i '0,/^:[a-zA-Z0-9 _-]*/s//:ZypherOS/' "$CONF_PATH"
echo "Boot menu successfully branded as ZypherOS."

# 3. Inject the Snapper menu into the main Limine config
if ! grep -q "limine-snapper.conf" "$CONF_PATH"; then
  echo "" | sudo tee -a "$CONF_PATH"
  echo "# Include BTRFS Snapshots Menu" | sudo tee -a "$CONF_PATH"
  echo "remember: yes" | sudo tee -a "$CONF_PATH"
  echo "include: boot():/limine-snapper.conf" | sudo tee -a "$CONF_PATH"
  echo "Snapper snapshot menu linked to Limine."
fi

# 4. Generate the first snapshot menu
# This check ensures the script doesn't error out if the AUR script hasn't run yet
if command -v limine-snapper &>/dev/null; then
  sudo limine-snapper
  echo "Limine configuration complete!"
else
  echo "Warning: limine-snapper not found. Make sure your AUR script ran successfully."
fi

fastfetch
