#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Starting Arch-Hyprland automated installation..."

# Ensure git  is installed in the live environment
echo "📦 Installing Ansible..."
sudo pacman -Sy --noconfirm git ansible

# Clone the installation repository
echo "📥 Cloning installation repository..."
INSTALL_DIR="/tmp/arch-auto-install"
rm -rf "$INSTALL_DIR"
sudo git clone https://github.com/mahatmus-tech/arch-auto-install.git "$INSTALL_DIR"

# Run archinstall using the custom script
echo "⚙️  Running archinstall..."
cd "$INSTALL_DIR/ansible"
ansible-playbook -i localhost, -c local playbook.yml -K

echo "✅ Installation complete! You can now reboot into your new Arch system."
