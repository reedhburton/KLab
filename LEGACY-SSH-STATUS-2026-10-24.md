# Historical SSH status — 2026-10-24

## Linux 2.2.26 i386: PASS

KLab now has a checksum-pinned historical SSH root using Debian BusyBox static 0.60.2, glibc 2.1.3, zlib 1.1.4, and Dropbear 0.44. Both BusyBox and Dropbear declare a GNU/Linux 2.0.30 ELF floor. The Linux 2.2 configuration enables a 32 MiB RAM disk plus built-in eepro100 and NE2000 PCI networking.

Live proof used QEMU `ne2k_pci`, an RSA user key, and a deliberately narrow SSH2 proposal compatible with Dropbear 0.44. The authenticated remote command returned:

```
2.2.26
uid=0(root) gid=0(root)
KLAB_LINUX22_HISTORICAL_SSH_OK
```

The isolated test image maps `/dev/random` to the nonblocking kernel RNG device because an entropy-starved deterministic VM otherwise blocks during key exchange. Host keys are generated during artifact construction. Modern clients must select `ssh-rsa`, `diffie-hellman-group1-sha1`, `aes128-cbc`, and `hmac-sha1` specifically for this isolated legacy guest.

## Linux 2.0.40 i386: PASS

KLab now boots Linux 2.0.40 from an ext2 IDE root, configures the built-in ISA NE2000 device, installs the connected and default routes, and starts the same checksum-pinned Dropbear 0.44 service with the Slink `/bin/sash` login shell. The image builder supplies `/dev/console` as the Linux 2.0-compatible `c 4:0` device and repairs the ext2 image after deterministic `debugfs` edits.

The Linux 2.0 modern-host patch also fixes GCC 3.3.6 compatibility in the old constant segment-copy helpers. Copies larger than 16 bytes now fall back to the generic implementation; this is required for 32-byte `ifreq`, routes, and socket traffic. The complete patch dry-runs cleanly against the cached pristine Linux 2.0.40 tarball.

Live proof used QEMU `ne2k_isa` at I/O `0x300`, IRQ 9, an RSA user key, and the same narrow SSH2 proposal. The authenticated remote command returned:

```
KLAB_LINUX20_HISTORICAL_SSH_OK
```

The sealed historical userspace SHA-256 is `a4f0777a30ef3c85d3cce7571138a0dd4bdaa67becedca25a81dd8b2109bf14c`.
