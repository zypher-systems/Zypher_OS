# Clear the screen and auto-launch the ZypherOS Installer
clear
if [ -x /root/install.sh ]; then
    /root/install.sh
fi
