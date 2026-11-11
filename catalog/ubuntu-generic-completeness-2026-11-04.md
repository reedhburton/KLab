# Ubuntu x86_64 generic kernel completeness — 2026-11-04

Authoritative discovery used the package names currently published by the official Ubuntu repositories. All discovered rows have complete local KLab targets.

| Release | Published generic ABIs | Local | Missing |
|---|---:|---:|---:|
| 20.04 | 214 | 214 | 0 |
| 22.04 | 141 | 141 | 0 |
| 24.04 | 42 | 42 | 0 |
| 26.04 | 11 | 11 | 0 |

New security-update targets validated in native userspace:

| Target | Result | Portable bundle SHA-256 |
|---|---|---|
| `ubuntu:22.04:5.15.0-202-generic` | PASS | `ebc0af28b64cc5a9db57ce8d06b39d7201ed33460d535869fdfb3d9753dccecc` |
| `ubuntu:24.04:7.0.0-42-generic` | PASS | `154c7bac16328f3fb8c900a66a48e20a56db5601ba0b1e59d343271ccc992725` |
| `ubuntu:26.04:7.0.0-42-generic` | PASS | `8849840be14595124a9c011e8ca6e980301b19c935949442b5245b9ef4ce13f5` |

Evidence:

- Catalog: `/home/reed/klab/results/ubuntu-generic-current-2026-11-04.tsv`
- Validation: `/home/reed/klab/results/ubuntu-generic-security-refresh-2026-11-04/status.tsv`
- Unified inventory: `/home/reed/klab/results/current-target-inventory-2026-11-04.tsv`
