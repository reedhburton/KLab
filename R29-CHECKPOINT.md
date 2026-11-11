# R29 integrated root-layout checkpoint

R29 combines the verified R28 vintage/toolchain/provenance source with the recovered R25 unified-root overlay. Work was performed in a separate source copy. Existing runtime roots and input archives were not modified.

## Integration changes

- First-party shell commands use KLAB_ROOT and canonical stores, with compatibility links off by default. KLAB_HOME remains a checked compatibility alias.
- Updated newer runner/bundle/buildenv child calls and temporary post-capture roots to propagate both root aliases consistently. Derived paths are recalculated for children.
- Buildenvs use artifacts/buildenvs/sha256; distro toolchains use artifacts/distro-toolchains/sha256. Shared typed objects use artifacts/objects, with userspace, toolchain, firmware and source views under artifacts.
- Direct Python artifact commands resolve the same root identity; explicit --home remains a per-command override.
- Fixed R25 compatibility-link creation so state/MODE stays a file instead of being created as a directory.
- Made recovered regression fixtures portable and updated storage-path expectations without removing integrity/provenance assertions. Added real source-artifact import, KLAB_ROOT-only buildenv/distro imports, child isolation, MODE, and real-directory prune refusal coverage.
- Extended the root application script for actual R28 helpers and ensured the legacy M2 installer includes root helper dependencies. The live harness now sets both root aliases for its isolated roots.
- R28 alternatives assertion fix and production ownership behavior retained. Ownership, package provenance, compiler bindings and relocation checks remain enforced.

## Validation

PASS: combined suite, 58 network-free tests, plus shell/Python syntax.
PASS: updated installer-smoke and root-layout tests rerun after adding final dependency/prune assertions.
PASS: overlay applied twice to an actual R28 copy; all non-backup source bytes unchanged on second application.
PASS: residual-path audit on integrated source.
PASS: release archive checksum and per-file archive manifest verification.

Initial combined runs exposed outdated fixture dependencies; those failures and their logs are retained. A separate exploratory install-m2.sh --check-only against the already-patched R28 tree rejected it with “provider refactor milestone 2 already applied.” That legacy M2 installer is for pre-M2 source trees, not R28 upgrades; its supported unpatched fixture preflight/install and installed helper execution passed.

No live Ubuntu, network capture, bwrap build, or QEMU validation was run in this integration. Target remains Ubuntu 17.04 / 4.10.0-42-generic / kernel-recorded GCC 6.3.0.

## Use and upgrade boundary

Use this complete integrated source package directly. Set only KLAB_ROOT:

```bash
export KLAB_ROOT="$HOME/klab-r29"
./klab-root init
./klab-root doctor
./klab status
```

For an existing R28 runtime, use a fresh R29 root and re-import the saved transfer artifacts with `./klab import /path/to/transfer-directory`. Import order remains shared artifacts, distro toolchains, buildenvs, then targets. The old artifacts/objects/sha256 and artifacts/toolchains/sha256 stores are not automatically moved by R25 normalize/migrate; previously generated bundle.env paths also require regeneration through target import. Keep the old root until the new one is validated. No existing runtime was migrated here.

The updated apply-root-layout.sh is a source-layout integration helper. Prefer this full R29 package for matching tests, documentation, and installer dependencies. Do not run install-m2.sh on an already M2-patched R28 checkout.

Next: run live-validation-ubuntu1704.sh from this source tree with a fresh KLAB_LIVE_BASE to exercise the exact historical target, save the log, and diagnose any live failure. This remains pending.

## Inputs

R28 archive SHA-256: 65a01a04c48dfd194f69223318dbd84a8642dd4d17f1d99251abab07bf39a210
R25 root overlay SHA-256: 7c954fb326a636b5ee632fe77744295d28a4139812d332f118bdbac2abb25a9d (locally calculated; no independently supplied original checksum).

Working source: /home/reed/Documents/ChatGPT/Klab/work/r29
Local Library: /home/reed/Documents/ChatGPT/Klab/library/r29
This is a local Library checkpoint; no ChatGPT Library upload was performed.
