#!/bin/bash
echo "Configuring Limine Bootloader for ZypherOS..."

# 1. Force the config to the root of /boot to satisfy the sync tool
if [ -f /boot/limine/limine.conf ]; then
    sudo mv /boot/limine/limine.conf /boot/limine.conf
fi
CONF_PATH="/boot/limine.conf"
MACHINE_ID=$(cat /etc/machine-id)

# 2. Rebrand and inject Machine ID (Temporary file bypasses FAT32 limits)
echo "Rebranding boot menu..."
sed 's/Arch Linux/ZypherOS/g' "$CONF_PATH" > /tmp/limine_temp.conf

if ! grep -q "machine-id" /tmp/limine_temp.conf; then
    sed -i "s/.*ZypherOS.*/&\n    comment: machine-id=${MACHINE_ID}/" /tmp/limine_temp.conf
fi

cat /tmp/limine_temp.conf | sudo tee "$CONF_PATH" > /dev/null
rm /tmp/limine_temp.conf
echo "Boot menu successfully branded as ZypherOS."

# 3. Inject the Snapper menu
if ! grep -q "limine-snapshots.conf" "$CONF_PATH"; then
    echo "" | sudo tee -a "$CONF_PATH" > /dev/null
    echo "# Include BTRFS Snapshots Menu" | sudo tee -a "$CONF_PATH" > /dev/null
    echo "remember: yes" | sudo tee -a "$CONF_PATH" > /dev/null
    echo "include: boot():/limine-snapshots.conf" | sudo tee -a "$CONF_PATH" > /dev/null
    echo "Snapper snapshot menu linked to Limine."
fi

# 4. Configure sync variables
echo "Setting variables for limine-snapper-sync..."
sudo mkdir -p /etc/default
echo 'ESP_PATH="/boot"' | sudo tee /etc/default/limine > /dev/null
echo 'TARGET_OS_NAME="ZypherOS"' | sudo tee -a /etc/default/limine > /dev/null

# 5. Generate the snapshot menu
if command -v limine-snapper-sync &> /dev/null; then
    sudo limine-snapper-sync
    echo "Limine configuration complete!"
else
    echo "Warning: limine-snapper-sync command not found."
fi

fastfetch
