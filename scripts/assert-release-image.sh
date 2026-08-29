#!/bin/sh
# Hard-fail guard for release (v* tag) builds: the shipped rootfs must contain
# no SSH daemon and no unlocked root account. Asserts against the actual
# rootfs.ext4 — the artifact genimage stamps into both A/B slots of
# sdcard.img — not just the build config, so a forgotten or broken
# configs/release.fragment can never silently ship an open image.
#
# Usage: scripts/assert-release-image.sh <path/to/.config> <path/to/rootfs.ext4> [<images-dir>]
# With <images-dir> (output/images) it additionally asserts the hardened boot
# artifacts: no serial console in cmdline.txt, UART off in config.txt, and a
# non-interruptible U-Boot env (bootdelay=-2, stdin=nulldev).
# Requires: debugfs (e2fsprogs). No root needed.
set -eu

CONFIG="${1:?usage: assert-release-image.sh <.config> <rootfs.ext4> [<images-dir>]}"
ROOTFS="${2:?usage: assert-release-image.sh <.config> <rootfs.ext4> [<images-dir>]}"
IMAGES_DIR="${3:-}"

fail() { echo "RELEASE ASSERTION FAILED: $*" >&2; exit 1; }

[ -f "$CONFIG" ] || fail "config not found: $CONFIG"
[ -f "$ROOTFS" ] || fail "rootfs image not found: $ROOTFS"

# debugfs exits 0 even when a path does not exist ("File not found" goes to
# stderr), so parse its output instead of relying on exit codes.
fs_has() {
    ! debugfs -R "stat $1" "$ROOTFS" 2>&1 | grep -q "File not found"
}

# Sanity: prove debugfs can actually read this image, so a corrupt or wrong
# file can never make the negative checks below pass vacuously.
fs_has etc/os-release || fail "sanity check: etc/os-release missing — is $ROOTFS a valid rootfs?"

if grep -q "^BR2_PACKAGE_OPENSSH=y" "$CONFIG"; then
    fail "BR2_PACKAGE_OPENSSH=y still present in $CONFIG"
fi

for p in usr/sbin/sshd usr/bin/sshd sbin/sshd bin/sshd; do
    if fs_has "$p"; then
        fail "$p present in $ROOTFS"
    fi
done

if fs_has etc/ssh/sshd_config; then
    fail "etc/ssh/sshd_config present in $ROOTFS"
fi

# No generic download primitive in shipped images: release.fragment merges a
# BusyBox config fragment that drops the wget applet. Nothing on the device
# calls it (the app installer uses Python's urllib.request), so its presence
# means the fragment silently did not apply.
for p in usr/bin/wget bin/wget; do
    if fs_has "$p"; then
        fail "$p present in $ROOTFS — BusyBox wget applet was not dropped"
    fi
done

# Bluetooth is not a product feature and the off-switch is the kernel, not a
# device-tree overlay: with CONFIG_BT unset there is no bluetooth module tree
# at all. Asserted on the built rootfs because the config.txt check this
# replaces was commented out once and the radio driver then shipped unnoticed.
# (The overlay is deliberately NOT used — it broke boot on a Pi 4 Rev 1.5; see
# board/raspberrypi4-64/config.txt.)
kver="$(debugfs -R "ls lib/modules" "$ROOTFS" 2>/dev/null \
    | tr -c 'A-Za-z0-9._-' '\n' | grep -E '^[0-9]+\.[0-9]+' | head -1)"
if [ -n "$kver" ]; then
    for d in "lib/modules/$kver/kernel/net/bluetooth" "lib/modules/$kver/kernel/drivers/bluetooth"; do
        if fs_has "$d"; then
            fail "$d present in $ROOTFS — Bluetooth stack was not removed from the kernel"
        fi
    done
fi

# Root must be locked: shadow password field is '*' or starts with '!'.
# An empty field (passwordless login) or any hash fails this check.
shadow_root="$(debugfs -R "cat etc/shadow" "$ROOTFS" 2>/dev/null | grep "^root:")" \
    || fail "no root entry found in etc/shadow"
case "$shadow_root" in
    root:\**) : ;;
    root:\!*) : ;;
    *) fail "root account is not locked in etc/shadow" ;;
esac

# The rootfs is read-only, so /etc/machine-id is a symlink onto /data and
# something must create the target at boot. That provisioning once lived in a
# drop-in for sshd — which this variant deletes along with OpenSSH, leaving a
# dangling symlink that breaks everything needing a machine ID, including
# systemd-networkd's DHCP client (it fails the whole link, so the device
# associates to Wi-Fi and never gets an address). Hardening must not take
# non-SSH functionality with it.
if ! debugfs -R "cat etc/systemd/system/prepare-data-dirs.service" "$ROOTFS" 2>/dev/null \
        | grep -q "machine-id"; then
    fail "nothing provisions the machine id in $ROOTFS (prepare-data-dirs.service)"
fi

# No local login prompt: the getty templates must be masked (symlink to
# /dev/null), so systemd's getty-generator cannot spawn a login shell on the
# serial console even if a console= parameter reappeared in the cmdline.
for unit in serial-getty@.service console-getty.service getty@.service; do
    fs_has "etc/systemd/system/$unit" \
        || fail "etc/systemd/system/$unit missing — getty template not masked"
    debugfs -R "stat etc/systemd/system/$unit" "$ROOTFS" 2>/dev/null \
        | grep -q "/dev/null" \
        || fail "etc/systemd/system/$unit is not a mask (symlink to /dev/null)"
done

# The dashboard must not be a hard dependency of the splash screen. When a
# Requires= dependency fails, systemd DISCARDS the dependent unit's start job
# without a word: the app is never started, so it never fails, so
# StartLimitAction=reboot cannot fire and the device sits on the splash
# forever. It also never writes /boot/instrument-cluster.log, because main.py
# is never imported — so the one support channel a release image has goes
# silent exactly when it is needed. A Waveshare 5" shipped that way; the fault
# took a day to find because nothing on the device could report it.
sl_unit="$(debugfs -R "cat usr/lib/systemd/system/instrument-cluster.service" \
    "$ROOTFS" 2>/dev/null)"
echo "$sl_unit" | grep -q "splashscreen" \
    || fail "instrument-cluster.service does not reference splashscreen.service at all"
if echo "$sl_unit" | grep -qE "^Requires=.*splashscreen"; then
    fail "instrument-cluster.service Requires= splashscreen.service — a failed splash would discard the dashboard's start job (use Wants=)"
fi

# Boot-artifact assertions (only when the images dir is provided).
if [ -n "$IMAGES_DIR" ]; then
    CMDLINE="$IMAGES_DIR/rpi-firmware/cmdline.txt"
    CONFTXT="$IMAGES_DIR/rpi-firmware/config.txt"
    UBOOTENV="$IMAGES_DIR/uboot-env.bin"
    [ -f "$CMDLINE" ]  || fail "not found: $CMDLINE"
    [ -f "$CONFTXT" ]  || fail "not found: $CONFTXT"
    [ -f "$UBOOTENV" ] || fail "not found: $UBOOTENV"

    # No serial console for the kernel/getty.
    if grep -q "console=ttyAMA" "$CMDLINE"; then
        fail "serial console still present in cmdline.txt"
    fi
    # UART must not be brought up by the firmware.
    if grep -q "^enable_uart=1" "$CONFTXT"; then
        fail "enable_uart=1 still present in config.txt"
    fi
    # U-Boot must autoboot without an abort check, and stdin must be a device
    # that exists and never reports a keypress. The env image is NUL-separated
    # text, so grep -a works on it.
    grep -a -q -e "bootdelay=-2" "$UBOOTENV" \
        || fail "uboot-env.bin does not contain bootdelay=-2"
    # Assert nulldev POSITIVELY. A negative "no stdin=serial" check is not
    # enough: console_init_r() falls back to serial whenever the named device
    # is not registered, so any bogus name (this used to say usbkbd, with USB
    # compiled out of the U-Boot build) passes a negative check while giving
    # the image a live serial console.
    grep -a -q -e "stdin=nulldev" "$UBOOTENV" \
        || fail "uboot-env.bin does not set stdin=nulldev — U-Boot falls back to serial for any unregistered device"
    if grep -a -q -e "stdin=serial" "$UBOOTENV"; then
        fail "uboot-env.bin still lists serial as stdin"
    fi
fi

echo "OK: release image assertions passed (no sshd, no sshd_config, no wget, no bluetooth, root locked,
     machine id provisioned, getty masked${IMAGES_DIR:+, serial console off,
     U-Boot non-interruptible})."
