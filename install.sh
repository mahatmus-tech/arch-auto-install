#!/usr/bin/env bash

set -euo pipefail

# ======================
# CONFIGURATION
# ======================
INSTALL_DIR="~/Apps"
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

    # change pacman parallel downloads
    sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf

    # Update packages
    sudo pacman -Syu --needed --noconfirm
    install_packages git base-devel curl python meson systemd dbus libinih wget
    
    # Create user directories
    mkdir -p ~/{Downloads,Documents,Pictures,Projects,.config,Apps}
}

install_tkg_kernel() {
    # clone linux-tkg kernel
    status "Cloning linux-tkg kernel..."
    clone_and_build "git clone https://github.com/Frogging-Family/linux-tkg.git" "linux-tkg" \
		    "echo Repository Linux TKG has been cloned!"

    #Download linux-tkg kernel
    sudo wget -P /boot https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/tags/1.0/tkg-kernel/vmlinuz-linux614-tkg-eevdf
    sudo wget -P /boot https://github.com/mahatmus-tech/arch-auto-install/releases/download/1.0/initramfs-linux614-tkg-eevdf.img
    sudo wget -P /boot https://github.com/mahatmus-tech/arch-auto-install/releases/download/1.0/initramfs-linux614-tkg-eevdf-fallback.img
    sudo wget -P /boot/loader/entries https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/tags/1.0/tkg-kernel/linux-tkg.conf
    sudo wget -P /boot/loader/entries https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/tags/1.0/tkg-kernel/linux-tkg-fallback.conf

    #Edit the linux-tkg.conf
    UUID=$(blkid -s UUID -o value $(findmnt -n -o SOURCE /))    
    sudo sed -i -E "s/52cd2305-c1ca-4c5c-ba62-9b265a1cf699/$UUID/g" /boot/loader/entries/linux-tkg.conf
    sudo sed -i -E "s/52cd2305-c1ca-4c5c-ba62-9b265a1cf699/$UUID/g" /boot/loader/entries/linux-tkg-fallback.conf    
    sudo bootctl update
    # set linux-tkg as default
    sudo bootctl set-default linux-tkg.conf
}

install_extra_package_managers() {
    status "Installing yay (AUR helper)..."
    clone_and_build "$YAY_URL" "yay-bin"

    status "Installing flatpak..."
    install_packages flatpak

    status "Installing snap..."
    clone_and_build "https://aur.archlinux.org/snapd.git" "snapd"

    sudo systemctl enable --now snapd.socket
    sudo ln -s /var/lib/snapd/snap /snap
}

install_firmware() {
    status "Installing firmware packages..."
    
    case $CPU in
        "intel") install_packages intel-ucode;;
        "amd") install_packages amd-ucode;;
    esac
    
    install_aur \
	ast-firmware mkinitcpio-firmware
    
    clone_and_build "https://github.com/mahatmus-tech/uPD72020x-Firmware.git" "uPD72020x-Firmware"
}

install_graphics_stack() {
    status "Installing graphics stack for $GPU..."
    
    # GPU-specific packages
    case $GPU in
        "nvidia")
	    clone_and_build "https://github.com/Frogging-Family/nvidia-all.git" "nvidia-all"
            # Old cards 
            # install_packages nvidia-dkms 
            # Turing or newer hardware only
            # install_packages nvidia-open-dkms
            #install_packages \
            #   nvidia-utils nvidia-settings nvidia-prime \
	    #	lib32-nvidia-utils  opencl-nvidia \
  	    #	libva-nvidia-driver lib32-libva-nvidia-driver
            ;;
        "amd")
	install_packages \
		xf86-video-amdgpu \
		vulkan-radeon lib32-vulkan-radeon \
		libva-mesa-driver lib32-libva-mesa-driver \
		mesa-vdpau lib32-mesa-vdpau
            ;;
        "intel")
            install_packages \
                vulkan-intel lib32-vulkan-intel \
                intel-media-sdk libva-intel-driver
            ;;
    esac

    # Input & GPU Acceleration
    install_packages \
	libinput libglvnd mesa lib32-mesa \
	libvdpau lib32-libvdpau libva lib32-libva \
	vulkan-icd-loader lib32-vulkan-icd-loader
 
    # QT Support
    install_packages \
        qt5ct qt6ct
}

install_wayland() {
    status "Installing Wayland..."
    install_packages \
        wayland wayland-protocols wayland-utils \
	lib32-wayland xorg-xwayland \
	egl-wayland qt5-wayland qt6-wayland
}

install_xorg() {
    status "Installing Xorg..."
    install_packages \
        xorg-server xorg-xinit xorg-xinput egl-x11
}

install_hyprland_stack() {
    status "Installing Hyprland and components..."
    
    # Installing Dendencies of Hyprland
    install_aur \
    	ninja gcc cmake meson libxcb xcb-proto xcb-util xcb-util-keysyms libxfixes 
        libx11 libxcomposite libxrender libxcursor pixman wayland-protocols cairo 
	pango libxkbcommon xcb-util-wm xorg-xwayland libinput libliftoff libdisplay-info 
        cpio tomlplusplus hyprlang-git hyprcursor-git hyprwayland-scanner-git xcb-util-errors 
        hyprutils-git glaze hyprgraphics-git aquamarine-git re2 hyprland-qtutils
	
    # Builing and installing Hyprland 
    clone_and_build "--recursive https://github.com/hyprwm/Hyprland" "Hyprland" \
		    "make all && sudo make install"      
    
    # Required dependencies
    install_packages \
        hyprpolkitagent
	
    install_aur \
      xdg-desktop-portal-hyprland-git
 
}

install_multimedia() {
    status "Installing multimedia support..."
    install_packages \
        ffmpeg gstreamer gst-libav gst-plugins-bad \
        gst-plugins-good gst-plugins-ugly \
        lame flac wavpack opus faac faad2 \
        x264 x265 libvpx dav1d aom libmpeg2 libmad

}

install_gaming() {
    status "Installing gaming support..."
    install_packages \
        steam lutris wine-staging goverlay \
	gamescope gamemode lib32-gamemode mangohud lib32-mangohud        
         
    install_aur \
      proton-ge-custom-bin
    
    # Wine dependencies - https://github.com/lutris/docs/blob/master/WineDependencies.md
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
        emacs micro kitty man-db sysfsutils \
        htop nvtop btop fastfetch \
        docker docker-compose wlr-randr

    install_aur \
	brave-bin teams-for-linux

    flatpak install -y flathub dev.vencord.Vesktop
    flatpak install -y com.freerdp.FreeRDP
    sudo snap install spotify

}

# ======================
# POST-INSTALL
# ======================
configure_system() {
    status "Configuring system..."

    # Synchronize package database
    sudo pacman -Sy --noconfirm
    
    # Add user to required groups
    sudo usermod -aG docker,video,input,gamemode $USER

    # Add ftrim to ssd
    sudo systemctl enable --now fstrim.timer

    # set async journal
    sudo tune2fs -E mount_opts=journal_async_commit $(findmnt -n -o SOURCE /)
    sudo tune2fs -o journal_data_writeback $(findmnt -n -o SOURCE /)
    # Define the UUID of the partition
    UUID=$(blkid -s UUID -o value $(findmnt -n -o SOURCE /))
    # Define the new mount options
    NEW_MOUNT_OPTIONS="defaults,noatime"
    # Edit the fstab file to change the mount options
    sudo sed -i -E "s|^UUID=$UUID.*|UUID=$UUID \/ ext4 $NEW_MOUNT_OPTIONS 0 2|" /etc/fstab    
    # remount the root partition
    sudo mount -o remount /
    

    # Get the dot files

    # monitor profile
    sudo wget -P /etc https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/dotfiles/gamemode.ini

    # get blstrobe script	
    mkdir -p ~/Documents/scripts
    cd ~/Documents/scripts
    sudo wget -P https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/dotfiles/blstrobe-start.sh
    sudo chmod +x blstrobe-start.sh
}

# ======================
# MAIN INSTALLATION FLOW
# ======================
main() {
    echo -e "\n${GREEN}🚀 Starting Arch-Hyprland Automated Installation${NC}"
    
    # Detection phase
    detect_system
    
    # Installation phases
    install_base_system
    install_tkg_kernel
    install_extra_package_managers
    install_firmware
    install_multimedia
    install_compressions
    install_graphics_stack
    install_wayland
    #install_worg
    install_gaming
    install_hyprland_stack
    configure_system
    install_apps
    
    # Cleanup
    status "Cleaning up..."
    sudo rm -rf "$INSTALL_DIR"
    
    echo -e "\n${GREEN}✅ Installation completed successfully!${NC}"
    echo -e "${YELLOW}Please reboot your system to apply all changes.${NC}"
    echo -e "Consider copying your dotfiles to ~/.config"
}

# Execute
main
