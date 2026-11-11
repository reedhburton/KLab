# KLab Vintage Toolchain Audit — Pass 01

Date: 2026-09-22
Base: R11 live-test snapshot

## Trigger

Ubuntu 17.04 `4.10.0-42-generic` booted successfully in the offline guest, but a KLab-built smoke module failed to load with `Unknown rela relocation: 4`. The module contained `R_X86_64_PLT32` relocations. Its sealed fallback toolchain was GCC 6.5.0 + GNU binutils 2.32, while the guest kernel reports Ubuntu GCC 6.3.0 from 2017.

This demonstrates that compiler-major matching and vermagic matching are necessary but not sufficient for historical module compatibility. The assembler/linker generation is part of the compatibility contract.

## Design conclusions

1. Treat compiler + assembler + linker + helper programs as one historical toolchain contract.
2. Prefer the distribution-native toolchain package closure for distro kernels. Kernel.org crosstool remains useful for upstream/cross builds and as an explicit fallback, not as proof of exact distro fidelity.
3. Keep relocatable crosstools and distro-native toolchains as different execution/artifact modes. A distro GCC tree is not assumed to be relocatable outside its distro runtime.
4. Static validation must distinguish authoritative proof from heuristics. Exact kernel source can prove that a relocation type is handled; version-only rules cannot, because stable and distro kernels may backport loader support.
5. `Ready for transfer` should not be emitted after only vermagic validation when the generated module has an unresolved vintage relocation hazard.

## Implemented in R12 pass 01

### Vintage relocation validator

Added `klab-vintage-validate.sh` / `lib/vintage_compat.py`.

It:
- extracts relocation types from a generated `.ko`;
- can scan an exact kernel source architecture tree for relocation-handler tokens;
- treats source-backed support as authoritative for known relocation transitions;
- otherwise reports conservative `unproven` vintage hazards rather than pretending a kernel-version heuristic proves incompatibility;
- has strict mode for prepare-time gating.

The first encoded hazards are x86-64 `R_X86_64_PLT32` and i386 `R_386_PLT32`. The framework is architecture-aware and can be extended without putting distro-specific exceptions in the build path.

### Pre-transfer gate

The sealed buildenv/toolchain pair smoke test now runs the vintage validator after vermagic validation. An unproven vintage relocation hazard blocks prepare before transfer by default. `KLAB_ALLOW_UNPROVEN_VINTAGE_RELOCS=1` is an explicit escape hatch for deliberate testing, not a compatibility claim.

This would have stopped the observed Ubuntu 4.10 + binutils 2.32 module before the original `Ready for transfer` boundary.

### Distribution-native toolchain artifact

Added a new content-addressed artifact type with extension `.klabdistrotoolchain` and helper `klab-distro-toolchain.sh`.

The artifact contains:
- exact downloaded distro compiler/binutils package closure;
- package name/version/architecture inventory;
- compiler path/version/target;
- assembler path/version;
- linker path/version;
- per-file checksums and a content/spec identity;
- create, verify, inspect and import operations.

The new extension is intentionally separate from existing relocatable `.klabtoolchain` artifacts. This prevents the generic shared-artifact importer from treating distro package sets as directly executable relocatable compiler trees.

### Provider capture wiring

Added distribution-native package capture hooks for:
- Ubuntu / Debian via APT;
- Fedora / RHEL / newer CentOS via DNF;
- CentOS 7 via yum/yumdownloader.

`kernel-lab.sh toolchain distro-capture provider:release[:kernel] [--output ...]` invokes this path. When an exact kernel target is supplied, KLab detects its compiler version and APT prefers the matching versioned GCC package (for example `gcc-6` for a GCC 6.x-built Ubuntu kernel) when the historical repository provides it.

This is network/staging functionality and has not been live-tested in this pass.

## Important boundary still open

R12 pass 01 captures the actual distro GCC/binutils closure as a portable artifact, but the normal `prepare` buildenv execution path still uses the separately bound relocatable toolchain. The next implementation step is a `distro-native` buildenv compiler mode:

- buildenv runs `/usr/bin/gcc` or the detected versioned GCC inside the captured distro root;
- the buildenv manifest binds to the `.klabdistrotoolchain` object ID and compiler metadata;
- offline import requires both artifacts;
- the native toolchain package artifact is provenance/reconstruction material, while executable compiler files remain inside the matching distro runtime root;
- no host dynamic linker/library leakage is permitted.

That separation avoids trying to execute old dynamically-linked distro GCC binaries directly against a modern host libc.

## Validation status

Network-free tests added:
- `vintage-relocation-validation.sh`
- `vintage-pretransfer-gate.sh`
- `distro-toolchain-artifact.sh`
- `distro-toolchain-wiring.sh`

Existing network-free tests run during this pass continued to pass in the tested batches. Shell syntax and Python compilation pass. No live repository capture or QEMU runtime claim is made for R12 pass 01.

## Next investigations

1. Implement `distro-native` buildenv execution and bind buildenv identity to distro-toolchain artifact identity.
2. Live-capture Ubuntu 17.04 GCC 6.3/binutils from old-releases and verify the generated module uses loader-compatible relocations.
3. Add package-signature/key identity recording to distro-toolchain artifacts (especially CentOS 7 Vault).
4. Generalize source-backed relocation extraction for additional architectures and known historical assembler transitions.
5. Capture immutable repository provenance for the rest of buildenv dependencies, closing the existing dependency-provenance gap rather than solving only GCC/binutils.

## Pass 02 — distro-native execution binding and artifact hardening (2026-09-22)

### Implemented

- Added explicit `prepare ... --distro-toolchain` mode. This is intentionally opt-in until live historical-repository and QEMU validation is completed.
- Added buildenv format v3 compiler contract `distro-native-v1`. The buildenv content identity now pins the exact `.klabdistrotoolchain` SHA-256 object ID and rejects simultaneous relocatable-toolchain bindings.
- Added `klab-buildenv.sh run-module-native`. It verifies the buildenv target identity, verifies the pinned distro-toolchain object/provider/release/arch, verifies that the recorded GCC/as/ld paths exist inside the captured root, and executes kbuild in the read-only buildenv sandbox. The old distro binaries are never executed against the host filesystem/runtime.
- Added native relocation validation to capture: the smoke `.ko` built by the distro compiler is passed through the vintage relocation validator before the buildenv is accepted.
- Added final read-only distro-native smoke validation through the same imported buildenv + imported distro-toolchain path intended for offline workers.
- Thin `.klab` manifests now carry the buildenv compiler contract and distro-toolchain dependency ID. Import requires that dependency to be installed, and module builds dispatch by compiler contract.
- Hardened `.klabdistrotoolchain` format to v2. Verification now rejects unchecksummed extra archive members, malformed inventory rows, unsafe compiler paths, compiler metadata/manifest disagreement, and corrupt pre-existing installed objects. `lookup`, `list`, and `assert-installed` were added.
- Fixed a vintage compiler-probing bug: APT/DNF capture no longer assumes `gcc -dumpfullversion` exists; it falls back to `-dumpversion` for old GCC releases.

### Confirmed design point

The distro-native artifact is provenance/reconstruction material, while executable GCC/binutils live in the captured distro root. This avoids the false assumption that dynamically linked historical distro compilers are relocatable onto a modern host. The buildenv pins the artifact ID so the provenance package set cannot be silently substituted.

### Validation performed

PASS: buildenv-distro-native-binding.sh
PASS: distro-native-wiring.sh
PASS: distro-toolchain-artifact.sh
PASS: distro-toolchain-integrity.sh
PASS: buildenv-capture-pair.sh
PASS: buildenv-toolchain-runner.sh
PASS: combined-chain-audit.sh
PASS: thin-toolchain-compat.sh
PASS: directory-import-order.sh
PASS: distro-abi-vermagic.sh
PASS: provider-contract.sh/provider-routing
PASS: provider mirror/rootless/runtime-order regressions
PASS: vintage relocation/pre-transfer regressions
PASS: shell syntax over root/lib/backends/providers/tests
PASS: Python byte compilation

The monolithic run-all pass reached the execution-time limit after the early tests; the remaining relevant tests were then run individually and passed. This is not represented as a single uninterrupted all-tests pass.

### Not live-tested

- Historical Ubuntu/Debian APT distro-native capture.
- DNF/yum distro-native capture.
- End-to-end transfer/import/build/QEMU module insertion using `--distro-toolchain`.
- Ubuntu 17.04 / 4.10.0-42 with its GCC 6.3/binutils 2.28 generation.

### Next investigations

1. Record and validate repository/key/signature provenance for captured distro packages, especially CentOS 7 Vault and EOL APT repositories.
2. Validate that captured package closure is semantically complete and corresponds to the package inventory rather than only checksum-consistent.
3. Strengthen compiler matching: compare kernel-recorded compiler requirement with the distro-native artifact and distinguish exact, distro-compatible, and merely same-major matches.
4. Audit old kbuild host-tool requirements (perl, awk, sed, openssl, objtool, pahole, etc.) across kernel eras so native roots do not accidentally rely on packages inherited from the provider base image without provenance.
5. Live-test Ubuntu 17.04 first when interactive testing resumes.

## R14 pass 03 — repository provenance, compiler matching, closure audit

### Confirmed findings

1. R13 content-addressed the package archives but did not bind repository configuration, trusted-key inventory, or repository metadata state into `.klabdistrotoolchain` identity. This left an evidentiary gap between "these bytes were downloaded" and "which historical repository/key state selected these bytes".
2. `prepare --distro-toolchain` requested a compiler major derived from the kernel, but did not reject a capture whose *actual* GCC version differed from the compiler version recorded for the target kernel. This could silently turn an intended exact historical build into a merely same-major build.
3. APT capture generated `packages.tsv` from dependency metadata and downloaded archives afterward, but did not compare the semantic package/version/architecture identities of the downloaded DEBs back to that inventory. Archive checksums proved integrity, not closure equality.
4. CentOS 7 Vault configuration has `gpgcheck=1`, so package signatures are required, but KLab does not currently prove which repository signing key authenticated repository metadata. In particular, no `repo_gpgcheck=1` guarantee is claimed. This remains a live/provenance boundary rather than something this static pass can safely "fix" without proving Vault metadata-signature availability.
5. Historical kbuild host dependencies are broader than GCC/binutils. Current buildenv recipes explicitly install the primary external-module dependencies, but commands supplied by the provider base image (shell/coreutils/findutils/grep/sed/awk and, for some kernel/config paths, Perl/Python or generated host tools) are captured only as part of the realized root/image state, not as a separately sealed dependency archive closure. F16 therefore applies to more than the compiler.

### Implemented and statically tested

- `.klabdistrotoolchain` format v3 is used when repository provenance is supplied. The artifact identity now binds `spec/provenance.json`; v1/v2 remain readable for compatibility.
- APT and RPM distro-toolchain capture now emits repository provenance containing the effective repository configuration, trusted-key inventory, and a digest inventory of available APT list metadata / cached RPM `repomd.xml` metadata. The provenance JSON itself is checksummed and content-addressed by the artifact.
- Added `match-compiler` with explicit `exact` and `compatible` policies. `prepare --distro-toolchain` now defaults to **exact** matching when the kernel has a recorded GCC version and rejects a mismatched captured compiler before importing/building the environment. `compatible` is explicit only and currently means same GCC major/minor.
- APT distro-toolchain capture now reconstructs package/version/architecture identity from every downloaded DEB and requires exact equality with the resolved package inventory. A mismatch aborts capture rather than producing an apparently complete artifact.
- Added regression coverage for provenance identity binding and exact-vs-compatible compiler policy. Existing distro-toolchain integrity/artifact and distro-native wiring tests continue to pass in targeted execution.
- Shell syntax checks and Python byte-compilation pass after these changes.

### Proposals / not yet claimed

- Extend repository provenance from key *inventory* to the exact signer/key fingerprint used for each Release/InRelease or RPM repository metadata object where the package manager exposes that information robustly across historical releases.
- Generalize the semantic closure check to RPM captures as an independently named closure assertion even though RPM `packages.tsv` is currently generated directly from the downloaded RPM set.
- Add a buildenv host-tool manifest mapping every executable used by the kbuild smoke build to its owning distro package, then require those owning packages to be represented in the sealed dependency closure. Prefer observed execution tracing plus a conservative static baseline rather than guessing a universal host-tool list.
- Decide policy for kernels whose recorded compiler string is incomplete. Keep exact matching as the default whenever a complete version is available; require an explicit compatibility policy otherwise rather than silently weakening the match.

### Later live-test items

- Ubuntu 17.04 / 4.10.0-42-generic: prove that the captured compiler is exactly GCC 6.3.0, inspect the v3 repository provenance, run native smoke build, verify no unsupported PLT32 relocation, then insert in QEMU.
- CentOS 7.9 Vault: inspect the actual key inventory and cached repomd state and determine whether repository metadata signatures can be enforced without breaking Vault operation.
- Exercise APT closure equality against an EOL repository with packages already present in the OCI base image; this is the case most likely to expose dependency-resolution/archive-download disagreement.

## R15 pass 04 — provenance claim validation and host-tool closure boundary

### Confirmed bug fixed

R14 content-addressed `spec/provenance.json`, but its validator treated the digest fields *inside* that JSON as opaque claims. A provenance object could therefore be internally inconsistent (for example, `repository_config_sha256` could disagree with the embedded `repository_config`) and still form a valid content-addressed artifact. Provider/release in provenance were also not cross-checked against the artifact binding.

R15 validates the evidence semantically before create/import/verify: repository configuration and key-inventory digests are recomputed; repository-metadata rows and digests are validated and the metadata-inventory digest is recomputed; and provenance provider/release must equal the artifact provider/release. A regression test proves inconsistent embedded evidence and cross-provider provenance are rejected.

### Host-tool closure audit

The remaining reconstruction gap should **not** be solved by simply adding more names to `.klabdistrotoolchain`. That artifact has a clear compiler/binutils identity and is already pinned by the buildenv. The buildenv's `installed-packages.tsv` proves what was realized, but does not preserve the package archives/repository selection for every package in that realized root. Mixing all of those packages into the compiler artifact would blur two different contracts.

Recommended next artifact boundary: a build-environment dependency closure (or equivalent buildenv payload section) that binds the complete package archive set needed to reconstruct the captured root. It should be derived from the realized installed inventory and package ownership of host tools, and independently content-addressed. The first implementation should observe the smoke build's executed host tools where possible and supplement that with a conservative kbuild baseline. This avoids claiming a universal list such as perl/awk/sed/openssl/pahole when usage varies by kernel/configuration.

The immediate host-tool risk is therefore classified as **reconstruction provenance**, not current offline execution leakage: `run-module-native` executes inside the already captured read-only root. The root tree is identity-checked, so an imported buildenv does not silently borrow host `/usr/bin` tools. What remains unproven is whether KLab can reconstruct that exact root later from immutable package inputs.

### Validation

PASS: distro-toolchain-provenance-compiler.sh
PASS: distro-toolchain-provenance-semantics.sh (new)
PASS: distro-toolchain-artifact.sh
PASS: distro-toolchain-integrity.sh
PASS: buildenv-distro-native-binding.sh
PASS: distro-native-wiring.sh
PASS: shell syntax for affected backend/capture entry points
PASS: Python byte compilation

No live EOL repository or QEMU validation is claimed.

### Next investigations

1. Design the buildenv dependency-closure artifact/section without conflating it with `.klabdistrotoolchain`.
2. Add package ownership mapping for host tools used during a smoke build, then compare owning packages against the reconstructible closure.
3. Strengthen APT/RPM signer evidence from trusted-key inventory to exact authenticated metadata/package signer fingerprints where historical package-manager behavior exposes them reliably.
4. Live-test Ubuntu 17.04 first: exact GCC 6.3.0, period binutils, provenance v3, native relocation gate, offline import/build, QEMU insertion.

## R16 pass 05 — CentOS 7 Vault trust anchor hardening

### Confirmed bug

The CentOS 7 historical provider enabled `gpgcheck=1` but trusted the `RPM-GPG-KEY-CentOS-7` file inherited from the provider image without independently pinning its identity. Repository provenance recorded the installed key inventory after the fact, which is useful evidence but does not establish the trust anchor used to accept packages. The Vault base URLs also used plaintext HTTP. RPM package signatures protect package bytes, but an unpinned trust-anchor file leaves a bootstrap provenance gap.

### Implemented/tested fix

- The CentOS 7 provider now verifies `/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7` against the official historical CentOS 7 signing-key fingerprint `6341 AB27 53D7 8A78 A7C2 7BB1 24C6 A8A7 F4A8 0EB5` before creating/using the Vault repository configuration.
- CentOS 7 Vault base URLs were changed from HTTP to HTTPS. Package-level `gpgcheck=1` remains enabled; HTTPS is defense in depth and does not replace RPM signature verification.
- Added `tests/centos7-key-provenance.sh`, which statically enforces the pinned fingerprint and rejects regression to plaintext Vault base URLs.
- Existing provider contract/mirror/compatibility and distro-toolchain provenance/integrity tests continue to pass; shell syntax and Python byte-compilation checks pass.

### Deliberately not claimed

This pass does not claim a live CentOS 7 container/Vault transaction. In particular, the old CentOS 7 provider image must still be live-tested to confirm its bundled GnuPG accepts the fingerprint command form and that the Vault TLS path works with the image's historical CA/TLS stack. If either fails, the correct fallback is a dependency-free pinned hash/parser or an explicitly bootstrapped verifier, not removal of the trust-anchor check.

Repository metadata signer attribution also remains incomplete. `gpgcheck=1` authenticates RPM packages; it does not by itself prove `repomd.xml` authenticity. CentOS historically offered signed repository metadata via `repo_gpgcheck=1` for at least updates, but KLab should not enable that blindly across Vault sections until the archived metadata/signature availability is live-audited.

### Next pass

1. Add package-signature evidence to RPM distro-toolchain provenance: record each captured RPM's signature key ID/status and require exact coverage of the package archive set.
2. Determine whether CentOS 7 Vault base and updates retain usable `repomd.xml.asc`; if so, verify and record signer identity, otherwise classify metadata as transport/content-hash provenance with package signatures as the authoritative package authenticity boundary.
3. Continue the buildenv reconstruction closure: executable-to-owning-package mapping and immutable package archive coverage for kbuild host tools.

## Pass 05 — RPM package-signature evidence (R17, 2026-09-22)

### Confirmed bug / provenance gap
R16 pinned the CentOS 7 public-key fingerprint and required package-manager signature checking, but the exported `.klabdistrotoolchain` did not preserve per-RPM evidence that each captured archive actually passed a signature check. Consequently artifact verification could prove package bytes and repository/key inventories without proving one-to-one signature-check coverage of the RPM payload.

### Implemented and tested
- RPM distro-toolchain capture now runs `rpm --checksig` over every downloaded RPM and records filename, SHA-256, complete check diagnostic, and a strict verified flag in repository provenance.
- A successful process exit alone is deliberately insufficient: evidence must contain an RPM signature marker (`PGP` or `RSA`) and `OK`, and must not contain `NOKEY` or `NOT OK`. This prevents an unsigned package whose digests merely verify from being mislabeled as signature-authenticated.
- `.klabdistrotoolchain` semantic verification treats `package_signatures` as binding evidence when present: coverage must exactly equal the captured RPM set, entries cannot duplicate, every archive digest must match, and every result must be verified.
- Added `tests/rpm-signature-provenance.sh`; existing provenance/compiler, artifact-integrity, artifact create/import, distro-toolchain wiring, provider-contract and mirror-policy regressions pass. Shell syntax and Python byte-compilation pass.

### Still open / later live test
- This pass does not claim a live CentOS 7 Vault or modern DNF capture. Historical `rpm --checksig` output variants must be exercised live before freezing the evidence parser as a long-term schema.
- Signature evidence authenticates RPM payloads to an installed trusted key; exact cryptographic signer fingerprint attribution should be added rather than inferred solely from human-readable `rpm --checksig` output.
- Repository metadata authentication remains separate. Do not equate RPM signature coverage with authenticated `repomd.xml` selection.
- Buildenv reconstruction closure / observed kbuild executable-to-owning-package mapping remains the next major portability boundary.

## Pass 06 / R18 — historical kbuild host-tool runtime boundary

### Confirmed findings

1. The sealed distro-native runtime does **not** leak host `/usr/bin` into kbuild: bwrap mounts the captured buildenv root at `/`, clears the environment, and invokes `/bin/sh` and `/usr/bin/make` from that root. This is a runtime-isolation property, not reconstruction provenance.
2. Buildenv reconstruction provenance is still incomplete. `installed-packages.tsv` records the realized installed package set, but the immutable package archives currently retained across the kernel bundle and `.klabdistrotoolchain` do not necessarily cover that complete set. In particular, provider recipes install host-side build dependencies (for example build-essential/gcc/make, bc, kmod, libelf/libssl development packages, flex/bison, and sometimes pahole) in addition to the kernel packages. Therefore the captured root is reproducible as a content-addressed image, but is not yet proven reconstructible solely from retained package inputs.
3. A universal historical-kbuild executable list would be incorrect. Requirements vary by kernel era, architecture, generated-vs-prepared headers, and configuration. Perl/Python, objtool, pahole/BTF, OpenSSL helpers, flex/bison, and architecture-specific generators are conditional. Observed execution should be combined with a conservative baseline rather than treated as complete coverage.

### Implemented/tested fix

`run-module-native` now fails closed before kbuild if a conservative host-tool baseline is absent from the captured distro root: `/bin/sh`, `/usr/bin/make`, awk, sed, grep, find, xargs, basename, dirname, tr, cut, sort, head, mkdir, rm, cp, mv, ln, and cat. This does not pretend to solve package provenance; it makes the minimum runtime contract explicit and prevents a missing base-image utility from surfacing as an opaque mid-build failure. A static regression test protects the baseline and error path.

Targeted regression coverage passed for distro-native binding/wiring, compiler policy, repository-provenance semantics, RPM signature provenance, CentOS 7 key provenance, distro-toolchain integrity, shell syntax, and Python byte compilation.

### Proposed next implementation

Introduce a separately content-addressed buildenv reconstruction closure rather than widening `.klabdistrotoolchain` into a general root filesystem artifact. During provider realization, record (a) every installed package identity, (b) the immutable archive digest for every package required to reconstruct the root, and (c) executable-to-owning-package evidence for the conservative baseline plus tools actually exercised by the smoke build. Observed tools are evidence, not the sole closure criterion. Bind the reconstruction-closure ID into the buildenv identity and require exact package-inventory equality when reconstructing.

### Later live-test items

- Run the ownership/closure capture against Ubuntu 17.04 and CentOS 7 provider images and compare the retained archive set to `installed-packages.tsv`.
- Exercise multiple historical kernel/config combinations to discover conditional host tools without declaring the observed set universal.
- Continue to avoid claiming historical repository or QEMU validation until those tests are actually run.

## Pass 07 / R19 — host-tool ownership evidence

### Confirmed boundary
R18's runtime preflight proved that the conservative kbuild host-tool baseline exists inside the sealed distro root, but did not preserve which distro package owns each executable. The root digest prevents later mutation, yet reconstruction provenance could not distinguish a package-owned utility from an unexplained file inherited from the provider image.

### Implemented/tested fix
Buildenv capture now resolves every conservative baseline tool inside the provider root and records `logical tool -> resolved executable path -> owning package` in `/var/lib/klab/host-tool-owners.tsv`. Debian/Ubuntu ownership is obtained with `dpkg-query -S`; RPM-family ownership with `rpm -qf`. Capture fails closed when a baseline executable is absent or has no owning package. Because the inventory is stored inside the captured root, it participates in the existing root-tree content identity. `run-module-native` now requires the ownership inventory and verifies its recorded executable paths before invoking kbuild.

Static/regression validation passed for the new ownership contract, the R18 baseline preflight, distro-native wiring, buildenv inventory/artifact integrity, distro-toolchain provenance/compiler policy, provenance semantics, distro-toolchain artifact creation/import, and distro-toolchain corruption/unchecksummed-member rejection. Shell syntax and Python byte compilation passed. No live repository or QEMU validation is claimed.

### Proposal / next step
Do not treat the observed baseline as the complete reconstruction closure. Next, map the *entire realized installed package inventory* to immutable package archives, then add execution observation during representative smoke builds to annotate which packages/tools were exercised. Reconstruction should require exact package identity and archive digest coverage, while observation remains evidence rather than the definition of completeness. Conditional tools (Perl/Python, objtool, pahole, BTF/signing helpers, etc.) must remain kernel/config dependent.

### Later live-test items
Verify ownership queries on Ubuntu 17.04 and CentOS 7 Vault roots, including symlinked `/bin/sh` and merged-/usr edge cases; then run the imported read-only distro-native smoke build and QEMU module insertion. Preserve the R11 live baseline for comparison.

## Pass 07 / R20 — host-tool ownership semantics

### Confirmed bug
R19 recorded `host-tool-owners.tsv` inside the content-addressed buildenv root, but artifact verification did not prove that each recorded owner was present in `installed-packages.tsv`. A self-consistent root could therefore preserve an ownership claim whose package identity was absent from the separately sealed realized-package inventory.

A second verifier hazard was found while fixing this: ordinary host path resolution must not be used for absolute symlinks in a filesystem image. An image link such as `/bin/tool -> /usr/bin/tool` is rooted at the captured buildenv `/`, not the audit host `/`.

### Implemented/tested fixes
For format-v3 `distro-native-v1` buildenvs, creation, deep archive verification, and installed-object verification now semantically validate the host-tool ownership inventory. The validator requires the complete conservative baseline, unique logical tools and executable paths, safe absolute paths, executable regular-file targets resolved in the buildenv namespace, and an owner package present in the sealed installed-package inventory. Absolute symlinks are explicitly re-rooted into the buildenv image during validation.

Added `tests/buildenv-host-tool-owner-semantics.sh`. Existing buildenv artifact/inventory tests and distro-native host-tool/wiring tests remain passing. Legacy format-v1/v2 artifacts and non-distro-native compiler contracts retain their previous compatibility behavior.

### Still a proposal / next engineering boundary
This is not yet the full reconstruction closure. `installed-packages.tsv` proves which package identities were realized, but most of those identities are not yet paired with immutable package archives. The next artifact should bind the realized package set to archive hashes/signature evidence (or explicitly classify packages whose bytes are supplied by another content-addressed artifact), then test exact-set reconstruction in an empty root.

### Later live validation
No EOL APT/Vault fetch, package reconstruction, or QEMU insertion was performed in this pass. The Ubuntu 17.04 GCC 6.3.0 relocation case remains the motivating live test.

## Pass 09 / R21 — ownership re-proof and EOL APT authentication policy

### Confirmed bugs / gaps
- R19/R20 content-addressed `host-tool-owners.tsv` and checked that each claimed owner name existed in the realized package inventory, but native execution did not independently re-prove that the recorded executable was actually owned by that package. A false-but-well-formed ownership row could therefore survive semantic verification.
- EOL Ubuntu intentionally disables `Acquire::Check-Valid-Until` for expired Release metadata. That is a freshness exception, not an authentication exception. Distro-toolchain capture did not explicitly fail if a provider/setup later introduced APT's unauthenticated/insecure-repository bypasses.

### Implemented and tested
- `run-module-native` now re-queries the sealed root's own package database for every recorded baseline executable (`dpkg-query -S` or `rpm -qf`) and requires exact agreement with `host-tool-owners.tsv`. This happens inside the bwrap filesystem namespace, so the modern host package database cannot satisfy the check.
- APT distro-toolchain capture now rejects `APT::Get::AllowUnauthenticated=true`, `Acquire::AllowInsecureRepositories=true`, and `Acquire::AllowDowngradeToInsecureRepositories=true`. `Acquire::Check-Valid-Until=false` remains permitted for EOL archives.
- Added regressions `distro-native-host-tool-owner-reproof.sh` and `apt-authentication-policy.sh`; affected shell syntax, Python compilation, and existing host-tool/provenance tests pass.

### Proposals / remaining work
- Add a content-addressed buildenv reconstruction closure binding every realized package triple to an immutable DEB/RPM archive. Host-tool ownership evidence is now stronger, but it is still not proof that the whole captured root can be rebuilt from retained inputs.
- For APT, preserve positive repository-signature verification evidence rather than relying only on secure APT policy plus captured key/metadata inventories. DEBs generally rely on authenticated repository metadata/hash chains rather than an RPM-style per-package signature model.
- Continue separating repository freshness policy from authentication policy; do not treat expired EOL metadata as a reason to permit unsigned repositories.

### Later live tests
- Ubuntu 17.04 / 4.10.0-42-generic with distro GCC 6.3.0 remains the primary live test. Verify old APT's `apt-config dump` representation and authenticated old-releases behavior, then perform native smoke build, relocation gate, and QEMU insertion.
- CentOS 7 Vault still needs live validation of key-fingerprint tooling, TLS/CA behavior, RPM signature diagnostics, and repository-metadata signature availability.

## R22 vintage/toolchain pass 09 — compiler probe consistency

### Confirmed bugs
- The legacy YUM distro-toolchain capture path still recorded GCC with `-dumpversion` only. This escaped the R13 old-GCC probing hardening applied to APT/DNF and could record a less-specific compiler version than the actual distro compiler contract.
- `run-module-native` re-proved GCC with `-dumpversion` only, so capture and execution did not use the same version-probe semantics. GCC versions that report a shortened `-dumpversion` could be rejected despite a correctly captured full version.

### Implemented/tested fixes
- YUM capture now prefers `-dumpfullversion` and falls back to `-dumpversion`, matching the other distro-native capture paths.
- Native execution re-proof now uses the same full-version/fallback contract before comparing against the recorded compiler metadata.
- Added `tests/old-gcc-version-probe-consistency.sh` to keep APT/RPM capture and native execution from drifting back to inconsistent probing.
- Relevant compiler-policy, distro-native, host-tool ownership, APT-authentication, RPM-signature, CentOS-7-key, and artifact-integrity regressions pass; affected shell syntax and Python compilation pass.

### Proposals / next audit work
- Build the separately content-addressed buildenv reconstruction closure: exact realized package identity -> retained DEB/RPM bytes -> authentication/repository evidence. Do not infer completeness solely from tools observed during one kbuild run.
- For Debian/Ubuntu, preserve the signed Release/InRelease -> Packages index -> package hash chain as positive authentication evidence rather than inventing per-DEB signature semantics.
- For RPM roots, evolve R17 textual `rpm --checksig` evidence toward explicit signer-key identity when a stable cross-era extraction method is established.

### Later live-test items
- Ubuntu 17.04 `4.10.0-42-generic`: confirm the captured native compiler resolves to the kernel-recorded GCC 6.3.0 and that the smoke module no longer emits the incompatible relocation seen with GCC 6.5/binutils 2.32.
- Exercise both old-GCC probe branches in real historical images (`-dumpfullversion` supported and unsupported).
- CentOS 7 Vault: verify pinned-key inspection, HTTPS/TLS behavior, RPM signature evidence parsing, and any available repository-metadata signature path.
- No live repository or QEMU validation is claimed for R22.

## R23 final offline pass — APT package metadata closure

### Confirmed bug
The APT provenance object content-addressed repository list files and the retained DEBs, but did not semantically bind each retained DEB to the SHA-256 in the exact APT package stanza used to select that package. Thus the evidence stopped one edge short of the authenticated repository metadata -> package archive relationship.

### Implemented/tested fix
APT distro-toolchain capture now records `apt_package_metadata` for every exact package identity (name/version/architecture), retained DEB filename, and the SHA-256 advertised by APT metadata. Capture independently hashes each retained DEB and fails if it disagrees. Artifact verification requires exact coverage of the retained DEB set and rechecks every archive digest. The existing insecure-APT-option rejection remains in force; EOL `Check-Valid-Until=false` remains a freshness exception, not an authentication bypass.

Static regression `tests/apt-package-metadata-provenance.sh` proves a metadata/archive digest disagreement is rejected. No live old-releases Ubuntu, CentOS Vault, or QEMU result is claimed by this offline pass.

### Live-test transition
Offline audit has now reached diminishing returns for the motivating Ubuntu 17.04 failure. The next useful evidence is live: resolve/download the historical package closure, prove the exact GCC 6.3.x contract selected for `4.10.0-42-generic`, capture/import the artifacts, build the smoke module inside the sealed distro root, and boot/load it under QEMU. `live-validation-ubuntu1704.sh` automates that sequence and keeps staging/offline homes separate.
