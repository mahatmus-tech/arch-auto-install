#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Starting Arch-Hyprland automated installation..."

# Ensure pacman is up to date
echo "📦 Upgrading System..."
sudo pacman -Syu --needed --noconfirm

# Ensuring dependencies
echo "📦 Installing Ansible..."
sudo pacman -S --needed --noconfirm git base-devel ansible

# Clona o repositório do yay dentro do diretório
echo "📦 Clonando repositório yay..."
INSTALL_DIR="/tmp/yay"
rm -rf "$INSTALL_DIR"
sudo git clone https://aur.archlinux.org/yay.git "$INSTALL_DIR"

# Compila e instala o yay como aur-builder
echo "⚙️  Instalando yay..."
cd "$YAY_DIR"
makepkg -si --noconfirm

# Clone the installation repository
echo "📥 Cloning installation repository..."
INSTALL_DIR="/tmp/arch-auto-install"
rm -rf "$INSTALL_DIR"
sudo git clone https://github.com/mahatmus-tech/arch-auto-install.git "$INSTALL_DIR"

# Run archinstall using the custom script
echo "⚙️  Running archinstall..."
cd "$INSTALL_DIR/ansible"
ansible-galaxy role install jahrik.yay
ansible-playbook -i localhost, -c local playbook.yml -K

echo "✅ Installation complete! You can now reboot into your new Arch system."
