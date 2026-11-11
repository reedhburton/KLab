# KLab 0.0.0b wide-sweep fixes + Fedora Koji fallback r2

Date: 2026-09-25
Base: `klab-0.0.0b-widefix-fedora-koji-r1`

This checkpoint keeps the r1 fixes and adds the second Fedora historical-dependency path plus unattended broader-distro validation.

## Fedora r2: retained-build reconstruction

When the exact Koji `tag/repo_id/arch` buildroot repository is gone, KLab can now reconstruct an equivalent package source from the buildroot inventory already captured in `koji-buildroot.json`.

The helper lazily resolves native/noarch inventory rows back to exact Koji RPM/build IDs only when fallback is needed. The modern Koji client downloads each unique retained source build, KLab prunes the downloads to the exact recorded RPM filenames, `createrepo_c` generates a local repo, and the result is cached by buildroot package-inventory SHA-256.

`KLAB_FEDORA_KOJI_FALLBACK=auto|always|never` controls the behavior. `always` exists specifically so this path can be tested before an original repo expires.

`KLAB_FEDORA_STRICT_BUILDROOT_REPO=1` accepts either the original exact Koji repo or this exact reconstructed package source; it rejects release-repository fallback.

A generic read-only auxiliary-repository mount was added to buildenv capture through `KLAB_BUILDENV_AUX_REPO_DIR` so reconstructed package sources are not copied into kernel package sets or distro-toolchain artifacts.

## Broader distro testing

`klab-cross-distro-queue-v2.sh` covers:

- Mint/LMDE compatibility mappings
- Debian normal/cloud/RT
- CentOS Stream 9/10
- Arch standard/LTS/Zen/hardened
- Manjaro 6.1/6.6/6.12/6.18/7.2
- Oracle Linux UEK 8/9/10
- Amazon Linux 2023 6.1/6.12/6.18
- openSUSE Leap 15.6/16.0 and Tumbleweed
- Kali rolling
- Proxmox VE 8 6.8 and VE 9 6.14/6.17/7.0
- Rocky Linux 9/10
- AlmaLinux 9/10
- Alpine LTS/virt

External distributions remain exploratory custom-target captures. They do not yet claim the same distro-native compiler provenance guarantees as first-class KLab providers.

## Daytime runner

`klab-daytime-sweep-v1.sh` combines the original Ubuntu regressions, representative Fedora historical generations, forced Fedora fallback coverage (F29 and F44 by default), and the broad cross-distro queue. It never stops on an individual target failure and produces a compact results tarball for later review.

## Validation in this environment

PASS:

- `tests/wide-sweep-regressions.sh`
- `tests/fedora-koji-buildroot.sh`
- `tests/daytime-sweep-wiring.sh`
- provider contract/routing
- provider compatibility hardening
- distro-toolchain wiring
- APT list/candidate regression
- RPM signature provenance
- shell syntax for all `.sh` files
- Python bytecode compilation for `lib/*.py`

The fake-Koji test now additionally validates fallback-plan construction, source-build deduplication, exact RPM filename mapping, and pruning of unrelated downloaded RPMs.

A live Koji/container fallback reconstruction still requires the staging host; that is the purpose of the new daytime run.
