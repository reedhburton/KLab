# KLab r12 multi-architecture E2E checkpoint

Date: 2026-09-26
Base: r11 aarch64 E2E checkpoint

## Implemented

- Generalized `arch-smoke` from aarch64 bring-up into one stable E2E contract for x86_64, i386, aarch64 and armv7.
- Added `E2E_STATUS` and default E2E kernel-version sets to architecture profiles.
- MIPS profiles remain `E2E_STATUS=experimental` and fail closed unless a future explicit experimental-E2E path is enabled.
- Added `execution.e2e_status`, `execution.control_mode`, and `execution.control_device` to architecture-plan JSON.
- Added architecture-aware ELF validation for both the user-space probe and the kernel module.
- Added explicit armv7-vs-aarch64 and i386-vs-x86_64 rejection filters.
- Replaced ARM/aarch64 second-UART session control with virtio serial (`/dev/vport0p1`).
- Kept x86_64/i386 session control on `/dev/ttyS1`.
- Added `CONFIG_VIRTIO_CONSOLE` to ARM E2E kernel profiles.
- Added E2E column to `kernel-lab.sh architectures` and guest-control details to `arch-plan` human output.
- Added resumable `klab-multiarch-overnight-r12.sh` with per-architecture QEMU preflight and compact review tar.

## Validation

PASS individually:

- `tests/architecture-model.sh`
- `tests/arch-plan-cli.sh`
- `tests/provider-arch-model.sh`
- `tests/provider-contract.sh`
- `tests/provider-compat-hardening.sh`
- `tests/arch-e2e-dryrun.sh`
- `tests/arch-e2e-file-match.sh`
- `tests/qemu-control-model.sh`
- `tests/multiarch-overnight-r12-wiring.sh`
- `tests/multiarch-overnight-resume.sh`
- `tests/buildenv-artifact.sh`
- `tests/buildenv-capture-pair.sh`
- `tests/buildenv-distro-native-binding.sh`
- `tests/toolchain-boundary.sh`
- `tests/toolchain-boundary-patcher.sh`
- `tests/root-layout.sh`
- `tests/wide-sweep-regressions.sh`
- all shell syntax
- Python bytecode compilation

The combined long batch hit the execution environment timeout during long buildenv fixtures; no test failure was observed before the timeout, and the remaining focused tests were rerun individually.

## Live-test limitation

This development container has no `qemu-system-*` binaries, so the real i386/aarch64/armv7 boot path has not been claimed as validated. That is the purpose of the next major overnight feature run on the user's KLab host.

## Next likely feature work

After live multi-arch results:

1. fix architecture-specific QEMU/kernel/toolchain issues exposed by r12;
2. promote the first MIPS execution profile, likely `mipsel`/Malta;
3. introduce the generic guest-agent/test-scenario protocol for coordinated multi-process testing;
4. add distro ARM64 provider lanes once upstream aarch64 execution is stable.
