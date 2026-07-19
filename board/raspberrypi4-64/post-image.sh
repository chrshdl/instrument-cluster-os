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

# 2. Copy wpa_supplicant-wlan0.conf template into BINARIES_DIR
# This allows genimage to find it and put it on the FAT partition.
cp -f "${BOARD_DIR}/wpa_supplicant-wlan0.conf" \
      "${BINARIES_DIR}/wpa_supplicant-wlan0.conf"

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