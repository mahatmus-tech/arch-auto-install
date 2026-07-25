#!/usr/bin/env bash

# =============================================================================
# arch-performance-settings.sh
# System-level performance tuning for Arch Linux (and derivatives) — kernel,
# scx scheduler, NVIDIA driver, storage I/O, memory, systemd limits, audio
# latency, and a game-launch wrapper (game-boost).
#
# No Hyprland/Omarchy/desktop-environment dependency — safe to run on any
# Arch-based install, headless or with any DE/WM.
#
# Can be run standalone:
#   ./arch-performance-settings.sh
# Running it directly shows an interactive checklist so you can pick exactly
# which phases to apply — not every system wants CachyOS repos, NVIDIA
# tuning, etc.
#
# Can also be sourced from another provisioning script to reuse these phases
# (functions + the PHASE_FUNCS/PHASE_DESCS registry + select_menu) before
# layering DE-specific config on top — see install-omarchy.sh, which sources
# this and builds its own menu combining these phases with its Hyprland ones.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
YELLOW_W='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()             { echo -e "${BLUE}[i]${NC} $1"; }
warning()          { echo -e "${YELLOW_W}[!]${NC} $1"; }
error()            { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
status()           { echo -e "${GREEN}[+]${YELLOW} $1${NC}"; }
status_step()      { echo -e "${GREEN}    -${NC} $1"; }
status_step_info() { echo -e "${GREEN}      >${BLUE} $1"; }

install_packages() {
    local pkg
    for pkg in "$@"; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            sudo pacman -S --needed --noconfirm "$pkg" || warning "Failed to install $pkg"
        fi
    done
}

write_file() {
    local path="$1"
    local content="$2"
    echo "$content" | sudo tee "$path" > /dev/null
}

has_nvidia_gpu() {
    lspci -d ::0300 2>/dev/null | grep -qi nvidia || lspci -d ::0302 2>/dev/null | grep -qi nvidia
}

# =============================================================================
# Interactive checklist menu — lets the user pick which phases to apply.
# Usage: select_menu <output_array_name> "desc 1" "desc 2" ...
# Fills <output_array_name> with the 1-based indices confirmed by the user, in
# ascending order. Everything starts pre-selected (so hitting 'c' immediately
# reproduces the old "run everything" behavior); type a number to toggle it.
# Reused as-is by install-omarchy.sh for its own (larger) menu.
# =============================================================================
select_menu() {
    local -n _selected_out="$1"
    shift
    local -a descs=("$@")
    local -a picked=()
    local i idx n choice

    for ((i = 0; i < ${#descs[@]}; i++)); do picked[i]=1; done

    while true; do
        echo -e "\n${GREEN}Select the phases to apply${NC} ${BLUE}(all selected by default)${NC}"
        for ((i = 0; i < ${#descs[@]}; i++)); do
            if [[ "${picked[i]}" == "1" ]]; then
                echo -e "  ${GREEN}[x]${NC} $((i + 1))) ${descs[i]}"
            else
                echo -e "  [ ] $((i + 1))) ${descs[i]}"
            fi
        done
        echo -e "${BLUE}Numbers to toggle (e.g. '3 7'), 'a' all, 'n' none, 'c' confirm, 'q' quit${NC}"
        read -rp "> " choice || { echo; exit 1; }

        case "$choice" in
            a|A) for ((i = 0; i < ${#descs[@]}; i++)); do picked[i]=1; done ;;
            n|N) for ((i = 0; i < ${#descs[@]}; i++)); do picked[i]=0; done ;;
            c|C) break ;;
            q|Q) echo "Cancelled."; exit 1 ;;
            *)
                if [[ "$choice" =~ ^[0-9]+([[:space:]]+[0-9]+)*$ ]]; then
                    for n in $choice; do
                        idx=$((n - 1))
                        if ((idx >= 0 && idx < ${#descs[@]})); then
                            [[ "${picked[idx]}" == "1" ]] && picked[idx]=0 || picked[idx]=1
                        fi
                    done
                else
                    warning "Unrecognized input: $choice"
                fi
                ;;
        esac
    done

    _selected_out=()
    for ((i = 0; i < ${#descs[@]}; i++)); do
        if [[ "${picked[i]}" == "1" ]]; then
            _selected_out+=($((i + 1)))
        fi
    done
}

# =============================================================================
# PHASE 1 — CachyOS Repositories
# Adds CachyOS keyring + mirrorlist and cachyos/cachyos-v3 repos to pacman.conf
# Enables x86-64-v3 optimized packages (AVX2/BMI2) on CPUs that support it.
# =============================================================================
setup_cachyos_repos() {
    status "Phase 1 — CachyOS Repositories"

    if pacman -Q cachyos-keyring &>/dev/null; then
        status_step "CachyOS repos already configured, skipping"
        return
    fi

    status_step "Importing CachyOS signing key"
    sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key F3B607488DB35A47

    status_step "Installing keyring and mirrorlists"
    sudo pacman -U --noconfirm \
        'https://cdn.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
        'https://cdn.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-27-1-any.pkg.tar.zst' \
        'https://cdn.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-27-1-any.pkg.tar.zst'

    status_step "Enabling x86_64_v3 architecture in pacman.conf"
    sudo sed -i 's/^Architecture = auto$/Architecture = auto x86_64_v3/' /etc/pacman.conf

    status_step "Setting ParallelDownloads = 10"
    sudo sed -i 's/^ParallelDownloads = .*/ParallelDownloads = 10/' /etc/pacman.conf

    status_step "Adding CachyOS repos before [core]"
    if ! grep -q "\[cachyos\]" /etc/pacman.conf; then
        sudo sed -i '/^\[core\]/i [cachyos-v3]\nInclude = /etc/pacman.d/cachyos-v3-mirrorlist\n\n[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n' /etc/pacman.conf
    fi

    status_step "Syncing and upgrading packages (x86-64-v3)"
    sudo pacman -Syu --noconfirm

    status_step_info "Done — glibc, gcc-libs, zstd and others now use v3 builds"
}

# =============================================================================
# PHASE 2 — linux-cachyos Kernel (BORE Scheduler)
# Installs CachyOS kernel with BORE scheduler tuned for gaming/bursty threads.
# Keeps vanilla linux as fallback. Bootloader entry generated by pacman hook.
# =============================================================================
install_cachyos_kernel() {
    status "Phase 2 — linux-cachyos Kernel"

    if pacman -Q linux-cachyos &>/dev/null; then
        status_step "linux-cachyos already installed ($(pacman -Q linux-cachyos | awk '{print $2}'))"
        return
    fi

    status_step "Installing linux-cachyos and headers"
    # DKMS-based drivers (e.g. nvidia-open-dkms) rebuild automatically for the new kernel
    install_packages linux-cachyos linux-cachyos-headers

    if [[ -f /boot/limine.conf ]]; then
        status_step "Enabling Limine menu timeout for first boot selection"
        sudo sed -i 's/^#timeout: 3$/timeout: 5/' /boot/limine.conf
        status_step_info "After confirming boot: sudo sed -i 's/^timeout: 5$/#timeout: 3/' /boot/limine.conf"
    fi

    status_step_info "Reboot and select linux-cachyos from your bootloader menu"
}

# =============================================================================
# PHASE 3 — scx Scheduler (scx_bpfland Gaming Mode)
# scx_bpfland in Gaming mode dynamically prioritizes latency-critical threads,
# on top of BORE via the Linux sched_ext framework (kernel 6.12+).
# Also installs a polkit rule so wheel-group users can switch schedulers
# without a password prompt every few minutes (matches power-profiles-daemon's
# own allow_active=yes policy) — needed by game-boost below.
# =============================================================================
setup_scx_scheduler() {
    status "Phase 3 — scx Scheduler"

    if systemctl is-active --quiet scx_loader.service \
        && [[ -f /etc/scx_loader/config.toml ]] \
        && grep -q 'default_sched = "scx_bpfland"' /etc/scx_loader/config.toml; then
        status_step "scx_loader already configured and running, skipping"
        return
    fi

    status_step "Installing scx-scheds + scx-tools (provides scx_loader.service)"
    install_packages scx-scheds scx-tools

    status_step "Writing scx_loader config"
    sudo mkdir -p /etc/scx_loader
    sudo tee /etc/scx_loader/config.toml > /dev/null << 'EOF'
default_sched = "scx_bpfland"
default_mode = "Gaming"

[scheds.scx_bpfland]
auto_mode = []
gaming_mode = ["-m", "performance"]
lowlatency_mode = ["-s", "5000", "-S", "500", "-l", "5000", "-m", "performance"]
powersave_mode = ["-m", "powersave"]
server_mode = ["-p"]

[scheds.scx_lavd]
auto_mode = []
gaming_mode = ["--performance"]
lowlatency_mode = ["--performance"]
powersave_mode = ["--powersave"]
server_mode = []

[scheds.scx_flash]
auto_mode = []
gaming_mode = ["-m", "performance"]
lowlatency_mode = ["-s", "5000", "-S", "500", "-l", "5000", "-m", "performance"]
powersave_mode = ["-m", "powersave"]
server_mode = ["-p", "-c", "0"]

[scheds.scx_tickless]
auto_mode = []
gaming_mode = ["-f", "5000", "-s", "5000"]
lowlatency_mode = ["-f", "5000", "-s", "1000"]
powersave_mode = ["-f", "50", "-p"]
server_mode = ["-f", "100"]
EOF

    status_step "Enabling scx_loader service"
    sudo systemctl enable --now scx_loader.service

    status_step "Allowing wheel group to manage scx schedulers without a password prompt"
    sudo tee /etc/polkit-1/rules.d/45-scx-loader.rules > /dev/null << 'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.scx.loader.manage-schedulers" &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF
    sudo systemctl restart polkit

    status_step_info "Active scheduler: $(systemctl is-active scx_loader.service)"
}

# =============================================================================
# PHASE 4 — Kernel sysctl Settings
# Performance tuning for memory, IO, CPU and networking.
# Also loads ntsync module (NT sync primitives for Wine/Proton — reduces
# wineserver CPU overhead significantly in Windows games).
# Blacklists sp5100_tco (AMD TCO watchdog — causes system resets on Ryzen).
# =============================================================================
apply_kernel_settings() {
    status "Phase 4 — Kernel sysctl + Modules"

    status_step "Writing sysctl settings"
    sudo tee /usr/lib/sysctl.d/79-cachyos-gaming.conf > /dev/null << 'EOF'
# Memory — tuned for zram (swappiness raised to 150 by udev rule when zram loads)
vm.swappiness = 100
vm.vfs_cache_pressure = 50
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 67108864
vm.dirty_writeback_centisecs = 1500
vm.page-cluster = 0

# CPU
kernel.nmi_watchdog = 0
kernel.split_lock_mitigate = 0
kernel.unprivileged_userns_clone = 1

# Security / misc
kernel.printk = 3 3 3 3
kernel.kptr_restrict = 2
kernel.kexec_load_disabled = 1

# Network
net.core.netdev_max_backlog = 4096

# Files
fs.file-max = 2097152
EOF

    sudo sysctl --system > /dev/null 2>&1
    status_step_info "sysctl applied"

    status_step "Loading ntsync module"
    sudo tee /etc/modules-load.d/ntsync.conf > /dev/null << 'EOF'
ntsync
EOF
    sudo modprobe ntsync 2>/dev/null || warning "ntsync module not available in current kernel"

    status_step "Blacklisting sp5100_tco and iTCO_wdt watchdogs"
    sudo tee /etc/modprobe.d/watchdog-blacklist.conf > /dev/null << 'EOF'
# sp5100_tco: AMD SP5100 TCO watchdog — causes unexpected resets on Ryzen
# iTCO_wdt: Intel TCO watchdog — not needed, saves CPU cycles
blacklist sp5100_tco
blacklist iTCO_wdt
EOF
}

# =============================================================================
# PHASE 5 — NVIDIA Driver Settings
# Skipped entirely on machines without an NVIDIA GPU (lspci detection).
# Modprobe options for performance and stability.
# udev rule for runtime power management (d3cold on idle).
# NVreg_EnableResizableBar: enables Resizable BAR (SAM equivalent for NVIDIA).
# NVreg_RegistryDwords RMIntrLockingMode=1: reduces GPU interrupt stutter.
# nvidia-persistenced.service: keeps the driver initialized between launches,
# avoiding the clock/re-init ramp on the first frames. Works alongside
# NVreg_DynamicPowerManagement=0x02 (fine-grained RTD3) above — that's the
# officially supported combo, not a conflict.
# Writes /etc/modprobe.d/nvidia.conf directly (updating it in place if it
# already exists, e.g. from the driver install) instead of layering a second
# nvidia-custom.conf file that could disagree with it.
# =============================================================================
apply_nvidia_settings() {
    status "Phase 5 — NVIDIA Driver Settings"

    if ! has_nvidia_gpu; then
        status_step "No NVIDIA GPU detected, skipping"
        return
    fi

    local nvidia_conf="/etc/modprobe.d/nvidia.conf"
    if [[ -f "$nvidia_conf" ]]; then
        status_step "Updating existing $nvidia_conf"
    else
        status_step "Writing $nvidia_conf"
    fi
    sudo tee "$nvidia_conf" > /dev/null << 'EOF'
options nvidia_drm modeset=1
options nvidia NVreg_InitializeSystemMemoryAllocations=0   # Reduces VRAM initialization overhead
options nvidia NVreg_EnableResizableBar=1                  # Enables Resizable BAR (SAM) for better performance
options nvidia NVreg_RegistryDwords="RMIntrLockingMode=1"  # Better interrupt handling (reduces stutter)

# disabled
# options nvidia_drm modeset=1                               # after 570.86.16 driver fbdev has now been enabled by default when modset is enabled
# options nvidia NVreg_DynamicPowerManagement=0x02           # (only for mobile)
# options nvidia NVreg_UsePageAttributeTable=1               # (deprecated) Improves memory management
EOF

    if [[ -f /etc/modprobe.d/nvidia-custom.conf ]]; then
        status_step "Removing stale /etc/modprobe.d/nvidia-custom.conf (superseded by nvidia.conf above)"
        sudo rm -f /etc/modprobe.d/nvidia-custom.conf
    fi

    status_step "Writing NVIDIA udev runtime PM rule"
    sudo tee /usr/lib/udev/rules.d/89-nvidia-pm.rules > /dev/null << 'EOF'
# Enable runtime PM for NVIDIA GPU on driver bind
ACTION=="add|bind", SUBSYSTEM=="pci", DRIVERS=="nvidia", \
    ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", \
    TEST=="power/control", ATTR{power/control}="auto"

# Disable runtime PM on driver unbind
ACTION=="remove|unbind", SUBSYSTEM=="pci", DRIVERS=="nvidia", \
    ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", \
    TEST=="power/control", ATTR{power/control}="on"
EOF

    sudo udevadm control --reload
    sudo udevadm trigger
    status_step_info "udev rules reloaded"

    status_step "Enabling nvidia-persistenced.service"
    sudo systemctl enable --now nvidia-persistenced.service
}

# =============================================================================
# PHASE 6 — I/O Scheduler udev Rules + Storage Maintenance
# NVMe: kyber (low-latency, designed for fast SSDs)
# SATA SSD: mq-deadline (lower overhead than BFQ for SSDs)
# HDD: bfq (Budget Fair Queuing — best for rotational media)
# SATA ALPM: max_performance (disables SATA link power saving latency)
# fstrim.timer: weekly periodic TRIM. Without it (and without a live
# "discard" mount option, which most setups skip for latency reasons), freed
# blocks are never reclaimed by the SSD controller and write throughput
# degrades over time as the drive fills up.
# =============================================================================
apply_io_schedulers() {
    status "Phase 6 — I/O Schedulers + Storage Maintenance"

    status_step "Writing I/O scheduler udev rules"
    sudo tee /usr/lib/udev/rules.d/60-ioschedulers.rules > /dev/null << 'EOF'
# HDD — Budget Fair Queuing
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"

# SATA SSD / eMMC — mq-deadline
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

# NVMe — kyber (low-latency for fast storage)
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="kyber"
EOF

    status_step "Writing SATA ALPM max_performance rule"
    sudo tee /usr/lib/udev/rules.d/50-sata.rules > /dev/null << 'EOF'
ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", \
    ATTR{link_power_management_supported}=="1", \
    ATTR{link_power_management_policy}="max_performance"
EOF

    sudo udevadm control --reload
    sudo udevadm trigger
    status_step_info "I/O schedulers applied"

    status_step "Enabling fstrim.timer (weekly periodic TRIM)"
    sudo systemctl enable --now fstrim.timer
}

# =============================================================================
# PHASE 7 — Memory: zram + Transparent Hugepages
# zram: full RAM size with zstd compression, priority 100.
# THP enabled=madvise: only processes that explicitly opt in via madvise()
# (Proton/DXVK do) get hugepages — the kernel default "always" instead lets
# khugepaged transparently promote/compact hugepages for every process in the
# background, a known source of intermittent frame-time stutter in games.
# THP defrag: defer+madvise — hugepages allocated lazily and on madvise().
# THP shrinker: splits sparsely-used hugepages (max_ptes_none=409 = 80% empty).
# udev rule raises vm.swappiness to 150 when zram initializes.
# =============================================================================
setup_memory() {
    status "Phase 7 — Memory: zram + THP"

    status_step "Configuring zram (full RAM, zstd)"
    install_packages zram-generator
    sudo tee /usr/lib/systemd/zram-generator.conf > /dev/null << 'EOF'
[zram0]
compression-algorithm = zstd
zram-size = ram
swap-priority = 100
fs-type = swap
EOF

    status_step "Writing zram udev rule (swappiness=150 + disable zswap)"
    sudo tee /usr/lib/udev/rules.d/30-zram.rules > /dev/null << 'EOF'
ACTION=="change", KERNEL=="zram0", ATTR{initstate}=="1", \
    SYSCTL{vm.swappiness}="150", \
    RUN+="/usr/bin/sh -c 'echo N > /sys/module/zswap/parameters/enabled'"
EOF

    status_step "Configuring Transparent Hugepages (enabled=madvise, defrag=defer+madvise)"
    sudo tee /usr/lib/tmpfiles.d/thp.conf > /dev/null << 'EOF'
w! /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
w! /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise
EOF

    status_step "Configuring THP shrinker (max_ptes_none=409)"
    sudo tee /usr/lib/tmpfiles.d/thp-shrinker.conf > /dev/null << 'EOF'
w! /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 409
EOF

    sudo systemd-tmpfiles --create
    sudo udevadm control --reload
    status_step_info "zram and THP configured — reboot to activate zram"
}

# =============================================================================
# PHASE 8 — Systemd Limits + cgroup Delegation
# Raises file descriptor limits system-wide for gaming and Steam.
# cgroup delegation enables proper resource management for gamescope,
# pressure-vessel (Steam runtime) and scx_loader within user sessions.
# Reduced timeouts: faster service start/stop during gaming sessions.
# =============================================================================
setup_systemd() {
    status "Phase 8 — Systemd Limits + cgroup Delegation"

    status_step "System file descriptor limits"
    sudo mkdir -p /etc/systemd/system.conf.d
    sudo tee /etc/systemd/system.conf.d/10-limits.conf > /dev/null << 'EOF'
[Manager]
DefaultLimitNOFILE=2048:2097152
DefaultTimeoutStartSec=15s
DefaultTimeoutStopSec=10s
EOF

    status_step "User session file descriptor limits"
    sudo mkdir -p /etc/systemd/user.conf.d
    sudo tee /etc/systemd/user.conf.d/10-limits.conf > /dev/null << 'EOF'
[Manager]
DefaultLimitNOFILE=1024:1048576
DefaultTimeoutStartSec=15s
DefaultTimeoutStopSec=10s
EOF

    status_step "cgroup delegation for user sessions"
    sudo mkdir -p /etc/systemd/system/user@.service.d
    sudo tee /etc/systemd/system/user@.service.d/delegate.conf > /dev/null << 'EOF'
[Service]
Delegate=cpu cpuset io memory pids
EOF

    status_step "Journald size cap"
    sudo mkdir -p /etc/systemd/journald.conf.d
    sudo tee /etc/systemd/journald.conf.d/00-journal-size.conf > /dev/null << 'EOF'
[Journal]
SystemMaxUse=50M
EOF

    sudo systemctl daemon-reexec
    status_step_info "Systemd limits applied"
}

# =============================================================================
# PHASE 9 — Audio Realtime Permissions
# Grants audio group access to cpu_dma_latency, hpet and rtc0.
# These interfaces allow PipeWire/rtkit to request low-latency CPU states,
# which reduces audio glitches under gaming load.
# Disables snd_hda_intel power saving on AC (prevents audio crackle in games).
# =============================================================================
setup_audio_latency() {
    status "Phase 9 — Audio Realtime Permissions"

    status_step "cpu_dma_latency + hpet + rtc0 → audio group"
    sudo tee /usr/lib/udev/rules.d/99-cpu-dma-latency.rules > /dev/null << 'EOF'
DEVPATH=="/devices/virtual/misc/cpu_dma_latency", OWNER="root", GROUP="audio", MODE="0660"
EOF
    sudo tee /usr/lib/udev/rules.d/40-hpet-permissions.rules > /dev/null << 'EOF'
KERNEL=="rtc0",  GROUP="audio"
KERNEL=="hpet",  GROUP="audio"
EOF

    status_step "Disable snd_hda_intel power saving on AC"
    sudo tee /usr/lib/udev/rules.d/20-audio-pm.rules > /dev/null << 'EOF'
SUBSYSTEM=="power_supply", KERNEL=="AC*", ATTR{online}=="1", \
    RUN+="/usr/bin/sh -c 'find /sys/module/snd_hda_intel/parameters/ -name power_save -exec sh -c \"echo 0 > {}\" \;'"
EOF

    status_step "Set rtprio 99 for audio group"
    sudo tee /etc/security/limits.d/20-audio.conf > /dev/null << 'EOF'
@audio - rtprio 99
@audio - memlock unlimited
EOF

    status_step "Adding user to audio and realtime groups"
    sudo gpasswd -a "$USER" audio 2>/dev/null || true
    sudo gpasswd -a "$USER" realtime 2>/dev/null || true

    sudo udevadm control --reload
    sudo udevadm trigger
}

# =============================================================================
# PHASE 10 — game-boost (game-launch performance wrapper)
# Single consolidated wrapper — replaces having the same reinforcement logic
# duplicated across multiple launch scripts. Meant to be used either as a
# Steam launch-option prefix ("game-boost %command%") or a standalone launcher
# prefix on any DE/WM. It:
#   1. Reasserts the scx_loader "Gaming" mode (scx_bpfland) on entry — GameMode
#      used to do this via desiredgov; this replaces GameMode with scx_loader,
#      so the equivalent reinforcement is a SwitchScheduler D-Bus call.
#   2. Elevates the power profile to performance and inhibits sleep/idle
#      (systemd-inhibit --what=sleep:idle:handle-lid-switch), held only for the
#      lifetime of the wrapped process, reverting automatically when it exits.
# Both steps degrade gracefully (|| true / command -v checks) if scx_loader or
# power-profiles-daemon aren't installed. No monitor/workspace switching here
# — that's DE-specific and layered on top by callers that need it (e.g.
# tv-monitor/main-monitor in install-omarchy.sh end with `exec game-boost "$@"`
# after doing their own Hyprland monitor switch).
# =============================================================================
install_game_boost() {
    status "Phase 10 — game-boost (game-launch performance wrapper)"

    status_step "Installing /usr/local/bin/game-boost"
    sudo tee /usr/local/bin/game-boost > /dev/null << 'EOF'
#!/usr/bin/bash
# Wraps a game/app launch with performance reinforcement (inspired by CachyOS
# game-performance / GameMode). DE/WM-agnostic — no monitor switching here.
# Usage: game-boost %command%   (Steam launch options)
#        game-boost mygame      (standalone)

busctl call org.scx.Loader /org/scx/Loader org.scx.Loader SwitchScheduler su "scx_bpfland" 1 &>/dev/null || true

if command -v powerprofilesctl &>/dev/null && powerprofilesctl list | grep -q 'performance:'; then
	if command -v systemd-inhibit &>/dev/null; then
		exec systemd-inhibit --what=sleep:idle:handle-lid-switch \
			--why="game-boost gaming session" \
			powerprofilesctl launch -p performance -r "game-boost gaming session" -- "$@"
	else
		exec powerprofilesctl launch -p performance -r "game-boost gaming session" -- "$@"
	fi
fi

exec "$@"
EOF
    sudo chmod +x /usr/local/bin/game-boost
}

# =============================================================================
# Phase registry — PHASE_FUNCS[i] and PHASE_DESCS[i] must stay in sync; index 0
# here is menu option "1". install-omarchy.sh extends both arrays with its own
# Hyprland-specific phases to build one combined menu.
# =============================================================================
PHASE_FUNCS=(
    setup_cachyos_repos
    install_cachyos_kernel
    setup_scx_scheduler
    apply_kernel_settings
    apply_nvidia_settings
    apply_io_schedulers
    setup_memory
    setup_systemd
    setup_audio_latency
    install_game_boost
)
PHASE_DESCS=(
    "CachyOS Repositories (x86-64-v3 optimized packages)"
    "linux-cachyos Kernel (BORE scheduler)"
    "scx Scheduler (scx_bpfland Gaming Mode + polkit rule)"
    "Kernel sysctl Settings (memory/CPU/network tuning, ntsync, watchdog blacklist)"
    "NVIDIA Driver Settings (auto-skipped if no NVIDIA GPU detected)"
    "I/O Scheduler udev Rules (NVMe/SATA/HDD) + fstrim.timer"
    "Memory: zram + Transparent Hugepages (enabled=madvise)"
    "Systemd Limits + cgroup Delegation"
    "Audio Realtime Permissions"
    "game-boost (game-launch performance wrapper)"
)

# =============================================================================
# ENTRYPOINT
# run_arch_performance_settings runs every phase unconditionally — kept as a
# non-interactive entrypoint for scripted/automated use. Callers that source
# this file get it plus every function and array above, without the
# interactive banner/menu below firing automatically.
# =============================================================================
run_arch_performance_settings() {
    local func
    for func in "${PHASE_FUNCS[@]}"; do
        "$func"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "\n${GREEN}⚙ Arch Performance Settings${NC}\n"
    echo -e "${BLUE}Distro/DE-agnostic system performance tuning for Arch Linux.${NC}"
    echo -e "${BLUE}Safe to re-run (idempotent).${NC}"

    chosen=()
    select_menu chosen "${PHASE_DESCS[@]}"

    if [[ "${#chosen[@]}" -eq 0 ]]; then
        echo -e "\n${YELLOW}No phases selected, nothing to do.${NC}"
        exit 0
    fi

    sudo -v

    for idx in "${chosen[@]}"; do
        "${PHASE_FUNCS[$((idx - 1))]}"
    done

    echo -e "\n${GREEN}✓ Done.${NC}"
    echo -e "${YELLOW}→ Reboot to activate any kernel/zram/scx/sysctl phases you selected.${NC}"
    echo -e "${YELLOW}→ After reboot: confirm kernel with 'uname -r' and scheduler with 'scxtop'.${NC}"
    echo -e "${YELLOW}→ Prefix game launches with 'game-boost' to apply the performance wrapper.${NC}"
fi
