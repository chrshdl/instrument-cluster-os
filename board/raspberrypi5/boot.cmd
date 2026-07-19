# ==========================================================
# RAUC A/B Boot Script for Raspberry Pi 5
# ==========================================================
#
# The kernel lives INSIDE each rootfs slot (/boot/Image, installed by
# BR2_LINUX_KERNEL_INSTALL_TARGET), so kernel + modules always travel
# together through an OTA update; the FAT partition only carries the
# Pi firmware, the firmware-patched DTB, U-Boot and this script.
#
# Attempt counters are persisted with saveenv BEFORE booting: a kernel
# that hangs pre-Linux burns an attempt on every reset, so after 3
# failures U-Boot rotates to the other slot (rauc mark-good restores
# the counters from Linux once the new slot proves healthy).

test -n "${BOOT_ORDER}" || setenv BOOT_ORDER "A B"
test -n "${BOOT_A_LEFT}" || setenv BOOT_A_LEFT 3
test -n "${BOOT_B_LEFT}" || setenv BOOT_B_LEFT 3

setenv raucslot
for BOOT_SLOT in "${BOOT_ORDER}"; do
  if test "x${raucslot}" != "x"; then
    # Skip if we already found a slot
  elif test "x${BOOT_SLOT}" = "xA"; then
    if test ${BOOT_A_LEFT} -gt 0; then
      setenv raucslot "A"
      setenv raucpart 2
      setexpr BOOT_A_LEFT ${BOOT_A_LEFT} - 1
    fi
  elif test "x${BOOT_SLOT}" = "xB"; then
    if test ${BOOT_B_LEFT} -gt 0; then
      setenv raucslot "B"
      setenv raucpart 3
      setexpr BOOT_B_LEFT ${BOOT_B_LEFT} - 1
    fi
  fi
done

if test -n "${raucslot}"; then
  setenv bootargs "root=/dev/mmcblk0p${raucpart} rauc.slot=${raucslot} rootwait console=tty3 console=ttyAMA0,115200 quiet loglevel=3 video=HDMI-A-1:d video=HDMI-A-2:d logo.nologo vt.global_cursor_default=0 systemd.show_status=0"

  setenv silent 1
  setenv bootdelay 0

  # Persist the decremented attempt counter before booting.
  saveenv

  # Kernel from the selected slot; the DTB stays the firmware-patched
  # one (${fdt_addr}) - the Pi firmware applies config.txt overlays and
  # memory fixups that a raw DTB loaded from disk would lack.
  if ext4load mmc 0:${raucpart} ${kernel_addr_r} /boot/Image; then
    booti ${kernel_addr_r} - ${fdt_addr}
  fi
  # Load or boot failed (corrupt slot): the attempt is already burned,
  # so retrying eventually rotates to the other slot.
  reset
else
  setenv BOOT_A_LEFT 3
  setenv BOOT_B_LEFT 3
  saveenv
  reset
fi
