# KLab r5 — Fedora 20/23 vintage buildenv follow-up

## r4 result

The r4 focused retry produced 9 PASS and 2 FAIL results. Fedora 29, 42, 43 and 44 passed; CentOS Stream 9/10 passed; and the Debian Bookworm 6.1 resolver correctly selected 6.1.0-53-amd64 rather than a 6.12 kernel.

Only Fedora 20 and Fedora 23 remained.

## Exact remaining failure

Both vintage Fedora targets successfully:

- reused the exact fetched kernel target;
- resolved the historical Koji buildroot;
- resolved/downloaded the correct historical GCC/binutils/make builds;
- found/upgraded the reconstructed Koji fallback repository.

The failure occurred because KLab attempted to install a broad set of **KLab-only auxiliary RPMs** (kmod/module-init-tools, OpenSSL/ELF development packages, flex/bison, etc.). Those are not required to build an external module from a prepared `kernel-devel` tree. When one was absent from the reconstructed historical package set, KLab fell back to the release repositories while leaving the expired `klab-koji-buildroot` repository enabled. Fedora 20 then retried the known-dead Koji repo and Fedora 23 failed cache synchronization for the same repo.

## r5 correction

r5 removes that unnecessary auxiliary-package injection from the Fedora historical buildenv. The local kernel-devel/header RPMs and exact Koji compiler RPMs retain their own dependency declarations and resolve those dependencies against the exact/reconstructed Koji buildroot.

KLab previously installed kmod primarily so `modinfo -F vermagic` could validate the smoke module. r5 removes that artificial dependency by falling back to the ELF module's `vermagic=` string using `strings` when `modinfo` is unavailable. The sealed-toolchain smoke path uses the sealed toolchain's own `strings` binary for the same check.

For old yum compatibility, generated Fedora buildenv transactions now use split `-y -q` flags rather than the merged `-qy` form that Fedora 20 warned about.

## Focused validation

Network-free regression checks pass for:

- daytime-r5 regressions;
- daytime-r4 and r3 regressions;
- Fedora Koji buildroot/fallback wiring;
- provider contract/routing;
- RPM provenance;
- distro-native buildenv binding;
- distro-toolchain wiring;
- shell syntax and Python compilation.

## Retry scope

`klab-daytime-retry-r5.sh` runs only Fedora 20 and Fedora 23. It sets:

```text
KLAB_REFETCH=0
KLAB_FEDORA_KOJI_FALLBACK=always
KLAB_FEDORA_STRICT_BUILDROOT_REPO=1
```

so fetched kernel targets and reconstructed Koji package caches are reused and no release-repository fallback is accepted. Fedora 29+ and CentOS are not rerun.
