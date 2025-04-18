#!/usr/bin/env bash

set -euo pipefail

# ======================
# GLOBAL VARIABLES
# ======================
# Default install dir
INSTALL_DIR="$HOME/Apps"
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
	1  "Install JaKooLit DotFiles" on
)

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
# INSTALLATION FUNCTIONS
# ======================
status() { echo -e "${GREEN}[+]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

show_menu() {
    dialog --clear \
        --title "Arch Hyprland Installation" \
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
    local clone_flags=$4  # No default

    status "Building $dir_name from source..."
    sudo rm -rf "$INSTALL_DIR/$dir_name"
    git clone $clone_flags "$repo_url" "$INSTALL_DIR/$dir_name" || error "Failed to clone $dir_name"
    cd "$INSTALL_DIR/$dir_name" || error "Failed to enter $dir_name directory"
    sudo chown -R "$USER":"$USER" . || error "Failed to change ownership"
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

    status "Building Hyprland..."
	install_aur hyprland-git
}

install_jakoolit() {
	JAYKOOLIT_INSTALLED=true
	status "Installing JaKooLit DotFiles..."
	INSTALL_DIR=$HOME
	clone_and_build "https://github.com/JaKooLit/Arch-Hyprland.git" "Arch-Hyprland" \
					"sudo chmod +x install.sh && ./install.sh" "--depth=1"

}	 

# ======================
# POST-INSTALL
# ======================
configure_hyprland() {
    status "Configuring Hyprland..."
	local CONFIG=""
	
	# Upgrade and Synchronize package database
	sudo pacman -Syu --noconfirm
	
	if [ "$JAYKOOLIT_INSTALLED" = true ]; then
		CONFIG="$HOME/.config/hypr/UserConfigs/Startup_Apps.conf"
		echo "exec-once = systemctl --user start gamemoded.service" >> "$CONFIG"
		
		CONFIG="$HOME/.config/hypr/UserConfigs/WindowRules.conf"
		echo "# my settings" >> "$CONFIG"
		echo "windowrulev2 = content game, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = nodim, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = noanim, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = noborder, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = noshadow, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = norounding, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = allowsinput, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = immediate, tag:games*" >> "$CONFIG"
		
		CONFIG="$HOME/.config/hypr/UserConfigs/UserSettings.conf"
		sudo sed -i -E "s|#accel_profile =|accel_profile = flat|" "$CONFIG"
		sudo sed -i -E "s|direct_scanout = 0|direct_scanout = 2|" "$CONFIG"
		# Enable Anti Flicker
		#sudo sed -i -E "s|#opengl {|opengl {|" "$CONFIG"
		#sudo sed -i -E "s|#  nvidia_anti_flicker = true|  nvidia_anti_flicker = true|" "$CONFIG"
		#sudo sed -i -E "s|#}|}|" "$CONFIG" 

		CONFIG="$HOME/.zprofile"
  		sudo sed -i -E "s/#/ /g" "$CONFIG"

		if [ "$GPU" = "nvidia" ]; then
			CONFIG="$HOME/.config/hypr/UserConfigs/ENVariables.conf"
			# Force GBM as a backend
			echo "# my settings" >> "$CONFIG"
			echo "env = GBM_BACKEND,nvidia-drm" >> "$CONFIG"
			echo "env = __GLX_VENDOR_LIBRARY_NAME,nvidia" >> "$CONFIG"

			# Hardware acceleration on NVIDIA GPUs
			echo "env = LIBVA_DRIVER_NAME,nvidia" >> "$CONFIG" 
		fi

		# Correct SDDM login stuck bug 
		#local card_code=$(lspci -nn | grep -E "RTX|GTX" | awk '{print $1}')
		#local gpu_card=$(readlink /dev/dri/by-path/pci-0000:"${card_code}"-card | xargs basename)
		#echo "env = WLR_DRM_DEVICES=/dev/dri/$gpu_card" >> "$CONFIG"
 	else
		# Path to Hyprland config file
		CONFIG="$HOME/.config/hypr/hyprland.conf"
		
		# Startup - wayland
		echo "exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP" >> "$CONFIG"
		echo "exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP" >> "$CONFIG"

        # Startup - Apss
		echo "exec-once = waybar" >> "$CONFIG"
		echo "exec-once = swaync" >> "$CONFIG"
		echo "exec-once = blueman-applet" >> "$CONFIG"
		echo "exec-once = wl-paste --type text --watch cliphist store" >> "$CONFIG"
		echo "exec-once = wl-paste --type image --watch cliphist store" >> "$CONFIG"		
		echo "exec-once = hypridle" >> "$CONFIG"
		echo "exec-once = systemctl --user start gamemoded.service" >> "$CONFIG"

		# Environment variables
		if [ "$GPU" = "nvidia" ]; then
		    # Force GBM as a backend
			echo "env = GBM_BACKEND,nvidia-drm" >> "$CONFIG"
			echo "env = __GLX_VENDOR_LIBRARY_NAME,nvidia" >> "$CONFIG"
			# Hardware acceleration on NVIDIA GPUs
			echo "env = LIBVA_DRIVER_NAME,nvidia" >> "$CONFIG"		
		fi

		# game tags
		echo "windowrulev2 = tag +games, class:^(gamescope)$" >> "$CONFIG"
		echo "windowrulev2 = tag +games, class:^(steam_app_\d+)$" >> "$CONFIG"
		echo "windowrulev2 = content game, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = nodim, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = noanim, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = noborder, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = noshadow, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = norounding, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = allowsinput, tag:games*" >> "$CONFIG"
		echo "windowrulev2 = immediate, tag:games*" >> "$CONFIG"		
 	fi 
}

# ======================
# MAIN INSTALLATION FLOW
# ======================
main() {
	echo -e "\n${GREEN}🚀 Starting Hyprland Install ${NC}"
	
    if ! command -v dialog &> /dev/null; then
        echo -e "${YELLOW}Installing dialog for menu interface...${NC}"
        install_packages dialog
    fi

    # Show Menu Checker
    show_menu

    mapfile -t SELECTIONS < selected
    rm -f selected

    detect_system    
	install_hyprland

    for selection in "${SELECTIONS[@]}"; do
        case $selection in
            1)  install_jakoolit ;;
        esac
    done

	configure_hyprland
	
	echo -e "\n${GREEN} Installation completed successfully! ${NC}"
	echo -e "${YELLOW} Please reboot your system to apply all changes. ${NC}"
}

# Execute
main