# Proposal: DNS-SD service discovery for telemetry senders

**Status: proposal only — nothing in this document is implemented.**

## Problem

A telemetry sender needs the cluster's address. Today that travels out of
band: the pairing page rewrites `config.json` (`output` / `output_mdns`) into
the bundle the user downloads, and third-party senders (e.g. a SimHub plugin)
must ask the user to type the cluster's name or IP. With DNS-SD the sender
could instead *browse* for `_revokyte-telemetry._udp.local`, list every
cluster on the LAN, and connect with zero typing — the same UX as network
printers. The record set would be:

```
_revokyte-telemetry._udp.local  PTR  instrument-cluster._revokyte-telemetry._udp.local
instrument-cluster._revokyte-telemetry._udp.local  SRV  0 0 5600 instrument-cluster.local
instrument-cluster._revokyte-telemetry._udp.local  TXT  "v=1"
```

`TXT v=1` states the highest protocol version the receiver implements, which
gives senders a discovery-time version signal the wire itself doesn't carry.

## The hard constraint

**systemd-resolved — the image's only mDNS responder — cannot publish DNS-SD
services.** It answers hostname A-record queries (that is what
`MulticastDNS=yes` in `80-wlan0.network` enables) but has no configuration
file, D-Bus API or any other mechanism for arbitrary PTR/SRV/TXT record sets.
So this feature cannot ride the existing responder; it needs one of:

### Option A — add Avahi

The standard answer. `BR2_PACKAGE_AVAHI` + `BR2_PACKAGE_AVAHI_DAEMON` (pulls
in `BR2_PACKAGE_DBUS`; D-Bus is not otherwise required by this image today),
plus a static service file in the overlay:

`/etc/avahi/services/revokyte-telemetry.service` — declarative XML, published
automatically, no app involvement.

Costs and risks:
- A new always-on daemon (~1 MB + D-Bus) on a fast-boot appliance; boot-time
  impact must be measured against the deliberately fragile early-boot
  ordering (see CLAUDE.md "Boot-time ordering").
- **Two mDNS responders conflict.** Avahi and resolved's responder both want
  port 5353 ownership of the name. The clean configuration is: revert
  `MulticastDNS=yes` to `MulticastDNS=resolve` in `80-wlan0.network` and let
  Avahi own both hostname and services. That couples this proposal to the
  hostname guarantee in `docs/NETWORKING.md` — they must land as one change.
- Avahi is another CVE surface on the LAN listening path (triage workflow
  covers it once it's in the shipped package set).

### Option B — app-level responder in revokyte

A small pure-stdlib mDNS responder inside the cluster app (or a dedicated
~200-line daemon in the overlay): join 224.0.0.251, answer queries for the
service PTR/SRV/TXT and nothing else, leave hostname A-records to resolved.
- Fits the "plain python3, stdlib only" appliance constraint; no Buildroot
  package changes at all (ships with the app via the normal image pin).
- No new daemon if it lives on the app's existing UDP thread pool.
- But: RFC 6762 has real corner cases (probing, conflict defense, TTL
  refresh, goodbye packets, known-answer suppression). A minimal responder
  that only *answers* (never probes/announces) is defensible for a
  device-unique service instance, yet it is protocol code we then own
  forever, and coexistence on port 5353 with resolved requires
  SO_REUSEPORT-style sharing that must be verified against resolved's socket
  options on the shipped systemd.

### Option C — do nothing (status quo)

The hostname convention (`instrument-cluster.local` + IP fallback) already
gives senders an address with one line of user-visible configuration, and
PROTOCOL.md §2.5 specifies it. Discovery only removes the "type the name"
step and enables multi-cluster listing — nice, not necessary, while there is
exactly one cluster product and its name is fixed.

## Backward compatibility

- Old senders are unaffected by any option: discovery is additive; the
  `config.json` handoff and the hostname convention keep working unchanged.
- New senders MUST treat discovery as best-effort and keep the §2.5
  name+IP path: multicast is blocked on many "guest" networks, and old
  *images* (no service advertised) remain in the field indefinitely.
- A new descriptor/TXT field never changes the wire protocol; `v` in TXT is
  informational (PROTOCOL.md §3.2 still governs on-wire behavior).

## Recommendation

Defer (Option C) until the SimHub feed's UX proves the typing step is a real
adoption barrier. If/when it does: prefer **Option A (Avahi)** — service
publishing is exactly what it is for, and owning RFC 6762 corner cases in
app code (Option B) is the wrong place to spend maintenance — accepting the
D-Bus dependency, measuring boot impact, and switching resolved to
`MulticastDNS=resolve` in the same change so exactly one responder owns the
name. Rough cost when picked up: defconfig + overlay + release-image assert
updates, one image release, no app or protocol change.
