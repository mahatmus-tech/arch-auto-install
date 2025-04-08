# Arch Linux Automated Installation

This project automates the installation of Arch Linux with a customized configuration including Hyprland, Nvidia drivers, and gaming optimizations.

## Features

- Automated Arch Linux installation with custom partitioning and configuration
- Post-installation setup with Ansible
- Hyprland window manager configuration
- Nvidia driver installation and optimization
- Gaming setup with Steam, GameMode, and performance tweaks
- User applications and configuration

## Requirements

- Arch Linux live USB
- Internet connection

## Installation

1. Boot into the Arch Linux live environment
2. Run the following command:

```bash
bash <(curl -L https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/main/bootstrap.sh)
