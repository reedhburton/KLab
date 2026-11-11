# Ubuntu fine-grained kernel catalog

KLab retains every repository-visible x86_64 `-generic` kernel ABI for Ubuntu 20.04, 22.04, 24.04, and 26.04. `all` in the expansion matrix means no newest-N truncation is applied after exact package discovery.

A live official-repository scan on 2026-11-04 found and locally validated:

| Ubuntu release | Published generic ABIs | Local targets | Missing |
| --- | ---: | ---: | ---: |
| 20.04 | 214 | 214 | 0 |
| 22.04 | 141 | 141 | 0 |
| 24.04 | 42 | 42 | 0 |
| 26.04 | 11 | 11 | 0 |

These 408 exact x86_64 ABI releases are present as complete local targets. The three packages newly published since the prior scan (`22.04/5.15.0-202`, `24.04/7.0.0-42`, and `26.04/7.0.0-42`) also passed exact native boot and command-transport validation and were exported as verified portable `.klab` bundles.

Repository contents can change. Regenerate the package catalog rather than assuming these counts remain fixed. Each catalog run preserves the exact discovered list and each queue run preserves per-target evidence. Historical packages removed from current repositories remain separately retained when already downloaded, but are not counted as currently published packages.

AArch64 availability is tracked separately and must not be inferred from the x86_64 package list: Ubuntu repositories can expose different architecture-specific ABI sets.
