# KLab r16 architecture x kernel-version matrix checkpoint

## Added
The stable routed architecture matrix now has a representative kernel-version axis.

Four stable architecture topologies each receive three kernel cohorts:
- old
- middle
- modern

This produces 12 routed architecture/kernel scenarios.

Selected versions come only from each architecture's existing `E2E_DEFAULT_VERSIONS`:
- x86_64: v4.4 / v5.4 / v7.0
- i386: v4.4 / v5.4 / v7.0
- aarch64: v4.14 / v5.4 / v7.0
- armv7: v4.14 / v5.4 / v7.0

The cohort is applied independently per guest architecture, so an `old` mixed scenario can legitimately use x86 v4.4 and ARM v4.14.

## Overnight behavior
`KLAB_R16_KERNEL_MATRIX=1` is the default.
Set `KLAB_R16_KERNEL_MATRIX=0` to omit these cases; they are recorded as `SKIP_DISABLED`.
Normal `qemu_ready` checks still produce `SKIP_QEMU` when an emulator is unavailable.
Resume behavior remains case-based, so completed kernel/topology combinations are not rerun.

## Validation
PASS: 12 generated scenario structures.
PASS: every selected kernel appears in that architecture's E2E default list.
PASS: scenario target strings match kernel-version metadata.
PASS: shell syntax for the overnight runner and new regression test.

The full repeated planner regression is not claimed in this sandbox because Python startup/warmup overhead caused the aggregate test to exceed the execution window. Individual planner validation remains a host-side gate together with live QEMU.

## Next expansion
The next useful layer is test-payload variation: run both userspace cross-compiled binaries and kernel-module load/execute/unload probes across this architecture x kernel matrix, while preserving multi-process coordination and unified reports.

## Long-range legacy goal

The project roadmap now includes x86_64 testing back to Linux 2.6.0 and i386 testing through the 2.4, 2.2, and 2.0 stable series. These targets use graded success levels because early kernels may build or boot without supporting the modern KLab agent, Buildroot userspace, module API, or virtio transport. See `KLAB-ROADMAP.md`.
