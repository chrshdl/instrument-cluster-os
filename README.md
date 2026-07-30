<div align="center">

# instrument-cluster-os

[![Website](https://img.shields.io/badge/website-revokyte.com-3dd1d8)](https://www.revokyte.com)
[![Build Status](https://github.com/chrshdl/instrument-cluster-os/actions/workflows/ci.yml/badge.svg)](https://github.com/chrshdl/instrument-cluster-os/actions/workflows/ci.yml)
[![Download Raspberry Pi Image](https://img.shields.io/badge/download-pi4--64%20%C2%B7%20pi5-c51d4a?logo=raspberry-pi&logoColor=white)](https://github.com/chrshdl/instrument-cluster-os/releases)
[![Discord](https://img.shields.io/discord/1452332495683981478?label=chat&logo=discord&color=5865F2)](https://discord.gg/dEQJSuva7K)

</div>

## Why

A race car's dashboard doesn't have a desktop behind it. It doesn't ask you to log in, install dependencies, or wait for updates — you turn the key and it's on. We believe your sim racing instruments should work the same way: an appliance you power on and trust, not a computer you maintain.

## How

We build the whole operating system around that one job, and nothing else:

- **Boots straight into the dash** — no desktop, no login, no setup; the device is an instrument the moment it has power.
- **Nothing to break** — a minimal Buildroot system with a read-only rootfs, tuned for fast boot and low latency.
- **Locked down by default** — released images ship with no SSH server and no interactive root login, because an appliance shouldn't have doors you didn't ask for. Dev images exist precisely so tinkering stays a deliberate choice.

## What

The result is this repo: the Buildroot-based OS image for [Revokyte](https://www.revokyte.com), an embedded sim racing instrument cluster for Gran Turismo 7 and Assetto Corsa Competizione. Flash it to an SD card and the device boots into the cluster — no manual setup or dependency installation required. See the [Revokyte README](https://github.com/chrshdl/revokyte) for features, architecture, and hardware details.

## Getting started

Download the image for your board (Raspberry Pi 4 or 5) from the [releases](https://github.com/chrshdl/instrument-cluster-os/releases) and flash it to an SD card (e.g. with Raspberry Pi Imager). To pre-provision Wi-Fi, place a filled-in `wpa_supplicant-wlan0.conf` on the boot partition.

Released images are locked down: no SSH server and no interactive root login. If you want to hack on the device, use a dev image instead — download a `dev-*.img` artifact from a [CI workflow run](https://github.com/chrshdl/instrument-cluster-os/actions/workflows/ci.yml) or build one locally (dev is the default build variant) — which has SSH enabled with user `root`, password `root`.

## Legal

This project is provided without warranty of any kind, express or implied. Use at your own risk.

All trademarks, logos, and brand names are the property of their respective owners. *Gran Turismo*, *Gran Turismo 7*, *GT7*, and *PlayStation* are trademarks or registered trademarks of *Sony Interactive Entertainment Inc.* and *Polyphony Digital Inc.* *Assetto Corsa Competizione* and *ACC* are trademarks or registered trademarks of *Kunos Simulazioni S.r.l.* This project is independent and not affiliated with or endorsed by any of them.

## License

All of my code is MIT licensed. Libraries follow their respective licenses.

The released images aggregate many open-source components (Linux, U-Boot, BusyBox, glibc, the cluster app, ...). Each release therefore ships a `legal-info-*.tar.gz` next to the image with the full license manifest, license texts, and corresponding sources, as collected by Buildroot's `make legal-info`.
