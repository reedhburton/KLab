# Target parity status — 2026-10-24

The retained catalog contains 69 exact targets. All 69 retain a PASS from the clean import/standard execution gate in `/mnt/klab-store/recovery-inventory/fresh-import-reconciled.tsv`.

## What is now common

- Linux SSH is a runtime layer. Any Buildroot or native root can reuse its daemon or receive an architecture-matched static Dropbear in the disposable initramfs. The packaged target remains immutable.
- Key login no longer depends on `usermod`; legacy roots receive a minimal account database and safe `/root` permissions.
- Live SSH proofs cover x86_64, i386 (Linux 2.6.32), and mipsel Linux.
- NetBSD 11.0 (amd64, i386, arm64), OpenBSD 7.9 (amd64, arm64), DragonFly 6.2.2/6.4.2 amd64, FreeBSD 14.5 (amd64, i386, riscv64), and FreeBSD 15.1 (amd64, arm64) have native userspace plus real key-authenticated SSH proof.
- FreeBSD 15.1 arm64 automatically uses the installed pinned QEMU 10 container on hosts whose older QEMU cannot execute it. The wrapper supports the external `/mnt/klab-store` layout.

## Exact semantic limits

“Full native userspace” means the userspace from the named OS release. It is valid for distribution and BSD targets. A generic `upstream:vX.Y` kernel has no named distribution release, so KLab reports its larger Buildroot environment as **portable full**, never as native.

The current exact native-root cache matches Alpine 3.23 x86_64, Debian bookworm x86_64, Ubuntu 12.04 x86_64, Fedora 43 x86_64, and every retained BSD disk. Fedora 43 native-root capture verified as object `fd49143c9ffd56e3f65c3ab5633f5c81a4879536cb5ff52039cf883f069de555`, but its separate native-bound offline bundle is blocked because the exact installed archive `dnf5-0:5.2.18.0-5.fc43.x86_64` is unavailable to the dependency sealer. Its existing minimal target remains valid and SSH-capable; native-full is not yet claimed.

Linux 2.0, 2.2, and 2.4 remain legacy alternate-gate targets. Their retained standard/minimal evidence is valid, but modern SSH daemons and a full contemporary userspace are not a defensible compatibility promise for those kernels. Linux 2.6.32 i386 is now beyond that boundary and has a live SSH command proof.

## Live evidence added in this pass

- Linux 2.6.32.71 i386: `i686`, `2.6.32.71`, `KLAB_LINUX2632_SSH_OK`
- FreeBSD 14.5 amd64: `KLAB_FREEBSD145_X64_SSH_OK`
- FreeBSD 15.1 amd64: `KLAB_FREEBSD151_X64_SSH_OK`
- FreeBSD 15.1 arm64 through QEMU 10: `KLAB_FREEBSD151_ARM64_SSH_OK`
- FreeBSD 14.5 riscv64 through QEMU 10: `KLAB_FREEBSD_RISCV64_SSH_OK`
- Focused SSH/BSD/container regressions: PASS
- Complete network-free suite after the Linux/BSD transport changes and automatic QEMU 10 selection: `ALL M2 NETWORK-FREE TESTS: PASS`

This is not a claim that 69 separate SSH boots were rerun on 2026-10-24. It records shared runtime coverage, exact live boundary proofs, retained per-target standard evidence, and the remaining native-userspace limitations without promoting availability to proof.

## Fedora 43 exact native parity and legacy SSH follow-up

- **Fedora 43 x86_64: PASS.** KLab reconstructed the exact Koji dependency closure for `fedora:43:7.2.7-100.fc43.x86_64`, compiled the smoke module with the distribution-native GCC/binutils environment, packaged native Fedora 43 userspace, verified every archive member, and booted the exact kernel. Authenticated SSH returned `7.2.7-100.fc43.x86_64`, `Fedora release 43 (Forty Three)`, and `uid=0(root)`. Artifact: `/home/reed/klab-offline/variants/fedora-43-7.2.7-native-x86_64.klab`; SHA-256 `09f8ea988c983a77ce33fe87ea00ca72a43fec8c4485d57889d785cc6835c83d`.
- **Linux 2.4.37.11 i386 SSH: PASS.** The legacy initrd now creates `/dev/random` and `/dev/urandom` for pre-devtmpfs kernels, retains the explicit NIC name before sysfs exists, and fixes root ownership before Dropbear authentication. A live key-authenticated session returned kernel `2.4.37.11`, root identity, and `KLAB_LEGACY_SSH_OK`.
- **Linux 2.0/2.2 SSH: historical userspace work remains.** Their proven boot appliance is a syscall-only, no-libc init. A modern musl Buildroot root reaches Linux 2.2 but fails when starting its shell because modern libc requires a newer kernel ABI. A static Dropbear built with that same modern libc therefore cannot solve the boundary. Full SSH requires a separately sealed historical libc/BusyBox/Dropbear stack; Linux 2.0 additionally needs a QEMU-compatible legacy NIC enabled. Their existing kernel boot gates remain valid and unchanged.
- **Regression result:** the complete network-free `tests/run-all.sh` suite passes, including Fedora Koji exact-package fallback, native `.klab` create/import, legacy random devices, legacy NIC resolution, and Dropbear root ownership.
