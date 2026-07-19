#!/bin/sh
set -eu
umask 077

SRC=/boot/wpa_supplicant-wlan0.conf
DST=/etc/wpa_supplicant/wpa_supplicant-wlan0.conf
MARKER=/var/lib/wifi-config-installed   # created, but not used to skip

# Only proceed if the source file is present
[ -f "$SRC" ] || { echo "No $SRC found, skipping Wi-Fi setup."; exit 0; }

# Ensure dirs
mkdir -p /etc/wpa_supplicant /var/lib

# Copy while stripping Windows CRs; if you prefer, you can replace this with: cp "$SRC" "$DST"
tr -d '\r' < "$SRC" > "$DST"

chmod 600 "$DST"
touch "$MARKER"

# Hide the source file so it won't be re-used accidentally on next boot
mv -f "$SRC" "${SRC}.installed" 2>/dev/null || rm -f "$SRC"

sync
echo "Installed $DST from $SRC (normalized)."
