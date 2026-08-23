#!/bin/sh
set -eu

# $TARGET_DIR is passed by Buildroot
T="${TARGET_DIR}"

# Buildroot exports BR2_CONFIG, but we set a default just in case
BR2_CONFIG="${BR2_CONFIG:-.config}"

# ------------------------------------------------------------------------------
# Board Detection
# ------------------------------------------------------------------------------
# We check the actual configuration symbols to determine the board variant.

if grep -q "^BR2_PACKAGE_RPI_FIRMWARE_VARIANT_PI4=y" "$BR2_CONFIG"; then
    COMPAT_STR="InstrumentCluster-RPi4"
    BOARD_NAME="Raspberry Pi 4 B"
elif grep -q "^BR2_PACKAGE_RPI_FIRMWARE_VARIANT_PI5=y" "$BR2_CONFIG"; then
    COMPAT_STR="InstrumentCluster-RPi5"
    BOARD_NAME="Raspberry Pi 5"
else
    # Fallback: Check if the legacy RPi4 64-bit string exists in the config header
    # or default to a safe generic name.
    if grep -q "raspberrypi4-64" "$BR2_CONFIG"; then
        COMPAT_STR="InstrumentCluster-RPi4"
        BOARD_NAME="Raspberry Pi 4 B"
    else
        COMPAT_STR="InstrumentCluster-Generic"
        BOARD_NAME="Raspberry Pi (Generic)"
        echo "WARNING: Could not detect specific RPi firmware variant. Defaulting to Generic."
    fi
fi

echo "POST-BUILD: Detected Board: $BOARD_NAME ($COMPAT_STR)"

# ------------------------------------------------------------------------------
# Update RAUC Configuration
# ------------------------------------------------------------------------------
if [ -f "$T/etc/rauc/system.conf" ]; then
    sed -i "s/@BOARD_COMPATIBLE@/$COMPAT_STR/g" "$T/etc/rauc/system.conf"
    echo "POST-BUILD: Configured RAUC system.conf for $COMPAT_STR"
fi

# ------------------------------------------------------------------------------
# Generate /etc/os-release
# ------------------------------------------------------------------------------
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

echo "POST-BUILD: Generated /etc/os-release"

# ------------------------------------------------------------------------------
# Create Directory Structure & Permissions
# ------------------------------------------------------------------------------
mkdir -p \
  "$T/etc/systemd/system/multi-user.target.wants" \
  "$T/etc/systemd/system/getty.target.wants"

# Make installers executable if they exist
for script in "mount-overlay.sh"; do
    if [ -e "$T/usr/local/bin/$script" ]; then
        chmod 0755 "$T/usr/local/bin/$script"
    fi
done

# ------------------------------------------------------------------------------
# Systemd Tweaks
# ------------------------------------------------------------------------------
# We check for the directory existence instead of a specific optional service file.
UNITDIR=""
for d in /usr/lib/systemd/system /lib/systemd/system; do
  if [ -d "$T$d" ]; then
      UNITDIR="$d"
      break
  fi
done

if [ -n "$UNITDIR" ]; then
    echo "POST-BUILD: Found systemd unit dir at $UNITDIR"

    # Force a login prompt on tty1
    # if [ -e "$T$UNITDIR/getty@.service" ]; then
    #   ln -snf "$UNITDIR/getty@.service" \
    #     "$T/etc/systemd/system/getty.target.wants/getty@tty1.service"
    # fi
    
    # Mask the generic wpa_supplicant unit so only the @wlan0 instance runs
    # This prevents wpa_supplicant from fighting with NetworkManager or running without config
    ln -snf /dev/null "$T/etc/systemd/system/wpa_supplicant.service"
    rm -f "$T/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service" 2>/dev/null || true

    # DEBUG: Mask instrument-cluster service
    # if [ -e "${T}/usr/lib/systemd/system/instrument-cluster.service" ]; then
    #   ln -sf /dev/null "${T}/etc/systemd/system/instrument-cluster.service"
    # fi
else
    echo "POST-BUILD: WARNING - Systemd unit directory not found. Skipping systemd tweaks."
fi

# ------------------------------------------------------------------------------
# Build integrity (all variants — not release-specific)
# ------------------------------------------------------------------------------
# Kernel modules must actually be loadable. Buildroot's LINUX_RUN_DEPMOD
# target-finalize hook has already run by the time post-build scripts execute,
# so the tables below are final. depmod runs on the HOST and needs a
# decompressor matching the kernel's CONFIG_MODULE_COMPRESS_*
# (BR2_PACKAGE_HOST_KMOD_GZ / _XZ / _ZSTD). When those disagree, depmod cannot
# read a single .ko and fails SILENTLY, leaving empty tables — udev then
# resolves no aliases and autoloads nothing. Most Pi 4 drivers are built in, but
# panel-waveshare-dsi deliberately stays =m and would never load.
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

# ------------------------------------------------------------------------------
# Release Hardening
# ------------------------------------------------------------------------------
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

exit 0