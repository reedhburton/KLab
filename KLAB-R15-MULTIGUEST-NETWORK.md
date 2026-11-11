# KLab r15 checkpoint — simple to complex multi-guest testing

## Implemented

- Added `kernel-lab.sh multiguest-run`.
- Added `klab-multiguest-scenario-v1` planner/validator.
- Added privilege-free QEMU socket-multicast LAN backend integration to persistent sessions.
- Added per-architecture QEMU NIC profiles and required built-in Linux network drivers.
- Added static guest IPv4/MAC configuration and session metadata.
- Fixed same-target concurrent session Unix socket collisions by including session name in the socket/QMP hash.
- Added guest-agent host-controlled gates for cross-guest synchronization.
- Added merged multi-guest report/timeline format.
- Added static TCP server/client test program.
- Added simple 2-guest same-kernel network example.
- Added complex 3-guest kernel-span example with module lifecycle.
- Added mixed x86_64/aarch64/i386 example.
- Added resumable multi-guest overnight runner and r15 feature umbrella.

## Focused validation

PASS:

- guest-agent gate wait/status/release behavior,
- multi-guest schema validation and duplicate-address rejection,
- simple and complex multi-guest dry-run/report generation,
- per-architecture network-device metadata,
- network-pair native TCP server + two clients,
- multi-guest overnight no-QEMU classification and resume without duplicate rows,
- architecture model / arch-plan CLI,
- provider architecture model,
- architecture E2E dry-run and ELF filters,
- existing guest-agent process/barrier protocol,
- existing single-guest scenario planner/dry-run/canonical report,
- root layout,
- toolchain boundary + patcher,
- wide-sweep regression set,
- MIPS/mipsel architecture and ELF checks,
- shell syntax and C `-Wall -Wextra -Werror` for the new agent/network test sources.

The aggregate all-tests invocation still exceeds the development environment execution window during longer buildenv fixtures; focused tests show no r15 regression in the touched subsystems.

## Live validation pending

This development container has no system QEMU binaries. Therefore these are intentionally not yet promoted as live-proven:

- QEMU socket multicast traffic between two KLab guests,
- e1000/virtio-net-device/pcnet boot-time behavior across every target kernel,
- mixed-architecture guest-to-guest networking,
- MIPS guest networking.

The r15 report records enough stage and per-guest evidence to identify exactly which part fails on the first host run.
