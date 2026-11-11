# KLab 1.0.0-rc14 release pass

Date: 2026-11-11

## Result

KLab 1.0.0-rc14 is ready to cut as a release candidate. A final 1.0.0 release is defensible with the support boundary below; the broader catalog must remain labeled packaged or experimental until equivalent evidence exists.

## Verified gates

- All 198 network-free shell regressions passed, followed by the syntax-static gate and the final `ALL M2 NETWORK-FREE TESTS: PASS` marker.
- The upstream live-validation ledger is green for 137 of 137 exact target/architecture entries. Its gates cover quick, minimal, full userspace, SSH, and network modes.
- The release archive is built deterministically twice and compared byte-for-byte.
- The archive `MANIFEST.sha256` verifies after extraction.
- Installation from the extracted package passes `tests/installer-smoke.sh`.
- The staged Git diff passes `git diff --cached --check`, excluding historical patch payloads whose whitespace is part of their archived content.
- No embedded private-key markers or source files larger than 5 MiB were found.

## Support boundary

The current catalog contains 658 exact target/architecture entries. The 137-entry upstream matrix has current complete evidence. Other catalog entries are available as packaged or experimental targets and are not claimed fully supported solely by this release pass.

## Evidence

- Network-free log: `/home/reed/klab-data/results/release-pass-2026-11-11/network-free-release-tree.log`
- Upstream ledger: `/home/reed/klab-data/results/upstream-reconcile-2026-11-06/validation/status.tsv`
- Linux 2.0 final report: `/home/reed/klab-data/results/upstream-reconcile-2026-11-06/focused-v2.0.40-full-20261111T154736Z`
- Final archive and checksum are stored in `/home/reed/Documents/ChatGPT/Klab/release-pass/`.

## Cut decision

The code and packaging gates are clear for `1.0.0-rc14`. Cutting `1.0.0` should retain this documented support boundary and should not describe all 658 catalog entries as fully validated.
