# KLab r14 checkpoint — big-endian MIPS + coordinated guest agent

Date: 2026-09-26
Base: r13 experimental mipsel E2E

## Big-endian MIPS

r14 adds an explicitly gated 32-bit big-endian O32 MIPS execution profile:

- Linux `ARCH=mips`;
- Malta machine / 24Kf CPU;
- `qemu-system-mips`;
- 256 MiB, one vCPU;
- Buildroot `qemu_mips32r2_malta_defconfig`;
- kernel.org `mips-linux` cross-toolchain family;
- explicit `CPU_BIG_ENDIAN=y` and `CPU_LITTLE_ENDIAN=n` after Malta defconfig;
- strict `ELF 32-bit MSB ... MIPS` artifact identity checking.

`mipsel` remains the little-endian sibling with the inverse config settings and
strict LSB checking.  Both remain experimental until live host E2E runs pass.

Focused matrix:

```bash
./klab-mips-overnight-r14.sh
```

The general matrix can include both endian lanes with:

```bash
KLAB_MULTIARCH_ENABLE_MIPS=1 ./klab-multiarch-overnight-r14.sh
```

## Coordinated scenario framework

New components:

- `guest-agent/klab-agent.c`
- `lib/scenario_plan.py`
- `lib/test-scenario.sh`
- `kernel-lab.sh scenario-run`
- `examples/scenarios/multiprocess-basic.json`
- `examples/scenario-worker.c`
- `klab-scenario-overnight-r14.sh`
- `klab-feature-overnight-r14.sh`

The guest-agent native regression proves concurrent spawn, process groups,
named barriers, independent waits, stdout/stderr, signals and timestamped
events.  Scenario dry-runs validate x86_64/aarch64 and experimental MIPS plans.
A real QEMU scenario run remains the next-host validation gate.

## Next major overnight

`klab-feature-overnight-r14.sh` is the next-cycle umbrella runner. It executes:

1. the r14 multi-architecture E2E matrix with both MIPS endian lanes enabled;
2. the coordinated scenario matrix, also including the MIPS lanes.

Do not run it concurrently against the same `KLAB_ROOT` as an older active
KLab overnight process.  It is intended for the next cycle after the current
run is reviewed.

## Remaining framework work

The largest next step is multi-guest/network coordination: one host scenario
controller driving two or more guest-agent instances with cross-guest barriers,
network topology, and a single merged event timeline.  Distro-rootfs scenarios
can follow once cross-architecture distro userspace/buildenv support is mature.
