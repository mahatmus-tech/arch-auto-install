#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Starting Arch-Hyprland automated installation..."

echo "📦 Upgrading System..."
sudo pacman -Syu --needed --noconfirm

echo "📦 Installing basics..."
sudo pacman -S --needed --noconfirm git base-devel curl python

echo "⚙️  Instaling yay..."
INSTALL_DIR="/tmp/yay-bin"
sudo rm -rf "$INSTALL_DIR"
sudo git clone https://aur.archlinux.org/yay-bin.git "$INSTALL_DIR"
cd "$INSTALL_DIR"
sudo chown $USER:$USER "$INSTALL_DIR"
sudo chmod 755 "$INSTALL_DIR"
makepkg -si

echo "⚙️  Instaling uPD72020x..."
INSTALL_DIR="/tmp/uPD72020x-Firmware"
sudo rm -rf "$INSTALL_DIR"
sudo git clone https://github.com/mahatmus-tech/uPD72020x-Firmware.git "$INSTALL_DIR"
cd "$INSTALL_DIR"
sudo chown $USER:$USER "$INSTALL_DIR"
sudo chmod 755 "$INSTALL_DIR"
makepkg -si

echo "⚙️  Installing BLSTROBE..."
INSTALL_DIR="/tmp/blstrobe"
sudo rm -rf "$INSTALL_DIR"
sudo git clone https://github.com/fhunleth/blstrobe.git "$INSTALL_DIR"
cd "$INSTALL_DIR"
sudo chown $USER:$USER "$INSTALL_DIR"
sudo chmod 755 "$INSTALL_DIR"
./autogen.sh
./configure
make
sudo make install

echo "⚙️  Installing PACMAM ALL..."
# Depois de instalar o YAY, bora instalar tudo
sudo pacman -S --needed --noconfirm linux-headers linux-firmware linux-firmware-qlogic kitty man-db wget htop nvtop fastfetch pokemon-colorscripts gst-libav gst-plugins-bad gst-plugins-good gst-plugins-ugly ffmpeg gstreamer libva libvdpau lame flac wavpack opus faac faad2 x264 x265 libvpx dav1d aom libmpeg2 libmad zip unzip p7zip gzip bzip2 xz tar rar unrar lrzip zstd lzip lzop arj cabextract cpio unace waybar wayland qt5-wayland qt6-wayland qt5ct qt6ct wayland-protocols wlr-randr steam gamescope mangohud lib32-mangohud nvidia-dkms nvidia-utils nvidia-settings lib32-nvidia-utils libva-nvidia-driver egl-wayland vulkan-icd-loader vulkan-tools libglvnd opencl-nvidia wine-staging emacs micro flatpak amd-ucode

echo "⚙️  Installing Wine Dependencies..."
sudo pacman -S --needed --asdeps giflib lib32-giflib gnutls lib32-gnutls v4l-utils lib32-v4l-utils libpulse lib32-libpulse alsa-plugins lib32-alsa-plugins alsa-lib lib32-alsa-lib sqlite lib32-sqlite libxcomposite lib32-libxcomposite ocl-icd lib32-ocl-icd libva lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs lib32-gst-plugins-base-libs vulkan-icd-loader lib32-vulkan-icd-loader sdl2-compat lib32-sdl2-compat

echo "⚙️  Installing YAY ALL ..."
sudo yay -S --needed --noconfirm mkinitcpio-firmware ast-firmware ffmpeg-full ninja gcc cmake meson libxcb xcb-proto xcb-util xcb-util-keysyms libxfixes libx11 libxcomposite libxrender libxcursor pixman wayland-protocols cairo pango libxkbcommon xcb-util-wm xorg-xwayland libinput libliftoff libdisplay-info cpio tomlplusplus hyprlang-git hyprcursor-git hyprwayland-scanner-git xcb-util-errors hyprutils-git glaze hyprgraphics-git aquamarine-git re2 hyprland-qtutils teams-for-linux brave-bin

echo "⚙️  Installing Flatpak..."
sudo flatpak install flathub dev.vencord.Vesktop
sudo flatpak install com.freerdp.FreeRDP

echo "⚙️  Installing Hyprland..."
sudo git clone --recursive https://github.com/hyprwm/Hyprland
cd Hyprland
make all && sudo make install  git clone --recursive https://github.com/hyprwm/Hyprland
cd Hyprland
make all && sudo make install









