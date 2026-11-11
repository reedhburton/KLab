# KLab r11 — aarch64 E2E checkpoint

Date: 2026-09-26
Base: KLab r10 multi-architecture target model

## Goal

Turn the r10 architecture-role model into a complete executable validation path before expanding distro ARM or MIPS support.

## New command

```bash
./kernel-lab.sh arch-smoke upstream:v6.6 --arch aarch64
```

The command uses `buildroot:minimal` by default and performs:

1. architecture/version planning and capability gating;
2. QEMU binary preflight before expensive work;
3. cross-built upstream kernel prepare;
4. Buildroot rootfs + relocatable SDK creation;
5. `.klab` package creation and verification;
6. static user-space probe compilation with the target SDK;
7. external kernel-module cross build;
8. persistent QEMU guest boot;
9. target user binary upload/execution;
10. guest ISA and pointer-width assertions;
11. module load and dmesg assertion;
12. module unload and dmesg assertion;
13. durable structured result generation.

## Report schema

Each run emits a `klab-arch-e2e-v1` report with:

- target/build/toolchain/guest architecture plan;
- stage-by-stage timestamps/status;
- QEMU version;
- `uname -a` and `uname -m`;
- cross-compiled user-program output;
- module load/unload dmesg excerpts;
- SHA-256 identities for bundle, user binary and module;
- final PASS/FAIL and last completed/current stage.

Reports are written even for failures, allowing the next overnight run to distinguish cross-toolchain, rootfs, packaging, boot, control-channel, user-space and module failures.

## Next overnight feature matrix

`klab-multiarch-overnight-r11.sh` defaults to:

- expected rejection: aarch64 Linux v3.6;
- full E2E: v4.14, v5.4, v5.15, v6.1, v6.6, v6.12, v7.0.

The version set is configurable with `KLAB_AARCH64_VERSIONS`.

## Validation completed here

PASS:

- `tests/architecture-model.sh`
- `tests/arch-plan-cli.sh`
- `tests/provider-arch-model.sh`
- `tests/arch-e2e-dryrun.sh`
- `tests/buildenv-artifact.sh`
- `tests/buildenv-negative.sh`
- `tests/toolchain-boundary.sh`
- `tests/toolchain-boundary-patcher.sh`
- `tests/root-layout.sh`
- `tests/buildenv-inventory.sh`
- `tests/combined-chain-audit.sh`
- all shell syntax checks
- Python bytecode compilation

The broad combined validation command hit the execution environment time cap after several passing buildenv tests; the remaining relevant checks were run individually.

## Live-validation limitation

This assistant environment does not have `qemu-system-aarch64`, so a real aarch64 boot was not claimed. The next host execution is the first live proof of the complete E2E path.
