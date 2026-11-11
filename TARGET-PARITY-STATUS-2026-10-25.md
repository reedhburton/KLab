# KLab target parity status — 2026-10-25

KLab's retained imported baseline is fully green: 59 of 59 canonical targets passed the full validation gate (56 Linux and 3 FreeBSD; 55 x86_64 and 4 aarch64). The full gate subsumes standard validation and covers the target's applicable kernel-module build/load checks, ordered and concurrent process workloads, two-guest TCP, native userspace, and authenticated SSH checks.

The first popular-distribution expansion target, `alpine:3.18:6.1.175-0-lts` on x86_64, also passed the full gate. The current store therefore reports 60 of 60 canonical targets as standard- and full-runnable. This is an expansion checkpoint, not a v1 release declaration.

Evidence:

- Retained matrix: `/home/reed/Documents/ChatGPT/Klab/library/all-target-full-validation-2026-10-24/status.tsv`
- Alpine expansion report: `/home/reed/Documents/ChatGPT/Klab/library/popular-distro-expansion-2026-10-25-attempt3/reports/alpine-3.18-6.1.175-0-lts-x86_64`
- Final network-free suite: `/home/reed/Documents/ChatGPT/Klab/library/network-free-after-expansion-fix2-2026-10-25.log` (`ALL M2 NETWORK-FREE TESTS: PASS`)

The resumable expansion catalog covers Alpine 3.18–3.22, Debian Bullseye/Bookworm/Trixie, Fedora 39/41/43, CentOS Stream 9/10, and Ubuntu 20.04/22.04/24.04/26.04, including selected Ubuntu aarch64 releases. Each retained expansion row captures native userspace, prepares an offline `.klab` with SDK/toolchain material, and must pass full validation before receiving PASS.

## Fine-grained Ubuntu expansion

Ubuntu 20.04, 22.04, and 24.04 now retain every repository-visible `-generic` ABI for x86_64 and aarch64. The 2026-10-25 scan found 395 exact targets per architecture: 214 for 20.04, 140 for 22.04, and 41 for 24.04. Across x86_64 and aarch64 this contributes 790 fine-grained Ubuntu rows to the 813-row expansion queue. See `UBUNTU-FINE-GRAIN-CATALOG.md`.
