#!/usr/bin/env bash
# selinux.sh
# SELinux rule injections for GrayRavens Vindicator drivers + NTSYNC
# Sourced by build.sh — must be called from inside $KSRC
# Author: GrayRavens Team

SELINUX_RULES_C="drivers/kernelsu/selinux/rules.c"

# Sanity check — gracefully skip if KernelSU isn't installed
if [[ ! -f "$SELINUX_RULES_C" ]]; then
    echo "selinux.sh: $SELINUX_RULES_C not found — KernelSU not installed, skipping SELinux injection."
    return 0
fi

inject_selinux() {
    local label="$1"
    local rules="$2"
    echo "Injecting ${label} SELinux rules..."
    sed -i "/rcu_assign_pointer(selinux_state.policy, pol);/i ${rules}" \
        "$SELINUX_RULES_C"
}

# ---------------------------------------------------------------------------
# NTSYNC — Allow kernel worker to chmod and relabel /dev/ntsync
#         Allow Winlator (untrusted_app) to use /dev/ntsync
# ---------------------------------------------------------------------------
inject_selinux "NTSYNC" \
' ksu_allow(db, "kernel", "device", "chr_file", "setattr");\n\
ksu_allow(db, "kernel", "device", "chr_file", "relabelfrom");\n\
ksu_allow(db, "kernel", "gpu_device", "chr_file", "relabelto");\n\
ksu_allow(db, "kernel", "gpu_device", "chr_file", "setattr");\n\
ksu_allow(db, "kernel", "untrusted_app", "gpu_device", "chr_file", "read");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "write");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "open");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "ioctl");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "map");\n'

# ---------------------------------------------------------------------------
# Vindicator — sysfs enforcement framework
# The framework's enforce() callbacks re-apply tunables that vendor init
# keeps reverting. Needs broad sysfs dir/file access.
# ---------------------------------------------------------------------------
inject_selinux "Vindicator" \
' ksu_allow(db, "kernel", "sysfs", "dir", "search");\n\
ksu_allow(db, "kernel", "sysfs", "dir", "getattr");\n\
ksu_allow(db, "kernel", "sysfs", "file", "read");\n\
ksu_allow(db, "kernel", "sysfs", "file", "write");\n\
ksu_allow(db, "kernel", "sysfs", "file", "open");\n\
ksu_allow(db, "kernel", "sysfs", "file", "getattr");\n'

# ---------------------------------------------------------------------------
# Nocturne — screen-state power saving
# Writes to /dev/cpuset/background/cpus and system-background/cpus
# (cgroupfs) when the display turns off. Also reads DRM/backlight sysfs
# for screen-state detection on DRM/KMS kernels.
# ---------------------------------------------------------------------------
inject_selinux "Nocturne" \
' ksu_allow(db, "kernel", "cgroup", "dir", "search");\n\
ksu_allow(db, "kernel", "cgroup", "dir", "write");\n\
ksu_allow(db, "kernel", "cgroup", "dir", "getattr");\n\
ksu_allow(db, "kernel", "cgroup", "file", "read");\n\
ksu_allow(db, "kernel", "cgroup", "file", "write");\n\
ksu_allow(db, "kernel", "cgroup", "file", "open");\n\
ksu_allow(db, "kernel", "cgroup", "file", "getattr");\n\
ksu_allow(db, "kernel", "sysfs_backlight", "dir", "search");\n\
ksu_allow(db, "kernel", "sysfs_backlight", "dir", "getattr");\n\
ksu_allow(db, "kernel", "sysfs_backlight", "file", "read");\n\
ksu_allow(db, "kernel", "sysfs_backlight", "file", "open");\n\
ksu_allow(db, "kernel", "sysfs_backlight", "file", "getattr");\n\
ksu_allow(db, "kernel", "sysfs_drm", "dir", "search");\n\
ksu_allow(db, "kernel", "sysfs_drm", "dir", "getattr");\n\
ksu_allow(db, "kernel", "sysfs_drm", "file", "read");\n\
ksu_allow(db, "kernel", "sysfs_drm", "file", "open");\n\
ksu_allow(db, "kernel", "sysfs_drm", "file", "getattr");\n'

# ---------------------------------------------------------------------------
# Equilibrium — profile-aware memory/swap tuning
# Writes /proc/sys/vm/dirty_ratio, dirty_background_ratio, and
# vfs_cache_pressure via filp_open + kernel_write on profile changes.
# ---------------------------------------------------------------------------
inject_selinux "Equilibrium" \
' ksu_allow(db, "kernel", "proc", "file", "write");\n\
ksu_allow(db, "kernel", "proc", "file", "open");\n\
ksu_allow(db, "kernel", "proc", "file", "getattr");\n'

# ---------------------------------------------------------------------------
# Herald — kernel-to-userspace property relay
# Exposes pending properties under /sys/kernel/herald/queue/*/.
# The kernel creates these (kernfs — no file open needed).
# Userspace daemon (system_app domain) reads them.
# ---------------------------------------------------------------------------
inject_selinux "Herald" \
' ksu_allow(db, "system_app", "sysfs_kernel", "dir", "search");\n\
ksu_allow(db, "system_app", "sysfs_kernel", "file", "read");\n\
ksu_allow(db, "system_app", "sysfs_kernel", "file", "open");\n\
ksu_allow(db, "system_app", "sysfs_kernel", "file", "getattr");\n'

# ---------------------------------------------------------------------------
# Iyashi / Kasumi — thermal performance management
# Iyashi relaxes cooling device targets to hold a performance floor.
# Kasumi dampens thermal_zone_get_temp() readings by a configurable offset.
# Both read/write thermal zone sysfs nodes.
# ---------------------------------------------------------------------------
inject_selinux "Iyashi / Kasumi" \
' ksu_allow(db, "kernel", "sysfs_therm", "dir", "search");\n\
ksu_allow(db, "kernel", "sysfs_therm", "file", "read");\n\
ksu_allow(db, "kernel", "sysfs_therm", "file", "write");\n\
ksu_allow(db, "kernel", "sysfs_therm", "file", "open");\n'

# ---------------------------------------------------------------------------
# Oto — audio thread SCHED_FIFO boost + PM QoS + CPUSet manager
# Promotes audio server threads to SCHED_FIFO priority 2 (needs
# dac_override capability). Engages PM QoS latency lock (100 µs).
# Watchdog corrects vendor cpuset rollback via cgroup writes.
# ---------------------------------------------------------------------------
inject_selinux "Oto" \
' ksu_allow(db, "kernel", "kernel", "capability", "dac_override");\n\
ksu_allow(db, "kernel", "cgroup", "dir", "search");\n\
ksu_allow(db, "kernel", "cgroup", "dir", "write");\n\
ksu_allow(db, "kernel", "cgroup", "dir", "getattr");\n\
ksu_allow(db, "kernel", "cgroup", "file", "read");\n\
ksu_allow(db, "kernel", "cgroup", "file", "write");\n\
ksu_allow(db, "kernel", "cgroup", "file", "open");\n\
ksu_allow(db, "kernel", "cgroup", "file", "getattr");\n'

# ---------------------------------------------------------------------------
# Kiryuu — native root command execution engine
# Executes /data/adb/ksud (and other root commands) via
# call_usermodehelper(). Needs process transition to KSU domain
# and execute/read permissions on shell and ADB data files.
# ---------------------------------------------------------------------------
inject_selinux "Kiryuu" \
' ksu_allow(db, "kernel", KERNEL_SU_DOMAIN, "process", "transition");\n\
ksu_allow(db, "kernel", "shell_exec", "file", "execute");\n\
ksu_allow(db, "kernel", "shell_exec", "file", "execute_no_trans");\n\
ksu_allow(db, "kernel", "shell_exec", "file", "read");\n\
ksu_allow(db, "kernel", "shell_exec", "file", "open");\n\
ksu_allow(db, "kernel", "shell_exec", "file", "getattr");\n\
ksu_allow(db, "kernel", "shell_exec", "file", "map");\n\
ksu_allow(db, "kernel", "adb_data_file", "dir", "search");\n\
ksu_allow(db, "kernel", "adb_data_file", "file", "execute");\n\
ksu_allow(db, "kernel", "adb_data_file", "file", "execute_no_trans");\n\
ksu_allow(db, "kernel", "adb_data_file", "file", "read");\n\
ksu_allow(db, "kernel", "adb_data_file", "file", "open");\n\
ksu_allow(db, "kernel", "adb_data_file", "file", "getattr");\n\
ksu_allow(db, "kernel", "adb_data_file", "file", "map");\n'

# ---------------------------------------------------------------------------
# Vindicator Targets — cpufreq governor + read_ahead enforcement
# Enforces that scaling_governor stays on "zenith" and read_ahead_kb
# stays tuned. Reads/writes /sys/devices/system/cpu/ nodes.
# ---------------------------------------------------------------------------
inject_selinux "Vindicator Targets" \
' ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "dir", "search");\n\
ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "dir", "getattr");\n\
ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "read");\n\
ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "write");\n\
ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "open");\n\
ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "getattr");\n'

echo "✅ All GrayRavens SELinux rules injected successfully"
