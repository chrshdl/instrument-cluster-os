# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A **Buildroot external tree** that produces a minimal embedded Linux OS image for a sim racing instrument cluster (Gran Turismo 7 and Assetto Corsa Competizione telemetry dash) running on Raspberry Pi 4 (64-bit) and Raspberry Pi 5. It is not a standalone project — it requires a separate Buildroot checkout to build.

## Build Commands

Buildroot must be checked out alongside this repo at the version pinned in the `BUILDROOT_VERSION` file (single source of truth — CI reads it too):

```sh
# One-time: clone Buildroot next to this repo
git clone --branch "$(cat BUILDROOT_VERSION)" https://github.com/buildroot/buildroot buildroot

# Configure for RPi4 64-bit
make -C buildroot BR2_EXTERNAL=$(pwd) O=$(pwd)/output raspberrypi4-64_defconfig

# Full build (takes ~1-2h on first run; incremental is fast)
make -C buildroot O=$(pwd)/output

# Rebuild a single package (e.g. after bumping a version)
make -C buildroot O=$(pwd)/output python-instrument-cluster-rebuild

# Open menuconfig to browse/change options
make -C buildroot O=$(pwd)/output menuconfig

# Save defconfig changes back to configs/
make -C buildroot O=$(pwd)/output savedefconfig
```

Build outputs land in `output/images/`:
- `sdcard.img` — full factory flash image (renamed to `factory-raspberrypi4-64.img` in CI)
- `rootfs.ext4` — root filesystem (the private Pro OS repo turns it into signed RAUC update bundles)

## Architecture

### Repository Layout

```
Config.in             # Declares all custom packages to Buildroot
external.mk           # Includes all package .mk files; sets numpy to use OpenBLAS
external.desc         # Buildroot external tree name/description
configs/              # Buildroot defconfigs (checked in here, not in Buildroot tree)
board/
  raspberrypi/        # Shared: rootfs overlay, patches applied to linux/u-boot
  raspberrypi4-64/    # RPi4-specific: linux.config, genimage.cfg, boot.cmd, U-Boot fragment
  raspberrypi5/       # RPi5-specific: linux.fragment, genimage.cfg
package/              # One directory per custom package
  python-instrument-cluster/   # Main app (fetched from GitHub)
  python-pygame-261/           # Pinned pygame build (specific git commit)
  python-pyopengl/             # PyOpenGL with Mesa/EGL deps
keys/                 # RAUC signing cert/key (not committed; generated externally)
```

### Packages

Each package under `package/` follows the standard Buildroot pattern: a `Config.in` (bool option) and a `<name>.mk`. Key notes:

- **python-instrument-cluster**: Tracks `chrshdl/revokyte` on GitHub by tag. Bump `PYTHON_INSTRUMENT_CLUSTER_VERSION` and run `-rebuild` to update.
- **python-synthesizer**: Currently uses `SITE_METHOD = local` pointing to `/Users/cwasilei/projects/synthesizer`. Must be changed to a GitHub tag before CI can build it.
- **python-pygame-261**: Pinned to a specific commit hash, not a release tag — this is intentional to track a pre-2.6.1 fix.

### SD Card Layout (A/B OTA)

```
(raw)      0x400000 + 0x404000   Redundant U-Boot env (two 16K copies, no partition)
mmcblk0p1  /boot    FAT32   64M   U-Boot, Pi firmware + DTB, boot.scr, wpa_supplicant config  (offset 8M)
mmcblk0p2  (none)   ext4    ~     rootfs slot A (incl. its kernel at /boot/Image)
mmcblk0p3  (none)   ext4    ~     rootfs slot B (incl. its kernel at /boot/Image)
mmcblk0p4  /data    ext4  512M   Persistent data (Wi-Fi config, RAUC status, logs)
```

**The kernel lives inside each rootfs slot** (`/boot/Image`, installed by `BR2_LINUX_KERNEL_INSTALL_TARGET`), so an OTA bundle updates kernel + modules + userspace atomically per slot — a Buildroot bump can never strand a new rootfs's `/lib/modules/<ver>` under an old kernel. The FAT partition keeps only what must be there: the Pi firmware and the DTB it patches (config.txt overlays, memory fixups — which is why `boot.scr` boots with the firmware-passed `${fdt_addr}` rather than a DTB from disk), U-Boot, its env file, and `boot.scr`. The DTB is therefore factory-pinned; within an LTS kernel branch that skew is acceptable.

### A/B Updates (RAUC + U-Boot)

- `board/raspberrypi4-64/boot.cmd` is compiled to `boot.scr` during `post-image.sh`. It reads `BOOT_ORDER`, `BOOT_A_LEFT`, `BOOT_B_LEFT` from U-Boot env, selects the active slot, **persists the decremented attempt counter (`saveenv`) before booting**, and `ext4load`s `/boot/Image` from that slot. A kernel that hangs pre-Linux burns an attempt on every reset, so three failures rotate to the other slot even without Linux ever running; `rauc status mark-good` restores the counters.
- The U-Boot environment is **redundant raw-MMC** (`CONFIG_SYS_REDUNDAND_ENVIRONMENT`): two copies at `0x400000`/`0x404000` in the gap before the first partition, written alternately by both `saveenv` (boot.scr) and `fw_setenv` (RAUC, via `/etc/fw_env.config`). An interrupted write leaves the other copy valid, so a power cut during an env update can't lose `BOOT_ORDER`. The three offset definitions (U-Boot fragments, genimage.cfg, fw_env.config) must stay in sync.
- `board/raspberrypi/rootfs_overlay/etc/rauc/system.conf` contains `@BOARD_COMPATIBLE@` which `post-build.sh` replaces at build time based on the detected firmware variant.
- `instrument-cluster-health.service` waits 15 s after the app signals ready, runs `ota-health-check.sh` (display + V3D DRM nodes, `wlan0` exists, an input device enumerated — the things a driver/kernel regression breaks while the app still starts; polled for a 30 s grace window), and only then calls `rauc status mark-good`. If the app crashes first, or a check fails, the slot is never marked good and the burned boot attempts roll back to the other slot within three reboots. The check deliberately never forces a reboot itself — a genuine hardware fault would ping-pong both slots forever; hard failures are already covered by the app's watchdog + `StartLimitAction=reboot`.
- Update-bundle signing happens in the private Pro OS repo's CI (its `RAUC_CERT_PEM` / `RAUC_KEY_PEM` secrets); this repo builds unsigned factory images only. Local signing requires placing cert/key under `keys/`.

### Runtime Services (systemd)

| Service | Role |
|---|---|
| `instrument-cluster.service` | Main Python cluster app (pygame + OpenGL) |
| `instrument-cluster-proxy.service` | Feed-agnostic telemetry proxy: runs whichever feed the user installed (granturismo for GT7, acc for ACC), republishing on `127.0.0.1:5600` |
| `instrument-cluster-proxy.path` | Starts the proxy once a feed is installed (`/opt/telemetry/active/proxy-wrapper.py` appears; `active` is a symlink the installer points at the selected feed) |
| `instrument-cluster-health.service` | Verifies display/GPU/Wi-Fi/touch (`ota-health-check.sh`), then `rauc status mark-good` |
| `wifi-setup.service` | One-time: copies `wpa_supplicant-wlan0.conf` from `/boot` to `/etc/wpa_supplicant/` on first boot |
| `splashscreen.service` | Shows `etc/splash.png` via `fbv` during boot |
| `prepare-data-dirs.service` | Creates expected dirs on `/data` partition before other services start |

Wi-Fi credentials are provisioned by placing a pre-filled `wpa_supplicant-wlan0.conf` on the boot FAT partition. `install-wifi-config.sh` moves it to `/etc/wpa_supplicant/` and renames the source so it only runs once.

### Telemetry Data Flow

```
Game (GT7 on PS5 / ACC on PC) → UDP → instrument-cluster-proxy (Python feed)
                                            ↓ UDP 127.0.0.1:5600
                             instrument-cluster app (Python/pygame/OpenGL)
```

The proxy is the feed program the app installs on the device (granturismo for GT7, acc for ACC); the app itself only reads NDJSON on `127.0.0.1:5600` and is game-agnostic. The game's IP and output target are configured via `/data/etc/instrument-cluster-proxy` (persists across OTA updates), written by the on-device installer for the selected feed.

## CI

GitHub Actions (`.github/workflows/ci.yml`) triggers on `v*` tags and PRs. It:
1. Builds with the Buildroot version pinned in `BUILDROOT_VERSION` on `ubuntu-latest`
2. Uploads `factory-<tag>-<board>.img` and `legal-info-<tag>-<board>.tar.gz` (Buildroot `make legal-info`: license manifest + texts + corresponding sources for everything the image distributes — GPL compliance for the published binaries) as release assets

No update bundles and no signing secrets here: the community image has no OTA (devices update by re-flashing), so the signed `.raucb` production lives in the private Pro OS repo that layers on this tree.

Release assets are published using the default `GITHUB_TOKEN` — no PAT required (workflow has `permissions: contents: write`).

### Buildroot point-release triage

`.github/workflows/triage-buildroot.yml` runs monthly (and via `workflow_dispatch`): when the pinned LTS series has a tag newer than `BUILDROOT_VERSION`, it configures both boards against the new tag, derives the *actual* shipped package set from `make show-info` (implicit dependencies included), filters the release changelog to those packages plus infrastructure paths (`linux/`, `boot/`, `toolchain/`, …), and attaches a best-effort `pkg-stats` CVE report scoped to our versions. The result lands as an issue; when at least one shipped package is touched, it also opens a one-line `BUILDROOT_VERSION` bump PR with the report as body. Quiet months filter to "nothing we ship was touched" — skip those, batch them into the next platform release; fast-track only CVEs against the device's real surface (Wi-Fi stack, kernel netstack, TLS).

PRs opened with the default `GITHUB_TOKEN` don't trigger the CI workflow (GitHub recursion guard): either configure the optional `TRIAGE_PR_PAT` secret so bump PRs behave like human-opened ones, or add the `build` label and close/reopen the PR to run the image build.

### Coordinated changes with `revokyte` (avoid a throwaway build)

When an OS-side change pairs with an app change (e.g. a new app feature that
needs a systemd/rootfs tweak here), don't build this repo twice. The CI build
only runs on PRs and tags — **not** on push to `main` — and the app's
`bump-os.yml` opens a `bump/python-instrument-cluster-<tag>` PR here only when a
`v*` **tag** is pushed in `revokyte` (not on app PR merge). So:

1. Merge the OS-side PR with the **`skip-build`** label → it lands on `main`
   with no image build (the `build` job's `if:` guard skips it).
2. Merge the app PR, then push the app release tag `vX`.
3. `bump-os` opens the bump PR here on top of `main` (which already has the OS
   change) → that single build validates the OS change + the new app together.
   Merge it.

Apply `skip-build` at PR creation (`gh pr create --label skip-build`); the
guard is evaluated when the run starts, so labelling after open means cancelling
the first run. `bump/**` PRs are unlabelled and always build.
