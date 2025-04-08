#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Starting Arch-Hyprland automated installation..."

# Ensure pacman is up to date
echo "📦 Upgrading System..."
sudo pacman -Syu --needed --noconfirm

# Ensuring dependencies
echo "📦 Installing Ansible..."
sudo pacman -S --needed --noconfirm git base-devel ansible

# Create temporary user
# Remove o usuário aur-builder se existir
if id -u "aur-builder" >/dev/null 2>&1; then
    echo "🧹 Removendo usuário aur-builder existente..."
    userdel -r aur-builder || true  # ignora erro se home não existir
fi

# Cria diretório temporário
INSTALL_DIR="/tmp/aur-build"
mkdir -p "$INSTALL_DIR"
chmod 1777 "$INSTALL_DIR"

# Cria o usuário aur-builder com home no diretório temporário
useradd -r -d "$INSTALL_DIR" -s /bin/bash aur-builder
chown aur-builder "$INSTALL_DIR"

# Clone YAY repository
echo "📦 Cloning yay respository..."
rm -rf "$INSTALL_DIR"
git clone https://aur.archlinux.org/yay.git "$INSTALL_DIR"

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
