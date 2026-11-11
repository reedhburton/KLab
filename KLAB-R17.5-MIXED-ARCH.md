# KLab 0.0.0b r17.5 mixed-architecture checkpoint

This release closes the four failures exposed by the seven-case routed multi-guest matrix.

## Fixes

- Select serial upload flow from the session control mode.
- Keep the Linux virtio/serial host relay alive across independent CLI invocations and reconnect it after QEMU chardev EOF.
- Preserve empty fields in multi-guest planner records.
- Resolve guest interfaces by configured MAC address instead of kernel enumeration order.
- Derive host RPC wait timeouts from guest process timeouts.
- Record exact shell error context for failed multi-guest phases.
- Ignore guest-agent `SIGPIPE`, reduce portable request/reply memory, and wait for a complete PING handshake at startup.
- Send each guest-agent request and terminating newline in one write. This removes an `EPIPE` race visible under slow MIPS emulation.
- Flatten single-root Buildroot SDK archives during import, rewrite imported source provenance to canonical paths, and make atomic cleanup handle read-only immutable sources.
- Let offline smoke and repack wrappers select non-x86 architectures; repack now preserves the imported Buildroot SDK and bound toolchain.

## Live validation

All seven routed cases are now known passing across x86_64, i386, AArch64, ARMv7, MIPSel, and big-endian MIPS. The repaired cases are retained at:

- `/home/reed/klab-data/results/live-mixed-relay-fix-r19/attempt2-stable-arm64-x86-armv7`
- `/home/reed/klab-data/results/live-mixed-relay-fix-r19/attempt7-experimental-x86-arm64-mipsel`
- `/home/reed/klab-data/results/live-mixed-relay-fix-r19/attempt8-experimental-mipsel-x86-armv7`
- `/home/reed/klab-data/results/live-mixed-relay-fix-r19/attempt9-experimental-mips-arm64-x86`

Every repaired case reached `LAST_STAGE=complete`, exchanged the expected routed payload, and recorded exit 0 for both endpoint processes.

## Regression validation

All 103 network-free shell tests and static syntax checks pass. The packaged-source seven-case rerun and fresh-root offline MIPSel validation are recorded separately in `R17.5-PACKAGE-VALIDATION.txt`.
