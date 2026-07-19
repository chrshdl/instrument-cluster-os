#!/bin/sh
# Gate for `rauc status mark-good`: verify the hardware a driver/kernel
# regression would silently break, not just "the app started".
#
# Run by instrument-cluster-health.service after the cluster app has been
# up for 15 s. Exiting non-zero skips mark-good, so the slot keeps burning
# boot attempts (boot.scr persists BOOT_x_LEFT) and U-Boot rotates to the
# other slot after three reboots. Deliberately NO forced reboot here: a
# genuine hardware fault (not update-related) would otherwise ping-pong
# both slots in an endless reboot loop, and the hard failures (app crash,
# hang) are already covered by the app's systemd watchdog + StartLimit.
#
# Checks are polled for a grace window — some devices probe late (the
# GT911 touch needs goodix-rebind.service after DSI panel bring-up).
set -u

TRIES=15
DELAY=2

check_display() {
    # KMS display device (vc4). Without it the app cannot render at all.
    ls /dev/dri/card* >/dev/null 2>&1
}

check_gpu() {
    # V3D render node - the app's GL context runs on it
    # (MESA_LOADER_DRIVER_OVERRIDE=v3d).
    ls /dev/dri/renderD* >/dev/null 2>&1
}

check_wifi() {
    # brcmfmac probed and created the interface. Association is NOT
    # required - a device at the track may have no known network, but the
    # driver coming up must never regress silently.
    [ -d /sys/class/net/wlan0 ]
}

check_touch() {
    # At least one input device - the touchscreen is this appliance's only
    # input. Generic on purpose: the overlay is shared across panels with
    # different touch controllers (GT911, Waveshare).
    ls /dev/input/event* >/dev/null 2>&1
}

failed=""
i=0
while [ "$i" -lt "$TRIES" ]; do
    failed=""
    check_display || failed="$failed display"
    check_gpu     || failed="$failed gpu"
    check_wifi    || failed="$failed wifi"
    check_touch   || failed="$failed touch"

    if [ -z "$failed" ]; then
        echo "ota-health-check: all checks passed"
        exit 0
    fi
    i=$((i + 1))
    sleep "$DELAY"
done

echo "ota-health-check: FAILED checks:$failed - NOT marking slot good" >&2
exit 1
