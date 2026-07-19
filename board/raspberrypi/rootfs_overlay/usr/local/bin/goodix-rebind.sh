#!/bin/sh
# Work around the Goodix GT911 touch controller failing to probe at boot.
#
# On the Raspberry Pi Touch Display 2 (vc4-kms-dsi-ili9881-7inch overlay) the
# touch's power/reset is sequenced by the panel MCU (display_mcu@45,
# raspberrypi,v2-touchscreen-panel-regulator) as part of DSI panel bring-up.
# The goodix i2c driver probes at ~t=3.3s, before the panel is ready, and NAKs
# with EREMOTEIO (-121), so no input device is created and ALL touch is dead.
# Bumping the touch regulator's startup-delay does NOT help (verified) — the
# dependency is the panel coming up, not power settling. Rebinding the driver
# once the panel is up succeeds.
#
# This unit retries the bind until the input device appears, then exits. It is
# ordered Before=instrument-cluster.service so pygame enumerates the touch at
# startup. On builds/panels without a Goodix touch it detects that and no-ops
# immediately (the rootfs overlay is shared across board targets).
set -u

DRV=/sys/bus/i2c/drivers/Goodix-TS

ready() { grep -qi goodix /proc/bus/input/devices 2>/dev/null; }

# Already probed cleanly (transient success, or a future firmware/overlay fix)?
if ready; then
    echo "goodix-rebind: touch already present, nothing to do"
    exit 0
fi

# Find the GT911 i2c device (e.g. 11-005d). Absent on board targets/panels
# without a Goodix touch -> nothing to do, so we don't delay boot.
dev=
for d in /sys/bus/i2c/devices/*; do
    [ -r "$d/name" ] || continue
    if [ "$(cat "$d/name" 2>/dev/null)" = "gt911" ]; then
        dev=$(basename "$d")
        break
    fi
done

if [ -z "$dev" ] || [ ! -e "$DRV/bind" ]; then
    echo "goodix-rebind: no Goodix touch present, nothing to do"
    exit 0
fi

i=0
while [ "$i" -lt 30 ]; do
    echo "$dev" > "$DRV/bind" 2>/dev/null
    if ready; then
        echo "goodix-rebind: touch up ($dev) after $i retries"
        exit 0
    fi
    # bind failed -> driver auto-unbinds on probe error; the explicit unbind is
    # a harmless no-op that guarantees a clean state before the next attempt.
    echo "$dev" > "$DRV/unbind" 2>/dev/null
    i=$((i + 1))
    sleep 1
done

echo "goodix-rebind: FAILED to bind $dev after $i attempts" >&2
exit 1
