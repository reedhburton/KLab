# Kernel Lab architecture profiles — target model v1

KLab treats architecture as data. `architectures/*.conf` describes a canonical
**target architecture**: the architecture on which the kernel and test payload
execute. The central model is implemented by `lib/arch-model.sh`.

The model deliberately separates five roles:

- `target_arch`: kernel/test-program ISA/ABI under test.
- `build_arch`: worker architecture that runs the build process.
- `toolchain_exec_arch`: architecture of the compiler/linker executables;
  currently equal to `build_arch`.
- `toolchain_target_arch`: architecture emitted by the toolchain; equal to
  `target_arch`.
- `guest_arch`: QEMU/physical guest architecture; currently equal to
  `target_arch`.

Therefore an x86_64 worker cross-compiling for ARM64 has:

```
target_arch=aarch64
build_arch=x86_64
toolchain_exec_arch=x86_64
toolchain_target_arch=aarch64
guest_arch=aarch64
cross_compile=true
```

This distinction is also used by provider capability checks. A provider may
advertise `arches=x86_64,aarch64 cross-arch=no`: that means the provider can
stage ARM64 on an ARM64 worker, but an x86_64 worker must not pretend it can
stage the same target.

## Profile fields

Identity/ABI:

- `ARCH_ID`, `ARCH_ALIASES`
- `ARCH_STATUS=stable|experimental|disabled`
- `ARCH_FAMILY`
- `ARCH_BITS`
- `ARCH_ENDIAN=little|big`
- `ARCH_ABI`
- `KERNEL_MIN_VERSION`, optional `KERNEL_MAX_VERSION`

Kernel:

- `KERNEL_ARCH`
- `KERNEL_DEFCONFIG`
- `KERNEL_IMAGE`
- `KERNEL_CONFIG_ENABLE`, optional `KERNEL_CONFIG_DISABLE`

Execution/toolchain:

- `QEMU_BINARY`, `QEMU_MACHINE`, `QEMU_TCG_CPU`
- `LINUX_CONSOLE`, `LINUX_CONTROL_TTY`
- `TOOLCHAIN_TARGET`
- `KVM_HOSTS`

Userspace/package ecosystems:

- `BUILDROOT_DEFCONFIG`
- `DEBIAN_ARCH`
- `RPM_ARCH`
- `APK_ARCH`
- `BUSYBOX_FILE_MATCH`
- optional `FREEBSD_ARCH`

## Shipped profiles

Stable model profiles:

- `x86_64`
- `i386`
- `aarch64`
- `armv7`

Experimental profiles (modelled but not yet end-to-end validated):

- `mips` — 32-bit big-endian O32
- `mipsel` — 32-bit little-endian O32
- `mips64` — 64-bit big-endian N64
- `mips64el` — 64-bit little-endian N64

Experimental architectures require:

```bash
export KLAB_ENABLE_EXPERIMENTAL_ARCHES=1
```

before build/boot operations. Their presence in `kernel-lab.sh architectures`
means the architecture contract is known; it does **not** claim that every
provider, toolchain, rootfs, or QEMU boot path has been validated yet.

## Version capability rules

Profiles can reject kernel/architecture combinations before an expensive build.
For example `aarch64` declares `KERNEL_MIN_VERSION=3.7`, so Linux 3.0–3.6 is a
capability skip/error rather than a misleading compiler/build failure.

Inspect a concrete build plan with:

```bash
./kernel-lab.sh arch-plan aarch64 --build x86_64 --kernel v6.6
./kernel-lab.sh arch-plan mipsel --build x86_64 --kernel v5.15 --json
```

### r13 mipsel execution profile

`mipsel` is the first MIPS profile wired into the common E2E harness. It remains
experimental and requires both architecture and E2E opt-ins. The profile uses
QEMU Malta/24Kf, 256 MiB, one vCPU, `malta_defconfig`, Buildroot
`qemu_mips32r2el_malta_defconfig`, and the kernel.org `mips-linux` crosstool
archive family. The target architecture remains `mipsel`; compiler-archive
naming is not used as the target ISA/endian identity.

### r14 big-endian MIPS execution profile

`mips` is the experimental big-endian O32 sibling of `mipsel`. It uses the
Malta/24Kf model, `qemu-system-mips`, Buildroot
`qemu_mips32r2_malta_defconfig`, and the kernel.org `mips-linux` compiler
family. KLab explicitly enables `CPU_BIG_ENDIAN` and disables
`CPU_LITTLE_ENDIAN` after applying the Malta kernel defconfig; the `mipsel`
profile explicitly performs the inverse. Artifact checks require 32-bit MSB or
LSB MIPS respectively and reject MIPS64/wrong-endian payloads.
