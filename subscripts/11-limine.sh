#!/bin/bash
echo "[11/11] Configuring Limine Bootloader for ZypherOS..."

CONF_PATH="/boot/limine/limine.conf"

# 1. Safely rename the OS using a temporary file
echo "Rebranding boot menu..."
sed 's/^:Arch Linux/:ZypherOS/' "$CONF_PATH" >/tmp/limine_temp.conf
cat /tmp/limine_temp.conf | sudo tee "$CONF_PATH" >/dev/null
rm /tmp/limine_temp.conf
echo "Boot menu successfully branded as ZypherOS."

# 2. Inject the Snapper menu into the main Limine config
if ! grep -q "limine-snapshots.conf" "$CONF_PATH"; then
  echo "" | sudo tee -a "$CONF_PATH" >/dev/null
  echo "# Include BTRFS Snapshots Menu" | sudo tee -a "$CONF_PATH" >/dev/null
  echo "remember: yes" | sudo tee -a "$CONF_PATH" >/dev/null
  echo "include: boot():/limine/limine-snapshots.conf" | sudo tee -a "$CONF_PATH" >/dev/null
  echo "Snapper snapshot menu linked to Limine."
fi

# 3. Tell limine-snapper-sync exactly where to look and what to copy
echo "Setting variables for limine-snapper-sync..."
sudo mkdir -p /etc/default
echo 'ESP_PATH="/boot/limine"' | sudo tee /etc/default/limine >/dev/null
echo 'TARGET_OS_NAME="ZypherOS"' | sudo tee -a /etc/default/limine >/dev/null

# 4. Generate the snapshot menu
if command -v limine-snapper-sync &>/dev/null; then
  sudo limine-snapper-sync
  echo "Limine configuration complete!"
else
  echo "Warning: limine-snapper-sync command not found."
fi

fastfetch
