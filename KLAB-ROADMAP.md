# KLab roadmap

## Ideal goal: historical x86 kernels

KLab should eventually build, package, boot, and test kernels back to the early Linux 2.x era. This is an ideal compatibility target rather than a claim that the current Buildroot, module, or QEMU paths already support these releases.

### x86_64 ladder

Start at the beginning of the 2.6 stable series and establish representative checkpoints:

- Linux 2.6.0: earliest target.
- Linux 2.6.12: early mature 2.6 checkpoint.
- Linux 2.6.18: common enterprise-era checkpoint.
- Linux 2.6.32: late 2.6 LTS-era checkpoint.
- Linux 3.0 and newer: connect the legacy lane to the existing matrix.

### i386 ladder

Attempt progressively older stable series:

- Linux 2.6.0 and 2.6.32.
- Linux 2.4.37.11 and an early 2.4 release.
- Linux 2.2.26 and 2.2.0.
- Linux 2.0.40 and, if practical, Linux 2.0.

The kernel.org archives retain the 2.0, 2.2, and 2.4 source series. Exact patch-level targets may change when a nearby release has materially better build or emulator compatibility, but failures must remain recorded rather than silently skipped.

### Graded success levels

Each target should report the highest level reached:

1. `SOURCE_VERIFIED`: source archive and signature/checksum provenance captured.
2. `BUILD_PASS`: kernel image produced with a recorded historical toolchain.
3. `BOOT_PASS`: kernel reaches a serial boot marker in QEMU.
4. `USERSPACE_PASS`: a period-compatible init/userspace probe executes.
5. `MODULE_PASS`: a version-appropriate module builds, loads, exercises behavior, and unloads.
6. `NETWORK_PASS`: isolated TCP/UDP and multi-process coordination tests pass where the kernel provides the required facilities.

A target can remain useful at a lower level. For example, an early 2.0 kernel that boots but cannot run the modern KLab guest agent should be recorded as `BOOT_PASS`, not treated as an all-or-nothing failure.

### Expected compatibility work

- Historical GCC and binutils selection, including compilers old enough for pre-modern kernel build assumptions but patched to build on a current host.
- Compatibility patches for obsolete C constructs, host compiler behavior, modern `make`, and modern libc headers.
- Legacy QEMU machine/device profiles: `pc`, IDE, ISA serial, legacy NICs, and older interrupt/timer behavior instead of virtio-only assumptions.
- Period-compatible root filesystems and init programs. Modern Buildroot releases will not cover the full range.
- Versioned module examples for pre-2.6 and early-2.6 module APIs.
- Boot reporting that does not require virtio-serial or a modern `/proc`, sysfs, udev, module utilities, or networking stack.
- Explicit separation between pristine-source results and results requiring a documented compatibility patch set.

### Proposed implementation order

1. Add a legacy x86 capability model and graded-result schema without changing existing stable architecture gates.
2. Prove x86_64 on 2.6.32, then walk backward through 2.6.18, 2.6.12, and 2.6.0.
3. Prove i386 on 2.6.32 and 2.4.37.11.
4. Add a minimal non-Buildroot legacy initramfs and IDE/ISA QEMU profile.
5. Attempt i386 2.2.26 and 2.0.40.
6. Add version-specific module and networking payloads only after repeatable boot/userspace results exist.

### Acceptance goal

The ideal milestone is a resumable report spanning Linux 2.0 through current kernels, with every attempted target retaining source identity, toolchain identity, patches, build logs, boot evidence, and its highest verified success level.

## Ideal goal: BSD compatibility and historical releases

KLab should also provide a reproducible BSD lane covering current and historical FreeBSD, NetBSD, OpenBSD, and DragonFly BSD releases. The lane must use per-OS expectations rather than assuming Linux interfaces, filesystem layouts, module tools, or guest agents.

### Target ladders

- FreeBSD: retain the proven FreeBSD 15.1 amd64 baseline, then test 14.x, 13.x, 12.x, and 11.x before descending into 10.x and 9.x as best-effort historical targets. Add current aarch64 after the amd64 lane is repeatable, and use i386 for historical releases where viable.
- NetBSD: establish a current amd64 baseline, then descend through representative 10, 9, 8, 7, 6, 5, 4, 3, 2, and late 1.x releases. Add additional architectures after the control transport and userspace probes work reliably on amd64.
- OpenBSD: establish a current amd64 baseline and then arm64. Walk backward through obtainable prior releases while recording unavailable installation media explicitly. Test boot, userspace, networking, process coordination, and native compilation; kernel-module testing is not an expected OpenBSD gate.
- DragonFly BSD: establish a current x86_64 baseline, then cover representative 6.x releases and descend through older official images as emulator and installer compatibility permits.

Exact patch releases should be selected from verified official media available when each matrix is generated. Every selected image must retain its download origin, digest, release identity, architecture, and acquisition date.

### Graded success levels

Each BSD target should report the highest applicable level reached:

1. `MEDIA_VERIFIED`: installation or live media provenance and digest recorded.
2. `BOOT_PASS`: the OS reaches a serial console or deterministic boot marker in QEMU.
3. `USERSPACE_PASS`: the KLab probe or a period-compatible replacement executes and returns structured results.
4. `NETWORK_PASS`: isolated TCP/UDP tests and multi-process coordination pass.
5. `NATIVE_BUILD_PASS`: a userspace payload builds and runs inside the guest.
6. `KERNEL_EXTENSION_PASS`: a native kernel extension builds, loads, exercises behavior, and unloads when that operating system and release expose a supported practical mechanism.
7. `OFFLINE_REIMPORT_PASS`: the complete target can be exported, re-imported into a fresh KLab root, and exercised without network access.

Inapplicable gates must be recorded as `N/A` with the OS-specific reason. A lower-level success remains a useful result and must not be collapsed into a generic failure.

### Required platform work

- Introduce BSD-aware image acquisition, disk layouts, installer automation, boot arguments, serial-console detection, and shutdown handling.
- Abstract the guest control transport from Linux-only virtio, `/proc`, sysfs, udev, shell, and package-manager assumptions.
- Provide OS-specific userspace, networking, multi-process, compiler, and kernel-extension probes.
- Keep FreeBSD `kld` behavior, NetBSD module behavior, DragonFly module behavior, and OpenBSD's lack of a general third-party loadable-module workflow as separate capability profiles.
- Capture base-system compiler and ABI identities, and support both native builds and KLab cross-compilation where the target ABI is supported.
- Preserve install media, packages or source sets, target metadata, scripts, and licenses needed to reproduce successful targets in the pseudo-offline repository.
- Record pristine-media results separately from targets that require installer, source, compiler, or emulator compatibility patches.

### Proposed implementation order

1. Convert the existing FreeBSD 15.1 amd64 proof into a repeatable regression case with structured evidence.
2. Test FreeBSD 14, 13, and 12 on amd64, then current FreeBSD on aarch64.
3. Build a shared BSD serial/control transport and prove current NetBSD amd64.
4. Prove current OpenBSD amd64 and DragonFly BSD x86_64 using their own capability profiles.
5. Add cross-compiled userspace, networking, and multi-process payloads to every passing modern target.
6. Descend each historical ladder, introducing period-compatible transports and build probes only where needed.
7. Export every passing target as a checksum-verified offline-reimportable `.klab` artifact.

### Acceptance goal

The milestone is a resumable cross-BSD report in which every attempted release retains media provenance, machine configuration, compiler identity, patches, logs, boot evidence, and its highest applicable success level. Passing targets must also populate the pseudo-offline repository with the material and instructions needed to reproduce them.
