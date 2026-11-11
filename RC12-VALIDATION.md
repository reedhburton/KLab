# KLab RC12 retained-image conformance — 2026-10-18

## Release gate

- Linux: **49/49 PASS**, with **9/9 probes** on every retained image.
- FreeBSD: **3/3 PASS**, with a fresh kernel-module build/load smoke and **8/8 probes** on every retained image.
- Network-free regressions: **134/134 PASS**, including shell and Python syntax checks.

## Linux coverage

| Provider | Targets | Result |
|---|---:|---:|
| Ubuntu | 35 | 35 PASS |
| Fedora | 11 | 11 PASS |
| Alpine | 1 | 1 PASS |
| Debian | 1 | 1 PASS |
| CentOS | 1 | 1 PASS |
| **Total** | **49** | **49 PASS** |

Each Linux guest was checked for distribution and kernel identity, writable filesystem behavior, `/proc` and `/sys`, multiprocess coordination, native C compilation and execution, Python execution and `fork`, loopback and ping networking, module listing/loading facilities, and an orderly shutdown path.

## FreeBSD coverage

| Release | Architecture | Module smoke | Guest probes | Result |
|---|---|---:|---:|---:|
| 14.5-RELEASE | x86_64 | PASS | 8/8 | PASS |
| 15.1-RELEASE | x86_64 | PASS | 8/8 | PASS |
| 15.1-RELEASE | aarch64 | PASS | 8/8 | PASS |

The FreeBSD probes cover identity, filesystem behavior, kernel interfaces through `sysctl`, process coordination, native `cc`/`make` compilation and execution, runtime linkage, kernel-module listing, and shutdown tooling. Guest networking is currently disabled by the FreeBSD backend and is therefore outside this eight-probe gate.

## Fixes proven by this run

- Native Fedora roots with read-only `/usr/lib` can receive exact-kernel module trees during session staging.
- Containerized QEMU preserves KLab's daemon and host-PID semantics instead of exiting when QEMU daemonizes.
- FreeBSD/aarch64 runs on QEMU 10.0.13 and discovers its virtio control port without relying on unstable guest port numbering.
- The retained FreeBSD 15.1 aarch64 image built and loaded a real kernel module before passing its persistent-guest checks.

The canonical detailed evidence is stored outside the source archive in `library/retained-conformance-2026-10-18/` and `library/retained-bsd-conformance-2026-10-18/`.
