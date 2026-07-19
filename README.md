## About

An embedded sim racing dash with a real instrument-cluster layout. Built for readability and reliability while racing. Runs on Raspberry Pi with 7" displays and supports Gran Turismo 7 and Assetto Corsa Competizione telemetry. The application it boots into lives at [chrshdl/revokyte](https://github.com/chrshdl/revokyte); this repo builds the OS image around it.

<div align="center">

[![INSTRUMENT CLUSTER IN ACTION](https://img.youtube.com/vi/VLkjhCFHSfc/0.jpg)](https://www.youtube.com/watch?v=VLkjhCFHSfc)

<h3>

[Video: 1](https://www.youtube.com/watch?v=VLkjhCFHSfc), [2](https://youtube.com/shorts/_H9sxo7xVY8) <span> · </span> [Community](https://discord.gg/dEQJSuva7K)

</h3>

[![Build Status](https://github.com/chrshdl/instrument-cluster-os/actions/workflows/ci.yml/badge.svg)](https://github.com/chrshdl/instrument-cluster-os/actions/workflows/ci.yml)
[![Download Raspberry Pi 4 64 Image](https://img.shields.io/badge/download-pi4--64--image-c51d4a?logo=raspberry-pi&logoColor=white)](https://github.com/chrshdl/instrument-cluster-os/releases)
[![Discord](https://img.shields.io/discord/1452332495683981478?label=chat&logo=discord&color=5865F2)](https://discord.gg/dEQJSuva7K)


Join the chat to share ideas and influence what gets built next.
</div>


## Features

### Telemetry & Gauges

* Tire temperatures
* Vehicle speed
* Gear indicator
* Graphical RPM


### Driver Coaching

* Shift lights (torque-based optimal shift point)
* Best lap time
* Previous lap time
* Predicted lap time
* Live delta (in real-time)


### Supported Hardware

- Single-board computers
  - Raspberry Pi 4 Model B (1GB RAM, built-in Wi-Fi)

- Displays
  - Raspberry Pi Touch Display 2, 24-bit RGB, 720×1280, five-finger touch

- Peripherals
  - Pimoroni Blinkt! 8-LED bar

- Input
  - Touch control (UI buttons)
  - On-screen soft keys for display brightness (+ / −)


### Standalone Solution

Available as a standalone OS image, pre-configured for minimal latency and fast boot times. No manual setup or dependency installation is required.

To get started, download the image from the [releases](https://github.com/chrshdl/instrument-cluster-os/releases) and flash it to your SD card (e.g. with Raspberry Pi Imager). To pre-provision Wi-Fi, place a filled-in `wpa_supplicant-wlan0.conf` on the boot partition.

[![Download Raspberry Pi 4 64 Image](https://img.shields.io/badge/download-pi4--64--image-c51d4a?logo=raspberry-pi&logoColor=white)](https://github.com/chrshdl/instrument-cluster-os/releases)


## Legal Disclaimer

This project is created for educational and personal use and provided without warranty of any kind, express or implied. Use at your own risk.

All trademarks, logos, and brand names are the property of their respective owners.

*Gran Turismo*, *Gran Turismo 7*, *GT7* and *PlayStation* are trademarks or registered trademarks of *Sony Interactive Entertainment Inc.* and *Polyphony Digital Inc.*


## License

All of my code is MIT licensed. Libraries follow their respective licenses.

The released images aggregate many open-source components (Linux, U-Boot,
BusyBox, glibc, the cluster app, ...). Each release therefore ships a
`legal-info-*.tar.gz` next to the image with the full license manifest,
license texts, and corresponding sources, as collected by Buildroot's
`make legal-info`.
