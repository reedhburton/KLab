# KLab r11 — aarch64 end-to-end execution path

This checkpoint turns the r10 architecture model into an executable validation path.

## `arch-smoke`

`kernel-lab.sh arch-smoke upstream:v6.6 --arch aarch64`

The command validates one complete target/build/execution chain:

1. Resolve the architecture plan and reject impossible kernel/ISA combinations.
2. Require the architecture-specific QEMU binary before doing expensive work.
3. Cross-build the upstream kernel with the target architecture and bind a portable toolchain.
4. Build/package the matching Buildroot rootfs plus relocatable SDK into a fresh `.klab` and verify it.
5. Cross-compile the built-in user-space probe with the target SDK.
6. Cross-build the built-in hello kernel module against the target kernel.
7. Boot a persistent QEMU guest using the data-driven machine/CPU/console profile.
8. Push and execute the user probe; validate guest `uname -m` and pointer width.
9. Load the module; verify the load marker in dmesg.
10. Unload the module; verify the unload marker.
11. Emit a durable `klab-arch-e2e-v1` JSON report with architecture plan, stage timeline, hashes and guest output.

The implementation is architecture-generic, but aarch64 is the first intended live validation target. It requires a Buildroot userspace because the same profile supplies the cross SDK used for user-space probes.

## Report layout

By default:

`$KLAB_ROOT/results/arch-e2e/<run-id>/`

contains `report.json`, `summary.txt`, `stages.tsv`, QEMU version, uname output, user program output, module dmesg snapshots, the generated `.klab`, user binary and module.

`--artifact-dir DIR` makes `DIR` the report/output directory, which is useful for matrix runners.

## Failure behavior

Reports are written even when a stage fails. `last_stage` identifies the failing layer (preflight, prepare, user-build, module-build, boot, user-run, module-load or module-unload). A failed QEMU preflight happens before network/kernel build work.

## Next-overnight matrix

`klab-multiarch-overnight-r11.sh` runs the full E2E chain across a configurable aarch64 upstream set. Default targets are v4.14, v5.4, v5.15, v6.1, v6.6, v6.12 and v7.0, plus an expected pre-3.7 rejection check.

Override with:

`KLAB_AARCH64_VERSIONS='v5.15 v6.6 v7.0' ./klab-multiarch-overnight-r11.sh`

The matrix is deliberately separate from the currently-running r9 overnight sweep.
