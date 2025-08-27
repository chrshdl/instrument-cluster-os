#!/bin/sh
set -eu

T="${TARGET_DIR}"

# Ensure target dirs exist
mkdir -p \
  "$T/etc/systemd/system/multi-user.target.wants" \
  "$T/etc/systemd/system/getty.target.wants" \
  "$T/etc/wpa_supplicant"

# Make sure the Wi-Fi installer is executable
if [ -e "$T/usr/local/bin/install-wifi-config.sh" ]; then
  chmod 0755 "$T/usr/local/bin/install-wifi-config.sh"
fi

# Find systemd unit dir in the image
UNITDIR=""
for d in /lib/systemd/system /usr/lib/systemd/system; do
  if [ -e "$T$d/systemd-networkd.service" ]; then UNITDIR="$d"; break; fi
done
[ -n "$UNITDIR" ] || { echo "ERROR: systemd unit dir not found in target"; exit 1; }

# Force a login prompt on tty1
if [ -e "$T$UNITDIR/getty@.service" ]; then
  ln -snf "$UNITDIR/getty@.service" \
    "$T/etc/systemd/system/getty.target.wants/getty@tty1.service"
fi

# Mask the generic wpa_supplicant unit so only the @wlan0 instance runs
ln -snf /dev/null "$T/etc/systemd/system/wpa_supplicant.service"
rm -f "$T/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service" 2>/dev/null || true

# FOR DEBUG: mask instrument-cluster so it doesn't start
# if [ -e "${TARGET_DIR}/usr/lib/systemd/system/instrument-cluster.service" ]; then
#   ln -sf /dev/null "${TARGET_DIR}/etc/systemd/system/instrument-cluster.service"
# fi