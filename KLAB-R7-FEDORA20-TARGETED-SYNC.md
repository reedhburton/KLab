# KLab r7 — Fedora 20 targeted historical runtime synchronization

## r6 result

Focused r6 retry (`daytime-retry-r6-20260926T061413Z`) produced:

- Fedora 23 / 4.4.9-300.fc23.x86_64: **PASS** — buildenv created, module smoke passed, `.klab` packed and verified.
- Fedora 20 / 3.14.9-200.fc20.x86_64: **FAIL** during the historical `distro-sync` transaction.

The Fedora 20 failure is no longer a Koji download, kernel identity, compiler selection, or fallback-repository problem. Yum attempted to downgrade `rpm` from 4.11.3-3.fc20 to the buildroot-era 4.11.2-2.fc20, while the container's installed `rpm-python-4.11.3-3.fc20` requires exactly `rpm = 4.11.3-3.fc20`. This makes a whole-root distro-sync self-conflicting.

## r7 change

r7 stops synchronizing the entire Fedora execution image. For vintage Fedora (<=23), KLab synchronizes only:

1. installed `glibc` / `glibc-common`, and
2. already-installed packages whose names are present in the exact Koji-pinned compiler/binutils/make artifact.

The candidate set is resolved only against the selected exact Koji source (original buildroot or reconstructed fallback). KLab deliberately leaves the package-manager control plane (`rpm`, `rpm-python`, Yum/DNF, Python) alone.

This directly addresses the actual r5 incompatibilities (`glibc`, `libstdc++`, compiler runtime packages) without trying to downgrade Yum's own runtime underneath itself.

## Validation

Passed locally:

- `tests/fedora-vintage-root-sync.sh`
- `tests/fedora-koji-buildroot.sh`
- `tests/wide-sweep-regressions.sh`
- `tests/provider-contract.sh`
- `tests/provider-compat-hardening.sh`
- `tests/distro-toolchain-wiring.sh`
- `tests/rpm-signature-provenance.sh`
- `tests/toolchain-boundary.sh`
- all shell syntax checks
- Python module compilation

No Docker/Podman is available in the assistant environment, so Fedora 20 must still be live-validated on the user's host.

## Retry sequence

Run `./klab-daytime-retry-r7.sh` first. It reuses the fetched Fedora 20/23 kernel targets and reconstructed Koji RPM caches. If both pass, run `./klab-overnight-regression-v3.sh` from the same r7 tree.
