# KLab provider API — milestone 2

A provider is one file named `providers/<id>.sh`. The unified dispatcher discovers it from the target's first field (`<id>:<release>[:<kernel>]`) and invokes namespaced shell functions. Experimental providers live under `providers/experimental/` and require `KLAB_ENABLE_EXPERIMENTAL_PROVIDERS=1`.

Required operations:

```text
klab_provider_<id>_describe RELEASE
klab_provider_<id>_capabilities RELEASE
klab_provider_<id>_list RELEASE PATTERN
klab_provider_<id>_fetch RELEASE KERNEL_RELEASE BUNDLE_DIR
klab_provider_<id>_build_module RELEASE KERNEL_RELEASE BUILD_IMAGE PACKAGES_DIR MODULE_DIR JOBS [BUILD_DIR] [ARCH]
klab_provider_<id>_capture_buildenv RELEASE KERNEL_RELEASE BUNDLE_DIR OUTPUT.klabbuildenv ARCH
```

Provider responsibilities:

- Select release/repository policy (normal mirror, archive/vault, snapshot, entitlement, etc.).
- Select reusable backend helpers when possible.
- Return normalized kernel release strings from `list` that can be passed unchanged to `fetch`/`prepare`.
- Declare supported target architectures with `arches=` in `capabilities`.
- Keep provider-specific package-manager/repository behavior out of `kernel-lab.sh`.
- Capture a build environment through the common `.klabbuildenv` boundary rather than silently borrowing worker state.

Backend responsibilities:

- `lib/backends/apt.sh`: APT listing, exact package download, validation, extraction handoff, connected module builds, and buildenv capture.
- `lib/backends/rpm.sh`: DNF/YUM listing, exact package download, validation, extraction handoff, connected module builds, and buildenv capture.

Core responsibilities remain: target parsing, cache/bundle layout, normalization, `.klab` creation/import, QEMU, offline operation, sessions, and test execution. The provider dispatcher validates declared architectures and exact kernel-release token syntax before repository operations.

## Capability fields

Capabilities are whitespace-separated `key=value` fields. Current M2 fields include:

```text
list=yes|entitled|experimental
fetch=yes|entitled|experimental
build-module=yes|...
buildenv=yes|entitled|...
historical=yes|limited|koji
snapshots=yes|no|koji
cross-arch=yes|no
arches=x86_64[,aarch64,...]
```

`arches=` declares which kernel target architectures the provider currently supports. `cross-arch=` is separate: it states whether a staging host may prepare a target for a different execution architecture.

As of the multi-architecture target model, these fields are evaluated independently. For example `arches=x86_64,aarch64 cross-arch=no` permits native aarch64 staging on an aarch64 worker but rejects x86_64-to-aarch64 staging. `cross-arch=yes` is an explicit claim that the provider backend can prepare a foreign target architecture from the current build worker.

## Adding a provider

Copy `_template.sh.example` to `<id>.sh`, implement all six operations, then run:

```bash
./tests/provider-contract.sh
./tests/provider-compat-hardening.sh
bash -n providers/<id>.sh
./kernel-lab.sh providers
./kernel-lab.sh list <id>:<release>
```

A provider may wrap an existing discovery/fetch implementation temporarily, but its module-build/buildenv paths still need to obey the normalized artifact and toolchain boundaries.
