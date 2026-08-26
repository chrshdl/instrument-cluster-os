#!/bin/bash

set -e

# $1 is the first argument passed by Buildroot, which is the images directory (output/images)
BINARIES_DIR="$1"
BOARD_DIR="$(dirname $0)"
GENIMAGE_CFG="${BOARD_DIR}/genimage.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# 1. Compile U-Boot script (boot.cmd -> boot.scr)
# This is the "brain" of the A/B switching logic.
# Requires 'host-uboot-tools' to be enabled in menuconfig.
if [ -f "${BOARD_DIR}/boot.cmd" ]; then
    echo "Generating boot.scr from ${BOARD_DIR}/boot.cmd..."
    "${HOST_DIR}/bin/mkimage" -A arm64 -T script -C none -n "U-Boot boot script" \
        -d "${BOARD_DIR}/boot.cmd" "${BINARIES_DIR}/boot.scr"
fi

# 2. Release hardening of the boot artifacts (same release detection as
# post-build.sh: configs/release.fragment drops OpenSSH). Dev builds keep
# serial console + interruptible U-Boot for the bench workflow.
# Only the staged copies in BINARIES_DIR are touched, never the source tree.
# CI's assert-release-image.sh verifies all three on the built artifacts.
if ! grep -q "^BR2_PACKAGE_OPENSSH=y" "${BR2_CONFIG}"; then
    echo "POST-IMAGE: release — hardening boot artifacts"

    # No serial console: kernel logs/getty stay off the UART...
    sed -i 's/ console=ttyAMA[0-9]*,[0-9]*//' "${BINARIES_DIR}/rpi-firmware/cmdline.txt"
    # ...and the UART is not brought up by the firmware at all.
    sed -i 's/^enable_uart=1/enable_uart=0/' "${BINARIES_DIR}/rpi-firmware/config.txt"

    # Non-interruptible U-Boot, two independent ways: bootdelay=-2 autoboots
    # without ever calling abortboot, and stdin is pointed at "nulldev", whose
    # tstc() always returns 0 (common/stdio.c, CONFIG_SYS_DEVICE_NULLDEV=y on
    # both boards) — so even if bootdelay were somehow reset, no keypress can
    # be seen.
    #
    # It MUST name a device that exists. This previously said "usbkbd" on the
    # theory that USB is compiled out of the U-Boot build so it would be
    # inert; the opposite is true. console_init_r() ends with
    #
    #     if (inputdev == NULL)
    #             inputdev = console_search_dev(DEV_FLAGS_INPUT, "serial");
    #
    # so naming a device that does not exist falls straight back to serial,
    # and the release image had a live serial console with bootdelay as its
    # only guard. assert-release-image.sh now asserts stdin=nulldev
    # positively, because "does not contain stdin=serial" was satisfied by the
    # very value that produced serial input.
    #
    # Regenerate the redundant env image from a hardened copy of
    # uboot-env.txt; size/redundancy must match the defconfig's
    # BR2_PACKAGE_HOST_UBOOT_TOOLS_ENVIMAGE_SIZE/_REDUNDANT (0x4000, -r).
    sed -e 's/^bootdelay=.*/bootdelay=-2/' \
        -e 's/^stdin=.*/stdin=nulldev/' \
        "${BOARD_DIR}/uboot-env.txt" > "${BUILD_DIR}/uboot-env-release.txt"
    "${HOST_DIR}/bin/mkenvimage" -r -s 0x4000 \
        -o "${BINARIES_DIR}/uboot-env.bin" "${BUILD_DIR}/uboot-env-release.txt"
fi

# 3. Generate the SD Card Image
# We use a temporary directory for rootpath to keep the image generation clean.
trap 'rm -rf "${ROOTPATH_TMP}"' EXIT
ROOTPATH_TMP="$(mktemp -d)"

rm -rf "${GENIMAGE_TMP}"

genimage \
    --rootpath "${ROOTPATH_TMP}"   \
    --tmppath "${GENIMAGE_TMP}"    \
    --inputpath "${BINARIES_DIR}"  \
    --outputpath "${BINARIES_DIR}" \
    --config "${GENIMAGE_CFG}"

exit $?