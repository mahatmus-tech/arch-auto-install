#!/usr/bin/env bash

set -euo pipefail

# ======================
# GLOBAL VARIABLES
# ======================
# Default install dir
INSTALL_DIR="$HOME/Apps"
# Initialization
JAYKOOLIT_INSTALLED=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
YELLOW_W='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Initialize the options array for whiptail checklist
options_command=(
    whiptail --title "Select Options" --checklist "NOTE: 'SPACEBAR' to select & 'TAB' to navigate" 10 50 3
)

# Add the remaining static options
options_command+=(
    "hyprland"  "> Install Hyprland "           "ON"
    "jakoolit"  "> Install JaKooLit DotFiles "  "ON"
    "settings"  "> Install Hyprland Settings "  "ON"
)

# ======================
# INSTALLATION FUNCTIONS
# ======================
info()             { echo -e "${BLUE}[i]${NC} $1"; }
warning()          { echo -e "${YELLOW_W}[!]${NC} $1"; }
error()            { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
status()           { echo -e "${GREEN}[+]${YELLOW} $1${NC}"; }
status_step()      { echo -e "${GREEN}    -${NC} $1"; }
status_step_info() { echo -e "${GREEN}      >${BLUE} $1"; }


sudo_cache() {
    status "Saving Sudo Password"
    sudo -v
    
	# Allow makepkg without password (safer than editing sudoers directly)
	sudo rm -f /etc/sudoers.d/42-user-nopassword
    echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/pacman" | sudo tee /etc/sudoers.d/42-user-nopassword >/dev/null
}

sudo_release() {
	sudo rm -f /etc/sudoers.d/42-user-nopassword
}

install_packages() {
    local pkg
    for pkg in "$@"; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            sudo -v
            sudo pacman -S --needed --noconfirm --quiet "$pkg" >/dev/null 2>&1 || {
                warning "Failed to install $pkg. Continuing..."
                return 1
            }
        fi
    done
}


install_aur() {
    local pkg
    for pkg in "$@"; do
        if ! paru -Q "$pkg" &>/dev/null; then
            sudo -v
            paru -S --needed --noconfirm --quiet "$pkg" >/dev/null 2>&1 || {
                warning "Failed to install $pkg. Continuing..."
                return 1
            }
        fi
    done
}

clone_and_build() {
    local repo_url=$1
    local dir_name=$2
    local build_cmd=${3:-"makepkg -si --needed --noconfirm >/dev/null 2>&1"}
    local clone_flags=$4  # No default

    sudo rm -rf "$INSTALL_DIR/$dir_name"
	git clone "$clone_flags" "$repo_url" >/dev/null 2>&1 "$INSTALL_DIR/$dir_name" || error "Failed to clone $dir_name"
    cd "$INSTALL_DIR/$dir_name" || error "Failed to enter $dir_name directory"
    sudo chown -R "$USER":"$USER" . || error "Failed to change ownership"
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


# ======================
# SYSTEM DETECTION
# ======================
detect_system() {
    status "Detecting System Hardware"

    status_step "CPU:"
    # ---------------
    if grep -iq "intel" /proc/cpuinfo; then
        export CPU="intel"        
    elif grep -iq "amd" /proc/cpuinfo; then
        export CPU="amd"
    else
        export CPU="unknown"
        warning "Unknown CPU type"
    fi
    status_step_info "$CPU"
    # ---------------

    status_step "GPU"
    # ---------------
    if lspci | grep -iq "nvidia"; then
        export GPU="nvidia"
    elif lspci | grep -iq "amd"; then
        export GPU="amd"
    elif lspci | grep -iq "intel"; then
        export GPU="intel"
    else
        export GPU="unknown"
        warning "Unknown GPU - installing basic drivers"
    fi
    status_step_info "$GPU"
    # ---------------
}

# ======================
# INSTALLATION SECTIONS
# ======================
install_hyprland() {
	status "Installing Hyprland"

 	# Update packages
	paru -Syuq --needed --noconfirm >/dev/null

	status_step "pacman package"
	install_packages hyprland
}

install_jakoolit() {
	status "Installing JaKooLit DotFiles"

	status_step "Download Files"
	# --------------------------
	JAYKOOLIT_INSTALLED=true
	INSTALL_DIR=$HOME
    clone_and_build "https://github.com/JaKooLit/Arch-Hyprland.git" "Arch-Hyprland" \
					"sudo chmod +x install.sh" "--depth=1"
	# --------------------------

	status_step "Install"
	# -------------------
	cd "$INSTALL_DIR/Arch-Hyprland"
	# remove nvidia execution
	sudo sed -i -E "s|execute_script "nvidia.sh"|#execute_script "nvidia.sh"|" install.sh
	sudo sed -i -E "s|execute_script "nvidia_nouveau.sh"|#execute_script "nvidia_nouveau.sh"|" install.sh
	# remove reboot execution
	sudo sed -i -E "s|systemctl reboot|#systemctl reboot|" install.sh
    # install
    bash install.sh
    # -------------------
}	 

configure_hyprland() {
    status "Installing Hyprland Settings"
	local CONFIG=""
	
	if [ "$JAYKOOLIT_INSTALLED" = true ]; then
	    status_step "WindowRules"
		CONFIG="$HOME/.config/hypr/UserConfigs/WindowRules.conf"
		echo -e "\n# -----------\n# My Settings\n# -----------\n" >> "$CONFIG"

        echo -e "\n# Gaming" >> "$CONFIG"
        echo "windowrulev2 = nodim, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = noblur, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = noanim, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = noborder, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = noshadow, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = immediate, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = norounding, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = fullscreen, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = allowsinput, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = content game, tag:games*" >> "$CONFIG"
		
		status_step "UserSettings"
		CONFIG="$HOME/.config/hypr/UserConfigs/UserSettings.conf"
		sudo sed -i -E "s|#accel_profile =|accel_profile = flat|" "$CONFIG"
		sudo sed -i -E "s|direct_scanout = 0|direct_scanout = 2|" "$CONFIG"
		
		if [ "$GPU" = "nvidia" ]; then
			status_step "ENVariables (Nvidia)"
			CONFIG="$HOME/.config/hypr/UserConfigs/ENVariables.conf"
			echo -e "\n# -----------\n# My Settings\n# -----------\n" >> "$CONFIG"

			echo -e "\n# Force GBM as a backend" >> "$CONFIG"
			echo "env = GBM_BACKEND,nvidia-drm" >> "$CONFIG"
			echo "env = __GLX_VENDOR_LIBRARY_NAME,nvidia" >> "$CONFIG"

			echo -e "\n# Hardware acceleration on NVIDIA GPUs" >> "$CONFIG"
			echo "env = LIBVA_DRIVER_NAME,nvidia" >> "$CONFIG"

            echo -e "\n# VA-API hardware video acceleration on NVIDIA GPUs" >> "$CONFIG"
            echo "env = NVD_BACKEND,direct" >> "$CONFIG"
		fi
		
        # Fix SDDM Bug
		CONFIG="$HOME/.zprofile"
  		sudo sed -i -E "s/#/ /g" "$CONFIG"

		# Correct SDDM login stuck bug 
		#local card_code=$(lspci -nn | grep -E "RTX|GTX" | awk '{print $1}')
		#local gpu_card=$(readlink /dev/dri/by-path/pci-0000:"${card_code}"-card | xargs basename)
		#echo "env = WLR_DRM_DEVICES=/dev/dri/$gpu_card" >> "$CONFIG"
 	else
		# Path to Hyprland config file
		CONFIG="$HOME/.config/hypr/hyprland.conf"
		echo -e "\n# -----------\n# My Settings\n# -----------\n" >> "$CONFIG"

		status_step "Startups"

		echo -e "\n# Startup - wayland" >> "$CONFIG"
		echo "exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP" >> "$CONFIG"
		echo "exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP" >> "$CONFIG"

        echo -e "\n# Startup - Apss" >> "$CONFIG"
		echo "exec-once = waybar" >> "$CONFIG"
		echo "exec-once = swaync" >> "$CONFIG"
		echo "exec-once = blueman-applet" >> "$CONFIG"
		echo "exec-once = wl-paste --type text --watch cliphist store" >> "$CONFIG"
		echo "exec-once = wl-paste --type image --watch cliphist store" >> "$CONFIG"		
		echo "exec-once = hypridle" >> "$CONFIG"

		if [ "$GPU" = "nvidia" ]; then
            status_step "ENVariables (Nvidia)"		
			echo -e "\n# Force GBM as a backend" >> "$CONFIG"
			echo "env = GBM_BACKEND,nvidia-drm" >> "$CONFIG"
			echo "env = __GLX_VENDOR_LIBRARY_NAME,nvidia" >> "$CONFIG"

			echo -e "\n#  Hardware acceleration on NVIDIA GPUs" >> "$CONFIG"
			echo "env = LIBVA_DRIVER_NAME,nvidia" >> "$CONFIG"
            echo -e "\n#  VA-API hardware video acceleration on NVIDIA GPUs" >> "$CONFIG"
            echo "env = NVD_BACKEND,direct" >> "$CONFIG"          
		fi

        status_step "WindowRules"        

        echo -e "\n# Game Tags" >> "$CONFIG"
        echo "windowrule = tag +games, class:^(gamescope)$" >> "$CONFIG"
        echo "windowrule = tag +games, class:^(steam_app_\d+)$" >> "$CONFIG"

        echo -e "\n# Gaming" >> "$CONFIG"        
        echo "windowrulev2 = nodim, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = noblur, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = noanim, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = noborder, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = noshadow, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = immediate, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = norounding, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = fullscreen, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = allowsinput, tag:games*" >> "$CONFIG"
        echo "windowrulev2 = content game, tag:games*" >> "$CONFIG"	
 	fi 
}

# ======================
# MAIN INSTALLATION FLOW
# ======================
main() {
	echo -e "\n${GREEN}🚀 Starting Hyprland Install ${NC}\n"

	sudo_cache
    show_menu
    detect_system

    for option in "${options[@]}"; do
        case "$option" in
            hyprland)
                install_hyprland
                ;;
            jakoolit)
                install_jakoolit
                ;;
            settings)
                configure_hyprland
                ;;
            *)
                echo "Unknown option: $option"
                ;;
        esac
    done
	
    sudo_release

	echo -e "\n${GREEN} Installation completed successfully! ${NC}"
	echo -e "${YELLOW} Please reboot your system to apply all changes. ${NC}"
}

# Execute
main
