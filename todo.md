# TODO

## Wire the Wi-Fi regulatory domain (`country=`) to a build variable

Today the Wi-Fi regulatory domain is hard-coded to `DE` in several places. For
non-DE markets this needs to be a single build-time variable, substituted at
build time the same way `@BOARD_COMPATIBLE@` is (see
`board/raspberrypi4-64/post-build.sh`).

### Why
- An incorrect `country=` restricts/forbids channels (e.g. the 5 GHz band and
  high 2.4 GHz channels), so devices in other regions may fail to see or join
  their network.
- Right now changing region means editing 3–4 files by hand.

### Where `country=DE` / `"DE"` lives today
- [ ] `board/raspberrypi/rootfs_overlay/etc/systemd/system/prepare-data-dirs.service`
      — the first-boot **seed** (`printf "...country=DE\n"`). Shared by RPi4 + RPi5.
- [ ] `board/raspberrypi4-64/wpa_supplicant-wlan0.conf`
- [ ] `board/raspberrypi5/wpa_supplicant-wlan0.conf`
- [ ] App repo `instrument-cluster`: `core/wifi_manager.py` → `DEFAULT_COUNTRY = "DE"`
      (used when the app **rewrites** the config on join).

### Proposed approach (matches the existing `@BOARD_COMPATIBLE@` pattern)
1. Replace every literal `DE` above with a placeholder `@WIFI_COUNTRY@`
   (including inside the `prepare-data-dirs.service` `printf` — the unit file is
   in the rootfs, so `post-build.sh` can `sed` it even though the config itself
   is generated at runtime).
2. Source the value from a single env var, defaulting to `DE`:
   `WIFI_COUNTRY="${WIFI_COUNTRY:-DE}"`.
3. In **both** `board/raspberrypi4-64/post-build.sh` and
   `board/raspberrypi5/post-build.sh`, after the existing RAUC sed:
   ```sh
   WIFI_COUNTRY="${WIFI_COUNTRY:-DE}"
   for f in \
       "$T/etc/systemd/system/prepare-data-dirs.service" \
       "$T/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"; do
       [ -f "$f" ] && sed -i "s/@WIFI_COUNTRY@/$WIFI_COUNTRY/g" "$f"
   done
   ```
   (Confirm the board `wpa_supplicant-wlan0.conf` actually lands at
   `$T/etc/wpa_supplicant/...`; it's only copied there when provisioned via
   `/boot`. If not, sed the source/overlay copy instead.)
4. Document `WIFI_COUNTRY` in `CLAUDE.md` (build commands section) and in CI if
   regional images are ever produced.

### App side (`instrument-cluster`)
- [ ] Make `WifiManager` **inherit** the existing `country=` from the on-device
      config header when rewriting on join, instead of hard-coding
      `DEFAULT_COUNTRY`. Fall back to `DE` only if no header is present. This
      keeps the app consistent with whatever the image was built with, with no
      app-side build variable needed.

### Acceptance
- [ ] Building with `WIFI_COUNTRY=US make ...` yields `country=US` in the seeded
      config, the board config, and any config the app later writes.
- [ ] Default build (no env var) still produces `country=DE`.
- [ ] On-display Wi-Fi scan shows region-appropriate channels.

### Nice-to-have / open question
- Promote `WIFI_COUNTRY` from a bare env var to a proper Buildroot config symbol
  (`BR2_PACKAGE_..._WIFI_COUNTRY`) so it's captured in the defconfig and visible
  in `menuconfig`, rather than relying on the environment at build time.

## OTA robustness follow-ups (after kernel-in-rootfs)

The kernel now ships inside each rootfs slot and `boot.scr` persists boot
attempts, so kernel updates are A/B-safe. Two residual hazards remain:

- [x] **Redundant U-Boot environment.** Done: env moved to raw MMC at
      `0x400000`/`0x404000` (`CONFIG_ENV_IS_IN_MMC` +
      `CONFIG_SYS_REDUNDAND_ENVIRONMENT`), boot partition pinned to 8M,
      `fw_env.config` lists both copies, envimage generated with the
      redundant flag byte. Offsets live in three places (U-Boot fragments,
      genimage.cfg, fw_env.config) — keep them in sync.
- [ ] **Factory-pinned DTB.** The Pi firmware loads and patches the DTB from
      FAT, so OTA never updates it. Acceptable within the 2025.02 LTS kernel
      branch; revisit if a platform update ever needs a newer DTB (options:
      ship dtb updates via a RAUC vfat slot, or accept a factory reflash).
- [x] **Smarter mark-good gate.** Done: `ota-health-check.sh` verifies DRM
      card + V3D render node, wlan0, and an enumerated input device (30 s
      grace window) before `instrument-cluster-health` runs mark-good.
