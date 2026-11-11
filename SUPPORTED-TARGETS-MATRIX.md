# KLab current target support matrix

Generated from the KLab 1.0.0-rc1 source catalogs and local evidence on 2026-10-07.

## Status meanings

- **Validated**: a recorded live guest reached the named success level.
- **Built**: a complete local target artifact exists, but this inventory does not claim a current live boot pass.
- **Implemented provider**: KLab can discover/import that family; exact releases are resolved dynamically and are not all release-gated.
- **Experimental architecture**: modeled and wired to QEMU/toolchain support, with less validation than stable architectures.

## Summary

| Category | Count | Meaning |
|---|---:|---|
| Formal legacy Linux targets | 9 | All pass their catalog gate |
| Formal BSD targets | 12 | All pass their catalog gate |
| Additional live distro targets | 4 | Recorded QEMU smoke/module passes |
| Cached upstream builds | 44 | Locally buildable artifacts across 2 architectures |
| Implemented providers | 8 | Dynamic discovery/import paths |
| Generic architecture definitions | 8 | Four stable and four experimental |

## Stable and experimental architectures

| Architecture | Status | QEMU | Linux | BSD |
|---|---|---|---|---|
| x86_64 | stable | ready/KVM | upstream+distro | automated |
| i386 | stable | ready/KVM | upstream | validated legacy + BSD |
| aarch64 | stable | ready | upstream | automated FreeBSD |
| armv7 | stable | ready | upstream | media/manual |
| mips | experimental | ready | upstream experimental | n/a |
| mipsel | experimental | ready | upstream experimental | n/a |
| mips64 | experimental | ready | upstream experimental | n/a |
| mips64el | experimental | ready | upstream experimental | n/a |
| riscv64 | BSD validated / generic model gap | QEMU 10 | not yet generic | FreeBSD 14.5 userspace pass |

The generic architecture catalog currently understates two proven paths: FreeBSD 14.5 i386 is live validated despite its older `14.x gated` label, and FreeBSD 14.5 riscv64 is validated although riscv64 has not yet been promoted into the generic architecture definitions.

## Formal legacy Linux release gate

| Target | Architecture | Achieved level |
|---|---|---|
| upstream:v2.0.40 | i386 | USERSPACE_PASS |
| upstream:v2.2.26 | i386 | USERSPACE_PASS |
| upstream:v2.4.37.11 | i386 | MODULE_PASS |
| upstream:v2.6.0 | i386 | MODULE_PASS |
| upstream:v2.6.0 | x86_64 | USERSPACE_PASS |
| upstream:v2.6.12 | x86_64 | USERSPACE_PASS |
| upstream:v2.6.18 | x86_64 | MODULE_PASS |
| upstream:v2.6.32.71 | i386 | NETWORK_PASS |
| upstream:v2.6.32.71 | x86_64 | NETWORK_PASS |

## Formal BSD release gate

| Target | Architecture | Achieved level |
|---|---|---|
| freebsd:15.1-RELEASE:x86_64 | x86_64 | MODULE_PASS |
| freebsd:15.1-RELEASE:aarch64 | aarch64 | MODULE_PASS |
| freebsd:14.5-RELEASE:x86_64 | x86_64 | MODULE_PASS |
| freebsd:14.5-RELEASE:i386 | i386 | USERSPACE_PASS |
| freebsd:14.5-RELEASE:riscv64 | riscv64 | USERSPACE_PASS |
| netbsd:11.0:x86_64 | x86_64 | USERSPACE_PASS |
| netbsd:11.0:i386 | i386 | USERSPACE_PASS |
| netbsd:11.0:aarch64 | aarch64 | USERSPACE_PASS |
| openbsd:7.9:x86_64 | x86_64 | USERSPACE_PASS |
| openbsd:7.9:aarch64 | aarch64 | USERSPACE_PASS |
| dragonfly:6.4.2:x86_64 | x86_64 | USERSPACE_PASS |
| dragonfly:6.2.2:x86_64 | x86_64 | USERSPACE_PASS |

## Additional recorded live distro passes

| Target | Architecture | Level | Evidence set |
|---|---|---|---|
| ubuntu:12.04:3.13.0-185-generic | x86_64 | SMOKE_PASS | compat-matrix attempt12 |
| debian:bookworm:6.12.107+deb12-amd64 | x86_64 | SMOKE_PASS | compat-matrix attempt3 |
| fedora:43:7.2.7-100.fc43.x86_64 | x86_64 | SMOKE_PASS | compat-matrix attempt6 |
| alpine:3.23:6.18.53-0-lts | x86_64 | MODULE_PASS | offline attempt4 |

## Cached upstream build targets

These are present in the current KLab root as built targets. The version list is exact; a build entry alone does not imply a live boot pass.

| Architecture | Built upstream versions |
|---|---|
| i386 | v5.10 |
| mipsel | v5.15 |
| x86_64 | v3.0, v3.10, v3.12, v3.16, v3.18, v3.2, v3.4, v3.6, v3.8, v4.0, v4.10, v4.12, v4.14, v4.16, v4.19, v4.1, v4.20, v4.4, v4.6, v4.9, v5.0, v5.10, v5.12, v5.15, v5.18, v5.4, v5.5, v5.8, v6.0, v6.10, v6.12, v6.14, v6.18, v6.1, v6.3, v6.5, v6.6, v6.8, v7.0, v7.1, v7.2.7, v7.2 |


## Implemented dynamic providers

| Provider | Resolution/import path |
|---|---|
| alpine | APK linux-lts / native musl |
| centos | CentOS 7.9 Vault and Stream/newer dnf |
| debian | APT current and snapshot |
| fedora | Koji exact kernel/buildroot provenance |
| freebsd | official release artifacts |
| rhel | entitled explicit build-tree contract |
| ubuntu | APT current |
| upstream | kernel.org source tags |

## Current boundary

The strongest supported floor is the 21-entry formal legacy/BSD matrix plus the four recorded distro passes above. The cached upstream set is broad build coverage. ARMv7 and the four MIPS variants are implemented architecture paths, but only mipsel v5.15 is present in this root and none should yet be described as broadly release-gated. RISC-V currently has a proven FreeBSD 14.5 userspace path rather than a general Linux architecture contract.

The machine-readable companion is `SUPPORTED-TARGETS.tsv`.
