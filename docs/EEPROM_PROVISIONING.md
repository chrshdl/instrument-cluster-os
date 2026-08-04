# Pi 5 bootloader EEPROM provisioning

The bootloader EEPROM is per-board state: it survives SD reflashes and OTA
updates, but a **brand-new Pi ships with factory defaults** — so every new
board needs this one-time step. It is worth doing: on the bench it cut
plug-to-fan from ~10 s to ~6 s and plug-to-dashboard from ~25 s to ~17 s
(v0.2.21-era image, official 27 W PSU).

## Recommended config

```ini
[all]
BOOT_UART=0
POWER_OFF_ON_HALT=0
BOOT_ORDER=0xf1
```

Two deltas against the Pi 5 factory config (`BOOT_UART=1`, `BOOT_ORDER=0xf41`):

- **`BOOT_UART=0`** — the bootloader otherwise prints its full diagnostic log
  (SDRAM training, board info, per-attempt boot progress) over the debug UART
  at 115200 baud before booting anything. Nobody reads that UART on a deployed
  dash; flip it back to 1 when debugging a board that won't boot.
- **`BOOT_ORDER=0xf1`** — SD only, retry forever (read right-to-left:
  1 = SD, f = restart loop). The factory `0xf41` inserts a USB probe after any
  SD failure. That matters here because this appliance is power-cut, not shut
  down: after a cut mid-write, many SD cards spend seconds in internal
  recovery and don't answer the bootloader's first attempt — with `0xf41` that
  detour costs multi-second USB timeouts on exactly the boots that are already
  slow.

## Reading the current config

On a dev image (release images have no SSH):

```sh
scp tools/eeprom_read.py root@instrument-cluster.local:/tmp/
ssh root@instrument-cluster.local python3 /tmp/eeprom_read.py
```

The script talks to the flash through `/dev/spidev10.0` with read-only NOR
opcodes. Note the two dead ends so nobody rediscovers them: the Pi 5 firmware
does not register the `vcgencmd` gencmd tags, and the stock kernel/DTB expose
the EEPROM as spidev, not `jedec,spi-nor`, so there is no `/dev/mtd0` for the
official `rpi-eeprom-update` tooling to use.

## Applying the config (no spare SD card needed)

The flash is applied by the official `recovery.bin` mechanism — the boot ROM
verifies a SHA-256 sidecar before writing, flashes, renames `recovery.bin` to
`RECOVERY.000` so it cannot run twice, and reboots. The update image is built
from the board's **own dump**, so the bootloader version never changes — the
delta is the config bytes only.

On the workstation:

```sh
# 1. Dump the board's current EEPROM
scp tools/eeprom_read.py root@instrument-cluster.local:/tmp/
ssh root@instrument-cluster.local "python3 /tmp/eeprom_read.py -o /tmp/eeprom.bin >/dev/null"
scp root@instrument-cluster.local:/tmp/eeprom.bin .

# 2. Fetch the official tools + flasher (pure python / sh + openssl)
base=https://raw.githubusercontent.com/raspberrypi/rpi-eeprom/master
curl -sLO $base/rpi-eeprom-config
curl -sLO $base/rpi-eeprom-digest
curl -sLO $base/firmware-2712/latest/recovery.bin

# 3. Embed the recommended config and sign
printf '[all]\nBOOT_UART=0\nPOWER_OFF_ON_HALT=0\nBOOT_ORDER=0xf1\n' > bootconf.txt
python3 rpi-eeprom-config --config bootconf.txt --out pieeprom.upd eeprom.bin
sh rpi-eeprom-digest -i pieeprom.upd -o pieeprom.sig

# 4. Stage on the boot FAT and flash on the next reboot
scp recovery.bin pieeprom.upd pieeprom.sig root@instrument-cluster.local:/boot/
ssh root@instrument-cluster.local "sync && reboot"
```

**Keep power stable during the ~15–30 s flash window after the reboot.** A
power cut mid-flash bricks the bootloader; recovery is then `rpiboot` over
USB-C from another machine — recoverable, but a bench job.

Afterwards, verify and clean up:

```sh
ssh root@instrument-cluster.local "python3 /tmp/eeprom_read.py"   # expect the new config
ssh root@instrument-cluster.local "rm /boot/RECOVERY.000 /boot/pieeprom.upd /boot/pieeprom.sig && sync"
```
