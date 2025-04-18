#!/usr/bin/env bash

set -euo pipefail

# ======================
# GLOBAL VARIABLES
# ======================
# Default install dir
INSTALL_DIR="$HOME/Apps"

# Log file
export LOG_FILE="/var/log/arch_auto_install_$(date "+%Y%m%d-%H%M%S").log"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Menu configuration
MENU_OPTIONS=(
    1  "Firewall UFW"                 on
    2  "Bluetooth"                    on
    3  "Gaming"                       on
    4  "Recommended Apps"             on
    5  "Build Your Linux TKG Kernel"  off
)

# ======================
# INSTALLATION FUNCTIONS
# ======================
status() { echo -e "${GREEN}[+]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

show_menu() {
    install_packages dialog
    
    dialog --clear \
        --title "Arch Auto Installation" \
        --checklist "Select extra options to install:" 20 60 15 \
        "${MENU_OPTIONS[@]}" 2>selected
    
    if [ ! -s selected ]; then
        error "No components selected. Exiting"
    fi  
}

install_packages() {
    status "Installing packages: $*"
    sudo pacman -S --needed --noconfirm "$@" || {
        warning "Failed to install some packages. Continuing..."
        return 1
    }
}

install_aur() {
    status "Installing packages: $*"
    yay -S --needed --noconfirm "$@" || {
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

clone_and_build() {
    local repo_url=$1
    local dir_name=$2
    local build_cmd=${3:-"makepkg -si --noconfirm"}
    
    status "Building $dir_name from source..."
    sudo rm -rf "$INSTALL_DIR/$dir_name"
    git clone "$repo_url" "$INSTALL_DIR/$dir_name" || error "Failed to clone $dir_name"
    cd "$INSTALL_DIR/$dir_name" || error "Failed to enter $dir_name directory"
    sudo chown -R "$USER" . || error "Failed to change ownership"
    sudo chmod -R 755 . || error "Failed to change permissions"
    eval "$build_cmd" || warning "Failed to build/install $dir_name"
    cd - >/dev/null || error "Failed to return to previous directory"
}

ask_user() {
    local prompt="${1:-Are you sure?}"
    while true; do
        read -rp "$prompt [y/n]: " yn
        case "${yn,,}" in  # lowercase input for consistency
            y|yes) info "Continuing..."; return 0 ;;
            n|no)  info "Skiping..."; return 1 ;;
            *)     info "Please answer y or n." ;;
        esac
    done
}

safe_download() {
    local dest=$1 url=$2
    if ! sudo wget -P "$dest" -q --show-progress "$url"; then
        error "Failed to download $url"
        return 1
    fi
}

# ======================
# SYSTEM DETECTION
# ======================
detect_system() {
    status "Detecting system hardware..."
    
    if [ -d /run/systemd/system ]; then
        info "System is using systemd"
    else
        error "This script is only compatible with Systemd-Boot!"
    fi

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
# INSTALLATION SECTIONS
# ======================
install_base_system() {
    status "Updating system and installing base packages..."
    
    status "Changing pacman settings..."
    sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
    sudo sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    sudo sed -i 's/^#ILoveCandy/ILoveCandy/' /etc/pacman.conf
    
    # Update packages
    sudo pacman -Syu --noconfirm
    # Base packages
    install_packages git base-devel curl python wget meson systemd dbus libinih
    # scheaduler
    install_packages scx-scheds
    sudo systemctl enable --now scx.service
    # pacman tool
    install_packages pacman-contrib
    sudo systemctl enable --now paccache.timer
    
    clone_and_build "https://aur.archlinux.org/yay.git" "yay"

    # Create user directories
    mkdir -p "$HOME"/{Downloads,Documents,Pictures,Projects,.config,Apps,Scripts}
}

install_tkg_kernel() {
    status "Cloning linux-tkg kernel..."
}

install_firmware() {
    status "Installing firmware packages..."

    install_packages linux-headers

    install_aur mkinitcpio-firmware

    clone_and_build "https://github.com/mahatmus-tech/uPD72020x-Firmware.git" "uPD72020x-Firmware"
}

install_ufw_firewall() {
    status "Installing firewall..."
    install_packages ufw
    sudo systemctl enable --now ufw.service
    sudo ufw enable
}

install_multimedia() {
    status "Installing multimedia support..."
    install_packages \
        ffmpeg gstreamer gstreamer-vaapi gst-libav \
		gst-plugins-bad gst-plugins-good gst-plugins-ugly \
        libmpeg2 libmad lame flac wavpack opus faac faad2 \
        x264 x265 libvpx dav1d aom ffmpegthumbs
}

install_bluetooth() {
    status "Installing bluetooth support..."
    install_packages \
		bluez bluez-plugins	bluez-utils	bluez-hid2hci bluez-libs
}

install_compressions() {
    status "Installing compressions support..."
    install_packages \
        zip unzip p7zip gzip bzip2 xz \
        unrar lrzip zstd lzip lzop arj \
        cabextract cpio unace tar
}

install_fonts() {
    status "Installing fonts support..."
    install_packages \
		ttf-droid ttf-fantasque-nerd ttf-fira-code \
		ttf-jetbrains-mono ttf-jetbrains-mono-nerd \
		adobe-source-code-pro-fonts noto-fonts \
		noto-fonts-emoji otf-font-awesome
}

install_graphics() {
    status "Installing graphics support..."

    # Input & GPU Acceleration - generic
    install_packages \
		libglvnd mesa lib32-mesa libva lib32-libva \
		libvdpau lib32-libvdpau libvdpau-va-gl \
		vulkan-icd-loader lib32-vulkan-icd-loader vulkan-mesa-layers    
    
    # GPU-specific packages
    case $GPU in
        "nvidia")
			clone_and_build "https://github.com/Frogging-Family/nvidia-all.git" "nvidia-all"

            # nvidia.conf
            sudo rm -f /etc/modprobe.d/nvidia.conf
            safe_download /etc/modprobe.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/nvidia.conf
            # nvidia.rules
            sudo rm -f /etc/udev/rules.d/89-nvidia-pm.rules
            safe_download /etc/udev/rules.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/89-nvidia-pm.rules	 
            # mkinitcpio.conf
            sudo sed -i -E "s|^MODULES=.*|MODULES=( nvidia nvidia_modeset nvidia_uvm nvidia_drm )|" /etc/mkinitcpio.conf

            # Old cards 
            # install_packages nvidia-dkms 
            # Turing or newer hardware only
            # install_packages nvidia-open-dkms
            #install_packages \
            #   nvidia-utils nvidia-settings nvidia-prime \
	        # lib32-nvidia-utils opencl-nvidia libva-nvidia-driver
            ;;
        "amd")
			install_packages \
				xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon
            ;;
        "intel")
			install_packages \
			    vulkan-intel lib32-vulkan-intel libva-intel-driver \
			    intel-media-sdk intel-media-driver intel-gmmlib
            ;;
    esac

    status "Installing Wayland..."
    install_packages \
        wayland wayland-protocols wayland-utils \
		lib32-wayland xorg-xwayland libinput \
		egl-wayland qt5-wayland qt6-wayland    
}

install_gaming() {
    status "Installing gaming support..."
    install_packages \
        steam goverlay gamescope gamemode \
        lib32-gamemode mangohud lib32-mangohud

    # Download gamemode.ini
    sudo rm -f /etc/gamemode.ini
    safe_download /etc https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/gamemode.ini

    if [[ "$CPU" == "amd" ]]; then
        # Enable EPP if supported
        if [[ -f "/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference" ]]; then
            sudo sed -i 's/;enable_amd_pstate_epp=1/enable_amd_pstate_epp=1/' /etc/gamemode.ini
            sudo sed -i 's/;amd_epp_profile=performance/amd_epp_profile=performance/' /etc/gamemode.ini
        else
            sudo sed -i 's/;enable_amd_pstate=1/enable_amd_pstate=1/' /etc/gamemode.ini
        fi
    fi
    systemctl --user enable --now gamemoded.service
    sudo usermod -aG gamemode "$USER"
         
    # installl proton-ge-custom
    safe_download "$HOME"/Scripts https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/proton-ge-custom-install.sh
    bash "$HOME/Scripts/proton-ge-custom-install.sh"
    
    # Wine & dependencies - https://github.com/lutris/docs/blob/master/WineDependencies.md
    install_packages wine-staging
    install_packages_asdeps \
        giflib lib32-giflib gnutls lib32-gnutls v4l-utils \
        lib32-v4l-utils libpulse lib32-libpulse alsa-plugins \
        lib32-alsa-plugins alsa-lib lib32-alsa-lib sqlite lib32-sqlite \
        libxcomposite lib32-libxcomposite ocl-icd lib32-ocl-icd libva \
        lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs \
        lib32-gst-plugins-base-libs vulkan-icd-loader \
        lib32-vulkan-icd-loader sdl2-compat lib32-sdl2-compat
    
    status "Installing controller support..."
    if ask_user "Do you want to install xpadneo? - It Improves Xbox gamepad support:"; then
        clone_and_build "https://aur.archlinux.org/xpadneo-dkms-git.git" "xpadneo-dkms-git"
    fi
    
    if ask_user "Do you want to install xone? - It improves Xbox gamepad support with a USB wireless dongle:"; then
        clone_and_build "https://aur.archlinux.org/xone-dkms-git.git" "xone-dkms-git" 
        clone_and_build "https://aur.archlinux.org/xone-dongle-firmware.git" "xone-dongle-firmware"
    fi
    
    if ask_user "Do you want to install PS5 controller support?:"; then
        clone_and_build "https://aur.archlinux.org/dualsensectl-git.git" "dualsensectl-git"
    fi
}

install_recomended_apps() {
    status "Installing recomended packages..."
    # terminal & editor
    install_packages kitty man-db man-pages fastfetch jq 
    # Linux resource monitors
    install_packages htop nvtop btop inxi duf
    # media controller & player
    install_packages playerctl mpv mpv-mpris
    # Audio Controller
    install_packages pavucontrol pamixer
    # brightness control
    install_packages brightnessctl
    # image viewer
    install_packages loupe imagemagick libspng
    # calculator
    install_packages qalculate-gtk
    # Desktop Theme
    install_packages kvantum qt5ct qt6ct qt6-svg nwg-look
    # notifications
    install_packages swaync
    # Menu Apps/Bar/Logout
    install_packages rofi-wayland waybar wlogout
    # printscreen
    install_packages slurp grim swappy
    # Copy/Paste utilities
    install_packages wl-clipboard cliphist
    # Monitor utilities
    install_packages nwg-displays
    # Wallpaper utilities
    install_packages swww
}

# ======================
# POST-INSTALL
# ======================
configure_system() {
    status "Configuring system..."
    
    # Upgrade and Synchronize packages
    sudo pacman -Syu --noconfirm
    
    # Add user to all required groups
    sudo usermod -aG wheel,video,input,audio,network,lp,storage,users,rfkill,sys "$USER"
    
    # Download scx using LAVD
    safe_download /etc/default https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/scx
    # Download optimal kernel.conf
    safe_download /usr/lib/sysctl.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/79-kernel-settings.conf
    sudo sysctl --system

    #status "Setting fstrim ..."
    # Get root filesystem type
    local root_fs_type=$(findmnt -n -o FSTYPE /)
    # Get the base device name (strip /dev/ and partition suffix)
    local root_source=$(findmnt -n -o SOURCE /)
    local root_device=$(basename "$root_source" | sed -E 's/p?[0-9]+$//')
    
    # Check for SSD or NVMe (rotational = 0)
    local is_ssd_or_nvme="false"
    if [[ -e /sys/block/$root_device/queue/rotational ]]; then
        if [[ "$(cat /sys/block/"$root_device"/queue/rotational)" == "0" ]]; then
            is_ssd_or_nvme="true"
        fi
    fi
    
    # Filesystems known to support TRIM
    #if [[ "$is_ssd_or_nvme" == "true" && \
    #      "$root_fs_type" =~ ^(ext3|ext4|btrfs|f2fs|xfs|vfat|exfat|jfs|nilfs2|ntfs-3g)$ ]]; then
    #    status "Filesystem '$root_fs_type' supports TRIM. Enabling fstrim.timer..."
    #    sudo systemctl enable --now fstrim.timer
    #fi
    
    status "Improving SSD journal performance..."
    if [[ "$is_ssd_or_nvme" == "true" ]]; then
        status "Setting ext4 root partition performance..."    
        # set async journal
        sudo tune2fs -E mount_opts=journal_async_commit $(findmnt -n -o SOURCE /)
        sudo tune2fs -o journal_data_writeback $(findmnt -n -o SOURCE /)
        # Define the UUID of the partition (adaptar para escolhera  partição)
        UUID=$(blkid -s UUID -o value $(findmnt -n -o SOURCE /))
        # Define the new mount options
        NEW_MOUNT_OPTIONS="defaults,noatime"
        # Edit the fstab file to change the mount options
        sudo sed -i -E "s|^UUID=$UUID.*|UUID=$UUID \/ ext4 $NEW_MOUNT_OPTIONS 0 2|" /etc/fstab
        # remount the root partition
        if ! sudo mount -o remount /; then
            error "Failed to remount root partition."
        fi
    fi
    
    # Reloads the systemd manager configuration
    # sudo systemctl daemon-reload
    # Regenerate Initramfs
    sudo mkinitcpio -P
}

# ======================
# MAIN INSTALLATION FLOW
# ======================
main() {
    echo -e "\n${GREEN}🚀 Starting Arch Auto Install ${NC}"
	
    # Show Menu Checker
    show_menu

    #mapfile -t SELECTIONS < selected
    #rm -f selected
    
    #for selection in "${SELECTIONS[@]}"; do
    #    case $selection in
    #        1) install_ufw_firewall ;;
    #        2) install_bluetooth ;;
    #        3) install_gaming ;;
    #        4) install_recomended_apps ;;
    #        5) install_tkg_kernel ;;
    #    esac
    #done

   # Detection phase
    detect_system
    install_base_system
    install_firmware
    install_graphics
    install_multimedia
    install_compressions
    install_fonts
    install_ufw_firewall
    install_bluetooth
    install_gaming
    install_recomended_apps
    install_tkg_kernel
    configure_system
	
    echo -e "\n${GREEN} Installation completed successfully! ${NC}"
    echo -e "${YELLOW} Please reboot your system to apply all changes. ${NC}"
}

# Execute
main
