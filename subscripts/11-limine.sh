#!/bin/bash
echo "[11/11] Configuring Limine Bootloader for ZypherOS..."

CONF_PATH="/boot/limine/limine.conf"

# 1. Safely rename the main OS entry to "ZypherOS"
# This reads the file, changes the first line starting with a colon, and securely overwrites it
sed '0,/^:.*/s/^:.*/:ZypherOS/' "$CONF_PATH" | sudo tee "$CONF_PATH" >/dev/null
echo "Boot menu successfully branded as ZypherOS."

# 2. Inject the Snapper menu into the main Limine config
if ! grep -q "remember: yes" "$CONF_PATH"; then
  echo "" | sudo tee -a "$CONF_PATH" >/dev/null
  echo "# Include BTRFS Snapshots Menu" | sudo tee -a "$CONF_PATH" >/dev/null
  echo "remember: yes" | sudo tee -a "$CONF_PATH" >/dev/null

  # limine-snapper-sync usually generates limine-snapshots.conf
  echo "include: boot():/limine/limine-snapshots.conf" | sudo tee -a "$CONF_PATH" >/dev/null
  echo "Snapper snapshot menu linked to Limine."
fi

# Tell limine-snapper-sync where the boot partition is mounted
echo "Setting ESP_PATH for limine-snapper-sync..."
sudo mkdir -p /etc/default
echo 'ESP_PATH="/boot"' | sudo tee /etc/default/limine >/dev/null

# 3. Generate the first snapshot menu manually to ensure the file exists
if command -v limine-snapper-sync &>/dev/null; then
  sudo limine-snapper-sync
  echo "Limine configuration complete!"
else
  echo "Warning: limine-snapper-sync command not found."
fi

fastfetch
