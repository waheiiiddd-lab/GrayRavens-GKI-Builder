#!/bin/bash
# android12-5.10 GKI Kernel Build Script
set -e

# Error handler
trap 'echo "Build failed at line $LINENO. Exit code: $?" >&2' ERR

# ── Environment setup ────────────────────────────────────────────────────────
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
export KBUILD_BUILD_USER="GrayRavens-Team"
export KBUILD_BUILD_HOST="ZenithXHikari-KasumiXIyashi"

# ── Clang toolchain ──────────────────────────────────────────────────────────
if [ -z "$CLANG_PATH" ]; then
    echo "ERROR: CLANG_PATH is not set. Did you run this from the workflow?" >&2
    exit 1
fi

export PATH="${CLANG_PATH}/bin:${PATH}"

echo "CLANG_VARIANT   : '${CLANG_VARIANT}'"
echo "Toolchain path  : $CLANG_PATH"
echo "Clang version   : $("$CLANG_PATH/bin/clang" --version | head -n1)"

# ── Compiler string (shown in /proc/version) ─────────────────────────────────
if [ "${CLANG_VARIANT}" = "NEUTRON-19" ]; then
    COMPILER_STRING="Neutron Clang 19.0.0 +PGO +BOLT +Polly +ThinLTO +O3"
elif [ "${CLANG_VARIANT}" = "CLANG-12" ]; then
    COMPILER_STRING="AOSP Clang r416183b (LLVM 12.0.5)"
else
    COMPILER_STRING="$("$CLANG_PATH/bin/clang" --version | head -n1)"
fi

echo "Compiler string : $COMPILER_STRING"

# ── KCFLAGS ──────────────────────────────────────────────────────────────────
export KCFLAGS="-w -march=armv8.2-a -mtune=cortex-a55"

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

# ── Patch mkcompile_h to force compiler string ───────────────────────────────
# The kernel reads compiler string from scripts/mkcompile_h directly
echo "Patching mkcompile_h to override compiler string..."
sed -i "s|LINUX_COMPILER=.*|LINUX_COMPILER=\"${COMPILER_STRING}\"|g" scripts/mkcompile_h 2>/dev/null || true

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
make -j$(nproc --all) O=out \
    KBUILD_COMPILER_STRING="${COMPILER_STRING}" \
    Image

# ── Post-build vmlinux verification ─────────────────────────────────────────
echo ""
echo "=== Post-build verification ==="

echo "--- Compiler used (from vmlinux .comment) ---"
readelf -p .comment out/vmlinux 2>/dev/null \
    | grep -v "^$\|String dump" || echo "Could not read .comment"

echo "--- LTO config check ---"
grep -E "CONFIG_LTO|CONFIG_THINLTO" out/.config || echo "No LTO configs found"

echo "--- ThinLTO cache ---"
if [ -d out/.thinlto-cache ] && [ "$(ls -A out/.thinlto-cache)" ]; then
    echo "ThinLTO cache present — ThinLTO ran successfully"
    ls -lah out/.thinlto-cache/ | head -5
else
    echo "No ThinLTO cache found"
fi

echo "--- Kernel compile.h ---"
cat out/include/generated/compile.h 2>/dev/null || echo "compile.h not found"

echo "=== Verification complete ==="

# ── KMI validation ───────────────────────────────────────────────────────────
echo "Running KMI validation..."
python3 KMI_function_symbols_test.py

echo "Build completed successfully! Toolchain: ${CLANG_VARIANT}"
