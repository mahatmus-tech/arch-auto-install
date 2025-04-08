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
INSTALL_DIR="/tmp/aur-build"
YAY_DIR="$INSTALL_DIR/yay"

# Remove o usuário aur-builder se existir
if id -u "aur-builder" >/dev/null 2>&1; then
    echo "🧹 Removendo usuário aur-builder existente..."
    userdel -r aur-builder || true
fi

# Cria diretório temporário
mkdir -p "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

# Cria o usuário aur-builder com home no diretório temporário
useradd -r -d "$INSTALL_DIR" -s /bin/bash aur-builder
chown -R aur-builder "$INSTALL_DIR"

# Clona o repositório do yay dentro do diretório
echo "📦 Clonando repositório yay..."
rm -rf "$YAY_DIR"
git clone https://aur.archlinux.org/yay.git "$YAY_DIR"
chown -R aur-builder "$YAY_DIR"

# Compila e instala o yay como aur-builder
echo "⚙️  Instalando yay..."
cd "$YAY_DIR"
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
