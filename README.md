# ⚡ ZypherOS

An automated, modular Arch Linux deployment framework designed for rapid provisioning of bare-metal machines, laptops, and virtual machines. 

ZypherOS takes a fresh system from an empty disk to a fully configured, production-ready environment—complete with a customized IDE—using a single execution script. It is optimized for use with local package mirrors and headless deployment.

## 🏗️ Architecture

The deployment is broken down into a master controller (`install.sh`) and 10 sequential sub-scripts. This modular approach allows for easy troubleshooting and the ability to swap out specific components (like the desktop environment or bootloader) without rewriting the entire installer.

### The Deployment Sequence
* **`install.sh`** - The master script. Sets up the environment and executes the sub-scripts in order.
* **`subscripts/01-disk.sh`** - Handles partition layout, formatting, and mounting.
* **`subscripts/02-base.sh`** - Bootstraps the Arch Linux base system (`pacstrap`) and generates the `fstab`.
* **`subscripts/03-packages.sh`** - Installs core system utilities, networking tools, and dependencies.
* **`subscripts/04-network.sh`** - Configures the hostname, hosts file, and enables NetworkManager.
* **`subscripts/05-locale.sh`** - Sets the system timezone, hardware clock, and generates locales.
* **`subscripts/06-bootloader.sh`** - Installs and configures the bootloader.
* **`subscripts/07-users.sh`** - Establishes the root password, creates the primary user account, and configures `sudo` privileges.
* **`subscripts/08-desktop.sh`** - Installs the desktop environment (KDE), display manager, and associated graphics drivers.
* **`subscripts/09-system.sh`** - Enables required systemd services and applies final OS-level tweaks.
* **`subscripts/10-neovim.sh`** - Installs Neovim dependencies (`ripgrep`, `fd`, `lazygit`) and bootstraps a customized LazyVim environment directly from version control.

## 🚀 Usage

**Warning:** This script automates disk partitioning. Running this on a machine will wipe the targeted drive. 

1. Boot into the live Arch Linux installation media.
2. Ensure you have an active internet connection.
3. Clone the repository and execute the installer:

```bash
git clone [https://github.com/zypher-systems/Zypher_OS.git](https://github.com/zypher-systems/Zypher_OS.git)
cd Zypher_OS
chmod +x install.sh subscripts/*.sh
./install.sh

Or use a single command to kick off the install: 

curl -fsSL https://zyphersystems.com/install | sh
