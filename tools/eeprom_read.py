#!/usr/bin/env python3
"""Read the Raspberry Pi 5 bootloader EEPROM — strictly read-only.

Runs ON the Pi (copy it over ssh; needs only the stock python3 of the dev
image). The firmware DTB exposes the 2 MiB bootloader flash as a plain
spidev device (/dev/spidev10.0, modalias spi:spidev — NOT jedec,spi-nor),
so this issues nothing but NOR read opcodes over the spidev ioctl:
0x9F (JEDEC ID, used as a sanity gate) and 0x03 (READ). No driver is
bound, no write/erase opcode exists anywhere in this file.

Why it exists: there is no other window into the EEPROM on this image —
vcgencmd's gencmd tags are not registered by the Pi 5 firmware, and the
rpi-eeprom tooling expects /dev/mtd0, which our kernel doesn't create.

Usage (on the device):
    python3 eeprom_read.py                # print the embedded boot config
    python3 eeprom_read.py -o eeprom.bin  # also keep the full 2 MiB dump

The dump doubles as the input for provisioning a config change with the
official rpi-eeprom-config tool — see docs/eeprom-provisioning.md.
"""

import argparse
import ctypes
import fcntl
import re
import struct
import sys

SPIDEV = "/dev/spidev10.0"
SPI_IOC_MESSAGE_1 = 0x40206B00  # _IOW('k', 0, char[32])
SPEED_HZ = 4_000_000
CHUNK = 2044  # + 4 command bytes = 2048, under the 4096 spidev bufsiz
FLASH_SIZE = 2 * 1024 * 1024


def xfer(fd, tx: bytes) -> bytes:
    n = len(tx)
    txb = ctypes.create_string_buffer(tx, n)
    rxb = ctypes.create_string_buffer(n)
    desc = struct.pack(
        "<QQIIHBBBBBB",
        ctypes.addressof(txb), ctypes.addressof(rxb),
        n, SPEED_HZ, 0, 8, 0, 0, 0, 0, 0,
    )
    fcntl.ioctl(fd, SPI_IOC_MESSAGE_1, desc)
    return rxb.raw


def read_flash(fd) -> bytes:
    jedec = xfer(fd, bytes([0x9F, 0, 0, 0]))[1:4]
    if jedec in (b"\x00\x00\x00", b"\xff\xff\xff"):
        sys.exit(f"no flash answering on {SPIDEV} (JEDEC {jedec.hex()}) — aborting")
    print(f"JEDEC ID: {jedec.hex()}", file=sys.stderr)

    out = bytearray()
    addr = 0
    while addr < FLASH_SIZE:
        n = min(CHUNK, FLASH_SIZE - addr)
        cmd = bytes([0x03, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF])
        out += xfer(fd, cmd + b"\x00" * n)[4:]
        addr += n
    return bytes(out)


def extract_config(data: bytes) -> str | None:
    """Find the bootconf.txt file section and return its text.

    The filename also appears as a string inside the bootloader code, so a
    hit only counts when actual config text follows the 12-byte name field.
    Content runs until the 0xFF erased-flash padding.
    """
    for m in re.finditer(re.escape(b"bootconf.txt"), data):
        body = data[m.start() + 12 :]
        text = body.split(b"\xff", 1)[0].strip(b"\x00 \t\r\n")
        if text.startswith(b"[") or b"=" in text[:64]:
            return text.decode(errors="replace")
    return None


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-o", "--out", metavar="FILE", help="write the full dump here")
    args = ap.parse_args()

    with open(SPIDEV, "rb+", buffering=0) as fd:
        data = read_flash(fd)

    if args.out:
        with open(args.out, "wb") as f:
            f.write(data)
        print(f"wrote {len(data)} bytes to {args.out}", file=sys.stderr)

    config = extract_config(data)
    if config is None:
        sys.exit("could not locate bootconf.txt in the image")
    print(config)


if __name__ == "__main__":
    main()
