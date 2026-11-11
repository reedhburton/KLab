# KLab r12 — generalized multi-architecture E2E harness

## Goal

Turn the r11 aarch64-only validation lane into one shared end-to-end harness for the four stable execution architectures:

- x86_64
- i386
- aarch64
- armv7

The same `arch-smoke` command now validates kernel preparation, Buildroot userspace/SDK, user-space cross compilation, external kernel-module compilation, QEMU boot, guest ISA/pointer width, module load, and module unload.

## Architecture roles

The r10 architecture contract remains authoritative:

- `target_arch`: kernel/program ISA being tested
- `build_arch`: worker architecture running the build
- `toolchain_exec_arch`: ISA of the compiler executable
- `toolchain_target_arch`: compiler output ISA
- `guest_arch`: ISA QEMU executes

`arch-smoke` additionally requires `E2E_STATUS=stable` (or explicit experimental-E2E opt-in). This prevents model-only MIPS profiles from being mistaken for validated execution backends.

## Guest control transport

x86_64/i386 continue to use the second 16550 serial port (`/dev/ttyS1`).

aarch64/armv7 now use a virtio serial port (`/dev/vport0p1`) instead of depending on a second PL011 UART. Their kernel profiles enable `CONFIG_VIRTIO_CONSOLE` and the existing virtio transports.

This makes the control plane independent of the relatively recent second-nonsecure-UART addition to QEMU's ARM `virt` board.

The architecture plan records:

- `execution.control_mode`
- `execution.control_device`
- `execution.e2e_status`

## ELF identity hardening

The E2E harness now validates both the cross-compiled user binary and `.ko` architecture from `file(1)` output.

Negative filters prevent common false matches:

- armv7 rejects AArch64 ELF objects
- i386 rejects x86-64 ELF objects

## Overnight matrix

`klab-multiarch-overnight-r12.sh` is the next-cycle feature matrix.

Defaults:

- x86_64: v6.6 control lane
- i386: v4.4, v5.4, v6.1, v6.6, v7.0
- aarch64: v4.14, v5.4, v5.15, v6.1, v6.6, v6.12, v7.0
- armv7: v4.14, v5.4, v5.15, v6.1, v6.6, v6.12, v7.0

Each architecture gets one QEMU/model preflight. If an emulator is missing, the architecture is recorded once as `QEMU_MISSING` and its expensive cases are skipped.

The runner is resumable:

```bash
KLAB_MULTIARCH_RESUME_RUN_ID=latest ./klab-multiarch-overnight-r12.sh
```

Completed architecture/target rows are not repeated.

Version lists are independently overrideable:

```bash
KLAB_I386_E2E_VERSIONS='v5.4 v6.6 v7.0' \
KLAB_AARCH64_E2E_VERSIONS='v5.15 v6.6 v7.0' \
KLAB_ARMV7_E2E_VERSIONS='v5.15 v6.6 v7.0' \
./klab-multiarch-overnight-r12.sh
```

## Still pending live validation

The assistant development environment does not have QEMU system emulators installed, so actual i386/aarch64/armv7 boots remain host-validation work. The new reporting contract is designed to identify the exact first failing stage on that run.

MIPS/MIPSel/MIPS64/MIPS64el remain model-only/experimental E2E targets and are deliberately not included in the r12 execution matrix.
