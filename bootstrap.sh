#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Starting Arch Linux automated installation..."

# Check if we're running in the live environment
if ! grep -i "archiso" /etc/hostname 2>/dev/null; then
    echo "❌ This script must be run from the Arch Linux live environment."
    exit 1
fi

# Clone the installation repository
echo "📥 Cloning installation repository..."
INSTALL_DIR="/tmp/arch-auto-install"
rm -rf "$INSTALL_DIR"
git clone https://github.com/mahatmus-tech/arch-auto-install.git "$INSTALL_DIR"

# Run archinstall using the custom script
echo "⚙️  Running archinstall..."
cd "$INSTALL_DIR/archinstall"
chmod +x install.sh
./install.sh

# Validate that /mnt was created
if [[ ! -d /mnt ]]; then
    echo "❌ Installation failed. /mnt not found."
    exit 1
fi

# Chroot into the new system and finalize setup with Ansible
echo "🛠 Running post-install configuration inside chroot..."
arch-chroot /mnt /bin/bash <<'EOF'
set -euo pipefail

echo "📥 Cloning repository inside chroot..."
git clone https://github.com/mahatmus-tech/arch-auto-install.git /tmp/arch-auto-install

echo "📦 Installing Git and Ansible inside chroot..."
pacman -Sy --noconfirm git ansible

echo "🧰 Running Ansible playbook..."
cd /tmp/arch-auto-install/ansible
ansible-playbook -i localhost, -c local playbook.yml
EOF

echo "✅ Installation complete! You can now reboot into your new Arch system."
