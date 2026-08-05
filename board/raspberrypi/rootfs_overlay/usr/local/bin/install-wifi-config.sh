#!/bin/sh
set -eu
umask 077

SRC=/boot/wpa_supplicant-wlan0.conf
DST=/etc/wpa_supplicant/wpa_supplicant-wlan0.conf
MARKER=/var/lib/wifi-config-installed   # created, but not used to skip

# Only proceed if the source file is present
[ -f "$SRC" ] || { echo "No $SRC found, skipping Wi-Fi setup."; exit 0; }

# An unedited template still carries the placeholder credentials it shipped
# with. Installing it would hand /data a network block the app's first-boot
# gate reads as "Wi-Fi provisioned" — it then skips the on-screen setup and
# polls association with a network that does not exist. Leave the file in
# place (untouched) so it can still be edited later for headless setup.
if grep -q "YOUR_WIFI_SSID" "$SRC"; then
    echo "Template $SRC unedited (placeholder SSID); leaving on-screen Wi-Fi setup in charge."
    exit 0
fi

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
