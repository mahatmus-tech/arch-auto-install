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
    "base"        "> Install Base Packages/Settings"    "ON"
    "firmware"    "> Install Firmwares"                 "ON"
    "firewall"    "> Install UFW Firewall"              "ON"
    "audio"       "> Install Audio Drivers"             "ON"
    "bluetooth"   "> Install Bluetooth Drivers"         "ON"
    "fonts"       "> Install Fonts"                     "ON"
    "multimedia"  "> Install Multimedia Support"        "ON"
    "compression" "> Install compressions Support"      "ON"
    "gpu"         "> Install Graphics Drivers"          "ON"
    "gaming"      "> Install Gaming Apps"               "ON"
    "performance" "> Install Performance System Tweaks" "ON"
    "apps"        "> Install Recommended Wayland Apps"  "ON"
)

# ======================
# INSTALLATION FUNCTIONS
# ======================
info()             { echo -e "${BLUE}[i]${NC} $1"; }
warning()          { echo -e "${YELLOW_W}[!]${NC} $1"; }
error()            { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
status()           { echo -e "${GREEN}[+]${YELLOW} $1${NC}"; }
status_step()      { echo -e "${GREEN}    >${NC} $1"; }
status_step_info() { echo -e "${BLUE}      $1"; }


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
    status "Detecting System Hardware"
    
    if ! [ -d /run/systemd/system ]; then
        error "This script is only compatible with Systemd-Boot"
    fi

    status_step "File System Type"
    # ----------------------------
    ROOT_FS_TYPE=$(findmnt -n -o FSTYPE /)
    status_step_info "$ROOT_FS_TYPE"
    # ----------------------------
    
    status_step "Disk Type"
    # ---------------------
    # Get the base device name (strip /dev/ and partition suffix)
    local root_source=$(findmnt -n -o SOURCE /)
    local root_device=$(basename "$root_source" | sed -E 's/p?[0-9]+$//')

    # Check for SSD or NVMe (rotational = 0)
    SSD_OR_NVME_DISK="false"
    if [[ -e /sys/block/$root_device/queue/rotational ]]; then
        if [[ "$(cat /sys/block/"$root_device"/queue/rotational)" == "0" ]]; then
            SSD_OR_NVME_DISK="true"
        fi
    fi

    if [[ "$SSD_OR_NVME_DISK" == "true" ]]; then
        status_step_info "$Found SSD/NVME Disk"
    else
        status_step_info "$Found HD Disk"
    fi    
    # ---------------------

    status_step "CPU"
    # ---------------
    if grep -iq "intel" /proc/cpuinfo; then
        export CPU="intel"
        status_step_info "Intel CPU has been found"
    elif grep -iq "amd" /proc/cpuinfo; then
        export CPU="amd"
        status_step_info "AMD CPU has been found"
    else
        export CPU="unknown"
        warning "Unknown CPU type"
    fi
    # ---------------

    status_step "GPU"
    if lspci | grep -iq "nvidia"; then
        export GPU="nvidia"
        status_step_info "NVIDIA GPU has been found"
    elif lspci | grep -iq "amd"; then
        export GPU="amd"
        status_step_info "AMD GPU has been found"
    elif lspci | grep -iq "intel"; then
        export GPU="intel"
        status_step_info "Intel GPU has been found"
    else
        export GPU="unknown"
        warning "Unknown GPU - installing basic drivers"
    fi
}

# ======================
# INSTALLATION SECTIONS
# ======================
install_base() {
    status "Installing Base Requirements"

    status_step "Default Directories"
    mkdir -p "$HOME"/{Downloads,Documents,Pictures,Projects,.config,Apps,Scripts}

    status_step "User Privileges"
    sudo usermod -aG wheel,video,input,audio,network,lp,storage,users,rfkill,sys "$USER"    

    status_step "Pacman Settings"
    # ---------------------------
    sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
    sudo sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    sudo sed -i 's/^#ILoveCandy/ILoveCandy/' /etc/pacman.conf    
    sudo pacman -Syuq --needed --noconfirm --noprogressbar >/dev/null

    install_packages pacman-contrib
    sudo systemctl enable --now paccache.timer    
    # ---------------------------

    status_step "YAY (AUR)"
    clone_and_build "https://aur.archlinux.org/yay.git" "yay"

    status_step "Base Packages"
    pkgs=(
        git 
        base-devel
        curl
        python
        wget
        meson
        systemd
        dbus
        libinih
        libinput
    )
    install_packages "${pkgs[@]}" 
}

install_firmware() {
    status "Installing Firmwares"

    install_packages linux-zen-headers

    status_step "mkinitcpio"
    install_aur mkinitcpio-firmware
    clone_and_build "https://github.com/mahatmus-tech/uPD72020x-Firmware.git" "uPD72020x-Firmware"
}

install_audio() {
    status "Installing Audio Support"
    
    status_step "Pipewire"    
    pkgs=(
        pipewire
        pipewire-alsa
        pipewire-jack
        pipewire-pulse
    )
    install_packages "${pkgs[@]}"


    status_step "Alsa"
    pkgs=(
        alsa-utils
        alsa-firmware
        alsa-ucm-conf
        alsa-plugins
        lib32-alsa-plugins        
    )
    install_packages "${pkgs[@]}"

    status_step "Others"
    pkgs=(
        rtkit
        mpg123
        lib32-mpg123
        sof-firmware
    )    
    install_packages "${pkgs[@]}"
}

install_multimedia() {
    status "Installing Multimedia Support"

    status_step "Gstreamer"
    pkgs=(
        gstreamer
        gstreamer-vaapi
    )    
    install_packages "${pkgs[@]}"

    status_step "Gst"
    pkgs=(
        gst-libav
        gst-plugins-base
        gst-plugins-good
        gst-plugins-bad
        gst-plugins-ugly
        gst-plugin-pipewire
        gst-plugins-base-libs
        lib32-gst-plugins-base-libs
    )
    install_packages "${pkgs[@]}"

    status_step "Codecs"
    pkgs=(
        aom
        lame
        flac
        opus
        faac
        x264
        x265
        dav1d
        faad2
        ffmpeg
        libvpx
        libmad
        wavpack
        libmpeg2
        ffmpegthumbs
    )
    install_packages "${pkgs[@]}"    
}

install_compressions() {
    status "Installing Compression Support"

    status_step "Zip"
    pkgs=(
        zip
        gzip
        lzip
        unzip
        p7zip
        lrzip
        bzip2
        unrar
    )
    install_packages "${pkgs[@]}"

    status_step "Others"
    pkgs=(
        xz
        arj
        tar
        cpio
        zstd
        lzop
        unace
        cabextract
    )
    install_packages "${pkgs[@]}"    
}

install_fonts() {
    status "Installing Fonts"

    status_step "TTF"
    pkgs=(
		ttf-droid
        ttf-fira-code
        ttf-liberation
        ttf-fantasque-nerd
		ttf-jetbrains-mono
        ttf-jetbrains-mono-nerd
    )
    install_packages "${pkgs[@]}"

    status_step "NOTO"
    pkgs=(
        noto-fonts
        noto-fonts-emoji
    )    
    install_packages "${pkgs[@]}"

    status_step "Others"
    pkgs=(
        otf-font-awesome
		adobe-source-code-pro-fonts
    )
    install_packages "${pkgs[@]}"
}

install_firewall() {
    status "Installing Firewall"

    status_step "UFW"
    install_packages ufw

    status_step "UFW Serice"
    sudo systemctl enable --now ufw.service
    sudo ufw enable
}

install_bluetooth() {
    status "Installing Bluetooth Support"

    status_step "Bluez"
    pkgs=(
        blueman
		bluez
        bluez-libs
        bluez-utils
        bluez-hid2hci
        bluez-plugins
    )
    install_packages "${pkgs[@]}"
}

install_graphics() {
    status "Installing Graphic Drivers"

    case $GPU in
        "amd")
            status_step "AMD Driver"

			pkgs=(
				xf86-video-amdgpu
                vulkan-radeon
                lib32-vulkan-radeon
            )
            install_packages "${pkgs[@]}"
            ;;
        "intel")
            status_step "Intel Driver"

			pkgs=(
                intel-gmmlib
                intel-media-sdk
                intel-media-driver
                libva-intel-driver
			    vulkan-intel
                lib32-vulkan-intel
            )
            install_packages "${pkgs[@]}"
            ;;    
        "nvidia")            
            status_step "Nvidia Driver"

			clone_and_build "https://github.com/Frogging-Family/nvidia-all.git" "nvidia-all" \
                            "{ printf "1\n"; printf "1\n"; printf "N\n"; } | makepkg -si --needed --noconfirm --noprogressbar"

            install_packages libva-nvidia-driver
            
            #pkgs=(
            #    nvidia-utils
            #    opencl-nvidia
            #    nvidia-settings
            #    nvidia-open-dkms
            #    lib32-nvidia-utils
            #    lib32-opencl-nvidia
            #    libva-nvidia-driver
            #)
            #install_packages "${pkgs[@]}"

            status_step "Nvidia Config File"
            sudo rm -f /etc/modprobe.d/nvidia.conf
            safe_download /etc/modprobe.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/nvidia.conf

            status_step "Nvidia Rule File"
            sudo rm -f /etc/udev/rules.d/89-nvidia-pm.rules
            safe_download /etc/udev/rules.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/89-nvidia-pm.rules	 

            status_step "Mkinitcpio Nvidia Modules"
            sudo sed -i -E "s|^MODULES=.*|MODULES=( nvidia nvidia_modeset nvidia_uvm nvidia_drm )|" /etc/mkinitcpio.conf
            ;;
    esac

    status_step "GPU Acceleration"
    pkgs=(
        gtk3
		mesa
        libva
        openal
        giflib
        ocl-icd
        libxslt
        libglvnd
		libvdpau
        libvdpau-va-gl
        libjpeg-turbo
        opencl-icd-loader
        vulkan-tools
		vulkan-icd-loader
        vulkan-mesa-layers
    )
    install_packages "${pkgs[@]}"
        
    # 32 Bits
    pkgs=(
        lib32-gtk3
		lib32-mesa
        lib32-libva
        lib32-openal
        lib32-giflib
        lib32-ocl-icd
        lib32-libxslt
        lib32-libglvnd
        lib32-libvdpau
        lib32-libjpeg-turbo
        lib32-opencl-icd-loader
        lib32-vulkan-icd-loader
        lib32-vulkan-mesa-layers
    )
    install_packages "${pkgs[@]}"

    status_step "Compatibilities"
    install_packages glfw
    install_aur vk-hdr-layer-kwin6-git
            
    status "Wayland"
    pkgs=(
        wayland
        wayland-protocols
        wayland-utils
        lib32-wayland
		egl-wayland
        qt5-wayland
        qt6-wayland        		
        xorg-xwayland
    )
    install_packages "${pkgs[@]}"
}

install_gaming() {
    status "Installing Gaming Apps"

    status "Controller Support"
    install_aur dualsensectl-git

    status_step "Gamescope"
    install_packages gamescope
        
    status_step "Mangohud"
    install_packages mangohud lib32-mangohud goverlay

    status_step "Steam"
    #---------------------
    install_packages steam protontricks
    install_aur protonup-qt
    #---------------------    
    
    status_step "Gamemode"
    #---------------------
    install_packages gamemode lib32-gamemode
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
    #---------------------

    #if ask_user "Do you want to install xpadneo? - It Improves Xbox gamepad support:"; then
    #    install_aur xpadneo-dkms-git
    #fi
    
    #if ask_user "Do you want to install xone? - It improves Xbox gamepad support with a USB wireless dongle:"; then
    #    install_aur xone-dkms-git xone-dongle-firmware
    #fi
    
    #if ask_user "Do you want to install PS5 controller support?:"; then
    #    install_aur dualsensectl-git
    #fi
}

install_apps() {
    status "Installing Recomended Apps"

    status_step "terminal & editor"
    install_packages kitty man-db man-pages fastfetch jq 

    status_step "Linux resource monitors"
    install_packages htop nvtop btop inxi duf

    status_step "media controller & player"
    install_packages playerctl mpv mpv-mpris

    status_step "Audio Controller"
    install_packages pavucontrol pamixer

    status_step "brightness control"
    install_packages brightnessctl

    status_step "image viewer"
    install_packages loupe imagemagick libspng

    status_step "calculator"
    install_packages qalculate-gtk

    status_step "Desktop Theme"
    install_packages kvantum qt5ct qt6ct qt6-svg nwg-look

    status_step "notifications"
    install_packages swaync

    status_step "Menu Apps/Bar/Logout"
    install_packages rofi-wayland waybar

    status_step "printscreen"
    install_packages slurp grim swappy

    status_step "Copy/Paste utilities"
    install_packages wl-clipboard cliphist

    status_step "Monitor utilities"
    install_packages nwg-displays

    status_step "Wallpaper utilities"
    install_packages swww
}

install_performance() {
    status "Installing System Performance Improvements"

    status_step "Systemd-Resolved as DNS Resolver"
    # -------------------------------
    sudo rm -f "/usr/lib/NetworkManager/conf.d/dns.conf"
    safe_download /usr/lib/NetworkManager/conf.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/dns.conf
    # -------------------------------    
    
    status_step "Scheaduler SCX LAVD"
    # -------------------------------
    install_packages scx-scheds
    sudo rm -f /etc/default/scx
    safe_download /etc/default https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/scx
    sudo systemctl enable --now scx.service
    # -------------------------------

    status_step "Kernel Settings"
    # -----------------------------------
    sudo rm -f /usr/lib/sysctl.d/79-kernel-settings.conf
    safe_download /usr/lib/sysctl.d https://raw.githubusercontent.com/mahatmus-tech/arch-auto-install/refs/heads/main/files/79-kernel-settings.conf
    sudo sysctl --system
    # -----------------------------------
    
    if [[ "$SSD_OR_NVME_DISK" == "true" && "$ROOT_FS_TYPE" == "ext4" ]]; then
        status_step "EXT4 Journal Performance"

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
}

# ======================
# MAIN INSTALLATION FLOW
# ======================
main() {
    echo -e "\n${GREEN}🚀 Starting Arch Auto Install ${NC}"

	sudo_cache
    show_menu
    detect_system
    
    for option in "${options[@]}"; do
        case "$option" in
            base)        install_base ;;
            firmware)    install_firmware ;;
            firewall)    install_firewall ;;
            audio)       install_audio ;;
            bluetooth)   install_bluetooth ;;
            fonts)       install_fonts ;;
            multimedia)  install_multimedia ;;
            compression) install_compressions ;;
            gpu)         install_graphics ;;
            gaming)      install_gaming ;;
            performance) install_performance ;;
            apps)        install_apps ;;
            *)           echo "Unknown option: $option" ;;
        esac
    done

    echo -e "\n${GREEN} Installation completed successfully! ${NC}"
    echo -e "${YELLOW} Please reboot your system to apply all changes. ${NC}"
}

# Execute
main