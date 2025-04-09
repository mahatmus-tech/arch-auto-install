#!/usr/bin/env bash

set -euo pipefail

# ======================
# CONFIGURATION
# ======================
INSTALL_DIR="/tmp/arch-install"
YAY_URL="https://aur.archlinux.org/yay-bin.git"
COLORS_ENABLED=true

# ======================
# COLOR OUTPUT FUNCTIONS
# ======================
if [ "$COLORS_ENABLED" = true ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

status() { echo -e "${GREEN}[+]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

# ======================
# SYSTEM DETECTION
# ======================
detect_system() {
    status "Detecting system hardware..."
    
    # GPU Detection
    if lspci | grep -iq "nvidia"; then
        export GPU="nvidia"
        info "Found NVIDIA GPU"
    elif lspci | grep -iq "amd"; then
        export GPU="amd"
        info "Found AMD GPU"
    elif lspci | grep -iq "intel"; then
        export GPU="intel"
        info "Found Intel GPU"
    else
        export GPU="unknown"
        warning "Unknown GPU - installing basic drivers"
    fi

    # CPU Detection
    if grep -iq "intel" /proc/cpuinfo; then
        export CPU="intel"
        info "Found Intel CPU"
    elif grep -iq "amd" /proc/cpuinfo; then
        export CPU="amd"
        info "Found AMD CPU"
    else
        export CPU="unknown"
        warning "Unknown CPU type"
    fi
}

# ======================
# INSTALLATION FUNCTIONS
# ======================
install_packages() {
    status "Installing packages: $*"
    sudo pacman -S --needed --noconfirm "$@" || {
        warning "Failed to install some packages. Continuing..."
        return 1
    }
}

install_packages_asdeps() {
    status "Installing packages: $*"
    sudo pacman -S --needed --noconfirm --asdeps "$@" || {
        warning "Failed to install some packages. Continuing..."
        return 1
    }
}

install_aur() {
    status "Installing AUR packages: $*"
    yay -S --needed --noconfirm "$@" || {
        warning "Failed to install some AUR packages. Continuing..."
        return 1
    }
}

clone_and_build() {
    local repo_url=$1
    local dir_name=$2
    local build_cmd=${3:-"makepkg -si --noconfirm"}
    
    status "Building $dir_name from source..."
    sudo rm -rf "$INSTALL_DIR/$dir_name"
    sudo git clone "$repo_url" "$INSTALL_DIR/$dir_name" || error "Failed to clone $dir_name"
    cd "$INSTALL_DIR/$dir_name" || error "Failed to enter $dir_name directory"
    sudo chown -R $USER:$USER . || error "Failed to change ownership"
    sudo chmod -R 755 . || error "Failed to change permissions"
    eval "$build_cmd" || warning "Failed to build/install $dir_name"
    cd - >/dev/null || error "Failed to return to previous directory"
}

# ======================
# INSTALLATION SECTIONS
# ======================
install_base_system() {
    status "Updating system and installing base packages..."
    sudo pacman -Syu --needed --noconfirm
    install_packages git base-devel curl python flatpak
    
    # Create user directories
    mkdir -p ~/{Downloads,Documents,Pictures,Projects,.config}
}

install_aur_helper() {
    status "Installing yay (AUR helper)..."
    clone_and_build "$YAY_URL" "yay-bin"
}

install_firmware() {
    status "Installing firmware packages..."
    
    case $CPU in
        "intel") install_packages intel-ucode;;
        "amd") install_packages amd-ucode;;
    esac

    install_packages \
	linux-headers linux-firmware linux-firmware-qlogic
    
    install_aur \
	ast-firmware mkinitcpio-firmware
    
    clone_and_build "https://github.com/mahatmus-tech/uPD72020x-Firmware.git" "uPD72020x-Firmware"
    
    clone_and_build "https://github.com/fhunleth/blstrobe.git" "blstrobe" \
		    "./autogen.sh && ./configure && make && sudo make install"    
}

install_graphics_stack() {
    status "Installing graphics stack for $GPU..."
    
    # Common graphics packages
    install_packages \
        mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader \
        wayland-protocols xorg-xwayland libglvnd \
        qt5-wayland qt6-wayland qt5ct qt6ct \
        egl-wayland libva libvdpau vulkan-tools
    
    # GPU-specific packages
    case $GPU in
        "nvidia")
            install_packages \
                nvidia-dkms nvidia-utils nvidia-settings \
                lib32-nvidia-utils libva-nvidia-driver \
                opencl-nvidia
            ;;
        "amd")
            install_packages \
                vulkan-radeon lib32-vulkan-radeon \
                libva-mesa-driver lib32-libva-mesa-driver
            ;;
        "intel")
            install_packages \
                vulkan-intel lib32-vulkan-intel \
                intel-media-sdk libva-intel-driver
            ;;
    esac
}

install_hyprland_stack() {
    status "Installing Hyprland and components..."    
    # Required dependencies
    install_packages \
        xdg-desktop-portal-hyprland hyprpolkitagent hyprland

    status "Installing Hyprland JakooLit DotFiles..."    
    sudo git clone --depth=1 https://github.com/JaKooLit/Arch-Hyprland.git ~/Arch-Hyprland
    cd ~/Arch-Hyprland
    sudo chmod +x install.sh
    ./install.sh    
}

install_multimedia() {
    status "Installing multimedia support..."
    install_packages \
        ffmpeg gstreamer gst-libav gst-plugins-bad \
        gst-plugins-good gst-plugins-ugly \
        lame flac wavpack opus faac faad2 \
        x264 x265 libvpx dav1d aom libmpeg2 libmad

    install_aur \
        ffmpeg-full
}

install_gaming() {
    status "Installing gaming support..."
    install_packages \
        steam gamescope mangohud lib32-mangohud \
        wine-staging lutris
    
    # Wine dependencies
    install_packages_asdeps \
        giflib lib32-giflib gnutls lib32-gnutls v4l-utils \
        lib32-v4l-utils libpulse lib32-libpulse alsa-plugins \
        lib32-alsa-plugins alsa-lib lib32-alsa-lib sqlite lib32-sqlite \
        libxcomposite lib32-libxcomposite ocl-icd lib32-ocl-icd libva \
        lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs \
        lib32-gst-plugins-base-libs vulkan-icd-loader \
        lib32-vulkan-icd-loader sdl2-compat lib32-sdl2-compat
}

install_compressions() {
    status "Installing compressions support..."
    install_packages \
        zip unzip p7zip gzip bzip2 xz \
        unrar lrzip zstd lzip lzop arj \
        cabextract cpio unace tar
}

install_apps() {
    status "Installing optional packages..."
    install_packages \
        emacs micro kitty man-db \
        htop nvtop btop wget fastfetch \
        docker docker-compose wlr-randr

    install_aur \
	brave-bin teams-for-linux

    flatpak install flathub dev.vencord.Vesktop
    flatpak install com.freerdp.FreeRDP

}

# ======================
# POST-INSTALL
# ======================
configure_system() {
    status "Configuring system..."
    
    # Add user to required groups
    sudo usermod -aG docker,video,input,gamemode $USER

    # Get the dot files
    sudo wget -P ~/.config/hypr/Monitor_Profiles https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/dotfiles/120hz.conf
    sudo wget -P /etc https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/dotfiles/gamemode.ini
}

# ======================
# MAIN INSTALLATION FLOW
# ======================
main() {
    echo -e "\n${GREEN}🚀 Starting Arch-Hyprland Automated Installation${NC}"
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR" || error "Failed to create installation directory"
    
    # Detection phase
    detect_system
    
    # Installation phases
    install_base_system
    install_aur_helper
    install_firmware
    install_graphics_stack
    install_multimedia
    install_compressions
    
    read -p "Install gaming support? (y/n) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && install_gaming

    install_apps    
    install_hyprland_stack
    configure_system
    
    # Cleanup
    status "Cleaning up..."
    sudo rm -rf "$INSTALL_DIR"
    
    echo -e "\n${GREEN}✅ Installation completed successfully!${NC}"
    echo -e "${YELLOW}Please reboot your system to apply all changes.${NC}"
    echo -e "Consider copying your dotfiles to ~/.config"
}

# Execute
main
