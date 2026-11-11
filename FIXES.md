# KLab Overnight Fix Log — Pass 01
## RC8 — Fedora 20–44 full userspace expansion

**Status:** IMPLEMENTED + regression and live QEMU validation.

Full native Fedora userspaces were captured and checksum-verified for releases 20, 23, 26, 29, 32, 35, 38, 40, 42, and 44. Eleven exact stored kernels from 3.14 through 7.2 passed live KVM boots, Fedora release identity, GCC, Python 3, OpenSSH server, and KLab command transport.

Fedora 23 exposed an undeclared `tar` dependency in the minimal OCI image. Fedora 20 also required yum fallback and repository capture without `/etc/dnf`. Native capture now handles both boundaries and uses an EXIT cleanup so failed captures do not leak containers. The behavioral cleanup regression and the complete network-free suite pass.

## RC7 — bounded archive staging and Ubuntu LTS validation

**Status:** IMPLEMENTED + regression and live QEMU validation.

KLab can register removable archive volumes and stage artifacts into a content-addressed local cache. Copies are atomic and SHA-256 verified, cached objects are reused, and least-recently-used objects can be removed while preserving a configurable free-space floor. Archive sources are never deleted. `klab load` uses this path automatically and `klab repo` exposes the staging controls.

`tests/archive-staging.sh`, `tests/simple-cli.sh`, Python/shell syntax checks, and the complete network-free suite pass. Native Ubuntu 16.04, 18.04, 20.04, 22.04, 24.04, and 26.04 root files pass manifest verification and live functional boots with their matching stored kernels.


Date: 2026-09-21 HST
Base: `klab-m2-hardened-snapshot-2026-09-21`
Base SHA-256: `560a7b32eded307867f6f0666e4de3168b9b6592aa3cc77bf636ead931d77e96`

## Rules for this pass
- Record every confirmed issue before changing code.
- Record the exact fix and regression test added or run.
- Preserve unresolved findings explicitly; do not silently drop them.
- Do not widen provider support until boundary/regression behavior stays clean.

## Findings

### F01 — Ubuntu LTS archive routing was stale
**Status:** FIXED + regression test.

The default `KLAB_UBUNTU_ARCHIVED_RELEASES` sent Ubuntu 14.04, 16.04 and 18.04 to `old-releases.ubuntu.com`. As of 2026-09-21, their `trusty`, `xenial`, and `bionic` suites and update pockets are still served by `archive.ubuntu.com`; `old-releases.ubuntu.com` is appropriate for non-LTS EOL releases such as 17.04/Zesty.

**Fix:** remove 14.04/16.04/18.04 from the default old-release set. Keep the environment override for site-specific policy. Added `tests/provider-compat-hardening.sh`.

### F02 — Provider architecture claims were not enforced uniformly
**Status:** FIXED + regression test.

Several providers advertised `cross-arch=no`, but only selected operations failed early on a non-x86_64 `ARCH`. A manually specified target could reach fetch/build code before discovering the mismatch.

**Fix:** provider capabilities now declare `arches=x86_64`, and the unified dispatcher checks the requested architecture before list/fetch/buildenv/module operations. This separates *supported target architectures* (`arches=`) from *cross-build capability* (`cross-arch=`), so future aarch64 support can be added without changing the contract.

### F03 — Exact kernel release strings were trusted as shell/package patterns
**Status:** FIXED + regression test.

Provider backends interpolate the exact kernel release into package names and shell commands. A malformed release containing glob/shell syntax could cause non-exact matching or command parsing.

**Fix:** unified provider dispatch now permits only kernel-release tokens matching `[A-Za-z0-9][A-Za-z0-9._+~-]*` before fetch/build/capture operations.

### F04 — APT `list` filter embedded user input into `bash -lc`
**Status:** FIXED + regression test.

The optional fixed-string list filter was inserted inside single quotes. A pattern containing a single quote could break out of the quoting inside the disposable provider container.

**Fix:** both provider regex and user filter are shell-escaped with Bash `%q` before construction. Added an injection regression (`tests/apt-list-quoting.sh`) that proves a malicious filter cannot create a marker file.

### F05 — Provider API documentation/template lagged behind M2
**Status:** FIXED.

`PROVIDER-API.md` still described milestone 1 and four required operations, while the dispatcher/tests require six (`describe`, `capabilities`, `list`, `fetch`, `build_module`, `capture_buildenv`). The template likewise omitted capabilities and buildenv capture, making a newly copied provider incomplete by construction.

**Fix:** rewrote the provider API for M2, documented `arches=` vs `cross-arch=`, and expanded `_template.sh.example` to the complete six-operation contract.

## Overnight passes 02–09 integrated 2026-09-22 HST

### F06 — Explicit operation architecture could bypass provider capability gate
**Status:** FIXED + regression test.

The dispatcher originally checked global `ARCH`, even when `build_module` or `capture_buildenv` carried an explicit architecture argument. A caller could therefore request an unsupported architecture while the global remained `x86_64`.

**Fix:** operation-specific architecture is now the value passed to `klab_provider_assert_arch()`. Added regression coverage in `tests/overnight-hardening-02-09.sh`.

### F07 — RPM list filter had the same quoting weakness as APT
**Status:** FIXED + regression test.

DNF/YUM list helpers embedded the optional fixed-string pattern directly inside a `bash -lc` program.

**Fix:** DNF/YUM list filters now use Bash `%q` before insertion into the container command. Regression coverage verifies shell metacharacters remain data.

### F08 — Module-build jobs value was not validated at provider dispatch
**Status:** FIXED + regression test.

`jobs` eventually reaches `make -j`. Non-decimal/zero/negative values were not rejected at the unified provider boundary.

**Fix:** provider module-build dispatch requires a positive decimal integer before entering a backend.

### F09 — RPM build-tree override was embedded raw into container shell
**Status:** FIXED + regression test.

The DNF/YUM module-build helpers placed `build_override` inside shell source. A quote/metacharacter in the path could alter the command.

**Fix:** build-tree overrides are serialized with Bash `%q` before insertion. Regression coverage verifies the raw value cannot become shell syntax.

### F10 — Provider release/snapshot grammar was open-ended
**Status:** FIXED + regression test.

Provider release strings were allowed to flow into image/repository/snapshot helpers without a single closed grammar.

**Fix:** base releases now use `[A-Za-z0-9][A-Za-z0-9._+-]*`; optional snapshots must be exactly `@YYYYMMDDTHHMMSSZ`. Multiple `@`, traversal, and shell syntax are rejected before provider execution.

### F11 — `@snapshot` syntax was not checked against provider capabilities
**Status:** FIXED + regression test.

A release could request timestamp snapshot semantics even when a provider had no such backend. In particular, archived Ubuntu releases use deterministic `old-releases.ubuntu.com`, not the timestamp snapshot path.

**Fix:** the dispatcher enforces `snapshots=yes` for `@timestamp` targets. Archived Ubuntu reports `snapshots=no`; CentOS and other non-timestamp providers reject the syntax.

### F12 — Buildenv execution-platform mismatch was only discovered late
**Status:** CLOSED by F13/F14.

The buildenv format distinguishes target and execution architectures, but provider capture could begin work before proving the staging host/container execution architecture matched the current v1/v2 same-architecture contract.

### F13 — Same-architecture staging precondition was missing
**Status:** FIXED + regression test.

**Fix:** buildenv capture canonicalizes the staging host and target architectures and fails before container creation if they differ. Stable provider claims remain x86_64-only until a cross-architecture path is implemented and tested.

### F14 — Provider container execution architecture was not verified before setup
**Status:** FIXED + regression test.

A matching staging host does not prove the selected OCI image executes the requested architecture.

**Fix:** immediately after container start, KLab runs `uname -m`, canonicalizes it, and compares it to the target before repository setup/package installation.

### F15 — Downloaded package manifest did not prove an exact package-file set
**Status:** FIXED + regression test.

A checksum file is insufficient if extra package archives can appear beside the checksummed files or if a listed package changes after the manifest is produced.

**Fix:** APT/RPM manifests now use normalized basenames. Capture verifies that `PACKAGES.sha256` covers exactly every `.deb`/`.rpm` in the package directory and verifies every SHA-256 before mounting the set into a provider container.

### F16 — Full dependency archive/repository provenance is not yet sealed
**Status:** FIXED — V4 enforcement and live acquisition are validated across current and historical APT, Fedora/Koji RPM, and Alpine APK.

Buildenv format V4 embeds immutable dependency archives, their exact SHA-256 manifest, and the repository snapshot metadata bytes referenced by provenance. Creation rejects closures whose package name/version/architecture identities do not exactly equal the realized installed-package inventory. Import retains the archive closure, and installed verification detects package, manifest, provenance, or repository-metadata mutation. `tools/seal-dependency-closure.py` builds this closure offline from real DEB, RPM, or APK metadata. The APT provider now downloads and identity-checks every exact installed DEB, retains signed repository state, seals it automatically, and fails closed when an installed version is no longer present in the authenticated repository. A live Ubuntu 24.04 / 6.8.0-142-generic capture produced and deeply verified V4 artifact `ee1ca01b10a57b7c1ea6fb115326c0af3a7f3ab3e2ef89e689a35babf12148a7`, including a successful fresh-root import. The RPM provider now captures exact installed NEVRAs, excludes RPM database pseudo-packages, retains DNF/YUM state, enforces signatures for normal repositories, and supports an explicit Koji mode that binds retained buildroot metadata to payload-digest-verified RPMs. Its checksum-bound identity handoff permits host-side sealing without a host RPM implementation. Fedora 44 / 7.2.11-200.fc44.x86_64 produced deeply verified V4 artifact `8ca3c0ee95b30db4c38bfd0ba55f5b2dd7201648d79fd725ac2f01928037ab1` and passed a fresh-root import. Alpine APK capture verifies signed exact-version origin archives and maps apk-tools 3 split installed identities to those archives; Alpine 3.23 / 6.18.57-0-lts produced deeply verified V4 artifact `bf08df25f4dd16724c8a020afbe41a174be45f23870ea3b53b4735701ecba907` and passed a fresh-root import. V1–V3 artifacts remain readable.

**Validation:** Ubuntu 17.04 / 4.10.0-42-generic exercised the archived old-releases path and retained all 153 exact installed DEBs plus authenticated repository state. The sealed archive closure is the immutable offline reconstruction source where timestamp-addressed snapshots do not exist. Existing distribution buildenvs do not gain reconstruction provenance retroactively.

### F17 — Provider image tag/name could stand in for immutable image identity
**Status:** FIXED + regression test.

A mutable OCI tag such as `ubuntu:22.04` is not adequate provenance for a content-addressed build environment.

**Fix:** capture now resolves the local image to a canonical `sha256:<64 hex>` image ID and fails if the runtime cannot provide one. Buildenv format v2 requires the canonical image content ID in its spec identity.

### F18 — Realized build dependency closure was not sealed in the artifact identity
**Status:** FIXED + regression tests.

`PACKAGES.sha256` describes downloaded kernel archives, but not the complete package set actually installed in the provider root.

**Fix:** buildenv capture records a sorted `installed-packages.tsv` from dpkg/rpm after installation. Buildenv format v2 stores and checksums this inventory, includes its SHA-256 in the content/spec ID, installs it beside the object metadata, and detects post-import mutation. Existing format-v1 artifacts remain verifiable/importable; newly created artifacts use v2.

## F06 — Rootless Docker bind-output ownership

Rootless Docker maps container uid 0 to the invoking host user. Provider output
must therefore remain uid 0 inside a rootless container; chowning it to the
host's numeric uid maps it into the subordinate uid range. Provider-core now
detects rootless Docker (or honors KLAB_CONTAINER_ROOTLESS=0/1), and APT/RPM
backends choose the correct bind-output owner for rootless versus rootful mode.
Regression: tests/provider-rootless-ownership.sh.


## F07 — Archived Ubuntu codename must come from the requested release

**Live symptom:** the first clean Ubuntu 17.04 provider test failed with `cannot determine Ubuntu codename`.

**Root cause:** the archived-release setup sourced `/etc/os-release` inside the historical Ubuntu container and required `VERSION_CODENAME`. Older Ubuntu images do not reliably expose that newer os-release field, even though KLab already knows the exact requested release.

**Fix:** KLab now maps the requested Ubuntu release to its codename in the provider and emits an explicit suite (for example, `17.04 -> zesty`) into the old-releases APT setup. Archived repository selection no longer depends on metadata fields present inside the container image.

**Regression:** `provider-contract.sh` requires Ubuntu 17.04 setup to pin `suite='zesty'` and rejects any dependency on `VERSION_CODENAME`.


## F08 — Historical Ubuntu OCI images may omit `/etc/apt`

The Ubuntu archived-release setup now creates the standard APT config/cache/list directory skeleton before writing `/etc/apt/sources.list`. This fixes clean `ubuntu:17.04` provider runs that failed with `No such file or directory` before repository configuration. Mirror-only APT setup receives the same defensive directory initialization. A regression test executes the generated 17.04 setup against an intentionally empty fake APT filesystem.

## R4 — container image/command ordering

- Fixed `run_container_root` / `run_container_user`: Docker/Podman now receive
  `run [OPTIONS] IMAGE [COMMAND ...]` in the required order.
- Previous ordering placed IMAGE last, so `ubuntu:17.04 ... bash -lc ...` could
  actually select `bash` as the image and pass `ubuntu:17.04` as a shell
  argument. This explains the misleading historical-provider `apt-get: command
  not found` failure even though `/usr/bin/apt-get` exists in the Ubuntu image.
- Rootless ownership detection now interrogates the selected Docker/Podman
  runtime instead of hardcoding Docker.
- Added `tests/container-runtime-ordering.sh`.

## R5: distro ABI validation
- Replaced `make kernelrelease == requested distro ABI` checks in APT/buildenv paths with an actual external-module build and exact vermagic-prefix validation.
- Ubuntu 4.10.0-42.46 reports the distro ABI as 4.10.0-42-generic while being based on upstream 4.10.17.

## R6: buildenv rootfs symlink semantics

- Fixed buildenv validation for absolute symlinks captured from distro root filesystems.
- Absolute links such as `bin/mt -> /etc/alternatives/mt` are now interpreted as rooted inside the buildenv/sandbox filesystem, matching `bwrap --ro-bind ROOT /` semantics, rather than being resolved against the host `/`.
- Relative symlinks are still checked lexically and rejected if `..` traversal would escape above the buildenv root.
- Special files remain rejected.
- Added a regression using the Debian/Ubuntu alternatives-style absolute symlink chain and retained the relative symlink escape rejection test.

## R7: safe hardlinks in captured buildenv roots

- Fixed buildenv archive validation to accept normal filesystem hardlinks such as `bin/bzcat` when their archive target remains inside the captured namespace and ultimately resolves to a regular-file member.
- Hardlink targets that are absolute, contain `..`, are missing, form cycles, or resolve to a non-regular member remain rejected.
- Duplicate archive member names remain rejected.
- Fixed the compressed-member iterator so an early validation failure cannot be obscured by a secondary `Exception ignored in ... outer_members`/SIGPIPE error.
- Added `tests/buildenv-hardlinks.sh`, covering a valid `bzcat`/`bzip2`-style hardlink and an escaping `../../etc/passwd` hardlink rejection.

## R8: read-only buildenv sandbox mountpoints
- Fixed final buildenv smoke validation failing with `bwrap: Can't mkdir /work: Read-only file system`.
- The captured buildenv remains mounted read-only at `/`.
- Ephemeral module workspace now lives under the writable `/tmp` tmpfs at `/tmp/klab-work/module`.
- The externally verified toolchain is mounted read-only at `/tmp/klab-toolchain`, avoiding creation of a toolchain mountpoint beneath the read-only captured root.
- Added `tests/buildenv-readonly-workspace.sh` to lock the sandbox mountpoint contract.

## R9 — transfer-directory import

- Fixed `kernel-lab.sh import DIRECTORY`: R8 imported `.klabbuildenv` files and then incorrectly passed the directory path to `klab-bundle.sh import`, which only accepts a `.klab` file.
- Directory import now installs typed shared artifacts, then `.klabbuildenv` objects, then `.klab` targets.
- `--force` is propagated to shared objects and targets; `--load-image` is propagated only to target bundles.
- Empty transfer directories fail explicitly.

## R10 — imported bundle.env relocation

- Fixed atomic target import serializing temporary `.klab-import.<pid>` paths into `bundle.env`.
- Fixed malformed distro `bundle.env` generation that accidentally embedded shell control text in the environment file.
- Distro and upstream imports now validate/extract in the staging directory but serialize only the final installed target paths.
- Added `tests/import-env-relocation.sh`.

## R11 — historical crosstool fallback compatibility

- Fixed kernel.org GCC fallback policy. When the exact recorded GCC version is unavailable, KLab no longer selects the newest release in the same major.
- KLab now selects the closest available release in the same major, preferring the first release at or above the requested compiler and otherwise the newest older release.
- This prevents large toolchain-vintage jumps such as Ubuntu 17.04 GCC 6.3.0 -> kernel.org GCC 6.5.0/binutils 2.32. That combination emits R_X86_64_PLT32 relocations that the tested Ubuntu 4.10 module loader rejects.
- For the observed Ubuntu 17.04 target, the resolver now selects kernel.org GCC 6.4.0 instead of GCC 6.5.0.
- Added `tests/toolchain-nearest-fallback.sh`.

## R12 vintage/toolchain pass 01

- Added source-aware/heuristic historical module relocation validation.
- Added a strict pre-transfer gate after sealed buildenv/toolchain pair compilation.
- Added content-addressed `.klabdistrotoolchain` create/verify/inspect/import support.
- Added APT/DNF/yum provider hooks to capture the distribution's actual GCC/binutils package closure.
- Added `toolchain distro-capture` command; exact kernel targets feed their detected compiler version into capture so APT can prefer a matching versioned GCC package.
- Kept distro-native package artifacts distinct from relocatable `.klabtoolchain` trees; native execution binding is intentionally not claimed complete yet.

### F29 — Distro-toolchain repository/key state was not identity-bound
**Status:** fixed for capture provenance; exact signer attribution remains follow-up.

R13 sealed package bytes but not the repository configuration/key/metadata state that selected them. Distro-toolchain format v3 now binds a provenance document containing effective repository configuration, trusted-key inventory, and repository metadata digests. Historical v1/v2 artifacts remain readable.

### F30 — Distro-native capture did not enforce the kernel-recorded GCC version
**Status:** fixed.

`prepare --distro-toolchain` now performs an exact numeric GCC-version match against the kernel compiler requirement when one is available. A separate explicit compatible policy exists but is not selected implicitly.

### F31 — APT package closure inventory was not compared to downloaded DEB identities
**Status:** fixed in capture path; live EOL-repository validation pending.

APT capture now extracts Package/Version/Architecture from every downloaded DEB and requires exact equality with the resolved inventory before artifact creation.

### F32 — Historical kbuild host-tool package provenance remains incomplete
**Status:** open; narrowed.

The realized build root is sealed, but tools inherited from provider base images are not all retained as immutable package archives with repository provenance. A future host-tool ownership manifest should map observed kbuild executables to packages and fold those packages into the sealed closure. This is part of F16's broader dependency-provenance closure.

## 2026-09-22 R15 vintage/toolchain pass 04
- Fixed repository provenance semantic validation: embedded config/key/metadata digest claims are now recomputed rather than merely preserved inside a content-addressed JSON file.
- Fixed provenance binding: provider and release inside provenance must match the distro-toolchain artifact.
- Added malformed repository-metadata row/digest rejection.
- Added `tests/distro-toolchain-provenance-semantics.sh` and upgraded the R14 provenance fixture to the full v1 evidence schema.
- Clarified host-tool gap as buildenv reconstruction provenance; do not inflate the compiler artifact into a universal build-root package closure.

### F34 — CentOS 7 Vault trust anchor was inherited but not pinned

**Status:** fixed and live-validated on CentOS 7.9 in RC4.

The CentOS 7 provider used `gpgcheck=1` but accepted the signing-key file inherited from the base image without independently checking its identity, and its Vault URLs used HTTP. The provider now pins the official CentOS 7 signing-key fingerprint before repository use and uses HTTPS Vault URLs. A regression test enforces both properties. Package signatures remain authoritative. Live validation on `quay.io/centos/centos:7` confirmed the pinned fingerprint check, old GnuPG compatibility, HTTPS Vault access with the pinned `archive.kernel.org` fallback, exact signed RPM closure capture, Buildenv V4 deep verification, and fresh-root import.

## R18 — distro-native host-tool baseline
- Added an explicit preflight for conservative kbuild host utilities inside the sealed distro-native root.
- Added `tests/distro-native-host-tool-baseline.sh`.
- Kept reconstruction provenance separate from runtime isolation; no claim is made that the full installed package closure is archived yet.

### R24 live fix — APT distro-toolchain package-metadata command quoting
**Status:** FIXED + regression test.

The first Ubuntu 17.04 live validation exposed a quoting defect in the R23 APT package-metadata provenance block. Double quotes introduced in the generated `bash -lc` program were not escaped at the outer shell-string layer, so the generated program was mangled before container execution and failed with `unexpected EOF while looking for matching \`'\``. The entire package-metadata block now preserves its intended quoting through generation. `tests/apt-capture-script-quoting.sh` captures the generated container program, syntax-checks it, and verifies the critical quoted expressions survive generation.

### R25 live validation — historical APT capture assumed Python 3 was preinstalled
**Status:** FIXED + regression test.

Ubuntu 17.04 live validation reached distro-native toolchain capture but failed with `python3: command not found`. The APT capture backend used Python to serialize compiler/repository provenance without declaring it as a capture-time dependency. R25 installs `python3` before the first guest-side Python invocation and uses `universal_newlines=True` instead of the Python >=3.7 `text=True` subprocess alias, preserving compatibility with Ubuntu 17.04-era Python. `tests/apt-vintage-python-bootstrap.sh` verifies generated-script syntax, dependency ordering, and the old-Python-compatible API.

### R26 live validation — APT buildenv provider wrapper referenced undeclared compiler_version
**Status:** FIXED + regression test.

Ubuntu 17.04 live validation completed distro-native toolchain capture far enough to enter buildenv capture, where `set -u` exposed an API-arity bug in both Ubuntu and Debian provider wrappers. `klab_provider_*_capture_buildenv` passed an undeclared `compiler_version` argument even though `klab_backend_apt_capture_buildenv` accepts only provider/release/kernel/bundle/image/setup/output/arch. R26 removes the stray argument from both APT providers while preserving the optional compiler-version argument on `capture_toolchain`. `tests/apt-buildenv-provider-arity.sh` prevents the wrappers from regressing.

## R27 live validation
- Fixed distro-native host-tool ownership capture for alternatives-managed commands such as Ubuntu `/usr/bin/awk`: resolve the command to the final executable before querying dpkg/rpm ownership, and record the resolved package-owned executable path.
- Added a regression for the alternatives/symlink ownership boundary.

## r10 multi-architecture target model (2026-09-26)

- Centralized architecture identity/planning in `lib/arch-model.sh`.
- Split target/build/toolchain-exec/toolchain-target/guest architecture roles.
- Added explicit aarch64 Linux >=3.7 capability gating.
- Added experimental MIPS family profiles.
- Replaced core distro x86_64 special-case with provider architecture/cross-staging capabilities.
- Added architecture plan metadata to new `.klab` and `.klabbuildenv` artifacts.
- Added `arch-plan` CLI and architecture-model regression tests.

## r11 — cross-architecture E2E validation

- Added `lib/arch-e2e.sh` and `kernel-lab.sh arch-smoke`.
- `arch-smoke` validates the complete upstream target chain: architecture plan, QEMU preflight, kernel prepare/package/verify, Buildroot rootfs+SDK, cross-compiled user probe, cross-built module, QEMU boot/control channel, user execution, module load, and module unload.
- Added durable `klab-arch-e2e-v1` reports with stage timeline, architecture plan, guest uname, user output, dmesg snapshots, and artifact hashes.
- Architecture profiles now declare accepted guest `uname -m` values; the architecture plan exports these values.
- Added `tests/arch-e2e-dryrun.sh` including pre-3.7 arm64 rejection and failure-report validation.
- Added `klab-multiarch-overnight-r11.sh`, an aarch64 feature matrix for the next overnight cycle.
- The current development environment lacks `qemu-system-aarch64`; live ARM boot validation remains intentionally pending host execution.

## r12 multi-architecture E2E

- Generalized the r11 architecture smoke path to x86_64/i386/aarch64/armv7.
- Added E2E capability state to architecture profiles and plans.
- Hardened user/module ELF architecture validation for 32-bit targets.
- Moved ARM session control from second PL011 UART to virtio serial for broader QEMU compatibility.
- Added resumable multi-architecture overnight feature matrix with per-architecture QEMU preflight.

## r13 experimental mipsel/Malta execution backend

- Promoted `mipsel` from model-only to an explicitly gated experimental E2E path.
- Corrected the modern Buildroot profile to `qemu_mips32r2el_malta_defconfig`.
- Corrected the kernel.org compiler archive target to `mips-linux`; target
  endianness remains represented by KLab as `mipsel` and selected by the Linux
  Malta configuration/Kbuild flags.
- Added strict 32-bit little-endian MIPS ELF validation and rejection of MSB or
  MIPS64 payloads.
- Added per-architecture QEMU memory/vCPU profile settings; mipsel starts at
  256 MiB and one vCPU for conservative Malta bring-up.
- Extended `arch-plan` with QEMU memory/vCPU metadata.
- Added opt-in mipsel support to the resumable multi-arch overnight runner and
  a dedicated `klab-mipsel-overnight-r13.sh` first-live matrix.
- Added tests for model wiring, explicit experimental gates, ELF identity and
  runner wiring.

## r14 — big-endian MIPS + coordinated scenario framework

- Added the experimental big-endian `mips` Malta E2E lane beside `mipsel`.
- Explicitly enforces Malta kernel endianness (`CPU_BIG_ENDIAN` vs
  `CPU_LITTLE_ENDIAN`) rather than relying on emulator name alone.
- Added strict MSB/LSB 32-bit MIPS ELF validation and a focused two-endian MIPS
  overnight matrix.
- Added a static-friendly C guest agent with process groups, signals,
  stdout/stderr capture, waits/timeouts, named barriers and timestamped events.
- Added `klab-scenario-v1`, `kernel-lab.sh scenario-run`, cross-compiled
  scenario builds, kernel module load/unload actions, detailed JSON reports,
  and a resumable cross-architecture scenario matrix.
- Added a next-cycle umbrella feature overnight runner combining multi-arch E2E
  and coordinated scenarios.

## r15 multi-guest network/scenario work

- Added simultaneous multi-guest scenario orchestration and reports.
- Added QEMU private Ethernet bus support to persistent boot sessions.
- Fixed control/QMP socket collisions for two sessions using the same target tuple.
- Added host-controlled guest-agent gates for cross-VM synchronization.
- Added architecture-specific NIC profiles and kernel network-driver configuration.
- Added simple two-guest, three-kernel, and mixed-architecture network scenarios.
- Added resumable multi-guest overnight runner.

## r16 topology/fault orchestration

- multi-NIC persistent sessions and named private LANs
- routed multi-LAN scenarios
- PCAP and fixed network delay filters
- QMP link flap/recovery
- readiness/dependency scheduling and dependency failure policy
- process signal, guest power-cut, and opt-in kernel-panic faults
- explicit MAGIC_SYSRQ/PROC_SYSCTL for E2E kernels
- stronger route/delay/fault validation
- resumable r16 fault overnight runner

## r16 continuation: fault trigger timing hardening

- Moved action registration ahead of process execution.
- Fault actions now fire on observed `started`, `ready`, and `exited` process transitions instead of being deferred until all process spawns complete.
- Preserved readiness/exit-triggered actions even when no dependency otherwise waits on that state.
- Added action trigger/timing/duration fields to canonical reports.
- Strengthened QMP link-control regression to cover both down and up commands on separate QMP connections.
- Changed link-flap recovery scenario to fault the client after process start so its retry loop experiences the outage and must recover.
- Added `tests/r16-freeze-gate.sh` for routed-topology + link-recovery synthetic validation.

## r16 continuation: destructive-fault hardening

- Ready-triggered actions now observe readiness immediately after process spawn instead of depending on another process to consume that readiness state.
- Added explicit `guest-loss-results.tsv` evidence and `guest_losses` in canonical report v2.
- Hardened guest power-cut so stale/already-dead session PIDs cannot be reported as successful cuts.
- Hardened panic injection so only a new panic marker after the injection point satisfies the action.
- Preserved panic-injection RPC return code as evidence because the crash can sever control before reply completion.
- Added Linux signal range and destructive `expected` boolean validation.
- Added `tests/r16-destructive-faults.sh` with real local guest-agent signal semantics and fresh-panic evidence checks.

## Native full-userspace gate (2026-10-17)

- Added provider-qualified native rootfs capture for Ubuntu, Debian, Fedora, CentOS, and Alpine with exact package inventory, repository-state archive, OCI image identity, and SHA-256 verification.
- Fixed native-shell serial receive by enabling `cread clocal -crtscts`; Ubuntu dash now supports the KLab RPC transport.
- Native sessions include the exact distro kernel module tree and depmod metadata, use 2 GiB RAM, and load the QEMU NIC module.
- Native OpenSSH supports the existing key/password/passwordless and loopback/LAN bind interface.
- Ubuntu 24.04 with 6.8.0-142-generic passed 9/9 guest conformance capabilities plus a real key-authenticated SSH/network/module gate.

## Native distro expansion (2026-10-17)

Debian Bookworm, Fedora 44, Alpine 3.23, and CentOS 7 join Ubuntu 24.04 at the full-function gate. All five exact x86_64 pairs pass 9/9 conformance capabilities plus real key-authenticated SSH and gateway networking. Provider fixes cover locked/missing shadow databases, read-only OCI directories, Alpine gzip-module metadata preservation, CentOS Quay/vault acquisition, and Python 3.6-compatible child-process testing.
