# KLab 1.0 test architecture

KLab tests are described by versioned manifests and executed through one lifecycle: `suite create`, `suite show`, and `suite run`. Suites live under `KLAB_ROOT/suites`; portable targets live in `KLAB_REPO`.

The test layers are:

1. Artifact integrity: provenance, checksums, safe import, and offline repack.
2. Build: userspace binaries, libraries, and kernel modules using the bound toolchain.
3. Boot: machine-specific QEMU boot and deterministic readiness.
4. Guest behavior: userspace, module lifecycle, signals, and process coordination.
5. Network: TCP/UDP, IPv4/IPv6, routing, concurrency, delay, and link faults.
6. Multi-guest: dependencies, gates, crashes, and topology-level results.
7. Legacy: graded source/build/boot/userspace/module/network levels for period-appropriate targets.

Every suite declares canonical architecture IDs and the capabilities it proves. Results retain the suite schema, target identity, architecture, toolchain identity, commands, exit/signal expectations, logs, and highest completed gate. A capability that cannot apply to an historical target is recorded explicitly rather than silently skipped.
