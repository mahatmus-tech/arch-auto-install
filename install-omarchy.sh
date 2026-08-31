#!/usr/bin/env bash

# =============================================================================
# install-omarchy.sh
# Post-install customization script for Omarchy
# Run after a fresh Omarchy install to apply all personal performance tweaks.
#
# Sources arch-performance-settings.sh for all DE-agnostic system tuning
# (CachyOS repos/kernel, scx scheduler, sysctl, NVIDIA, I/O schedulers,
# memory, systemd limits, audio latency, game-boost) so that logic lives in
# one place and also works standalone on non-Hyprland Arch installs.
#
# Extends that script's PHASE_FUNCS/PHASE_DESCS registry with the three
# Hyprland-specific phases below and reuses its select_menu checklist, so
# running this shows one combined interactive menu (system tuning + Omarchy
# extras) instead of applying everything unconditionally.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/arch-performance-settings.sh"

# =============================================================================
# OMARCHY EXTRA 1 — Gaming Scripts
# tv-monitor / main-monitor: per-monitor gaming launchers, meant to be set as
#   the Steam launch-option prefix (e.g. "tv-monitor mangohud %command%").
#   Each one:
#     1. Switches the gaming workspace (8 or 9) + primary monitor (xrandr,
#        works against the Xwayland server Hyprland exposes) for that display.
#     2. Exports NVIDIA/DXVK/Proton/DLSS env vars tuned for that specific
#        panel (HDMI-A-1 TV @120Hz VRR vs. DP-3 @360Hz VRR).
#     3. Ends with `exec game-boost "$@"` — the shared wrapper installed by
#        arch-performance-settings.sh (Phase 10 there) that reasserts the
#        scx_loader "Gaming" mode and elevates the power profile + inhibits
#        sleep/idle for the wrapped process only. Keeping that logic in one
#        place means tv-monitor, main-monitor and standalone launches all
#        stay in sync instead of drifting apart.
# toggle-hdmi: toggles HDMI-A-1 (TV) on/off via monitorv2 block + hyprctl reload
# toggle-hdmi-bitdepth: switches between HDR 10-bit and SDR 8-bit for screen sharing
#   (workaround for Hyprland bug: HDR + screencopy shows only wallpaper)
# =============================================================================
setup_gaming_scripts() {
    status "Omarchy Extra 1 — Gaming Scripts"

    status_step "tv-monitor (HDMI-A-1 TV, workspace 9, gaming perf wrapper)"
    sudo tee /bin/tv-monitor > /dev/null << 'EOF'
#!/usr/bin/bash

# SET MONITOR PREFERENCES
# -----------------------
	# Set Gaming Workspace
	CONFIG="$HOME/.config/hypr/hyprland.conf"
	sed -i -E "s/workspace = (8|9) #change/workspace = 9 #change/g" "$CONFIG"
	# Set HDMI-A-1 as primary monitor
	xrandr --output HDMI-A-1 --primary
	# Reload Hyprland configuration
	hyprctl reload
# -----------------------

# SET ENV Variables
# -----------------

	# Monitor Settings
	export __GL_GSYNC_ALLOWED=1               # Controls if G-Sync capable monitors should use Variable Refresh Rate (VRR)
	export __GL_VRR_ALLOWED=1                 # Controls if Adaptive Sync should be used. Recommended to set as “0” to avoid having problems on some games.
	export __GL_SYNC_TO_VBLANK=0              # used to control whether swaps are synchronized to a display device's vertical refresh.
	export __GL_SYNC_DISPLAY_DEVICE=HDMI-A-1  # specify to which display device OpenGL should sync

	# General Settings
	export WLR_DRM_NO_ATOMIC=1                      # Disable vsync and allow tearing (reduces input lag)
	export WLR_NO_HARDWARE_CURSORS=1                # Fix cursor corruption in some games
	export DXVK_STATE_CACHE=1                       # reduces stutter by caching shaders
	export __GL_SHADER_DISK_CACHE=1                 # reduces stutter by caching shaders
	export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1    # reduces stutter by caching shaders
	export __GL_SHADER_DISK_CACHE_SIZE=100000000000 # reduces stutter by caching shaders
	export __GL_YIELD=USLEEP                        # helps with CPU-bound scenarios
	export __GL_MaxFramesAllowed=1                  # reduces input lag
	export __GL_SHOW_GRAPHICS_OSD=0                 # Disable NVIDIA's Debug Warnings - Reduces log spam
	export __GL_PERSISTENT_DISPLAY_PRIORITY=1       # prevents GPU from downclocking during lighter loads
	export NVIDIA_REFRESH_RATE=120                  # NVIDIA Reflex Support (Reduces latency further)
	#export LD_PRELOAD=""                           # reduces stutter AND block steam overlay!
	#export __GL_THREADED_OPTIMIZATIONS=1	        # (lower performance on rivals)
	#export VKD3D_DISABLE_EXTENSIONS=VK_KHR_present_wait #(fix crash on rivals but, lower performance)

	# DLSS Settings
	export PROTON_ENABLE_NVAPI=1                    # Enable DLSS
	export PROTON_ENABLE_NGX_UPDATER=1              # Force DLSS Update
	# Enable Latest DLSS version
	export DXVK_NVAPI_DRS_NGX_DLSS_RR_OVERRIDE=on
	export DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE=on
	export DXVK_NVAPI_DRS_NGX_DLSS_FG_OVERRIDE=on
	export DXVK_NVAPI_DRS_NGX_DLSS_RR_OVERRIDE_RENDER_PRESET_SELECTION=render_preset_latest
	export DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE_RENDER_PRESET_SELECTION=render_preset_latest
	export DXVK_NVAPI_SET_NGX_DEBUG_OPTIONS=DLSSIndicator=0,DLSSGIndicator=0      # Disable DLSS Indicator
	#export DXVK_NVAPI_SET_NGX_DEBUG_OPTIONS=DLSSIndicator=1024,DLSSGIndicator=2  # Enable DLSS Indicator

	# Sync Settings
	export PROTON_USE_NTSYNC=1                      # Use kernel ntsync (loaded by arch-performance-settings.sh) instead of fsync/esync — lower wineserver CPU overhead, falls back automatically if unsupported

	# Documentation
	# - https://github.com/jp7677/dxvk-nvapi
	# - https://download.nvidia.com/XFree86/Linux-32bit-ARM/375.26/README/openglenvvariables.html

# -----------------

# applied variables, now hand off to game-boost (scx reassert + performance
# power profile + sleep/idle inhibit, held only for this process's lifetime —
# see arch-performance-settings.sh)
exec game-boost "$@"
EOF
    sudo chmod +x /bin/tv-monitor

    status_step "main-monitor (DP-3 360Hz, workspace 8, gaming perf wrapper)"
    sudo tee /bin/main-monitor > /dev/null << 'EOF'
#!/usr/bin/bash

# SET MONITOR PREFERENCES
# -----------------------
	# Set Gaming Workspace
	CONFIG="$HOME/.config/hypr/hyprland.conf"
	sed -i -E "s/workspace = (8|9) #change/workspace = 8 #change/g" "$CONFIG"
	# Set DP-3 as primary monitor
	xrandr --output DP-3 --primary
	# Reload Hyprland configuration
	hyprctl reload
# -----------------------

# SET ENV Variables
# -----------------

	# Monitor DP-3 settings
	export __GL_GSYNC_ALLOWED=1                     # Controls if G-Sync capable monitors should use Variable Refresh Rate (VRR)
	export __GL_VRR_ALLOWED=1                       # Controls if Adaptive Sync should be used — measured to reduce input latency and jitter (marco-nett.de input latency study)
	export __GL_SYNC_TO_VBLANK=0                    # used to control whether swaps are synchronized to a display device's vertical refresh.
	export __GL_SYNC_DISPLAY_DEVICE=DP-3            # specify to which display device OpenGL should sync

	# General Settings
	export WLR_DRM_NO_ATOMIC=1                      # Disable vsync and allow tearing (reduces input lag)
	export WLR_NO_HARDWARE_CURSORS=1                # Fix cursor corruption in some games
	export DXVK_STATE_CACHE=1                       # reduces stutter by caching shaders
	export __GL_SHADER_DISK_CACHE=1                 # reduces stutter by caching shaders
	export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1    # reduces stutter by caching shaders
	export __GL_SHADER_DISK_CACHE_SIZE=100000000000 # reduces stutter by caching shaders
	export __GL_YIELD=USLEEP                        # helps with CPU-bound scenarios
	export __GL_MaxFramesAllowed=1                  # reduces input lag
	export __GL_SHOW_GRAPHICS_OSD=0                 # Disable NVIDIA's Debug Warnings - Reduces log spam
	export __GL_PERSISTENT_DISPLAY_PRIORITY=1       # prevents GPU from downclocking during lighter loads
	export NVIDIA_REFRESH_RATE=360                  # NVIDIA Reflex Support (Reduces latency further)
	#export LD_PRELOAD=""                           # reduces stutter AND BLOCK STEAM OVERLAY!
	#export __GL_THREADED_OPTIMIZATIONS=1	        # (lower performance on rivals)
	#export VKD3D_DISABLE_EXTENSIONS=VK_KHR_present_wait #(fix crash on rivals but, lower performance)

	# DLSS Settings
	export PROTON_ENABLE_NVAPI=1                    # Enable DLSS
	export PROTON_ENABLE_NGX_UPDATER=1              # Force DLSS Update
	# Enable Latest DLSS version
	export DXVK_NVAPI_DRS_NGX_DLSS_RR_OVERRIDE=on
	export DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE=on
	export DXVK_NVAPI_DRS_NGX_DLSS_FG_OVERRIDE=on
	export DXVK_NVAPI_DRS_NGX_DLSS_RR_OVERRIDE_RENDER_PRESET_SELECTION=render_preset_latest
	export DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE_RENDER_PRESET_SELECTION=render_preset_latest
	export DXVK_NVAPI_SET_NGX_DEBUG_OPTIONS=DLSSIndicator=0,DLSSGIndicator=0      # Disable DLSS Indicator
	#export DXVK_NVAPI_SET_NGX_DEBUG_OPTIONS=DLSSIndicator=1024,DLSSGIndicator=2  # Enable DLSS Indicator

	# Sync Settings
	export PROTON_USE_NTSYNC=1                      # Use kernel ntsync (loaded by arch-performance-settings.sh) instead of fsync/esync — lower wineserver CPU overhead, falls back automatically if unsupported

	# Documentation
	# - https://github.com/jp7677/dxvk-nvapi
	# - https://download.nvidia.com/XFree86/Linux-32bit-ARM/375.26/README/openglenvvariables.html

# -----------------

# applied variables, now hand off to game-boost (scx reassert + performance
# power profile + sleep/idle inhibit, held only for this process's lifetime —
# see arch-performance-settings.sh)
exec game-boost "$@"
EOF
    sudo chmod +x /bin/main-monitor

    status_step "toggle-hdmi (SUPER+ALT+T)"
    tee "$HOME/.local/bin/toggle-hdmi" > /dev/null << 'EOF'
#!/bin/bash

HDMI_STATE="$HOME/.config/hypr/hdmi-state.conf"

if hyprctl monitors | grep -q "Monitor HDMI-A-1"; then
    echo "monitor=HDMI-A-1,disable" > "$HDMI_STATE"
else
    cat > "$HDMI_STATE" << 'HYPR'
monitorv2 {
    output = HDMI-A-1
    mode = 3840x2160@120
    position = 0x0
    scale = 1
    bitdepth = 10
    cm = hdr
    vrr = 3
    supports_wide_color = 1
    supports_hdr = 1
    sdr_max_luminance = 700
    sdr_min_luminance = 0
    sdrbrightness = 1.0
    sdrsaturation = 1.3
    min_luminance = 0
    max_luminance = 700
    max_avg_luminance = 300
}
HYPR
fi

hyprctl reload
EOF
    chmod +x "$HOME/.local/bin/toggle-hdmi"

    status_step "toggle-hdmi-bitdepth (SUPER+ALT+CTRL+T)"
    tee "$HOME/.local/bin/toggle-hdmi-bitdepth" > /dev/null << 'EOF'
#!/bin/bash

HDMI_STATE="$HOME/.config/hypr/hdmi-state.conf"

if ! hyprctl monitors | grep -q "Monitor HDMI-A-1"; then
    notify-send "HDMI-A-1" "Monitor desligado, ative-o primeiro (SUPER+ALT+T)"
    exit 0
fi

if grep -q "bitdepth = 10" "$HDMI_STATE"; then
    cat > "$HDMI_STATE" << 'HYPR'
monitorv2 {
    output = HDMI-A-1
    mode = 3840x2160@120
    position = 0x0
    scale = 1
    bitdepth = 8
    vrr = 3
}
HYPR
    notify-send "HDMI-A-1" "Modo SDR 8-bit (screen sharing)"
else
    cat > "$HDMI_STATE" << 'HYPR'
monitorv2 {
    output = HDMI-A-1
    mode = 3840x2160@120
    position = 0x0
    scale = 1
    bitdepth = 10
    cm = hdr
    vrr = 3
    supports_wide_color = 1
    supports_hdr = 1
    sdr_max_luminance = 700
    sdr_min_luminance = 0
    sdrbrightness = 1.0
    sdrsaturation = 1.3
    min_luminance = 0
    max_luminance = 700
    max_avg_luminance = 300
}
HYPR
    notify-send "HDMI-A-1" "Modo HDR 10-bit"
fi

hyprctl reload
EOF
    chmod +x "$HOME/.local/bin/toggle-hdmi-bitdepth"
}

# =============================================================================
# OMARCHY EXTRA 2 — Hyprland Gaming Config
# allow_tearing + direct_scanout: eliminates compositor vsync overhead.
# Window rules (immediate, nodim, noblur, noanim, norounding): disable all
#   visual effects for steam_app_* windows to maximize raw frame throughput.
# Keybindings:
#   SUPER+ALT+T        → toggle HDMI-A-1 TV on/off
#   SUPER+ALT+CTRL+T   → toggle HDR/SDR on HDMI-A-1 (screen sharing fix)
# =============================================================================
setup_hyprland_gaming() {
    status "Omarchy Extra 2 — Hyprland Gaming Config"

    local HYPR_DIR="$HOME/.config/hypr"

    status_step "Installing gamescope (DRM/KMS direct flip for XWayland-only games)"
    install_packages gamescope lib32-gamescope

    status_step "Writing gaming window rules"
    tee "$HYPR_DIR/gaming.conf" > /dev/null << 'EOF'
# Gaming performance rules
# sourced from hyprland.conf

misc {
    allow_tearing = true
    direct_scanout = 2
}

# Apply to all Steam games (steam_app_XXXXXXXX class)
windowrule = immediate,    class:^(steam_app_.*)$
windowrule = fullscreen,   class:^(steam_app_.*)$
windowrule = nodim,        class:^(steam_app_.*)$
windowrule = noblur,       class:^(steam_app_.*)$
windowrule = noanim,       class:^(steam_app_.*)$
windowrule = noborder,     class:^(steam_app_.*)$
windowrule = noshadow,     class:^(steam_app_.*)$
windowrule = norounding,   class:^(steam_app_.*)$
EOF

    status_step "Sourcing gaming.conf from hyprland.conf"
    if ! grep -q "source.*gaming.conf" "$HYPR_DIR/hyprland.conf"; then
        echo "" >> "$HYPR_DIR/hyprland.conf"
        echo "source = ~/.config/hypr/gaming.conf" >> "$HYPR_DIR/hyprland.conf"
    fi

    status_step "Writing keybindings for HDMI toggle scripts"
    # Keybindings are in bindings.conf — add only if not present
    if ! grep -q "toggle-hdmi$" "$HYPR_DIR/bindings.conf"; then
        cat >> "$HYPR_DIR/bindings.conf" << 'EOF'

bindd = SUPER ALT, T, Toggle HDMI TV, exec, toggle-hdmi
bindd = SUPER ALT CTRL, T, Toggle HDMI bitdepth (HDR/SDR), exec, toggle-hdmi-bitdepth
EOF
    fi

    status_step "Writing monitors.conf with HDMI-A-1 managed by hdmi-state.conf"
    tee "$HYPR_DIR/hdmi-state.conf" > /dev/null << 'EOF'
monitor=HDMI-A-1,disable
EOF

    if ! grep -q "hdmi-state.conf" "$HYPR_DIR/monitors.conf"; then
        # Replace any static HDMI-A-1 line with the sourced state file
        sed -i '/HDMI-A-1/d' "$HYPR_DIR/monitors.conf"
        echo "" >> "$HYPR_DIR/monitors.conf"
        echo "# TV — managed by toggle-hdmi script" >> "$HYPR_DIR/monitors.conf"
        echo "source = ~/.config/hypr/hdmi-state.conf" >> "$HYPR_DIR/monitors.conf"
    fi

    hyprctl reload 2>/dev/null && status_step_info "Hyprland config reloaded" || true
}

# =============================================================================
# OMARCHY EXTRA 3 — Voxtype (Voice Typing)
# Installs voxtype (push-to-talk voice-to-text) from AUR and configures it
# to use the large-v3-turbo Whisper model with GPU acceleration.
# `voxtype setup model` is an interactive picker with no documented
# non-interactive flag; menu entry [10] large-v3-turbo is fed via stdin —
# if a future voxtype version reorders the menu, run `voxtype setup model`
# manually instead.
# =============================================================================
setup_voxtype() {
    status "Omarchy Extra 3 — Voxtype (Voice Typing)"

    if ! pacman -Q voxtype-bin &>/dev/null; then
        status_step "Installing voxtype-bin (AUR)"
        yay -S --needed --noconfirm voxtype-bin || warning "Failed to install voxtype-bin"
    else
        status_step "voxtype-bin already installed, skipping"
    fi

    local config="$HOME/.config/voxtype/config.toml"
    if [[ -f "$config" ]] && grep -q 'model = "large-v3-turbo"' "$config"; then
        status_step "large-v3-turbo model already configured, skipping download"
    else
        status_step "Downloading large-v3-turbo model (menu option [10])"
        printf '10\n' | voxtype setup model
    fi

    status_step "Enabling GPU acceleration"
    sudo voxtype setup gpu --enable

    status_step_info "Voxtype configured with large-v3-turbo + GPU acceleration"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    echo -e "\n${GREEN}🎮 Omarchy Post-Install Customization${NC}\n"
    echo -e "${BLUE}This script applies personal performance tweaks on top of Omarchy.${NC}"
    echo -e "${BLUE}Run after a fresh omarchy install. Safe to re-run (idempotent).${NC}"

    local -a all_funcs=("${PHASE_FUNCS[@]}" setup_gaming_scripts setup_hyprland_gaming setup_voxtype)
    local -a all_descs=(
        "${PHASE_DESCS[@]}"
        "Gaming Scripts (tv-monitor/main-monitor/toggle-hdmi, Hyprland-specific)"
        "Hyprland Gaming Config (tearing, window rules, HDMI keybinds, gamescope)"
        "Voxtype (Voice Typing, AUR + GPU acceleration)"
    )

    local -a chosen=()
    select_menu chosen "${all_descs[@]}"

    if [[ "${#chosen[@]}" -eq 0 ]]; then
        echo -e "\n${YELLOW}No phases selected, nothing to do.${NC}"
        exit 0
    fi

    sudo -v

    local idx
    for idx in "${chosen[@]}"; do
        "${all_funcs[$((idx - 1))]}"
    done

    echo -e "\n${GREEN}✓ Done.${NC}"
    echo -e "${YELLOW}→ Reboot to activate any kernel/zram/scx/sysctl phases you selected.${NC}"
    echo -e "${YELLOW}→ After reboot: confirm kernel with 'uname -r' and scheduler with 'scxtop'.${NC}"
    echo -e "${YELLOW}→ Prefix game launches with 'game-boost' (or use tv-monitor/main-monitor).${NC}"
}

main
