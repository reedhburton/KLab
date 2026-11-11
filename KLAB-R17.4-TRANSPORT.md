# KLab 0.0.0b r17.4 checkpoint

This release fixes Buildroot SDK consumption and validates the first complete AArch64 v6.6 architecture smoke run.

- Extracts single-root Buildroot SDK archives into the expected SDK root.
- Keeps SDK relocation diagnostics off command-substitution stdout.
- Adds a bounded virtio-serial READY handshake before the first RPC.
- Reopens the guest control port after host disconnects so independent RPCs and uploads remain usable.
- Removes minimal guest dependencies on `dirname` and `tail`.
- Adds transport and minimal-guest regression assertions.
- Validates AArch64 v6.6 boot, cross-compiled userspace execution, file transfer, module load, and module unload.
- Disables ARMv7 GCC plugins that require host development headers when using portable kernel.org cross compilers.
- Validates ARMv7 v6.6 boot, 32-bit EABI userspace execution, file transfer, module load, and module unload.
- All 102 network-free regression tests and static syntax checks pass.

Live validation artifacts are in `/home/reed/klab-data/results/manual-r17.4-aarch64-v6.6-attempt7` and `/home/reed/klab-data/results/manual-r17.4-armv7-v6.6-attempt2`.
