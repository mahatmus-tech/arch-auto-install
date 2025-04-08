#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Starting Arch-Hyprland automated installation..."

# Ensure pacman is up to date
echo "📦 Upgrading System..."
sudo pacman -Syu --needed --noconfirm

# Ensuring dependencies
echo "📦 Installing Ansible..."
sudo pacman -S --needed --noconfirm git base-devel ansible

# Clone YAY repository
echo "📦 Cloning yay respository..."
INSTALL_DIR="/usr/local/yay"
rm -rf "$INSTALL_DIR"
git clone https://aur.archlinux.org/yay.git "$INSTALL_DIR"

# Create temporary user
useradd -r -d /tmp/aur-build -s /bin/bash aur-builder
chown aur-builder /tmp/aur-build

# Run yay install
echo "⚙️  Running yay install..."
cd "$INSTALL_DIR"
sudo -u aur-builder makepkg -si --noconfirm

# Cleanup
userdel aur-builder
rm -rf /tmp/aur-build

# Clone the installation repository
echo "📥 Cloning installation repository..."
INSTALL_DIR="/usr/local/arch-auto-install"
rm -rf "$INSTALL_DIR"
git clone https://github.com/mahatmus-tech/arch-auto-install.git "$INSTALL_DIR"

# Run archinstall using the custom script
echo "⚙️  Running archinstall..."
cd "$INSTALL_DIR/ansible"
ansible-galaxy role install jahrik.yay
ansible-playbook -i localhost, -c local playbook.yml -K

echo "✅ Installation complete! You can now reboot into your new Arch system."
