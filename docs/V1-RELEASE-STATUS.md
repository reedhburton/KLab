# 1.0.0 release validation status

The 1.0.0 artifact set contains **174 target/architecture combinations that passed the full offline runtime gate**. Eight additional targets are retained for later repair and are not claimed as supported by this release.

The full gate covers boot, external kernel-module build and insertion, ordered multi-process workloads, two-guest TCP, native userspace, and SSH command execution where the target supports those facilities. The authoritative row-level ledger is [`catalog/v1-release-validation-2026-11-19.tsv`](../catalog/v1-release-validation-2026-11-19.tsv).

## Deferred targets

| Target | Reason |
| --- | --- |
| `arch:rolling:6.18.59-1-lts` | Historical Arch build environment must be reconstructed from retained packages. |
| `arch:rolling:7.2.10-hardened1-3-hardened` | Historical Arch build environment must be reconstructed from retained packages. |
| `arch:rolling:7.2.11-arch1-1` | Historical Arch build environment must be reconstructed from retained packages. |
| `arch:rolling:7.2.11-zen1-1-zen` | Historical Arch build environment must be reconstructed from retained packages. |
| `debian:bookworm:6.12.113+deb12-cloud-amd64` | Repair must reuse the sealed Buildroot SDK instead of rebuilding it. |
| `debian:bookworm:6.12.113+deb12-rt-amd64` | Repair must reuse the sealed Buildroot SDK instead of rebuilding it. |
| `fedora:38:6.2.15-300.fc38.x86_64` | Exact GCC 13.1 must be isolated from the provider image's libstdc++ 13.2 runtime. |
| `fedora:42:6.14.11-300.fc42.x86_64` | Exact Koji buildroot reconstruction did not finish before the release cutoff. |

Deferred artifacts and failure reports are preserved so these targets can be added in a later repository release without changing the 1.0.0 claims.

## Portable artifact archive

- File: `klab-portable-complete-2026-11-17.tar.zst`
- Size: `481985276578` bytes (`448.88 GiB`)
- SHA-256: `766fbbad962b58b857f04ebec7ac87aaa79618df412bb737c810ff0cc5004560`
- Checksum verification: passed on 2026-11-19

The archive is content-addressed and immutable. Keep its adjacent `.sha256` file with it during transfer.
