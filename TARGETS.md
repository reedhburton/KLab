# Finding a KLab target

KLab uses exact target IDs so a test can be repeated against the same operating-system
release, kernel build, and architecture. This page explains which list to use and what
each status means.

## What can I run on this machine?

```bash
./klab targets
```

This is the authoritative runtime list. It shows targets already imported into
`KLAB_ROOT`; these can be used without downloading anything.

To list portable bundles in the configured offline repository:

```bash
./klab repo list
```

A repository entry can be imported with `./klab load FILE.klab` or by loading the
whole repository with `./klab load`.

## What targets are known to this release?

The [complete catalog](catalog/current-target-inventory-2026-11-04.tsv) contains 658
exact target/architecture pairs. It is TSV so it remains easy to search, sort, or feed
to scripts. The [inventory summary](catalog/current-target-inventory-2026-11-04.md)
breaks the catalog down by provider, architecture, Ubuntu release, and state.

The release-candidate catalog includes:

| Family | Exact target/architecture pairs |
|---|---:|
| Ubuntu | 467 |
| Upstream Linux | 137 |
| Fedora | 18 |
| Debian | 8 |
| Alpine | 7 |
| CentOS | 5 |
| FreeBSD | 5 |
| NetBSD | 3 |
| OpenBSD | 2 |
| DragonFly BSD | 2 |
| Arch Linux | 4 |

## Status meanings

| State | Meaning |
|---|---|
| `validated` | Current validation evidence is recorded for that exact pair. |
| `packaged` | A portable `.klab` artifact exists; this alone does not claim every validation gate. |
| `local` | A complete local target directory exists, but packaging or current validation may still be needed. |

The 137-entry upstream validation ledger is completely green for this release pass.
Do not infer the same gate coverage for every entry merely because it appears in the
catalog. [RC14-RELEASE-PASS.md](RC14-RELEASE-PASS.md) records the exact release scope.

## Target ID examples

```text
upstream:v2.0.40                         # architecture is supplied separately
upstream:v6.6
ubuntu:24.04:6.8.0-142-generic
debian:bookworm:6.1.0-53-amd64
fedora:43:7.2.7-100.fc43.x86_64
alpine:3.23:6.18.57-0-lts
arch:rolling:7.2.11-arch1-1
freebsd:14.5-RELEASE:x86_64
netbsd:11.0:aarch64
openbsd:7.9:x86_64
dragonfly:6.4.2:x86_64
```

Commands that accept multiple targets use `TARGET@ARCH` when the architecture must be
part of one argument:

```bash
./klab test driver-test on \
  upstream:v6.6@x86_64 \
  ubuntu:24.04:6.8.0-142-generic@x86_64
```

Single-target commands normally use a separate option:

```bash
./klab validate upstream:v6.6 --arch x86_64 --level full
./klab build ubuntu:24.04:6.8.0-142-generic ./my-module --arch x86_64
```

## Filter the complete catalog

Show validated targets:

```bash
awk -F '\t' 'NR == 1 || $4 == "validated"' \
  catalog/current-target-inventory-2026-11-04.tsv | column -t -s $'\t'
```

Show Ubuntu 24.04 x86-64 kernels:

```bash
awk -F '\t' 'NR == 1 || ($1 ~ /^ubuntu:24[.]04:/ && $2 == "x86_64")' \
  catalog/current-target-inventory-2026-11-04.tsv | column -t -s $'\t'
```

Show every BSD target:

```bash
awk -F '\t' 'NR == 1 || $3 ~ /^(freebsd|netbsd|openbsd|dragonfly)$/' \
  catalog/current-target-inventory-2026-11-04.tsv | column -t -s $'\t'
```

If `column` is unavailable, omit the final pipe; the output remains valid TSV.
