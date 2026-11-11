# Kernel Lab v16 — Stable Workflow

Kernel Lab v16 keeps the stable test workflow, but shared dependencies are now typed, content-addressed artifacts so a series of kernel targets does not duplicate toolchains, guest root filesystems, or SDKs.

```text
staging:  init -> prepare -> transfer thin .klab + shared typed artifacts
offline:  init -> import <directory> -> targets -> smoke/test
```

## Shared artifacts and thin `.klab` targets

By default, `prepare` now emits a **thin target bundle** plus reusable dependency files in the same directory:

```text
linux-6.6.52-aarch64.klab
kernelorg-gcc-12.5-aarch64--<hash>.klabtoolchain
buildroot-minimal-aarch64-2025.02.18--<hash>.klabrootfs
buildroot-minimal-aarch64-2025.02.18--<hash>.klabsdk   # only with --with-sdk
```

The typed extensions are intentionally descriptive:

- `.klabtoolchain` — compiler/binutils toolchain
- `.klabrootfs` — guest userspace/root filesystem
- `.klabsdk` — userspace cross-development SDK/sysroot
- `.klabfirmware` — reusable firmware blobs
- `.klabsource` — reusable source/cache content
- `.klab` — one exact kernel/test target

Each shared artifact is identified by the SHA-256 of its canonical payload. If twenty kernel versions use the same toolchain, `prepare` reuses the same typed artifact filename and the offline warehouse stores only one object.

For a single all-in-one transfer, retain the old behavior explicitly:

```bash
./kernel-lab.sh prepare upstream:v6.6 --arch aarch64 --standalone -o linux-6.6-full.klab
```

A thin target refuses to import if one of its referenced shared artifacts is absent. The easiest air-gap workflow is therefore to copy the entire transfer directory and import it once:

```bash
./kernel-lab.sh import /media/transfer/kernel-set/
```

Kernel Lab imports `.klabtoolchain`, `.klabrootfs`, `.klabsdk`, `.klabfirmware`, and `.klabsource` files before importing the `.klab` targets.

Inspect installed shared objects with:

```bash
./kernel-lab.sh artifacts
```


## 1. Staging machine

```bash
./kernel-lab.sh init --staging
./kernel-lab.sh prepare upstream:v6.6 --arch x86_64 -o linux-6.6-x86_64.klab
./kernel-lab.sh prepare upstream:v6.6 --arch aarch64 --userspace buildroot:minimal --with-sdk -o linux-6.6-aarch64.klab
```

Distribution/provider targets use the same `prepare` interface.

## 2. Offline test machine

```bash
./kernel-lab.sh init --offline
./kernel-lab.sh import /media/transfer/kernel-set/
./kernel-lab.sh targets
./kernel-lab.sh smoke upstream:v6.6 --arch x86_64
./kernel-lab.sh test upstream:v6.6 --arch x86_64 --module ./driver --script ./tests/smoke.sh
```

`test` never fetches a missing target. In offline mode network-facing provider commands fail closed.

## 3. Parallel testing

`test-set` now has a bounded worker pool:

```bash
./kernel-lab.sh test-set \
  --workers 4 \
  --jobs-per-worker 8 \
  --arch x86_64 \
  --module ./driver \
  --script ./tests/smoke.sh \
  upstream:v5.15 upstream:v6.1 upstream:v6.6 upstream:v6.12
```

Each worker is a separate Kernel Lab process with its own module job directory and log. Results are summarized at the end and logs are kept under `kernel-lab/logs/test-set-*`.

If `--jobs-per-worker` is omitted, Kernel Lab divides `KLAB_JOBS` by the worker count and never assigns fewer than one compiler job per worker.

## 4. Arbitrary/custom Linux kernels

A vendor/private kernel no longer needs a provider implementation if you already have its kernel image and prepared module-build tree:

```bash
./kernel-lab.sh register-linux acme \
  --release 6.6.42-acme1 \
  --arch aarch64 \
  --kernel /srv/acme/Image \
  --build-dir /srv/acme/kernel-build \
  --source-dir /srv/acme/linux-source
```

This creates the target:

```text
custom:acme:6.6.42-acme1
```

Test it locally just like any other target:

```bash
./kernel-lab.sh test custom:acme:6.6.42-acme1 --arch aarch64 --module ./driver --script ./tests/smoke.sh
```

The default registration mode copies the artifacts into the Kernel Lab warehouse so the target can be exported:

```bash
./kernel-lab.sh prepare custom:acme:6.6.42-acme1 --arch aarch64 -o acme-aarch64.klab
```

`--reference` avoids copying large trees but is deliberately local-only and cannot be exported as a portable bundle.

## 5. Architecture profiles

Architecture-specific kernel/QEMU/toolchain details now live in:

```text
architectures/*.conf
```

The shipped profiles are `x86_64`, `i386`, `aarch64`, and `armv7`.

```bash
./kernel-lab.sh architectures
```

A profile defines items such as:

```text
ARCH_ID
ARCH_ALIASES
KERNEL_ARCH
KERNEL_DEFCONFIG
KERNEL_IMAGE
KERNEL_CONFIG_ENABLE
QEMU_BINARY
QEMU_MACHINE
QEMU_TCG_CPU
LINUX_CONSOLE
LINUX_CONTROL_TTY
TOOLCHAIN_TARGET
BUILDROOT_DEFCONFIG
```

To prototype another architecture such as MIPS, PowerPC, or RISC-V, copy an existing profile into another directory and set:

```bash
export KLAB_ARCH_PROFILES_DIR=/path/to/my-architectures
```

The core runner and bundle/cache tools all use the same profile directory. The architecture is not considered production-ready until its QEMU machine, console/control transport, kernel config, toolchain, and guest userspace have been validated.

## 6. General cross-compilation

The Buildroot SDK cache is now exposed independently of any kernel target.

Print an environment suitable for an ARM64 cross build:

```bash
./kernel-lab.sh cross env --arch aarch64 --profile minimal
```

Run an arbitrary build command with the SDK environment:

```bash
./kernel-lab.sh cross exec --arch aarch64 --profile minimal -- make -C ./userspace
```

Compile one or more C files directly:

```bash
./kernel-lab.sh cross cc --arch aarch64 --profile minimal \
  --source client.c --source protocol.c -o ./out/client -- -O2 -Wall
```

This makes Kernel Lab useful as a general offline cross-build warehouse in addition to kernel-module testing. The `network` SDK profile can be selected when the program needs the richer Buildroot sysroot.

## 7. Buildroot source cache

On the connected machine:

```bash
./klab-buildroot-cache.sh create \
  --architectures x86_64,i386,aarch64,armv7 \
  --profiles minimal,network \
  -o buildroot-cache.tar.zst
```

On the isolated build/test host:

```bash
./klab-buildroot-cache.sh verify buildroot-cache.tar.zst
./klab-buildroot-cache.sh install buildroot-cache.tar.zst --dest /srv/kernel-lab/buildroot
KLAB_HOME=/srv/kernel-lab ./kernel-lab.sh buildroot-cache check --all
```

Offline Buildroot operation uses `BR2_PRIMARY_SITE_ONLY=y` and a local primary site, so a missing source is a hard error rather than an internet fallback.

## 8. Persistent guests

```bash
./kernel-lab.sh boot upstream:v6.6 --name k66
./kernel-lab.sh push k66 ./fixture.bin /tmp/fixture.bin
./kernel-lab.sh load-module k66 ./out/mydriver.ko debug=1
./kernel-lab.sh exec k66 'dmesg | tail -100'
./kernel-lab.sh unload-module k66 mydriver
./kernel-lab.sh stop k66
```

Linux uses `insmod/rmmod/lsmod`; FreeBSD maps the same neutral commands to `kldload/kldunload/kldstat`.

## 9. Crash capture

Serial panic/oops output is always retained. Optional full guest-memory capture:

```bash
./kernel-lab.sh test upstream:v6.6 --module ./driver --script ./tests/stress.sh --crashdump
```

Strict warning handling:

```bash
... --crashdump --panic-on-warn
```

Use `crashes` and `crash-info` to inspect archived failures.

## 10. Operational commands

```bash
./kernel-lab.sh doctor
./kernel-lab.sh architectures
./kernel-lab.sh userspaces
./kernel-lab.sh targets
./kernel-lab.sh sessions
./kernel-lab.sh capabilities TARGET
./kernel-lab.sh info TARGET
```

The stable interface is intended to stay provider-neutral. Legacy/provider-development commands remain available but are not required for normal use.
