# ZypherOS Project Documentation

ZypherOS is a modern, hardware-aware Linux distribution built on top of Arch Linux. Designed for power users, developers, and homelab administrators, it bridges the gap between the bleeding-edge performance of Arch and the stability of a production-ready system. 

Our goal is to eliminate the tedious boilerplate of setting up a highly optimized Linux workstation, providing a beautifully integrated, developer-first environment right out of the box.

### Project Goals & Philosophy

1. **Hardware-Aware Automation:** The OS should intelligently adapt to the silicon it runs on—from dynamic CPU microcode injection to scaling compressed RAM swap, without forcing the user to memorize esoteric configuration flags.
2. **Bulletproof by Default:** Mistakes happen. Updates break things. ZypherOS is built on a BTRFS filesystem with pre-configured Snapper snapshots, ensuring you can always roll back your system in seconds.
3. **Developer-First Ergonomics:** We believe your terminal and editor should be first-class citizens. ZypherOS comes pre-configured with modern, high-performance CLI tools, the Fish shell, the Ghostty terminal emulator, and a fully integrated Neovim (LazyVim) environment.
4. **Homelab Ready:** Whether deployed on bare metal, a dedicated gaming rig, or as a headless VM on a hypervisor, the OS is designed to be easily accessible and remotely manageable from the first boot.

### Core Features

#### The Deployment Engine
ZypherOS utilizes a custom, interactive TUI (Text User Interface) installer that handles the heavy lifting of system deployment:
* **Smart Silicon Detection:** Automatically identifies your CPU architecture (AMD/Intel) for proper microcode patching and detects your GPU to deploy the correct open-source or proprietary graphics stack.
* **Dynamic Performance Tuning:** Automatically hunts for the fastest global package mirrors and dynamically configures ZRAM (compressed swap) based on your machine's physical memory.
* **Network & Security Validation:** Enforces strict user account creation rules, configures your network (DHCP or Static IP), and offers optional SSH enablement for immediate remote access.

#### The System Architecture
* **Filesystem:** BTRFS root with strict subvolume boundaries (`@`, `@home`, `@log`, `@pkg`) optimized for SSD/NVMe drives.
* **Snapshots:** Fully integrated Snapper configuration for both system and user directories.
* **Bootloader:** Modern, blazing-fast Limine bootloader with automatic EFI/BIOS detection and hardware-specific kernel parameter injection.
* **Desktop Environment:** A customized, highly polished KDE Plasma (Wayland) experience featuring the Breeze Dark aesthetic and ZypherOS native branding.

#### The Developer Stack
ZypherOS ships with a curated selection of modern, rust-based, and high-performance utilities out of the box, including:
* **Terminal & Shell:** Ghostty, Fish shell, `zoxide`, `eza`, `bat`, `btop`, `fzf`, `yazi`.
* **Editor:** Neovim pre-configured with a custom LazyVim profile, `ripgrep`, `fd`, and `lazygit`.
* **AUR Support:** Pre-compiled with `yay` for immediate access to the Arch User Repository.

### Getting Started

*(Note: ZypherOS is currently in Alpha. Deployment on production data without backups is not recommended.)*

To install ZypherOS, download the latest ISO file from the tag section of release.
