#!/usr/bin/env bash

set -euo pipefail

# Check if we're running in the live environment
if ! grep -q "archiso" /etc/hostname 2>/dev/null; then
    echo "This script must be run from the Arch Linux live environment."
    exit 1
fi

# Install dependencies for archinstall
#pacman -Sy --noconfirm git python python-pip ansible curl base-devel

# Clone this repository
git clone https://github.com/mahatmus-tech/arch-auto-install.git /tmp/arch-auto-install
cd /tmp/arch-auto-install

# Run archinstall
cd archinstall
chmod +x install.sh
./install.sh

# Chroot into the new system and run Ansible
arch-chroot /mnt bash -c "pacman -S --needed --noconfirm ansible && \
                          git clone https://github.com/mahatmus-tech/arch-auto-install.git /tmp/arch-auto-install && \
                          cd /tmp/arch-auto-install/ansible && \
                          ansible-playbook -i localhost, -c local playbook.yml"

echo "Installation complete! You can now reboot into your new system."
