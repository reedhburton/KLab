# KLab r16 mixed-architecture matrix checkpoint

## Stable/default matrix
- x86_64 client -> aarch64 router -> i386 server
- aarch64 client -> x86_64 router -> armv7 server
- armv7 client -> aarch64 router -> x86_64 server
- i386 client -> x86_64 router -> aarch64 server

Each case has two isolated IPv4 LANs, a two-NIC forwarding router, endpoint static routes, PCAP capture, static netpair builds, and a cross-guest server READY dependency.

## Experimental matrix
- x86_64 -> aarch64 -> mipsel
- mipsel -> x86_64 -> armv7
- mips -> aarch64 -> x86_64

MIPS and MIPSel remain ARCH_STATUS/E2E_STATUS experimental. These cases are planner-validated but disabled by default. Set `KLAB_R16_EXPERIMENTAL_MATRIX=1` to schedule them. Otherwise the overnight report records `SKIP_DISABLED` rows.

## Overnight controls
- `KLAB_R16_MIXED_MATRIX=1` (default): run stable matrix.
- `KLAB_R16_EXPERIMENTAL_MATRIX=0` (default): record experimental cases as disabled.
- Existing per-scenario QEMU checks still produce `SKIP_QEMU` when a required system emulator is absent.
- Resume semantics remain case-based, so completed matrix rows are skipped on a resumed overnight run.

## Validation
PASS: all seven scenario files through multiguest planner validation.
PASS: `tests/r16-mixed-arch-matrix.sh`.
PASS: shell syntax for matrix test and overnight runner.

## Live boundary
No live QEMU traffic is claimed in this environment. Stable host validation now needs qemu-system-x86_64, qemu-system-i386, qemu-system-aarch64, and qemu-system-arm plus prepared target/userspace bundles. Experimental MIPS additionally needs qemu-system-mips/mipsel and suitable toolchain/userspace artifacts.
