#!/usr/bin/env bash

set -euo pipefail


# ======================
# GLOBAL VARIABLES
# ======================
# Default install dir
INSTALL_DIR="$HOME"
# Initialization
JAYKOOLIT_INSTALLED=false
# Log file
export LOG_FILE="/var/log/arch_auto_install_hyprland_$(date "+%Y%m%d-%H%M%S").log"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Menu configuration
MENU_OPTIONS=(
	1  "Install Hyprland"          on
	2  "Install JaKooLit DotFiles" off
	3  "Configure Hyprpland"       on
)


# ======================
# INSTALLATION FUNCTIONS
# ======================
status() { echo -e "${GREEN}[+]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

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
install_hyprland() {
	status "Installing Hyprland Dependecies..."
 	# Update packages
	sudo pacman -Syu --needed --noconfirm

	status "Checking YAY..."
	# Check if the package is installed
	if $(pacman -Qi yay &>/dev/null); then
	    info "yay is installed"
	else
	    clone_and_build "https://aur.archlinux.org/yay-bin.git" "yay-bin"
	fi 
 
    install_aur \
		ninja gcc cmake meson libxcb xcb-proto xcb-util xcb-util-keysyms \
  		libxfixes libx11 libxcomposite libxrender libxcursor pixman wayland-protocols \
		cairo pango libxkbcommon xcb-util-wm xorg-xwayland libinput libliftoff libdisplay-info \
  		cpio tomlplusplus hyprlang-git hyprcursor-git hyprwayland-scanner-git xcb-util-errors \
		hyprutils-git glaze hyprgraphics-git aquamarine-git re2 hyprland-qtutils

    status "Building Hyprland..."
	clone_and_build "--recursive https://github.com/hyprwm/Hyprland" "Hyprland" \
					"make all && sudo make install"

	status "Installing must have packages..."
	# Notification/idle daemon
	install_packages swaync hypridle
	# correct xdg-desktop-portal-hyprland for screensharing
	install_aur xdg-desktop-portal-hyprland-git
	# QT Support
	install_packages hyprland-qt-support hyprland-qtutils
	# Authentication
	install_packages hyprpolkitagent
	# Screen lock
	install_packages hyprlock
	# Graphics Resources
	install_packages hyprgraphics
	# Cursor library
	install_packages hyprcursor
}

install_jakoolit() {
	JAYKOOLIT_INSTALLED=true
	status "Installing JaKooLit DotFiles..."
	clone_and_build "--depth=1 https://github.com/JaKooLit/Arch-Hyprland.git" "Arch-Hyprland" \
					"sudo chmod +x install.sh && ./install.sh"
}	 

# ======================
# POST-INSTALL
# ======================
configure_hyprland() {
    status "Configuring hyprland..."
	
	# Upgrade and Synchronize package database
	sudo pacman -Syyu --noconfirm
	
	if [ "$JAYKOOLIT_INSTALLED" = true ]; then
		local CONFIG="$HOME/.config/hypr/UserConfigs/Startup_Apps.conf"
		echo "exec-once = systemctl --user start gamemoded.service" >> "$CONFIG"
		
		local CONFIG="$HOME/.config/hypr/UserConfigs/WindowRules.conf"
		echo "windowrulev2 = content game, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = nodim, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = noanim, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = noborder, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = noshadow, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = norounding, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = allowsinput, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = immediate, tag:games*" >> "$CONFIG"

		local CONFIG="$HOME/.config/hypr/UserConfigs/UserSettings.conf"
        sudo sed -i -E "s|^#accel_profile =.*|#accel_profile = flat|" $CONFIG
		sudo sed -i -E "s|^direct_scanout = 0.*|direct_scanout = 2|" $CONFIG
  		sudo sed -i -E "s|^#opengl {.*|opengl {|" $CONFIG
		sudo sed -i -E "s|^#  nvidia_anti_flicker = true.*|  nvidia_anti_flicker = true|" $CONFIG	
  		sudo sed -i -E "s|^#}.*|}|" $CONFIG	
	 
 
 	else
		# Path to Hyprland config file
		local CONFIG="$HOME/.config/hypr/hyprland.conf"

		# Startup
		exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
		exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP  
        echo "exec-once = waybar" >> "$CONFIG"
		echo "exec-once = swaync" >> "$CONFIG"
  		echo "exec-once = blueman-applet" >> "$CONFIG"
		#clipboard manager
  		echo "exec-once = wl-paste --type text --watch cliphist store" >> "$CONFIG"
		echo "exec-once = wl-paste --type image --watch cliphist store" >> "$CONFIG"		
		# Starting hypridle to start hyprlock
  		echo "exec-once = hypridle" >> "$CONFIG"
        # gamemoded
		echo "exec-once = systemctl --user start gamemoded.service" >> "$CONFIG"
 	fi

	

	
	# Check if line already exists
	if grep -q "exec-once = waybar" "$CONFIG"; then
	echo "Waybar is already configured"
	exit 0
	fi
	
	# Append the line to the end of file
	echo "exec-once = waybar" >> "$CONFIG"
	echo "Added Waybar to hyprland.conf"

        
    if [ "$JAYKOOLIT_INSTALLED" = true ]; then
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
}

# ======================
# MAIN INSTALLATION FLOW
# ======================
main() {
	exec > >(tee -a "$LOG_FILE") 2>&1
 
	echo -e "\n${GREEN}🚀 Starting Arch Auto Install ${NC}"
	
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
            1)  install_hyprland ;;
            2)  install_jakoolit ;;
            3)  configure_system ;;
        esac
    done
	
	echo -e "\n${GREEN}✅ Installation completed successfully!${NC}"
	echo -e "${YELLOW}Please reboot your system to apply all changes.${NC}"
	echo -e "Consider copying your dotfiles to ~/.config"
}

# Execute
main
