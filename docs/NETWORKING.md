# The networking contract the image guarantees

Telemetry senders, the revokyte app and the docs all make assumptions about
this image's network behavior. This file states what the image actually
guarantees, from the shipped configuration — it is the OS-side counterpart of
the wire protocol spec (revokyte `docs/PROTOCOL.md`, "Revokyte Telemetry
Protocol v1"), whose transport section defers to the image for bind, firewall
and name-advertising facts.

## Interfaces and addressing

- **wlan0** is the product's network interface: managed by systemd-networkd
  (`80-wlan0.network` in the rootfs overlay), DHCPv4 only (IPv6 deliberately
  off — see the comments in that file), client identity by MAC so the router
  sees a stable device across reflashes. Credentials come from
  `wpa_supplicant-wlan0.conf` on `/data`, written exclusively by the app's
  on-screen setup (the boot-partition provisioning path was removed — plaintext
  PSK on FAT).
- **Ethernet (known gap):** Buildroot generates a DHCP config for `eth0`
  (`BR2_SYSTEM_DHCP="eth0"`), but the Pi's onboard NIC is named **`end0`** by
  the kernel, so that file matches nothing and the Ethernet port is
  **unmanaged — no DHCP, no address**. Plugging in a cable does nothing today.
  Documented rather than fixed for now; the fix is renaming the match (or the
  `BR2_SYSTEM_DHCP` value) when Ethernet support is actually wanted, and it
  must be paired with a `MulticastDNS=` decision for that link (see below).

## Hostname and mDNS

- Hostname: `instrument-cluster` (`BR2_TARGET_GENERIC_HOSTNAME`).
- `instrument-cluster.local` is answered by **systemd-resolved's mDNS
  responder on wlan0**, enabled by the `MulticastDNS=yes` line in
  `80-wlan0.network`. That line is load-bearing: resolved is built with mDNS
  on globally, but networkd defaults every managed link to `MDNS=no` and
  resolved takes the *minimum* of the two — without the line the device
  advertises no name at all.
- History, so nobody re-learns this the hard way: the name *appeared* to work
  before that line existed because AVM Fritz!Box routers answer `.local`
  mDNS queries on behalf of their DHCP clients (verified by source-tracing
  buildroot/systemd and by capturing the responder's address on the LAN —
  it was the router, and the device's own resolved reported `-mDNS` on
  wlan0). Most routers do not do this; on such networks only the literal-IP
  fallback kept the ACC agent sending, and `ssh instrument-cluster.local`
  did not work at all.
- What relies on the name: the dev workflow (`deploy_pi.sh`,
  `ssh root@instrument-cluster.local`), the ACC game-PC agent's preferred
  `output_mdns` sink (IP fallback mandatory per PROTOCOL.md §2.5), and any
  future third-party sender following the protocol's addressing convention.
- The responder answers **hostname A-record queries only**. Nothing in the
  image publishes DNS-SD *services* — systemd-resolved cannot; see
  `proposals/dns-sd-discovery.md` for what service discovery would take.

## Ports

| Port | Owner | Notes |
|---|---|---|
| 5600/udp | revokyte app (telemetry sink) | Bound to `127.0.0.1` when an on-device feed proxy is the sender; bound to `0.0.0.0` after a game-PC agent is paired (the app persists that in its config). |
| 8321/tcp | revokyte app (agent pairing page) | Only while the pairing screen is open; serves the agent bundle to the game PC. |
| 22/tcp | sshd | **Dev images only.** Release images drop OpenSSH entirely (`configs/release.fragment`, asserted by `scripts/assert-release-image.sh`). |

Feed proxies additionally talk *outbound* to the game (GT7: heartbeat to
console port 33739, stream from 33740; ACC: Broadcasting API on the game PC,
default 9000). Nothing listens for the games.

## Firewall

**There is none.** The image ships no iptables/nftables userspace and no
filtering configuration. Reachability of the ports above is governed solely
by what binds them and on which address. The telemetry protocol's v1 trust
model (any LAN sender, PROTOCOL.md §6) matches this reality; adding a
firewall would be a product decision, not a bugfix.

## What senders may assume (summary)

1. The cluster is reachable as `instrument-cluster.local` (mDNS, wlan0) —
   *from images containing the `MulticastDNS=yes` line onward*; older flashed
   images only have the name on mDNS-proxying routers. Always implement the
   literal-IP fallback.
2. UDP port 5600 accepts telemetry per PROTOCOL.md once the user has selected
   a network feed on the device; no firewall will interfere.
3. The device's IP is DHCP-assigned and **does drift**; re-resolve the name
   periodically rather than caching an address forever.
