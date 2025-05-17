#!/usr/bin/env bash

set -euo pipefail

# ======================
# GLOBAL VARIABLES
# ======================
# Default install dir
INSTALL_DIR="$HOME/Apps"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
YELLOW_W='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Initialize the options array for whiptail checklist
options_command=(
    whiptail --title "Select Options" --checklist "Choose options to install or configure\nNOTE: 'SPACEBAR' to select & 'TAB' key to change selection" 14 68 6
)

# Add the remaining static options
options_command+=(
    "gpu"        "> Install GPU Drivers"              "ON"
    "firewall"   "> Install UFW Firewall"             "ON"
    "bluetooth"  "> Install Bluetooth Drivers"        "ON"
    "gaming"     "> Install Gaming Apps & Settings"   "ON"
    "apps"       "> Install Recommended Apps"         "ON"
    "tkg"        "> Install TKG Kernel(! LONG TIME)"  "ON"
)

# ======================
# INSTALLATION FUNCTIONS
# ======================
status() { echo -e "${GREEN}[+]${YELLOW} $1${NC}"; }
status_step() { echo -e "${GREEN}    >${NC} $1"; }
warning() { echo -e "${YELLOW_W}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

sudo_cache() {
    status "Caching Sudo Password"
    # Prompt once for sudo password
    if sudo -v; then
    # Keep the sudo session alive in the background
    while true; do
        sleep 60
        sudo -n true
        kill -0 "$$" || exit
    done 2>/dev/null &
    else
    echo "Sudo authentication failed"
    exit 1
    fi    
}

install_packages() {    
    local pkg
    for pkg in "$@"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            status_step "$pkg"
            sudo pacman -S -qq --needed --noconfirm --noprogressbar "$pkg" 2>/dev/null || {
                warning "Failed to install $pkg. Continuing..."
                return 1
            }
        fi
    done
}

install_aur() {
    local pkg
    for pkg in "$@"; do
        if ! yay -Qi "$pkg" &>/dev/null; then
            status_step "$pkg"
            yay -S -qq --needed --noconfirm --noprogressbar "$pkg" 2>/dev/null || {
                warning "Failed to install $pkg. Continuing..."
                return 1
            }
        fi
    done
}

install_packages_asdeps() {    
    local pkg
    for pkg in "$@"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            status_step "$pkg"
            sudo pacman -S -qq --needed --noconfirm --noprogressbar --asdeps "$pkg" 2>/dev/null || {
                warning "Failed to install $pkg. Continuing..."
                return 1
            }
        fi
    done
}

clone_and_build() {
    local repo_url=$1
    local dir_name=$2
    local build_cmd=${3:-"makepkg -si --needed --noconfirm --noprogressbar"}

    status_step "$dir_name"
    sudo rm -rf "$INSTALL_DIR/$dir_name"
    git clone -q "$repo_url" "$INSTALL_DIR/$dir_name" || error "Failed to clone $dir_name"
    cd "$INSTALL_DIR/$dir_name" || error "Failed to enter $dir_name directory"
    sudo chown -R "$USER" . || error "Failed to change ownership"
    sudo chmod -R 755 . || error "Failed to change permissions"
    eval "$build_cmd" || warning "Failed to build/install $dir_name"
    cd - >/dev/null || error "Failed to return to previous directory"
}

show_menu() {
    install_packages libnewt
    
    # Capture the selected options before the while loop starts
    while true; do
        selected_options=$("${options_command[@]}" 3>&1 1>&2 2>&3)

        # Check if the user pressed Cancel (exit status 1)
        if [ $? -ne 0 ]; then
            echo -e "\n"
            echo "You cancelled the selection. Goodbye!"
            exit 0  # Exit the script if Cancel is pressed
        fi

        # If no option was selected, notify and restart the selection
        if [ -z "$selected_options" ]; then
            whiptail --title "Warning" --msgbox "No options were selected. Please select at least one option." 10 60
            continue  # Return to selection if no options selected
        fi

        # Strip the quotes and trim spaces if necessary (sanitize the input)
        selected_options=$(echo "$selected_options" | tr -d '"' | tr -s ' ')

        # Convert selected options into an array (preserving spaces in values)
        IFS=' ' read -r -a options <<< "$selected_options"

        break
    done
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
    status "Detecting System Hardware..."
    
    if ! [ -d /run/systemd/system ]; then
        error "This script is only compatible with Systemd-Boot"
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
    status "Installing Base Requirements..."
    # Update packages
    sudo pacman -Syuq --needed --noconfirm --noprogressbar >/dev/null

    status_step "Pacman Settings"
    sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
    sudo sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    sudo sed -i 's/^#ILoveCandy/ILoveCandy/' /etc/pacman.conf

    # Base packages
    install_packages git base-devel curl python wget meson systemd dbus libinih
    # scheaduler
    install_packages scx-scheds
    sudo systemctl enable --now scx.service
    # pacman tool
    install_packages pacman-contrib
    sudo systemctl enable --now paccache.timer
    
    clone_and_build "https://aur.archlinux.org/yay.git" "yay"

    status_step "Default Directories"
    mkdir -p "$HOME"/{Downloads,Documents,Pictures,Projects,.config,Apps,Scripts}
}

install_firmware() {
    status "Installing Firmwares..."

    install_packages linux-headers

    install_aur mkinitcpio-firmware

    clone_and_build "https://github.com/mahatmus-tech/uPD72020x-Firmware.git" "uPD72020x-Firmware"
}

install_multimedia() {
    status "Installing Multimedia Support..."
    install_packages \
        ffmpeg gstreamer gstreamer-vaapi gst-libav \
		gst-plugins-bad gst-plugins-good gst-plugins-ugly \
        libmpeg2 libmad lame flac wavpack opus faac faad2 \
        x264 x265 libvpx dav1d aom ffmpegthumbs
}

install_compressions() {
    status "Installing Compressions Support..."
    install_packages \
        zip unzip p7zip gzip bzip2 xz \
        unrar lrzip zstd lzip lzop arj \
        cabextract cpio unace tar
}

install_fonts() {
    status "Installing Fonts..."
    install_packages \
		ttf-droid ttf-fantasque-nerd ttf-fira-code \
		ttf-jetbrains-mono ttf-jetbrains-mono-nerd \
		adobe-source-code-pro-fonts noto-fonts \
		noto-fonts-emoji otf-font-awesome
}

install_ufw_firewall() {
    status "Installing UFW Firewall..."
    install_packages ufw

    status_step "UFW Serice"
    sudo systemctl enable --now ufw.service
    sudo ufw enable
}

install_bluetooth() {
    status "Installing Bluetooth Support..."
    install_packages \
		bluez bluez-plugins	bluez-utils	bluez-hid2hci bluez-libs
}

install_graphics() {
    status "Installing GPU Acceleration..."
    install_packages \
		libglvnd mesa lib32-mesa libva lib32-libva \
		libvdpau lib32-libvdpau libvdpau-va-gl \
		vulkan-icd-loader lib32-vulkan-icd-loader \
        vulkan-mesa-layers vulkan-tools
    
    # GPU-specific packages
    case $GPU in
        "nvidia")
            status "Installing Nvidia Graphic Drivers..."
			#clone_and_build "https://github.com/Frogging-Family/nvidia-all.git" "nvidia-all" \
            #                "{ printf "1\n"; printf "1\n"; printf "N\n"; } | makepkg -si --needed --noconfirm --noprogressbar"

            install_packages \
                nvidia-open-dkms lib32-nvidia-utils lib32-opencl-nvidia \
                nvidia-settings opencl-nvidia nvidia-utils libva-nvidia-driver

            status_step "nvidia.conf"
            sudo rm -f /etc/modprobe.d/nvidia.conf
            safe_download /etc/modprobe.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/nvidia.conf

            status_step "nvidia.rules"
            sudo rm -f /etc/udev/rules.d/89-nvidia-pm.rules
            safe_download /etc/udev/rules.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/89-nvidia-pm.rules	 

            status_step "mkinitcpio.conf"
            sudo sed -i -E "s|^MODULES=.*|MODULES=( nvidia nvidia_modeset nvidia_uvm nvidia_drm )|" /etc/mkinitcpio.conf
            ;;
        "amd")
            status "Installing AMD Graphic Drivers..."
			install_packages \
				xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon
            ;;
        "intel")
            status "Installing Intel Graphic Drivers..."
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
    status "Installing Gaming Apps..."
    install_packages \
        steam goverlay gamescope gamemode \
        lib32-gamemode mangohud lib32-mangohud

    install_aur protonup-qt

    # Wine & dependencies - https://github.com/lutris/docs/blob/master/WineDependencies.md
    #install_packages wine-staging
    #install_packages_asdeps \
    #    giflib lib32-giflib gnutls lib32-gnutls v4l-utils \
    #    lib32-v4l-utils libpulse lib32-libpulse alsa-plugins \
    #    lib32-alsa-plugins alsa-lib lib32-alsa-lib sqlite lib32-sqlite \
    #    libxcomposite lib32-libxcomposite ocl-icd lib32-ocl-icd libva \
    #    lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs \
    #    lib32-gst-plugins-base-libs vulkan-icd-loader \
    #    lib32-vulkan-icd-loader sdl2-compat lib32-sdl2-compat    

    status "Installing Gaming Settings..."
    status_step "gamemode.ini"
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

    status_step "Gamemode Service"
    systemctl --user enable --now gamemoded.service
    sudo usermod -aG gamemode "$USER"

    status_step "Mangohud.conf"
    sudo rm -f "$HOME/.config/MangoHud/MangoHud.conf"
    safe_download "$HOME"/.config/MangoHud https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/MangoHud.conf
    
    
    status "Installing Controller Support..."
    if ask_user "Do you want to install xpadneo? - It Improves Xbox gamepad support:"; then
        install_aur xpadneo-dkms-git
    fi
    
    if ask_user "Do you want to install xone? - It improves Xbox gamepad support with a USB wireless dongle:"; then
        install_aur xone-dkms-git xone-dongle-firmware
    fi
    
    if ask_user "Do you want to install PS5 controller support?:"; then
        install_aur dualsensectl-git
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
    install_packages rofi-wayland waybar
    # printscreen
    install_packages slurp grim swappy
    # Copy/Paste utilities
    install_packages wl-clipboard cliphist
    # Monitor utilities
    install_packages nwg-displays
    # Wallpaper utilities
    install_packages swww
}

install_tkg_kernel() {
    status "Installing Linux-Tkg Kernel..."
    clone_and_build "https://github.com/Frogging-Family/linux-tkg.git" "linux-tkg" \
                    "makepkg -si"
    # create a .conf in /boot/loader/entries
    safe_download /boot/loader/entries https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/linux-tkg.conf
    local root_partuuid=$(blkid -s PARTUUID -o value "$(findmnt -no SOURCE /)")
    sudo sed -i -E "s|PATITION_ID|$root_partuuid|" /boot/loader/entries/linux-tkg.conf
    sudo sed -i -E "s|PATITION_ID|$root_partuuid|" /boot/loader/entries/linux-tkg-fallback.conf
    sudo bootctl set-default linux-tkg.conf

    # Download bore kernel.conf
    safe_download /usr/lib/sysctl.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/69-bore-scheduler.conf
    sudo sysctl --system
}

# ======================
# POST-INSTALL
# ======================
configure_system() {
    status "Configuring system..."
    
    status_step "Add user to all required groups"
    sudo usermod -aG wheel,video,input,audio,network,lp,storage,users,rfkill,sys "$USER"
    
    status_step "Set SCX = LAVD"
    sudo rm -f /etc/default/scx
    safe_download /etc/default https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/scx
    # Download optimal kernel.conf
    safe_download /usr/lib/sysctl.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/79-kernel-settings.conf
    sudo sysctl --system


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
    
    if [[ "$is_ssd_or_nvme" == "true" && "$root_fs_type" == "ext4" ]]; then
        status_step "Improving EXT4 Journal Performance"
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
    status_step "Regenerate Initramfs"
    sudo mkinitcpio -P >/dev/null
}

# ======================
# MAIN INSTALLATION FLOW
# ======================
main() {
    echo -e "\n${GREEN}🚀 Starting Arch Auto Install ${NC}"
	sudo_cache

    show_menu

    detect_system
    install_base_system
    install_firmware
    install_multimedia
    install_compressions
    install_fonts

    for option in "${options[@]}"; do
        case "$option" in
            gpu)
                install_graphics
                ;;
            firewall)
                install_ufw_firewall
                ;;
            bluetooth)
                install_bluetooth
                ;;
            gaming)
                install_gaming
                ;;
            apps)
                install_recomended_apps
                ;;
            tkg)
                install_tkg_kernel
                ;;
            *)
                echo "Unknown option: $option"
                ;;
        esac
    done    

    configure_system

    echo -e "\n${GREEN} Installation completed successfully! ${NC}"
    echo -e "${YELLOW} Please reboot your system to apply all changes. ${NC}"
}

# Execute
main
