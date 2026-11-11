# KLab multi-architecture target model — r10

Date: 2026-09-26

## Objective

Provide one architecture contract that can serve both of KLab's planned test
modes:

1. build/load kernel modules across a wide matrix of kernel versions;
2. cross-compile and execute user-space binaries across the same matrix.

The architecture model must support native workers, cross compilation, QEMU
execution, and later physical/remote workers without conflating those roles.

## Architecture roles

### Target architecture

`target_arch` describes the ISA/ABI being tested. The kernel, modules, and guest
programs are target artifacts.

Examples: `x86_64`, `i386`, `aarch64`, `armv7`, `mipsel`.

### Build architecture

`build_arch` describes the worker CPU executing Kbuild, GCC/Clang, binutils,
and test-program compilation.

A build can be native (`build_arch == target_arch`) or cross compiled.

### Toolchain execution and output architectures

`toolchain_exec_arch` describes the compiler executable itself. In model v1 it
must equal `build_arch`.

`toolchain_target_arch` describes code emitted by the compiler and must equal
`target_arch`.

This is the key distinction required for an x86_64 host running
`aarch64-linux-gnu-gcc`.

### Guest architecture

`guest_arch` describes the QEMU or physical execution machine. Model v1 requires
`guest_arch == target_arch`.

Future user-mode emulation can relax this for narrowly-scoped binary tests, but
full kernel testing always needs a target-architecture machine.

## Current plan schema

New bundles can carry `architecture_model` alongside the legacy `arch` field:

```json
{
  "schema": "klab-arch-plan-v1",
  "model_version": 1,
  "target_arch": "aarch64",
  "build_arch": "x86_64",
  "toolchain_exec_arch": "x86_64",
  "toolchain_target_arch": "aarch64",
  "guest_arch": "aarch64",
  "cross_compile": true
}
```

The old `arch` field remains authoritative for old readers and equals
`target_arch`. This avoids a bundle-format break while the rest of KLab migrates.

## Provider semantics

Provider capability fields keep two independent concepts:

```
arches=x86_64,aarch64
cross-arch=no
```

means:

- x86_64 target on x86_64 staging worker: allowed;
- aarch64 target on aarch64 staging worker: allowed;
- aarch64 target on x86_64 staging worker: rejected.

`cross-arch=yes` explicitly allows the third case.

This lets KLab add native ARM provider workers before package-manager backends
are capable of foreign-architecture staging.

## Kernel-version capability

Architecture profiles may declare minimum/maximum Linux versions. r10 includes
`aarch64 >= 3.7`, preventing the old sweep error where Linux 3.0–3.6 was sent to
an architecture that did not exist in those releases.

Capability rejection should eventually be reported as `UNSUPPORTED`/`SKIP`, not
as a build failure, in the generic test-matrix reporter.

## MIPS model

r10 adds experimental definitions for:

| KLab ID | Width | Endian | ABI | Linux ARCH | QEMU family |
|---|---:|---|---|---|---|
| mips | 32 | big | O32 | mips | qemu-system-mips |
| mipsel | 32 | little | O32 | mips | qemu-system-mipsel |
| mips64 | 64 | big | N64 | mips | qemu-system-mips64 |
| mips64el | 64 | little | N64 | mips | qemu-system-mips64el |

These profiles are deliberately `ARCH_STATUS=experimental`. They define target
identity, endianness, ABI, kernel/QEMU/toolchain naming, but do not yet claim an
end-to-end KLab boot/module test has passed.

## Buildenv evolution

Current `.klabbuildenv` format v1/v2-fullroot execution still requires the
buildenv's `exec_arch` to match the host. This is correct for native distro
compiler captures but is insufficient for a true cross buildenv.

The next buildenv evolution should represent:

```
target_arch
toolchain_exec_arch
toolchain_target_arch
rootfs_arch
```

rather than assuming target and compiler-execution architecture are identical.

Two paths then become possible:

1. **native provider capture** — run ARM container/compiler on an ARM worker;
2. **cross buildenv** — run x86_64 cross-compiler targeting ARM/MIPS while using
   a target kernel build tree/rootfs.

The first path is simpler for distro-native compiler provenance. The second is
ideal for upstream kernels and user-space binary tests.

## Test-framework implications

The future scenario runner should select a target tuple rather than just an
architecture string:

```
(kernel target, target_arch, userspace, build_arch, toolchain)
```

A test payload can then declare whether it is:

- architecture-independent source to build per target;
- a prebuilt target binary with an ELF/ABI requirement;
- a kernel module requiring a matching target build tree;
- a host-side coordinator program.

The runner must verify target compatibility before booting a VM.

## Implementation in r10

Implemented:

- central `lib/arch-model.sh`;
- stable metadata for x86_64/i386/aarch64/armv7;
- experimental MIPS family profiles;
- target/build/toolchain-exec/toolchain-target/guest plan generation;
- `kernel-lab.sh arch-plan` command;
- aarch64 minimum-kernel validation;
- provider same-arch versus cross-arch staging enforcement;
- central model use by kernel-lab, bundle and buildenv layers;
- architecture plan embedded in newly-created `.klab` manifests;
- compatibility validation between manifest `arch` and architecture plan;
- network-free regression tests.

Not yet implemented/validated:

- distro ARM package fetching;
- cross-architecture distro buildenv format;
- QEMU boot validation for armv7/MIPS in the current project checkpoint;
- MIPS guest BusyBox/Buildroot cache validation;
- multi-arch module-load matrix;
- multi-arch generic test-runner/guest-agent protocol.

## Recommended next implementation sequence

1. Promote **aarch64 upstream** to an end-to-end validated target: build kernel,
   build static guest, cross-compile test binary, QEMU boot, load module.
2. Validate **i386** end-to-end with the same tests.
3. Validate **armv7** upstream.
4. Introduce buildenv format capable of a cross toolchain whose executable
   architecture differs from its target architecture.
5. Add Ubuntu/Debian aarch64 provider support, first on same-arch ARM workers and
   then cross-staging where repository/buildenv mechanics are proven.
6. Bring up `mipsel` as the first MIPS target; after that add big-endian `mips`
   and 64-bit variants.
7. Feed the target tuple directly into the coordinated test framework.
