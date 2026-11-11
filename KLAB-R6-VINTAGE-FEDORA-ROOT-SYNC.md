# KLab r6 — vintage Fedora historical-root synchronization

## r5 result

The focused Fedora 20/23 r5 retry still failed, but it proved the remaining issue is not Koji identity, fallback reconstruction, or compiler selection.

Fedora 20 used a later container update state (`glibc-2.18-19.fc20`, `libstdc++-4.8.3-7.fc20`) while the kernel's recorded Koji buildroot required earlier exact packages (`glibc-2.18-12.fc20`, `libstdc++-4.8.3-1.fc20`). Fedora 23 had the same class of mismatch: the exact GCC package could not install because its matching historical glibc-devel/runtime state was not present.

## r6 change

For numeric Fedora releases <= 23, after selecting either the retained exact Koji repo or the reconstructed package fallback, KLab now runs the package manager's `distro-sync` against **only that Koji-backed source** before installing kernel-devel and the exact compiler/binutils/make packages.

This allows the historical execution root to downgrade/upgrade installed packages to the versions present at the kernel build event instead of mixing final Fedora update packages with an earlier buildroot.

The synchronization is deliberately vintage-only. Fedora 29/42/43/44 already passed in r4 and are left unchanged.

## Validation

Network-free checks passed:

- `tests/fedora-vintage-root-sync.sh`
- `tests/fedora-koji-buildroot.sh`
- `tests/wide-sweep-regressions.sh`
- provider contract/routing
- provider compatibility hardening
- distro-toolchain wiring
- RPM provenance
- toolchain boundary
- shell syntax and Python compilation

Live Fedora 20/23 validation is still required on the user's KLab host.

## Next run

Run `./klab-daytime-retry-r6.sh`. It retries only Fedora 20 and Fedora 23 and reuses the existing fetched kernel and reconstructed Koji package caches.

If both pass, proceed directly to `./klab-overnight-regression-v2.sh` from this same r6 source tree.
