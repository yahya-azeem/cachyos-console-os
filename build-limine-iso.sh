#!/bin/bash
# ============================================================================
# build-limine-iso.sh — Build CachyOS Live ISO with Limine bootloader
# ============================================================================
#
# This script builds a CachyOS Live ISO that uses Limine instead of GRUB.
# It works in two phases:
#   Phase 1: Use mkarchiso to build the root filesystem (squashfs, kernels, etc.)
#   Phase 2: Repackage the built content into a new ISO with Limine.
#
# Requirements:
#   - archiso (for mkarchiso)
#   - limine (provides /usr/share/limine/ binaries)
#   - xorriso (for ISO creation)
#   - Must be run as root (sudo)
#
# Usage:
#   sudo ./build-limine-iso.sh [-c] [-v] [-s]
#     -c    Skip cleaning (reuse previous mkarchiso build)
#     -v    Verbose output
#     -s    Skip Phase 1 (reuse existing mkarchiso output in build/)
#     -h    Show help
#
# ============================================================================

set -euo pipefail

# ————————————————————————————————————————————
# Configuration
# ————————————————————————————————————————————

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/build"
OUT_DIR="${SCRIPT_DIR}/out/limine"
ISO_ROOT="${WORK_DIR}/iso_root"
ARCHISO_PROFILE="${SCRIPT_DIR}/archiso"

# Limine binary locations (from the limine package)
LIMINE_DIR="/usr/share/limine"
LIMINE_CONF="${SCRIPT_DIR}/limine.conf"

# ISO metadata
ISO_NAME="cachyos"
INSTALL_DIR="arch"
ARCH="x86_64"

# Build options
CLEAN_FIRST=true
VERBOSE=false
SKIP_PHASE1=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ————————————————————————————————————————————
# Helper functions
# ————————————————————————————————————————————

msg()    { echo -e "${GREEN}==>${NC} $*"; }
msg2()   { echo -e "${BLUE}  ->${NC} $*"; }
warn()   { echo -e "${YELLOW}==> WARNING:${NC} $*"; }
error()  { echo -e "${RED}==> ERROR:${NC} $*" >&2; }

usage() {
    echo "Usage: ${0##*/} [options]"
    echo ""
    echo "Build a CachyOS Live ISO with Limine bootloader."
    echo ""
    echo "Options:"
    echo "    -c    Skip cleaning (reuse previous build artifacts)"
    echo "    -v    Verbose output"
    echo "    -s    Skip Phase 1 (reuse existing mkarchiso output)"
    echo "    -h    Show this help"
    echo ""
    echo "This script must be run as root (sudo)."
    exit "${1:-0}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root."
        echo "  Try: sudo $0 $*"
        exit 1
    fi
}

check_requirements() {
    local missing=()

    if ! command -v mkarchiso &>/dev/null; then
        missing+=("archiso (provides mkarchiso)")
    fi
    if ! command -v xorriso &>/dev/null; then
        missing+=("xorriso")
    fi
    if ! command -v limine &>/dev/null; then
        missing+=("limine")
    fi
    if [[ ! -d "$LIMINE_DIR" ]]; then
        missing+=("limine (missing $LIMINE_DIR)")
    fi
    if [[ ! -f "$LIMINE_CONF" ]]; then
        missing+=("limine.conf (missing $LIMINE_CONF)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing requirements:"
        for m in "${missing[@]}"; do
            echo "  - $m"
        done
        echo ""
        echo "Install missing packages:"
        echo "  sudo pacman -S archiso limine xorriso"
        exit 1
    fi

    msg2 "All requirements satisfied"
}

# ————————————————————————————————————————————
# Parse arguments
# ————————————————————————————————————————————

while getopts "cvsh" arg; do
    case "${arg}" in
        c) CLEAN_FIRST=false ;;
        v) VERBOSE=true ;;
        s) SKIP_PHASE1=true ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

# ————————————————————————————————————————————
# Pre-flight checks
# ————————————————————————————————————————————

check_root "$@"
msg "CachyOS Limine ISO Builder"
msg "=========================="
echo ""
check_requirements

# ————————————————————————————————————————————
# Phase 1: Build rootfs with mkarchiso
# ————————————————————————————————————————————

phase1_build() {
    msg "${CYAN}Phase 1:${NC} Building root filesystem with mkarchiso"
    echo ""

    if $CLEAN_FIRST; then
        msg2 "Cleaning previous build..."
        rm -rf "${WORK_DIR}"
    fi

    mkdir -p "${WORK_DIR}"

    # Copy the archiso profile to a working copy so we can prep it
    local profile_work="${WORK_DIR}/archiso"
    if [[ ! -d "$profile_work" ]]; then
        msg2 "Copying archiso profile to build directory..."
        cp -r "${ARCHISO_PROFILE}" "${profile_work}"
    fi

    # Prepare packages.x86_64 from the desktop package list
    if [[ -f "${profile_work}/packages_desktop.x86_64" ]]; then
        cp "${profile_work}/packages_desktop.x86_64" "${profile_work}/packages.x86_64"
        msg2 "Using desktop package list"
    fi

    # Ensure no display-manager symlink is created
    rm -f "${profile_work}/airootfs/etc/systemd/system/display-manager.service"

    # Generate MOTD
    cat << 'MOTDEOF' > "${profile_work}/airootfs/etc/motd"
This ISO is based on ArchLinux ISO modified to provide Installation Environment for CachyOS.
https://cachyos.org

CachyOS Archiso Sources:
https://github.com/cachyos/cachyos-live-iso

Built with Limine bootloader for improved hardware compatibility.

Welcome to your CachyOS!
MOTDEOF

    # Run mkarchiso
    local mkarchiso_args=("-w" "${WORK_DIR}" "-o" "${WORK_DIR}/mkarchiso_out")
    if $VERBOSE; then
        mkarchiso_args+=("-v")
    fi

    mkdir -p "${WORK_DIR}/mkarchiso_out"

    msg2 "Running mkarchiso (this may take a while)..."
    echo ""
    mkarchiso "${mkarchiso_args[@]}" "${profile_work}/"

    msg2 "Phase 1 complete — rootfs built successfully"
    echo ""
}

# ————————————————————————————————————————————
# Phase 2: Assemble Limine ISO
# ————————————————————————————————————————————

phase2_assemble() {
    msg "${CYAN}Phase 2:${NC} Assembling Limine ISO"
    echo ""

    # ———— Locate the built content ————
    # mkarchiso puts the ISO content under work_dir/iso/
    local iso_content="${WORK_DIR}/iso"

    if [[ ! -d "$iso_content" ]]; then
        error "Cannot find mkarchiso output at ${iso_content}"
        error "Make sure Phase 1 completed successfully, or run without -s."
        exit 1
    fi

    # Verify critical files exist
    local kernel_dir="${iso_content}/${INSTALL_DIR}/boot/${ARCH}"
    if [[ ! -f "${kernel_dir}/vmlinuz-linux-cachyos" ]]; then
        error "Cannot find kernel at ${kernel_dir}/vmlinuz-linux-cachyos"
        exit 1
    fi
    msg2 "Found mkarchiso output at ${iso_content}"

    # ———— Create ISO staging area ————
    msg2 "Creating ISO staging area..."
    rm -rf "${ISO_ROOT}"
    mkdir -p "${ISO_ROOT}"

    # Copy the arch/ directory (squashfs, kernels, initramfs, pkglist)
    msg2 "Copying arch/ directory (squashfs + kernels + initramfs)..."
    cp -a "${iso_content}/${INSTALL_DIR}" "${ISO_ROOT}/${INSTALL_DIR}"

    # Also copy any other top-level content from the ISO (memtest, shellx64, etc.)
    for item in "${iso_content}"/*; do
        local basename=$(basename "$item")
        if [[ "$basename" != "${INSTALL_DIR}" && "$basename" != "EFI" && "$basename" != "boot" && "$basename" != "syslinux" && "$basename" != "isolinux" ]]; then
            cp -a "$item" "${ISO_ROOT}/" 2>/dev/null || true
        fi
    done

    # ———— Install Limine files ————
    msg2 "Installing Limine bootloader files..."

    # Limine BIOS files
    mkdir -p "${ISO_ROOT}/boot/limine"
    cp "${LIMINE_DIR}/limine-bios.sys"    "${ISO_ROOT}/boot/limine/"
    cp "${LIMINE_DIR}/limine-bios-cd.bin" "${ISO_ROOT}/boot/limine/"
    cp "${LIMINE_DIR}/limine-uefi-cd.bin" "${ISO_ROOT}/boot/limine/"

    # UEFI EFI application (removable media standard path)
    mkdir -p "${ISO_ROOT}/EFI/BOOT"
    cp "${LIMINE_DIR}/BOOTX64.EFI"  "${ISO_ROOT}/EFI/BOOT/"
    # Also include IA32 for 32-bit UEFI firmware (some older boards)
    cp "${LIMINE_DIR}/BOOTIA32.EFI" "${ISO_ROOT}/EFI/BOOT/"

    # ———— Install and process limine.conf ————
    msg2 "Processing limine.conf (substituting placeholders)..."
    cp "${LIMINE_CONF}" "${ISO_ROOT}/boot/limine/limine.conf"

    # Determine the ISO UUID (same method archiso uses)
    # archiso generates this from iso_label in profiledef.sh
    # We source profiledef.sh to get the label
    local iso_label=""
    if [[ -f "${ARCHISO_PROFILE}/profiledef.sh" ]]; then
        # Source profiledef.sh in a subshell to extract iso_label
        iso_label=$(bash -c "declare -A file_permissions; source '${ARCHISO_PROFILE}/profiledef.sh' 2>/dev/null; echo \"\$iso_label\"")
    fi
    if [[ -z "$iso_label" ]]; then
        iso_label="COS_$(date +%Y%m)"
    fi

    # The ARCHISO_UUID is the ISO label used for searching the medium
    # mkarchiso stores this — let's try to find it from the existing build
    local archiso_uuid=""

    # Check if mkarchiso left a UUID file
    if [[ -f "${WORK_DIR}/iso/${INSTALL_DIR}/buildinfo" ]]; then
        archiso_uuid=$(grep -oP 'uuid=\K.*' "${WORK_DIR}/iso/${INSTALL_DIR}/buildinfo" 2>/dev/null || true)
    fi

    # Fallback: use the ISO volume label (this is what archiso uses as the search UUID)
    if [[ -z "$archiso_uuid" ]]; then
        archiso_uuid="${iso_label}"
    fi

    msg2 "ISO Label/UUID: ${archiso_uuid}"

    # Substitute placeholders in limine.conf
    sed -i "s|%INSTALL_DIR%|${INSTALL_DIR}|g" "${ISO_ROOT}/boot/limine/limine.conf"
    sed -i "s|%ARCH%|${ARCH}|g"               "${ISO_ROOT}/boot/limine/limine.conf"
    sed -i "s|%ARCHISO_UUID%|${archiso_uuid}|g" "${ISO_ROOT}/boot/limine/limine.conf"

    msg2 "Limine configuration:"
    echo "  ────────────────────────────────"
    cat "${ISO_ROOT}/boot/limine/limine.conf" | sed 's/^/  /'
    echo "  ────────────────────────────────"
    echo ""

    # ———— Create the ISO image ————
    local iso_version="$(date +%y%m%d)"
    local iso_filename="cachyos-desktop-linux-${iso_version}-limine.iso"

    mkdir -p "${OUT_DIR}"
    local iso_path="${OUT_DIR}/${iso_filename}"

    msg2 "Creating hybrid BIOS/UEFI ISO image..."
    msg2 "Output: ${iso_path}"

    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -joliet \
        -joliet-long \
        -rational-rock \
        -volid "${iso_label}" \
        -appid "CachyOS Live ISO (Limine)" \
        -publisher "CachyOS <https://cachyos.org>" \
        -preparer "build-limine-iso.sh" \
        -b boot/limine/limine-bios-cd.bin \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
        --efi-boot boot/limine/limine-uefi-cd.bin \
            -efi-boot-part \
            --efi-boot-image \
        --protective-msdos-label \
        "${ISO_ROOT}" \
        -o "${iso_path}"

    echo ""

    # ———— Patch MBR for BIOS boot ————
    msg2 "Patching ISO MBR for BIOS boot (limine bios-install)..."
    limine bios-install "${iso_path}"

    echo ""

    # ———— Generate checksums ————
    msg2 "Generating checksums..."
    cd "${OUT_DIR}"
    sha256sum "${iso_filename}" > "${iso_filename}.sha256"
    msg2 "SHA256: $(cat "${iso_filename}.sha256")"

    echo ""

    # ———— Summary ————
    local iso_size
    iso_size=$(du -h "${iso_path}" | cut -f1)

    msg "${GREEN}Build complete!${NC}"
    echo ""
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║  CachyOS Live ISO (Limine)                                 ║"
    echo "  ╠══════════════════════════════════════════════════════════════╣"
    echo "  ║  ISO:      ${iso_path}"
    echo "  ║  Size:     ${iso_size}"
    echo "  ║  Checksum: ${iso_filename}.sha256"
    echo "  ║  Label:    ${iso_label}"
    echo "  ╠══════════════════════════════════════════════════════════════╣"
    echo "  ║  Boot modes:                                               ║"
    echo "  ║    ✓ BIOS (Legacy) — via Limine MBR + El Torito            ║"
    echo "  ║    ✓ UEFI (x64)   — via Limine EFI + El Torito            ║"
    echo "  ║    ✓ UEFI (IA32)  — via Limine EFI (32-bit UEFI)          ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Test with QEMU:"
    echo "    BIOS:  qemu-system-x86_64 -cdrom ${iso_path} -m 4G"
    echo "    UEFI:  qemu-system-x86_64 -cdrom ${iso_path} -m 4G -bios /usr/share/edk2/x64/OVMF.fd"
    echo ""
    echo "  Write to USB:"
    echo "    sudo dd if=${iso_path} of=/dev/sdX bs=4M status=progress oflag=sync"
    echo ""
}

# ————————————————————————————————————————————
# Main
# ————————————————————————————————————————————

main() {
    local start_time
    start_time=$(date +%s)

    echo ""
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║          CachyOS Live ISO Builder (Limine)                  ║"
    echo "  ║          Hybrid BIOS + UEFI bootable ISO                   ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo ""

    # Phase 1: Build rootfs
    if ! $SKIP_PHASE1; then
        phase1_build
    else
        warn "Skipping Phase 1 (using existing mkarchiso output)"
        echo ""
    fi

    # Phase 2: Assemble Limine ISO
    phase2_assemble

    # Elapsed time
    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$(( end_time - start_time ))
    msg "Total build time: $(( elapsed / 60 ))m $(( elapsed % 60 ))s"
}

main "$@"
