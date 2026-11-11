# KLab Compatibility Audit — Overnight Pass 01

Date: 2026-09-21 HST
Base snapshot: `klab-m2-hardened-snapshot-2026-09-21`

## Provider/repository checks

| Target family | Result of this pass | Notes |
|---|---|---|
| Ubuntu 17.04 / 4.10 | Policy path retained | Zesty remains an old-releases target. Official `ubuntu:17.04` container tags still exist. Live KLab fetch/prepare remains a next-host test. |
| Ubuntu 14.04 LTS | Routing bug fixed | Trusty is still served from the primary Ubuntu archive in Sep 2026; do not redirect to old-releases by default. |
| Ubuntu 16.04 LTS | Routing bug fixed | Xenial is still served from the primary Ubuntu archive in Sep 2026. |
| Ubuntu 18.04 LTS | Routing bug fixed | Bionic is still served from the primary Ubuntu archive in Sep 2026. |
| Ubuntu 20.04/22.04/24.04/26.04 | Current/LTS path preserved | Not in KLab's default old-release set. |
| CentOS 7 / 3.10 | Live V4 PASS | `centos:7:3.10.0-1160.119.1.el7.x86_64` passed pinned-key HTTPS Vault acquisition, exact 197-RPM signed closure capture, Buildenv V4 deep verification, and fresh-root import. |
| Fedora/RHEL | No widening in this pass | Existing provider boundaries remain x86_64-only. |
| Rocky/AlmaLinux | Experimental only | Still requires explicit experimental-provider opt-in. |

## Architecture contract

This pass does **not** claim new live architecture support. Instead it removes ambiguity:

- Current distro providers now explicitly advertise `arches=x86_64`.
- The dispatcher rejects a provider operation before repository access when `ARCH` is not in that set.
- `cross-arch=no` remains separate from `arches=`. Future providers can declare, for example, `arches=x86_64,aarch64` while independently stating whether a staging host can cross-build those targets.
- KLab buildenv internals retain canonical mappings for x86_64, i386, aarch64 and armv7, but distro-provider support for those non-x86_64 targets remains unclaimed until live tested.

## Kernel-release compatibility probes

The provider input validator accepts representative exact distro kernel releases:

- `3.10.0-1160.119.1.el7.x86_64`
- `7.0.0-31-generic`

and rejects glob/shell/path forms such as `6.1.0-*`, `6.1.0;id`, command substitutions, and `../6.1.0`.

## Regression status

All 20 network-free functional test scripts passed individually after the changes in this pass, including the two new tests:

- `apt-list-quoting.sh`
- `provider-compat-hardening.sh`

Shell syntax and Python bytecode compilation also passed.

## Next live compatibility checks

1. Ubuntu 17.04: `list -> prepare -> buildenv capture -> smoke` against an exact 4.10 kernel.
2. CentOS 7 is complete for `3.10.0-1160.119.1.el7.x86_64`; retain it as a release regression target.
3. Modern Ubuntu 26.04/7.0 regression after provider-core changes.
4. Only after x86_64 is clean: introduce one non-x86_64 provider path at a time, preferably aarch64 first.

## Integrated overnight hardening — 2026-09-22

Passes 02–09 have now been folded into the working snapshot rather than remaining only as audit findings. F06–F15 and F17–F18 are implemented with regression coverage. F12 is closed by the same-architecture host/container checks in F13/F14.

**F16 provider acquisition is closed for the stable provider families.** Buildenv V4 retains and verifies an exact immutable dependency archive closure plus repository snapshot metadata, and rejects a closure that differs from the realized installed inventory. Current Ubuntu/Debian APT capture is automated and live-validated on Ubuntu 24.04 / 6.8.0-142-generic and Debian Bookworm / 6.1.0-53-amd64. Fedora/Koji RPM capture is automated and live-validated on Fedora 44 / 7.2.11-200.fc44.x86_64. All three passed deep verification and fresh-root imports. Koji mode binds retained buildroot metadata and verified RPM payload digests, while normal RPM repositories retain signature enforcement. Alpine/APK capture is automated and live-validated on Alpine 3.23 / 6.18.57-0-lts, including signed origin archives for split installed identities. Historical APT acquisition is live-validated on Ubuntu 17.04 / 4.10.0-42-generic with a complete 153-DEB closure. Historical yum acquisition is live-validated on CentOS 7 / 3.10.0-1160.119.1.el7.x86_64 with a complete 197-RPM signed closure and pinned signing-key fingerprint. Existing V1–V3 buildenvs retain their prior guarantees without claiming from-archive reconstruction; the new guarantees apply to V4 artifacts.

Compatibility claims remain deliberately conservative:
- stable distro providers: x86_64 target only;
- provider buildenv capture: same execution architecture as staging host;
- Ubuntu archived releases use old-releases and do not claim `@timestamp` snapshots;
- non-snapshot providers reject timestamp syntax before repository access.

## Vintage toolchain pass 01 — 2026-09-22

The Ubuntu 17.04 live test exposed a new compatibility boundary: vermagic matched, but GCC 6.5/binutils 2.32 emitted `R_X86_64_PLT32`, which the exact 4.10.0-42 guest rejected. R12 pass 01 adds a relocation-aware vintage preflight and a distinct content-addressed `.klabdistrotoolchain` package artifact for the distribution-native GCC/binutils closure. See `VINTAGE-TOOLCHAIN-AUDIT.md`.

No new runtime compatibility claim is made. Distro-native execution binding remains the next implementation step.
