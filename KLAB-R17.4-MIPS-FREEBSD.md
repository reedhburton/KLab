# KLab r17.4 MIPS and FreeBSD validation

## Big-endian MIPS

`klab arch-smoke upstream:v6.6 --arch mips --profile normal --userspace buildroot:minimal` passed end to end. The guest reported `machine=mips`, a 32-bit MSB MIPS32 rel2 userspace binary ran, and module load/unload markers passed.

Result directory: `/home/reed/klab-data/results/manual-r17.4-mips-v6.6-attempt1`.

## FreeBSD x86_64

`klab smoke freebsd:15.1-RELEASE --arch x86_64` passed against the official FreeBSD 15.1-RELEASE amd64 cloud image and matching `src.txz`. Both seed and source artifacts were attached as CD-ROM media with Rock Ridge filenames. The VM remained network-disabled.

KLab extracted the matching source tree, compiled `kernel_lab_hello.ko` with FreeBSD clang 19.1.7, booted a clean second VM, loaded the module, ran the test, and emitted `KLAB_FREEBSD_SMOKE_OK` followed by `FreeBSD test PASS`.

Result log: `/home/reed/klab-data/results/manual-r17.4-freebsd15.1-x86_64-attempt26/run.log`.

The FreeBSD control transport now uses one persistent upstream QEMU serial connection and a host-side Unix-socket relay. Sequential CLI RPC clients no longer force unreliable UART reconnects. Uploads use short, byte-counted EXEC frames. Source extraction runs under FreeBSD `daemon(8)` and is polled separately from compilation.

## Regression

The complete network-free suite ended with `ALL M2 NETWORK-FREE TESTS: PASS` after these changes.
