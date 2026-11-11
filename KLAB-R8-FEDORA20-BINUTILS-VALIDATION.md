# KLab r8 — Fedora 20 binutils runtime validation

## r7 live result

Focused retry `daytime-retry-r7-20260926T062826Z` produced:

- Fedora 23 / `4.4.9-300.fc23.x86_64`: **PASS** end-to-end. The buildenv was captured, smoke-tested, packed into a `.klab`, and `klab verify` passed.
- Fedora 20 / `3.14.9-200.fc20.x86_64`: **FAIL** only during the final read-only distro-native artifact smoke validation.

The Fedora 20 log reached:

- exact Koji GCC `4.8.3-1.fc20` download;
- exact Koji binutils `2.23.88.0.1-13.fc20` download;
- targeted historical runtime synchronization;
- successful initial module smoke (`KLAB_VINTAGE_STATUS=pass`);

and then failed with:

`distro-native assembler mismatch: expected 2.23.88.0.1`

This isolates the problem to the final validation rule, not compilation or Koji reconstruction.

## Root cause

For Fedora, `lib/fedora_koji.py` intentionally derives `as_version` and `ld_version` from the exact Koji `binutils` RPM Version field. The distro-native runtime validator was treating that RPM Version string as though it must appear verbatim in the first line of `as --version` and `ld --version`.

That assumption is not a reliable identity proof for old Red Hat/Fedora binutils snapshot packages. Fedora 20's exact package is `binutils-2.23.88.0.1-13.fc20`, but the executable banner need not reproduce the RPM Version string verbatim. The artifact already seals the exact RPM set and package inventory.

## r8 change

For Fedora distro-native execution only, final runtime validation now:

1. verifies `/usr/bin/as` and `/usr/bin/ld` are owned by the `binutils` RPM;
2. verifies the installed `binutils` RPM `%{VERSION}` equals the Koji-derived expected version for both assembler and linker;
3. verifies `as --version` and `ld --version` execute successfully;
4. retains the prior banner-string comparison for all non-Fedora providers.

This keeps Fedora's identity check tied to the exact package-manager provenance that produced the tool while avoiding a false equivalence between RPM Version metadata and GNU tool banner formatting.

## Scope

No Fedora package-selection, Koji reconstruction, historical runtime synchronization, kernel capture, or build logic changed in r8. Fedora 23 and Fedora 29+ remain on their already-working paths. The live retry therefore targets Fedora 20 only.

## Local validation

Passed:

- `tests/fedora-binutils-runtime-validation.sh`
- `tests/fedora-koji-buildroot.sh`
- `tests/fedora-vintage-root-sync.sh`
- `tests/wide-sweep-regressions.sh`
- `tests/provider-contract.sh`
- `tests/provider-compat-hardening.sh`
- `tests/distro-toolchain-wiring.sh`
- `tests/buildenv-distro-native-binding.sh`
- `tests/rpm-signature-provenance.sh`
- `tests/toolchain-boundary.sh`
- `tests/vintage-relocation-validation.sh`
- all shell syntax checks
- Python module compilation
