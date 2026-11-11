# KLab daytime compatibility sweep

The daytime sweep is designed to run unattended for several hours, continue after individual failures, and leave one small review bundle that can be uploaded for analysis later.

## Default run

```bash
cd /path/to/klab-0.0.0b
export KLAB_ROOT="$HOME/klab"
./klab-daytime-sweep-v1.sh
```

It runs:

1. KLab staging initialization and doctor checks.
2. The three Ubuntu regression targets from the prior wide sweep.
3. Fedora 20, 23, 29, 42, 43 and 44 exact historical targets with distro-native toolchain/buildenv capture.
4. Fedora 29 and 44 with `KLAB_FEDORA_KOJI_FALLBACK=always` by default, so the direct package-build reconstruction path is exercised even if Koji still retains the original buildroot repo.
5. A broad cross-distro queue covering Mint/LMDE compatibility mappings, Debian, CentOS Stream, Arch, Manjaro, Oracle UEK, Amazon Linux, openSUSE, Kali, Proxmox, Rocky, AlmaLinux and Alpine.

Failures do not stop the sweep.

## Useful overrides

Run only the targeted Fedora tests:

```bash
KLAB_DAY_UBUNTU=0 KLAB_DAY_CROSS_DISTRO=0 ./klab-daytime-sweep-v1.sh
```

Force different Fedora releases through the package-build fallback:

```bash
KLAB_DAY_FORCE_FEDORA_FALLBACK=20,29,44 ./klab-daytime-sweep-v1.sh
```

Run only selected broad-distro sections:

```bash
KLAB_DAY_UBUNTU=0 KLAB_DAY_FEDORA=0 \
KLAB_DAY_CROSS_SECTIONS=arch,manjaro,amazon,opensuse,proxmox \
./klab-daytime-sweep-v1.sh
```

Disable Fedora direct reconstruction while retaining normal exact-repo behavior:

```bash
KLAB_FEDORA_KOJI_FALLBACK=never ./klab-daytime-sweep-v1.sh
```

## Results to upload

At completion the script prints a path similar to:

`$KLAB_ROOT/results/daytime-sweep-YYYYMMDDTHHMMSSZ-results.tar.gz`

Upload that one file. It contains logs, summaries, system information and artifact filenames, but deliberately excludes the large kernel and `.klab` payloads.

The persistent artifacts remain under:

- `$KLAB_ROOT/transfer/exports/daytime-sweep/`
- `$KLAB_ROOT/artifacts/`
- `$KLAB_ROOT/cache/fedora-koji-fallback/`

The latest top-level summary is copied to:

`$KLAB_ROOT/results/daytime-sweep-latest-summary.tsv`

## Disk use

The direct Fedora fallback can be large because it reconstructs the native/noarch package set of an actual historical Koji buildroot. The cross-distro captures also retain staged kernel/header trees. The runner warns when less than 20 GiB is free, but it does not abort so the operator can decide whether to continue.
