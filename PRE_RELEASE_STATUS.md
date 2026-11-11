# Pre-v1 release-candidate status

This repository snapshot is **1.0.0-rc14**, not the final v1 release.

Completed gates:

- Complete network-free regression and syntax suite passes.
- 55/55 imported targets pass the full validation level; full subsumes standard.
- The matrix covers 52 Linux and 3 FreeBSD targets across x86_64 and aarch64.
- Ubuntu 20.04, 22.04, and 24.04 aarch64 native userspaces pass compilation, conformance, and SSH after correcting rootless foreign package capture.

Remaining release gate:

- Install into a fresh KLab root and offline repository on the new external storage, disconnect network access, import the retained artifacts, and run the final offline smoke/full subset.

Do not tag or publish `1.0.0` until that fresh-drive offline gate passes.

## Complex suite queue (2026-10-21)

The staged candidate now includes `klab-suite-v2`: resumable multi-target queues, per-target module and userspace builds, unchanged precompiled file deployment, ordered cross-process milestones, manual in-workflow module loading, and final `exec` replacement that preserves the sequence PID. Targeted regressions and the complete network-free suite pass. Live/offline target-matrix validation remains part of the planned fresh-drive release gate.

The complex-suite examples now include strict intentional kernel-panic console validation and a persistent Bash/file-producer coordination workload. Both targeted checks and the complete network-free suite pass. The intentional panic has not been executed in a live guest during this staging pass; that destructive target sweep belongs to the fresh-drive offline gate.

Suite creation now uses only the unified queue-capable schema. `klab suite run` is a single-target queue wrapper, and `klab suite migrate NAME` converts local pre-release v1 suites while retaining `suite.v1.json`. Simultaneous-user execution is validated with isolated per-user KLab roots and collision-resistant run IDs; users may share a read-only offline repository.
