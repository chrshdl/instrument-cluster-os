#!/bin/sh
set -eu
umask 077

SRC=/boot/wpa_supplicant-wlan0.conf
DST=/etc/wpa_supplicant/wpa_supplicant-wlan0.conf
MARKER=/var/lib/wifi-config-installed

# One-shot
[ -e "$MARKER" ] && { echo "Wi-Fi config already installed, skipping."; exit 0; }

# Only proceed if the source file is present
[ -f "$SRC" ] || { echo "No $SRC found, skipping Wi-Fi setup."; exit 0; }

# Ensure dirs
mkdir -p /etc/wpa_supplicant /var/lib

# Copy while stripping Windows CRs; preserve only what the user wrote
tr -d '\r' < "$SRC" > "$DST"

chmod 600 "$DST"
touch "$MARKER"

# Hide the source file so it won't be re-used
mv -f "$SRC" "${SRC}.installed" 2>/dev/null || rm -f "$SRC"

sync
echo "Installed $DST from $SRC (normalized)."
