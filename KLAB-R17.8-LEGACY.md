# KLab r17.8 legacy Linux checkpoint

R17.8 completes the version-1 Linux 2.0 and 2.2 legacy gates on i386. Linux 2.0.40 builds with the sealed Debian GCC 3.3.6 toolchain after modern-host fixes for raw multiline assembly, fixed-register constraints, ELF boot-image packing, and 64-bit host disk-field widths. Its GRUB linux16 ISO uses a 512 KiB uncompressed revision-0 ext2 root and a no-libc syscall init. Linux 2.2.26 was rebuilt through the same shared ISO path with its compressed ext2 root.

Both bundles passed import into independent fresh offline roots, booted under QEMU TCG, emitted USERSPACE_PASS, and returned their exact releases through persistent serial RPC:

- Linux 2.0.40 i386: `38a486c980dbfcd378eb8210e4dabaf608fa6f692967ef705933f1481a496a11`
- Linux 2.2.26 i386: `85c0d99adcb28f2e2dde7a453fc10684ef89e80e748c80f1d79baa43ea40834a`

The Linux 2.0.40 target exceeds its required BOOT_PASS gate with USERSPACE_PASS. Linux 2.2.26 retains USERSPACE_PASS. All 106 network-free regression checks pass after both live validations.

Packaged live regression also passed Linux 2.4.37.11 i386, Linux 2.6.0 x86_64, and Linux 6.6 aarch64 from a new offline root using the packaged R17.8 CLI.
