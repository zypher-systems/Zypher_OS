#!/bin/bash
echo "Configuring Limine Bootloader for ZypherOS..."

CONF_PATH="/boot/limine/limine.conf"
# Grab the system's unique hardware ID
MACHINE_ID=$(cat /etc/machine-id)

# 1. Safely replace "Arch Linux" with "ZypherOS"
echo "Rebranding boot menu and injecting Machine ID..."
sed 's/Arch Linux/ZypherOS/g' "$CONF_PATH" >/tmp/limine_temp.conf

# 2. The Backdoor: Inject the Machine ID directly under the OS names
# This finds any line with ZypherOS and adds the machine-id comment directly underneath it
if ! grep -q "machine-id" /tmp/limine_temp.conf; then
  sed -i "s/.*ZypherOS.*/&\n    comment: machine-id=${MACHINE_ID}/" /tmp/limine_temp.conf
fi

cat /tmp/limine_temp.conf | sudo tee "$CONF_PATH" >/dev/null
rm /tmp/limine_temp.conf
echo "Boot menu successfully branded as ZypherOS."

# 3. Inject the Snapper menu into the main Limine config
if ! grep -q "limine-snapshots.conf" "$CONF_PATH"; then
  echo "" | sudo tee -a "$CONF_PATH" >/dev/null
  echo "# Include BTRFS Snapshots Menu" | sudo tee -a "$CONF_PATH" >/dev/null
  echo "remember: yes" | sudo tee -a "$CONF_PATH" >/dev/null
  echo "include: boot():/limine/limine-snapshots.conf" | sudo tee -a "$CONF_PATH" >/dev/null
  echo "Snapper snapshot menu linked to Limine."
fi

# 4. Tell limine-snapper-sync exactly where the EFI folder is
echo "Setting variables for limine-snapper-sync..."
sudo mkdir -p /etc/default
echo 'ESP_PATH="/boot/limine"' | sudo tee /etc/default/limine >/dev/null
# We no longer need TARGET_OS_NAME because the Machine ID overrides it completely!

# 5. Generate the snapshot menu
if command -v limine-snapper-sync &>/dev/null; then
  sudo limine-snapper-sync
  echo "Limine configuration complete!"
else
  echo "Warning: limine-snapper-sync command not found."
fi

fastfetch
