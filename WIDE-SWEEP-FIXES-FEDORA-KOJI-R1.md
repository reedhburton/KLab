# KLab 0.0.0b wide-sweep fixes + Fedora Koji buildroot redesign r1

Date: 2026-09-24
Base: klab-0.0.0b

## Purpose

This patch set addresses the deterministic failures exposed by the 2026-09-24
wide x86_64 acquisition sweep, then replaces Fedora's repository-current
compiler selection with a kernel-build-specific Koji provenance path.

## Simple fixes included

- APT listing/fetch now rejects package names whose `apt-cache policy` Candidate
  is `(none)`.
- Ubuntu signed/unsigned image selection is mutually exclusive and based on a
  real installable candidate.
- `linux-modules-*` and `linux-modules-extra-*` are optional split packages;
  the exact image and exact flavour headers remain required.
- APT buildenv capture accepts a required GCC version, installs `gcc-<major>`,
  and explicitly passes that compiler to Kbuild.
- Buildenv smoke compilation preserves the real `make` return code instead of
  collapsing compiler/Kbuild failures into the generic no-module rc=43.
- RPM/YUM provenance helpers use an available Python 3 interpreter instead of
  assuming an unversioned `python` command.
- `prepare --artifact-dir DIR` is restored to match the documented/shared
  artifact workflow.
- matrix run keys include architecture, avoiding cross-architecture collisions.
- upstream git tag fetching now distinguishes network/remote failures from a
  genuinely absent tag.
- old upstream trees fall back from `olddefconfig` to `oldconfig`.
- the Docker-specific usrmerge regression test now uses Podman/Docker when
  available and cleanly skips when neither runtime is installed.

## Fedora redesign r1

Fedora kernel acquisition remains based on the exact completed Koji kernel
build, but portable compiler capture is now tied to the buildroot that actually
produced that kernel.

### Kernel fetch / provenance

`fetch_fedora_bundle()` now:

1. downloads the exact kernel NVR with a modern Koji client;
2. identifies the architecture-specific Koji buildroot that produced the
   kernel/core RPM;
3. records the buildroot package inventory, repo/tag/event identity, build
   configuration when available, external-repository metadata when available,
   and a canonical package-inventory digest in `koji-buildroot.json`;
4. records the Koji hub/topurl alongside the normalized target bundle.

### Discovery hardening

Fedora `list` output is parsed only from Koji kernel build NVR rows. Setup/package
manager chatter can no longer be mistaken for a kernel release (the failure
that produced the bogus Fedora 43 target based on the Koji client's own EVR).

### Distro-native toolchain

Fedora toolchain capture now requires an exact `fedora:release:kernel` target.
It resolves the `gcc`, `binutils`, and `make` packages from that kernel's own
Koji buildroot, maps each binary package back to its exact source build NVR,
and downloads those exact build outputs with a modern Koji client.

The distro-toolchain compiler metadata is derived from the exact Koji package
records rather than from whatever GCC happens to be current in the Fedora
release repositories. This removes the F42/F44 point-release drift observed in
the sweep and avoids executing a partially installed historical compiler merely
to discover its version.

### Buildenv assembly

The captured Fedora buildenv installs the kernel RPMs and then explicitly
installs the sealed Koji compiler/binutils/make RPM set as local packages.
For dependency resolution it first constructs the exact Koji buildroot repo URL
from the recorded build tag + repo ID + architecture and tries that repo alone.
When Koji has already garbage-collected that historical repo, KLab emits a
warning, records `release-fallback` in `/var/lib/klab/fedora-repo-source`, and
uses the matching Fedora release repositories for auxiliary/runtime dependencies.
Set `KLAB_FEDORA_STRICT_BUILDROOT_REPO=1` to fail instead of permitting that
fallback. When the exact repo is usable, the captured root records
`koji-buildroot:<url>`.

The resulting environment must compile the smoke module with `/usr/bin/gcc`,
pass vintage relocation validation, be sealed into the `.klabbuildenv`, and
then pass the existing read-only offline smoke validation.

This means the **compiler selection is never repository-current**, and r1 also
prefers the exact historical Koji dependency repository whenever Koji still
retains it.

## Remaining Fedora phase-2 work

The next Fedora hardening step is to remove the remaining dependency on live/EOL
Fedora release repositories for auxiliary compiler/runtime/build dependencies.
The captured Koji manifest already contains the exact historical buildroot
inventory and repo identity needed for that work. Candidate approaches are:

- reconstruct the required RPM dependency closure from the recorded buildroot
  package set and retained Koji builds when the exact `tag/repo_id/arch` repo
  has already been garbage-collected;
- seal the auxiliary dependency package bytes/provenance separately if we want
  a Fedora buildenv that never needs release-repository fallback during staging.

Do not fall back silently to a newer compiler. If an exact historical execution
root cannot be reconstructed, KLab should fail with a provenance/availability
error rather than claim reproducibility.

## Validation performed in this environment

- All shell files: `bash -n` PASS.
- Python helpers: bytecode compilation PASS.
- 62 network-free functional tests were exercised and passed.
- `distro-native-host-tool-usrmerge.sh` now reports SKIP when neither Podman nor
  Docker exists; this execution environment has neither.
- New Fedora fake-Koji regression proves buildroot selection, package inventory
  hashing, repo provenance capture, exact GCC/binutils/make source-build
  resolution, and compiler metadata derivation.

A live Fedora/Koji/container run was **not** possible in this analysis
container because it has no Podman/Docker runtime and no local python3-koji.
The next staging-machine validation should re-run representative Fedora 20, 23,
29, 42, 43 and 44 targets with `--distro-toolchain`.
