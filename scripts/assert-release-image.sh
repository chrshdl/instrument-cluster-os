#!/bin/sh
# Hard-fail guard for release (v* tag) builds: the shipped rootfs must contain
# no SSH daemon and no unlocked root account. Asserts against the actual
# rootfs.ext4 — the artifact genimage stamps into both A/B slots of
# sdcard.img — not just the build config, so a forgotten or broken
# configs/release.fragment can never silently ship an open image.
#
# Usage: scripts/assert-release-image.sh <path/to/.config> <path/to/rootfs.ext4>
# Requires: debugfs (e2fsprogs). No root needed.
set -eu

CONFIG="${1:?usage: assert-release-image.sh <.config> <rootfs.ext4>}"
ROOTFS="${2:?usage: assert-release-image.sh <.config> <rootfs.ext4>}"

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

echo "OK: release image assertions passed (no sshd, no sshd_config, root locked)."
