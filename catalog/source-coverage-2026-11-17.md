# Kernel source coverage (2026-11-17)

Exact target/architecture pairs audited: **658**.

| Coverage | Targets | Meaning |
|---|---:|---|
| Full source tree | 137 | An unpacked matching source tree is present. |
| Full source archive | 8 | A matching official source archive is present. |
| Module build tree | 509 | Exact headers/generated files support external modules; full implementation source is pending. |
| Runtime only | 4 | Runtime image exists; matching source still needs acquisition. |
| Missing | 0 | Neither a source nor module build tree was found. |

The acquisition queue is primarily distribution source packages: {'alpine': 7, 'arch': 4, 'centos': 5, 'debian': 8, 'fedora': 18, 'ubuntu': 467}.
Source objects use the content-addressed `.klabsource` format and may be shared by many target/architecture pairs.

## Remaining runtime-only source acquisitions

- `freebsd:14.5-RELEASE:i386@i386`
- `freebsd:14.5-RELEASE:riscv64@riscv64`
- `openbsd:7.9:aarch64@aarch64`
- `openbsd:7.9:x86_64@x86_64`

Exact rows and provenance: [`source-coverage-2026-11-17.tsv`](source-coverage-2026-11-17.tsv).
