#!/bin/bash
# android12-5.10 GKI Kernel Build Script
set -e

# Error handler
trap 'echo "Build failed at line $LINENO. Exit code: $?" >&2' ERR

# ── Environment setup ────────────────────────────────────────────────────────
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
export PGO_INSTRUMENT=1
export KBUILD_BUILD_USER="GrayRavens-Team"
export KBUILD_BUILD_HOST="ZenithXHikari-KasumiXIyashi"

# ── Clang toolchain ──────────────────────────────────────────────────────────
if [ -z "$CLANG_PATH" ]; then
    echo "ERROR: CLANG_PATH is not set. Did you run this from the workflow?" >&2
    exit 1
fi

export PATH="${CLANG_PATH}/bin:${PATH}"

echo "Using toolchain : ${CLANG_VARIANT:-unknown}"
echo "Toolchain path  : $CLANG_PATH"
echo "Clang version   : $("$CLANG_PATH/bin/clang" --version | head -n1)"

# ── Compiler string (shown in kernel version) ────────────────────────────────
case "${CLANG_VARIANT}" in
    NEUTRON_19)
        export KBUILD_COMPILER_STRING="Neutron Clang 19.0.0 +PGO +BOLT +Polly +ThinLTO +O3"
        ;;
    ZYC_12)
        export KBUILD_COMPILER_STRING="ZYC Clang 12.0.0 +ThinLTO +O3"
        ;;
    AOSP_12)
        export KBUILD_COMPILER_STRING="AOSP Clang r445002 (LLVM 12.0.5)"
        ;;
esac

echo "Compiler string : $KBUILD_COMPILER_STRING"

# ── KCFLAGS ──────────────────────────────────────────────────────────────────
# -march=armv8.2-a  : safe baseline for all SD/Dimensity chips on Android 12
# -mtune=cortex-a55 : tune for little cores (handle most background work)
# -w                : suppress warnings, keep log clean
export KCFLAGS="-w -march=armv8.2-a -mtune=cortex-a55"
export KBUILD_CFLAGS += -fno-reorder-blocks-and-partition
export KBUILD_LDFLAGS += --emit-relocs

# ── NTSYNC SELinux policy injection ─────────────────────────────────────────
RULES_FILE="drivers/kernelsu/selinux/rules.c"
if [ -f "$RULES_FILE" ]; then
    echo "Injecting NTSYNC SELinux rules into KernelSU..."
    sed -i '/rcu_assign_pointer(selinux_state.policy, pol);/i \
    \/\/ NTSYNC SEPol — allow kernel worker to chmod and relabel \/dev\/ntsync\n\
    ksu_allow(db, "kernel", "device", "chr_file", "setattr");\n\
    ksu_allow(db, "kernel", "device", "chr_file", "relabelfrom");\n\
    ksu_allow(db, "kernel", "gpu_device", "chr_file", "relabelto");\n\
    ksu_allow(db, "kernel", "gpu_device", "chr_file", "setattr");\n\
    \n\
    \/\/ NTSYNC SEPol — allow Winlator (untrusted_app) to use \/dev\/ntsync\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "read");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "write");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "open");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "ioctl");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "map");\n' \
    "$RULES_FILE"
    echo "NTSYNC SELinux rules injected."
else
    echo "No KernelSU rules.c found — skipping NTSYNC SELinux injection."
fi

# ── Generate kernel config ───────────────────────────────────────────────────
echo "Generating GKI defconfig..."
make O=out gki_defconfig

# ── Configure ThinLTO ────────────────────────────────────────────────────────
echo "Configuring ThinLTO..."
scripts/config --file out/.config \
    -e LTO_CLANG \
    -d LTO_NONE \
    -e LTO_CLANG_THIN \
    -d LTO_CLANG_FULL \
    -e THINLTO

# ── Build kernel image ───────────────────────────────────────────────────────
echo "Building kernel image..."
make -j$(nproc --all) O=out Image

# ── KMI validation ───────────────────────────────────────────────────────────
echo "Running KMI validation..."
python3 KMI_function_symbols_test.py

echo "Build completed successfully! Toolchain: ${CLANG_VARIANT}"
