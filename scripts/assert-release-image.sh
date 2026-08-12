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
# non-interruptible U-Boot env (bootdelay=-2, no serial stdin).
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
    # U-Boot must autoboot without an abort check and without serial stdin.
    # The env image is NUL-separated text, so grep -a works on it.
    grep -a -q -e "bootdelay=-2" "$UBOOTENV" \
        || fail "uboot-env.bin does not contain bootdelay=-2"
    if grep -a -q -e "stdin=serial" "$UBOOTENV"; then
        fail "uboot-env.bin still lists serial as stdin"
    fi
fi

echo "OK: release image assertions passed (no sshd, no sshd_config, root locked,
     machine id provisioned, getty masked${IMAGES_DIR:+, serial console off,
     U-Boot non-interruptible})."
