# KLab 1.0.0-rc2 validation

Date: 2026-10-08

## Regression suite

- 119 network-free shell checks: PASS
- Final marker: `ALL M2 NETWORK-FREE TESTS: PASS`
- Shell and Python syntax gate: PASS

## Modern Linux contract

Live package/verify, cross-userspace execution, module build/load/unload, and boot passed on x86_64, i386, AArch64, ARMv7, MIPSel, and big-endian MIPS. The coordinated multi-process matrix passed 6/6 lanes. Three routed client/router/server topologies passed and collectively covered all six architectures.

Fresh-root offline setup, import, repack, and verification passed 6/6 lanes with separate `KLAB_ROOT` and `KLAB_REPO` directories. Persistent development evidence is indexed by `library/v1-modern-multiarch-2026-10-08/V1-MODERN-GATE.tsv` in the project workspace.

## Legacy and BSD gates

Every required Linux 2.x target meets or exceeds its declared level in `legacy/targets-v1.json`, including Linux 2.0.40/i386 boot, representative 2.2/2.4 userspace and module gates, and Linux 2.6.32 networking on i386 and x86_64.

The BSD V1 matrix passes 12/12 rows across current and previous FreeBSD, NetBSD, OpenBSD, and DragonFly BSD releases and the tested x86_64, i386, AArch64, and RISC-V architectures.

## Remaining blocker for final 1.0

F16 remains open: distribution build roots seal their realized installed-package inventory and immutable provider-image identity, but KLab does not yet retain immutable package archives plus repository snapshot provenance for every dependency inherited or installed while constructing every build environment. RC2 does not claim full from-archive reconstruction provenance for those distribution roots.
