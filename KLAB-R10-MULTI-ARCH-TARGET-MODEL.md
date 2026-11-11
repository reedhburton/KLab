# KLab r10 — multi-architecture target model checkpoint

Date: 2026-09-26
Base: r9 power-loss/resume checkpoint

## Purpose

Establish the architecture contract required for:

- kernel-module testing across architectures and kernel generations;
- cross-compiled user-space binary testing;
- native ARM workers and x86-to-ARM/MIPS cross compilation;
- later coordinated multi-process/multi-VM testing without architecture-specific scenario syntax.

## Implemented

- Added `lib/arch-model.sh` as the central architecture identity/planning layer.
- Separated `target_arch`, `build_arch`, `toolchain_exec_arch`,
  `toolchain_target_arch`, and `guest_arch`.
- Added `kernel-lab.sh arch-plan` with human and JSON output.
- Added profile metadata for family, width, endianness, ABI, package ecosystem
  names, status, and Linux version boundaries.
- Added Linux arm64 minimum version gating (`aarch64 >= 3.7`).
- Added experimental `mips`, `mipsel`, `mips64`, and `mips64el` profiles.
- Experimental architecture build/boot operations require
  `KLAB_ENABLE_EXPERIMENTAL_ARCHES=1`.
- Replaced the core's hard-coded distro x86_64 gate with provider-declared
  `arches=` plus independent `cross-arch=` policy.
- Provider semantics now permit, for example, native aarch64 staging on an
  aarch64 worker while rejecting x86_64-to-aarch64 staging when
  `cross-arch=no`.
- Central model is consumed by kernel-lab, `.klab` bundle, provider dispatcher,
  buildenv shell, and buildenv capture paths.
- New `.klab` manifests include `architecture_model` while retaining legacy
  `arch` for backward compatibility.
- New `.klabbuildenv` manifests include compatible architecture-role metadata;
  identity hashing remains backward-compatible because the new field is
  descriptive metadata rather than part of the v3 spec ID.
- Bundle verification checks that `architecture_model.target_arch` matches the
  legacy `arch` field when the new model is present.

## Example

```
./kernel-lab.sh arch-plan aarch64 --build x86_64 --kernel v6.6
```

reports a cross build with:

```
target_arch=aarch64
build_arch=x86_64
toolchain_exec_arch=x86_64
toolchain_target_arch=aarch64
guest_arch=aarch64
```

## Validation

PASS:

- `tests/architecture-model.sh`
- `tests/arch-plan-cli.sh`
- `tests/provider-arch-model.sh`
- `tests/provider-contract.sh`
- `tests/provider-compat-hardening.sh`
- `tests/atomic-target-import.sh`
- `tests/import-env-relocation.sh`
- `tests/buildenv-artifact.sh`
- `tests/buildenv-inventory.sh`
- `tests/thin-toolchain-compat.sh`
- all shell syntax checks completed before the long-suite timeout
- Python compilation for `lib/*.py`

The monolithic `tests/run-all.sh` was attempted but the execution environment
cut off during the longer buildenv fixtures. No failure was observed before the
cutoff; the architecture-sensitive and artifact-compatibility tests above were
then run individually.

## Deliberate limitations

This checkpoint models MIPS but does not claim MIPS end-to-end validation.
Current stable distro providers still advertise x86_64 only, so behavior is
unchanged until an individual provider is promoted to additional target arches.
Current distro buildenv capture still requires same-architecture staging.

## Next implementation

After the current overnight x86_64 regression is reviewed:

1. validate upstream aarch64 end-to-end (kernel + rootfs + cross binary + module + QEMU);
2. validate i386 similarly;
3. validate armv7;
4. define cross-buildenv vNext where compiler execution arch may differ from
   target arch;
5. promote Ubuntu/Debian aarch64 provider paths;
6. bring up mipsel first, then big-endian and 64-bit MIPS variants;
7. connect this target tuple to the coordinated test-runner/guest-agent layer.
