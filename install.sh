#!/usr/bin/env bash

set -euo pipefail

# ======================
# CONFIGURATION
# ======================
INSTALL_DIR="~/Apps"
# Set log file path
export LOG_FILE="/var/log/arch_auto_install_$(date "+%Y%m%d-%H%M%S").log"

# Menu configuration
MENU_OPTIONS=(
    1  "Base System"          on
    2  "TKG Zen3 Kernel"      off
    3  "Extra Package Mgrs"   on
    4  "Firmware"             on
    5  "Audio"                on
    6  "Multimedia"           on
    7  "Bluetooth"            on
    8  "Compression Tools"    on
    9  "Fonts"                on
    10 "Graphics Stack"       on
    11 "Wayland"              on
    12 "Xorg"                 off
    13 "Gaming"               on
    14 "Apps"                 on
    15 "System Configuration" on
)

# ======================
# COLOR OUTPUT FUNCTIONS
# ======================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

show_menu() {
    dialog --clear \
        --title "Arch Auto Installation" \
        --checklist "Select components to install:" 20 60 15 \
        "${MENU_OPTIONS[@]}" 2>selected
}

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

ask_user() {
	while [true]
	do
		read -rp "$1 [y/n]: " choice
		if [ "${choice,,}" in YES|yes|y|Y ]; then
			info "Continuing..."
			return 0
		elif [ "${choice,,}" in No|no|n|N ]; then
			info "Skipping..."
			return 1
		else
			info "Please answer y or n."
		fi
	done
}

# ======================
# INSTALLATION SECTIONS
# ======================
install_base_system() {
	status "Updating system and installing base packages..."
	
	status "Changing pacman settings..."
	sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
	sudo sed -i 's/^#VerbosePkgLists$/VerbosePkgLists/' /etc/pacman.conf
	sudo sed -i 's/^#ILoveCandy$/ILoveCandy/' /etc/pacman.conf
	
	# Update packages
	sudo pacman -Syu --needed --noconfirm
	# Base packages
	install_packages git base-devel curl python wget meson systemd dbus libinih
	# firmware
	install_packages ufw
	# scheaduler
	install_packages scx-scheds
	# pacman tool
	install_packages pacman-contrib
	
	# Create user directories
	mkdir -p ~/{Downloads,Documents,Pictures,Projects,.config,Apps,Scrips}
}

install_tkg_zen3_kernel() {
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
    clone_and_build "https://aur.archlinux.org/yay-bin.git" "yay-bin"
    $YAY_INSTALLED=true

    status "Installing flatpak..."
    install_packages flatpak
    $FLATPAK_INSTALLED=true

    status "Installing snap..."
    clone_and_build "https://aur.archlinux.org/snapd.git" "snapd"
    $SNAP_INSTALLED=true
    sudo systemctl enable --now snapd.socket
    sudo ln -s /var/lib/snapd/snap /snap
}

install_firmware() {
    status "Installing firmware packages..."
    
    case $CPU in
        "intel") install_packages intel-ucode;;
        "amd") install_packages amd-ucode;;
    esac

    install_packages sof-firmware alsa-firmware
	
    clone_and_build "https://aur.archlinux.org/mkinitcpio-firmware.git" "mkinitcpio-firmware"
    clone_and_build "https://github.com/mahatmus-tech/uPD72020x-Firmware.git" "uPD72020x-Firmware"
}

install_audio() {
    status "Installing audio packages..."
	# remove conflicting packages
	sudo pacman -R --noconfirm jack2
    # install audio packages
    install_packages \
		pipewire pipewire-alsa pipewire-jack pipewire-pulse \
		lib32-pipewire alsa-utils alsa-plugins alsa-ucm-conf \
		gst-plugin-pipewire wireplumber pavucontrol pamixer
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

install_graphics_stack() {
    status "Installing graphics stack for $GPU..."

    # Input & GPU Acceleration - generic
    install_packages \
		libglvnd mesa lib32-mesa libva lib32-libva \
		libvdpau lib32-libvdpau libvdpau-va-gl \
		vulkan-icd-loader lib32-vulkan-icd-loader vulkan-mesa-layers    
    
    # GPU-specific packages
    case $GPU in
        "nvidia")
	    $NVIDIA_INSTALLED=true
	    clone_and_build "https://github.com/Frogging-Family/nvidia-all.git" "nvidia-all"
            # Old cards 
            # install_packages nvidia-dkms 
            # Turing or newer hardware only
            # install_packages nvidia-open-dkms
            #install_packages \
            #   nvidia-utils nvidia-settings nvidia-prime \
	    #	lib32-nvidia-utils opencl-nvidia libva-nvidia-driver
            ;;
        "amd")
	install_packages \
		xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon
            ;;
        "intel")
            install_packages \
                vulkan-intel lib32-vulkan-intel libva-intel-driver
		intel-media-sdk intel-media-driver intel-gmmlib
            ;;
    esac
}

install_wayland() {
    status "Installing Wayland..."
    $WAYLAND_INSTALLED=true
    install_packages \
        wayland wayland-protocols wayland-utils \
		lib32-wayland xorg-xwayland libinput \
		egl-wayland qt5-wayland qt6-wayland
}

install_xorg() {
    status "Installing Xorg..."
    install_packages \
        xf86-input-libinput xorg-server xorg-xinit xorg-xinput egl-x11
}

install_gaming() {
	status "Installing gaming support..."
	$GAMING_INSTALLED=true
	install_packages \
		steam goverlay gamescope gamemode \
		lib32-gamemode mangohud lib32-mangohud
		 
	# installl proton-ge-custom
	sudo wget -P ~/Scripts https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/proton-ge-custom-install.sh
	./proton-ge-custom-install.sh
	
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
		install_packages xpadneo-dkms-git
	fi
	
	if ask_user "Do you want to install xone? - It improves Xbox gamepad support with a USB wireless dongle:"; then
		install_packages xone-dkms-git xone-dongle-firmware
	fi
	
	if ask_user "Do you want to install PS5 controller support?:"; then
		install_packages dualsensectl-git
	fi
}

install_apps() {
	status "Installing optional packages..."
	# terminal & editor
	install_packages micro kitty man-db man-pages fastfetch jq
	# coding
	install_packages bash-completion
	# Linux resource monitors
	install_packages htop nvtop btop inxi duf
	# RDP client
	install_packages rdesktop
	# media controller & player
	install_packages playerctl mpv mpv-mpris
	# brightness control
	install_packages brightnessctl
	# image viewer
	install_packages loupe imagemagick libspng
	# calculator
	install_packages qalculate-gtk
	# Desktop Theme
	install_packages kvantum qt5ct qt6ct qt6-svg
	# notifications
	install_packages swaync
	# docker
	install_packages docker docker-compose 
	# Wayland apps
	if [ "$WAYLAND_INSTALLED" = true ]; then
		install_packages \
			grim slurp waybar wl-clipboard cliphist \
			nwg-displays swappy swww wlogout emacs-wayland
	fi
	
	if [ "$YAY_INSTALLED" = true ]; then
		install_aur brave-bin teams-for-linux
	fi
	
	if [ "$FLATPAK_INSTALLED" = true ]; then
		flatpak install -y flathub dev.vencord.Vesktop
		flatpak install -y com.freerdp.FreeRDP
	fi
	
	if [ "$SNAP_INSTALLED" = true ]; then
		sudo snap install spotify
	fi
}

# ======================
# POST-INSTALL
# ======================
configure_system() {
    status "Configuring system..."
	
	# Upgrade and Synchronize package database
	sudo pacman -Syyu --noconfirm
	
	# Detect actual user even if script is run with sudo
	local target_user="${SUDO_USER:-$USER}"
	# Add user to all required groups in one go (remove duplicates)
	sudo usermod -aG wheel,docker,video,input,gamemode,audio,network,lp,storage,users,rfkill,sys "$target_user"	 	
	
	# Download scx using LAVD
	sudo wget -P /etc/default https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/scx
	# Download optimal kernel.conf
	sudo wget -P /usr/lib/sysctl.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/79-kernel-settings.conf
        
    if [ "$GAMING_INSTALLED" = true ]; then
		# Download gamemode.ini
		sudo rm -f /etc/gamemode.ini
		sudo wget -P /etc https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/gamemode.ini
		# Cooler Master MM720 mouse fix
		sudo rm -f /etc/udev/rules.d/99-mm720-power.rules
		sudo wget -P /etc/udev/rules.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/99-mm720-power.rules
		# start
		sudo systemctl enable --now gamemoded.service
    fi
    
    if [ "$NVIDIA_INSTALLED" = true ]; then
	    # nvidia.conf 
		sudo rm -f /etc/modprobe.d/nvidia.conf
	    sudo wget -P /etc/modprobe.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/nvidia.conf
		# nvidia.rules
		sudo rm -f /etc/udev/rules.d/89-nvidia-pm.rules
		sudo wget -P /etc/udev/rules.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/89-nvidia-pm.rules	 
		# mkinitcpio.conf
	    sudo sed -i -E "s|^MODULES=.*|MODULES=( nvidia nvidia_modeset nvidia_uvm nvidia_drm )|" /etc/mkinitcpio.conf
    fi

    status "Setting fstrim ..."
	# Get root filesystem type
	local root_fs_type=$(findmnt -n -o FSTYPE /)
	# Get the base device name (strip /dev/ and partition suffix)
	local root_source=$(findmnt -n -o SOURCE /)
	local root_device=$(basename "$root_source" | sed -E 's/p?[0-9]+$//')
	
	# Check for SSD or NVMe (rotational = 0)
	local is_ssd_or_nvme="false"
	if [[ -e /sys/block/$root_device/queue/rotational ]]; then
	    if [[ "$(cat /sys/block/$root_device/queue/rotational)" == "0" ]]; then
		is_ssd_or_nvme="true"
	    fi
	fi
	
	# Filesystems known to support TRIM
	if [[ "$is_ssd_or_nvme" == "true" && \
	      "$root_fs_type" =~ ^(ext3|ext4|btrfs|f2fs|xfs|vfat|exfat|jfs|nilfs2|ntfs-3g)$ ]]; then
	    status "Filesystem '$root_fs_type' supports TRIM. Enabling fstrim.timer..."
	    systemctl enable fstrim.timer
	    sudo systemctl enable --now fstrim.timer    
	fi

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

    # services    
	sudo systemctl enable --now scx.service
	sudo systemctl enable --now paccache.timer
	sudo systemctl enable --now ufw.service && sudo ufw enable
}

# ======================
# MAIN INSTALLATION FLOW
# ======================
main() {
	echo -e "\n${GREEN}🚀 Starting Arch Automated Installation${NC}"
	
	# Detection phase
	detect_system

    if ! command -v dialog &> /dev/null; then
        echo -e "${YELLOW}Installing dialog for menu interface...${NC}"
        install_packages dialog
    fi

    # Show Menu Checker
    show_menu
    
    if [ ! -s selected ]; then
        error "No components selected. Exiting"
    fi

    mapfile -t SELECTIONS < selected
    rm -f selected
    
    for selection in "${SELECTIONS[@]}"; do
        case $selection in
            1)  install_base_system ;;
            2)  install_tkg_zen3_kernel ;;
            3)  install_extra_package_managers ;;
            4)  install_firmware ;;
            5)  install_audio ;;
            6)  install_multimedia ;;
            7)  install_bluetooth ;;
            8)  install_compressions ;;
            9)  install_fonts ;;
            10) install_graphics_stack ;;
            11) install_wayland ;;
            12) install_xorg ;;
            13) install_gaming ;;
            14) install_apps ;;
            15) configure_system ;;
        esac
    done
	
	echo -e "\n${GREEN}✅ Installation completed successfully!${NC}"
	echo -e "${YELLOW}Please reboot your system to apply all changes.${NC}"
	echo -e "Consider copying your dotfiles to ~/.config"
}

# Execute
main
