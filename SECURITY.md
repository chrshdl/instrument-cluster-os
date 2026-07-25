# Security Policy

## Reporting a vulnerability

Please do not report security problems in public issues.

- Preferred: [GitHub private vulnerability reporting](https://github.com/chrshdl/instrument-cluster-os/security/advisories/new)
  (Security tab → "Report a vulnerability")
- Alternatively: email <cwasilei@gmail.com> with "SECURITY" in the subject

You will get an acknowledgment within 7 days. We follow coordinated
disclosure: please give us a reasonable window (customarily 90 days) to
ship a fix before publishing details, and we will credit you in the
release notes unless you prefer otherwise.

Vulnerabilities in the Revokyte app itself
([chrshdl/revokyte](https://github.com/chrshdl/revokyte)) can be
reported through the same channels. For vulnerabilities in upstream
packages that the image merely bundles, reporting upstream is usually
more effective, but if you are unsure whether this image is affected,
report it here and we will triage it.

## Supported versions

Only the [latest release](https://github.com/chrshdl/instrument-cluster-os/releases)
is supported. Community devices update by re-flashing the latest
factory image; Pro devices receive signed over-the-air updates.

## Security update policy

Community and Pro images are built from the same source tree, and
security fixes land in both. Security is never a paid feature; the
editions differ in how updates are delivered, not in whether you get
them.

- **Pro**: fixes ship with the regular over-the-air updates.
- **Community**: fixes ship as new factory images. Vulnerabilities in
  the device's real attack surface (Wi-Fi stack, kernel network stack,
  TLS, the telemetry listener) trigger an out-of-band release;
  lower-severity issues are batched into the next platform release.

Buildroot point releases are triaged monthly by an automated workflow
(`triage-buildroot.yml`): it diffs the new tag against the exact
package set the image ships, attaches a CVE report scoped to our
versions, and opens a version-bump PR when a shipped package is
affected.

## Hardening and threat model

Release images are locked down: no SSH daemon, root account locked
(both enforced by `scripts/assert-release-image.sh`, which fails the
release build otherwise). The device listens for game telemetry on the
local network and needs no internet exposure. Do not port-forward to
it or place it on untrusted networks.

Dev images (CI artifacts from pull requests and manual runs, never
attached to releases) enable SSH with default credentials for the
development loop. They are for development hardware only and must not
be used as daily-driver images.
