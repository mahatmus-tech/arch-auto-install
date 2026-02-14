# Arch Linux Automated Installation

This project automates the installation of Arch Linux with a customized configuration, including Hyprland, Nvidia drivers, and gaming optimizations.

## Features

- Automated Arch Linux installation with custom partitioning and configuration
- Post-installation setup
- Hyprland window manager configuration
- Nvidia driver installation and optimization
- Gaming setup with Steam, GameMode, and performance tweaks
- User applications and configuration

## Requirements

- Install Arch using `archinstall` with the following options:
  - Kernel: `linux`
  - Bootloader: `systemd-boot`
  - Installation type: `minimal`
  - Audio: `pipewire`
  - Partitioning: `one partition`
  - Network: `network`
- For JaKooLit:
  - Do not select Nvidia options during installation.
  - **Important**: Do not reboot at the end of the JaKooLit installation process. Post-installation configurations will be applied afterward. If you have already rebooted, simply execute `install-hyprland.sh` again and uncheck the JaKooLit option.

## Installation Steps

1. **Boot into the Arch Linux live environment.**
2. **Run the following command to start the Arch installation process:**
   ```bash
   archinstall
   ```
3. **Reboot your system.**
4. **Run the following command to begin the automated installation:**
   ```bash
   bash <(curl -L https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/main/install-arch.sh)
   ```
5. **Reboot your system again.**
6. **Run the following command to install Hyprland and related configurations:**
   ```bash
   bash <(curl -L https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/main/install-hyprland.sh)
   ```
7. **Reboot your system to complete the installation.**


## Steam Configuration

1. **Go to Settings**
- In Downloads:
  - Enable: `Enable Shader Pre-Caching` 
  - Enable: `Allow background processing of Vulkan shaders`
- In Compatibility:
  - Enable: `Enable Steam Play for all other titles`
  - Run other titles with: `Proton-GE`
2. **Restart your Steam.**
3. **Set Launch settings for your games**
4. **Go to General**
- In Launcher Options:
   ```bash
   SteamDeck=1 gamemoderun mangohud %command%
   ```
   ```bash
   env -u SDL_VIDEODRIVER gamemoderun gamescope --hdr-enabled -O HDMI-A-1 -f -W 3840 -H 2160 -w 3840 -h 2160 -r 120 --mangoapp -- env DXVK_HDR=1 %command%
   ```      
5. **Run your game**