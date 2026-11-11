# Kernel Lab v15 — Buildroot Offline Cache

The Buildroot cache tool prepares all source archives required by selected Kernel Lab guest profiles without compiling the final root filesystems.

## Connected machine

```bash
./klab-buildroot-cache.sh create \
  --architectures x86_64,i386,aarch64,armv7 \
  --profiles minimal,network \
  -o klab-buildroot-sources-2025.02.18.tar.zst
```

The archive includes the pinned Buildroot source tarball, shared `dl/` source cache, generated configs, BusyBox fragment, manifest, and checksums.

## Closed machine

```bash
./klab-buildroot-cache.sh verify klab-buildroot-sources-2025.02.18.tar.zst
./klab-buildroot-cache.sh install klab-buildroot-sources-2025.02.18.tar.zst \
  --dest /srv/kernel-lab/buildroot

KLAB_HOME=/srv/kernel-lab ./kernel-lab.sh init --offline
KLAB_HOME=/srv/kernel-lab ./kernel-lab.sh buildroot-cache check --all
```

Offline builds use the local `BR2_DL_DIR`, a local `file://` primary site, and `BR2_PRIMARY_SITE_ONLY=y`. Missing sources therefore fail locally instead of falling back to the internet.

## Adding architecture profiles

v15 shares the architecture profile model with the main runner. If a new profile includes `BUILDROOT_DEFCONFIG`, it can be selected explicitly:

```bash
KLAB_ARCH_PROFILES_DIR=/srv/klab/architectures \
./klab-buildroot-cache.sh create \
  --architectures riscv64 \
  --profiles minimal \
  -o buildroot-riscv64-cache.tar.zst
```

The profile still needs to correspond to a real Buildroot defconfig and a validated Kernel Lab QEMU/kernel profile.

## Growing a cache

`install` merges source downloads into an existing cache. This makes it practical to begin with x86_64/aarch64 and later add i386, armv7, MIPS, PowerPC, RISC-V, or richer guest profiles without replacing the original cache.
