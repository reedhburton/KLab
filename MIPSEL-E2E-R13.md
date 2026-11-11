# KLab r13 — Experimental mipsel / Malta E2E backend

## Goal

Bring the first MIPS architecture through the same KLab execution contract as
x86/i386/ARM: upstream kernel build, Buildroot userspace+SDK, user binary,
external kernel module, QEMU boot, guest execution, module load/unload, and
structured report.

## Chosen first target

- KLab architecture: `mipsel`
- ISA/ABI: 32-bit MIPS32 Release 2, O32, little-endian
- Linux `ARCH`: `mips`
- Linux config: `malta_defconfig`
- Kernel image: `vmlinux`
- QEMU: `qemu-system-mipsel`
- QEMU machine: `malta`
- CPU: `24Kf`
- Bring-up memory: 256 MiB
- Bring-up vCPUs: 1
- Console: `ttyS0`
- KLab control: second serial channel, `/dev/ttyS1`
- Buildroot profile: `qemu_mips32r2el_malta_defconfig`
- Kernel.org compiler archive target: `mips-linux`
- Guest expected `uname -m`: `mips`

## Explicit safety gate

The architecture and E2E implementation both remain experimental. A real test
requires:

```bash
KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 \
KLAB_ENABLE_EXPERIMENTAL_E2E=1 \
./kernel-lab.sh arch-smoke upstream:v6.6 --arch mipsel
```

This prevents `mipsel` from being silently promoted merely because model and
static tests pass.

## First-live matrix

```bash
./klab-mipsel-overnight-r13.sh
```

Defaults:

- v4.14
- v5.4
- v5.15
- v6.1
- v6.6
- v6.12
- v7.0

The same resume format used by the r12 multi-arch runner is retained. The
focused wrapper uses the common results tree, so a powered-off run can be
continued by reusing the same run ID through the underlying r13 runner.

## Why `mips-linux` for a little-endian target

Kernel.org's portable GCC archive family is published as `mips-linux`, not a
separate `mipsel-linux` archive. KLab therefore distinguishes the target
architecture (`mipsel`) from the compiler archive target (`mips-linux`). Linux
Kbuild uses the little-endian Malta configuration to select the required MIPS
endianness flags. Userspace compilation uses the independently generated
Buildroot mipsel SDK.

## Validation status

Static/model validation completed in r13:

- mipsel architecture remains experimental: PASS
- mipsel E2E remains experimental: PASS
- Buildroot profile name: PASS
- kernel.org compiler-target mapping: PASS
- QEMU Malta/24Kf/256M/1-vCPU architecture plan: PASS
- experimental opt-in enforcement: PASS
- little-endian 32-bit MIPS ELF accepted: PASS
- big-endian MIPS rejected: PASS
- MIPS64 rejected: PASS
- r13 overnight wiring: PASS

No live MIPS QEMU boot was possible in the assistant development environment,
which lacks `qemu-system-mipsel`. A host run is therefore still required before
promotion from experimental.
