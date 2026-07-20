<div align="center">

# instrument-cluster-os

[![Build Status](https://github.com/chrshdl/instrument-cluster-os/actions/workflows/ci.yml/badge.svg)](https://github.com/chrshdl/instrument-cluster-os/actions/workflows/ci.yml)
[![Download Raspberry Pi Image](https://img.shields.io/badge/download-pi4--64%20%C2%B7%20pi5-c51d4a?logo=raspberry-pi&logoColor=white)](https://github.com/chrshdl/instrument-cluster-os/releases)
[![Discord](https://img.shields.io/discord/1452332495683981478?label=chat&logo=discord&color=5865F2)](https://discord.gg/dEQJSuva7K)

</div>

Buildroot-based OS image for [Revokyte](https://github.com/chrshdl/revokyte), an embedded sim racing instrument cluster for Gran Turismo 7 and Assetto Corsa Competizione. This repo builds the image the device boots into — pre-configured for minimal latency and fast boot, no manual setup or dependency installation required. See the [Revokyte README](https://github.com/chrshdl/revokyte) for features, architecture, and hardware details.

## Getting started

Download the image for your board (Raspberry Pi 4 or 5) from the [releases](https://github.com/chrshdl/instrument-cluster-os/releases) and flash it to an SD card (e.g. with Raspberry Pi Imager). To pre-provision Wi-Fi, place a filled-in `wpa_supplicant-wlan0.conf` on the boot partition.

## Legal

This project is created for educational and personal use and provided without warranty of any kind, express or implied. Use at your own risk.

All trademarks, logos, and brand names are the property of their respective owners. *Gran Turismo*, *Gran Turismo 7*, *GT7*, and *PlayStation* are trademarks or registered trademarks of *Sony Interactive Entertainment Inc.* and *Polyphony Digital Inc.* *Assetto Corsa Competizione* and *ACC* are trademarks or registered trademarks of *Kunos Simulazioni S.r.l.* This project is independent and not affiliated with or endorsed by any of them.

## License

All of my code is MIT licensed. Libraries follow their respective licenses.

The released images aggregate many open-source components (Linux, U-Boot, BusyBox, glibc, the cluster app, ...). Each release therefore ships a `legal-info-*.tar.gz` next to the image with the full license manifest, license texts, and corresponding sources, as collected by Buildroot's `make legal-info`.
