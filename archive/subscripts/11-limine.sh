#!/bin/bash
echo "Configuring Limine Bootloader for ZypherOS..."

# 1. Dynamically find the config file
if [ -f /boot/limine/limine.conf ]; then
    CONF_PATH="/boot/limine/limine.conf"
elif [ -f /boot/limine.conf ]; then
    CONF_PATH="/boot/limine.conf"
else
    echo "Error: limine.conf not found."
    exit 1
fi

# 2. Safely replace "Arch Linux" with "ZypherOS"
echo "Rebranding boot menu..."
sed 's/Arch Linux/ZypherOS/g' "$CONF_PATH" > /tmp/limine_temp.conf
cat /tmp/limine_temp.conf | sudo tee "$CONF_PATH" > /dev/null
rm /tmp/limine_temp.conf

echo "Boot menu successfully branded as ZypherOS."

fastfetch
