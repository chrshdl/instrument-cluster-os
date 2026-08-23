#!/bin/sh
set -eu

T="${TARGET_DIR}"

BR2_CONFIG=$BR2_CONFIG
[ -z "$BR2_CONFIG" ] && BR2_CONFIG=".config"

# Extract the defconfig name directly from the build config
# This avoids relying on the environment variable being exported
if grep -q "BR2_DEFCONFIG=.*raspberrypi4-64" "$BR2_CONFIG"; then
    COMPAT_STR="InstrumentCluster-RPi4"
    BOARD_NAME="Raspberry Pi 4 B"
else
    COMPAT_STR="InstrumentCluster-RPi5"
    BOARD_NAME="Raspberry Pi 5"
fi

# Update RAUC system.conf
if [ -f "$T/etc/rauc/system.conf" ]; then
    sed -i "s/@BOARD_COMPATIBLE@/$COMPAT_STR/g" "$T/etc/rauc/system.conf"
    echo "RAUC: Configured system.conf for $COMPAT_STR"
fi

# Generate a custom /etc/os-release
# This helps the Python code identify the hardware and version.
# Buildroot generated its own os-release earlier in target-finalize (and
# /etc/os-release symlinks to /usr/lib/os-release, so the heredoc below
# replaces it) — capture the Buildroot version first; the OTA screen shows it.
BUILDROOT_VERSION="$(sed -n 's/^VERSION_ID=//p' "$T/usr/lib/os-release" 2>/dev/null | tr -d '"')"
[ -n "$BUILDROOT_VERSION" ] || BUILDROOT_VERSION="${BR2_VERSION_FULL:-unknown}"

cat <<EOF > "$T/etc/os-release"
NAME="InstrumentCluster-OS"
ID=instrument-cluster
PRETTY_NAME="Instrument Cluster OS ($BOARD_NAME)"
BUILD_ID=$(date +%Y%m%d%H%M)
VARIANT_ID=$COMPAT_STR
BUILDROOT_VERSION="$BUILDROOT_VERSION"
EOF

# The OS release version (the git tag, e.g. v0.1.19) is passed in by CI on
# tagged builds. Local/PR builds omit it; the app then falls back to BUILD_ID.
if [ -n "${IC_OS_VERSION:-}" ]; then
    echo "VERSION_ID=\"$IC_OS_VERSION\"" >> "$T/etc/os-release"
fi

echo "OS-RELEASE: Created for $BOARD_NAME"

# Ensure target dirs exist
# NOTE: do NOT create "$T/etc/wpa_supplicant" here — the rootfs overlay symlinks
# it to /data/etc/wpa_supplicant, so at build time it's a dangling symlink and
# `mkdir -p` fails with "File exists" (a non-directory already exists). The real
# directory is created at runtime by prepare-data-dirs.service. (RPi4 omits it
# too.)
mkdir -p \
  "$T/etc/systemd/system/multi-user.target.wants" \
  "$T/etc/systemd/system/getty.target.wants"

# Make sure the mount-overlay installer is executable
if [ -e "$T/usr/local/bin/mount-overlay.sh" ]; then
  chmod 0755 "$T/usr/local/bin/mount-overlay.sh"
fi

# Find systemd unit dir in the image
UNITDIR=""
for d in /lib/systemd/system /usr/lib/systemd/system; do
  if [ -e "$T$d/systemd-networkd.service" ]; then UNITDIR="$d"; break; fi
done
[ -n "$UNITDIR" ] || { echo "ERROR: systemd unit dir not found in target"; exit 1; }

# Force a login prompt on tty1
# if [ -e "$T$UNITDIR/getty@.service" ]; then
#   ln -snf "$UNITDIR/getty@.service" \
#     "$T/etc/systemd/system/getty.target.wants/getty@tty1.service"
# fi

# Mask the generic wpa_supplicant unit so only the @wlan0 instance runs
ln -snf /dev/null "$T/etc/systemd/system/wpa_supplicant.service"
rm -f "$T/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service" 2>/dev/null || true

# FOR DEBUG: mask instrument-cluster so it doesn't start
# if [ -e "${TARGET_DIR}/usr/lib/systemd/system/instrument-cluster.service" ]; then
#   ln -sf /dev/null "${TARGET_DIR}/etc/systemd/system/instrument-cluster.service"
# fi

# ------------------------------------------------------------------------------
# Build integrity (all variants — not release-specific)
# ------------------------------------------------------------------------------
# Kernel modules must actually be loadable. Buildroot's LINUX_RUN_DEPMOD
# target-finalize hook has already run by the time post-build scripts execute,
# so the tables below are final. depmod runs on the HOST and needs a
# decompressor matching the kernel's CONFIG_MODULE_COMPRESS_*
# (BR2_PACKAGE_HOST_KMOD_GZ / _XZ / _ZSTD). When those disagree, depmod cannot
# read a single .ko and fails SILENTLY, leaving empty tables — udev then
# resolves no aliases and autoloads nothing. On the Pi 5 that is fatal (RP1
# I/O, the DSI panel and touch are all modules here) and presents as a reboot
# loop with no display.
for moddir in "$T"/lib/modules/*/; do
    [ -d "$moddir/kernel" ] || continue   # fully built-in kernel: nothing to check
    if [ ! -s "$moddir/modules.dep" ]; then
        echo "POST-BUILD ERROR: ${moddir}modules.dep is empty although modules are installed." >&2
        echo "  host depmod could not read them — BR2_PACKAGE_HOST_KMOD_GZ/_XZ/_ZSTD" >&2
        echo "  must match the kernel's CONFIG_MODULE_COMPRESS_*." >&2
        exit 1
    fi
    if ! grep -q "^alias " "$moddir/modules.alias" 2>/dev/null; then
        echo "POST-BUILD ERROR: ${moddir}modules.alias has no alias entries —" >&2
        echo "  udev cannot autoload any driver (same cause as an empty modules.dep)." >&2
        exit 1
    fi
    echo "POST-BUILD: module tables OK ($(wc -l < "$moddir/modules.dep") deps, $(grep -c "^alias " "$moddir/modules.alias") aliases)"
done

# The shared rootfs overlay always ships sshd config for dev images; release
# builds (configs/release.fragment) drop OpenSSH itself — remove the now-inert
# config so shipped images contain no SSH artifacts at all. CI's
# assert-release-image.sh verifies this on the built rootfs.ext4.
if ! grep -q "^BR2_PACKAGE_OPENSSH=y" "$BR2_CONFIG"; then
    rm -rf "$T/etc/ssh" "$T/etc/systemd/system/sshd.service.d"
    echo "POST-BUILD: OpenSSH not in config — removed SSH overlay leftovers"

    # No local login prompt in shipped images: mask the getty templates so
    # systemd's getty-generator cannot spawn a login shell on the serial
    # console (or any console). Root is locked in release, but the prompt
    # itself is still attack surface; post-image.sh additionally drops the
    # serial console from cmdline.txt and disables UART/U-Boot interruption.
    # CI's assert-release-image.sh verifies the masking on the built rootfs.
    ln -snf /dev/null "$T/etc/systemd/system/serial-getty@.service"
    ln -snf /dev/null "$T/etc/systemd/system/console-getty.service"
    ln -snf /dev/null "$T/etc/systemd/system/getty@.service"
    rm -f "$T/etc/systemd/system/getty.target.wants/"*getty* 2>/dev/null || true
    echo "POST-BUILD: release — masked getty templates (no local login prompt)"
fi