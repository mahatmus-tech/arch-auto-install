#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Starting Arch-Hyprland automated installation..."

# Validate that /mnt was created
if [[ ! -d /mnt ]]; then
    echo "❌ This script must be run from the Arch Linux live environment. /mnt not found."
    exit 1
fi

# Ensure git  is installed in the live environment
echo "📦 Installing Ansible..."
pacman -Sy --noconfirm ansible

# Clone the installation repository
echo "📥 Cloning installation repository..."
INSTALL_DIR="/tmp/arch-auto-install"
rm -rf "$INSTALL_DIR"
git clone https://github.com/mahatmus-tech/arch-auto-install.git "$INSTALL_DIR"

# Run archinstall using the custom script
echo "⚙️  Running archinstall..."
cd "$INSTALL_DIR/archinstall/ansible"
ansible-playbook -i localhost, -c local playbook.yml

echo "✅ Installation complete! You can now reboot into your new Arch system."
