# KLab r13 implementation checkpoint

r13 adds the first experimental MIPS execution backend without changing the
stable architecture set. The implementation reuses the r12 `arch-smoke`
contract instead of creating a MIPS-only test system.

Key implementation decisions:

1. `mipsel` stays `ARCH_STATUS=experimental` and `E2E_STATUS=experimental`.
2. A live E2E run requires both `KLAB_ENABLE_EXPERIMENTAL_ARCHES=1` and
   `KLAB_ENABLE_EXPERIMENTAL_E2E=1`.
3. Current Buildroot uses `qemu_mips32r2el_malta_defconfig`; the earlier model
   name was obsolete.
4. Kernel.org crosstool publishes `mips-linux`; KLab keeps compiler archive
   identity separate from the target architecture/endian identity.
5. Malta bring-up uses 256 MiB/1 vCPU rather than KLab's global 1 GiB/default
   SMP settings. Per-architecture QEMU memory/vCPU settings are now part of the
   architecture plan.
6. The standard session protocol remains on serial: console ttyS0, KLab control
   ttyS1.
7. `file(1)` validation now requires a 32-bit LSB MIPS object and rejects MSB
   and MIPS64 objects.
8. `klab-multiarch-overnight-r13.sh` adds mipsel only when
   `KLAB_MULTIARCH_ENABLE_MIPS=1`; `klab-mipsel-overnight-r13.sh` is the focused
   first-live runner.

The next decision depends on live evidence. If boot/user/module lifecycle is
clean, promote mipsel E2E to stable and start big-endian `mips`. If it fails,
the existing E2E stage report will identify whether the issue is kernel/toolchain,
Buildroot SDK, QEMU boot, serial control, user ELF, or module lifecycle.
