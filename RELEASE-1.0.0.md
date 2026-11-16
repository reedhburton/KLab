# KLab 1.0.0 release record

Release date: 2026-11-16

## Supported release boundary

- All 198 network-free shell regressions and the syntax-static gate pass.
- The live upstream ledger is green for 137/137 exact target/architecture pairs.
- Those live gates cover quick, minimal, and full userspaces, SSH, and guest networking.
- The broader 658-entry catalog remains available with explicit `validated`, `packaged`, and `local` states. Catalog presence alone is not a claim of full validation.

## Distribution

- Git source release and deterministic `klab-1.0.0.tar.gz`.
- Verified portable repository base: `klab-portable-2026-11-13.tar.zst`.
- The final 1.0.0 application package accompanies the portable base archive without rebuilding that 436 GiB base.

## Evidence

- Network-free release log: `/home/reed/klab-data/results/release-pass-2026-11-16/network-free-1.0.0.log`
- Upstream ledger: `/home/reed/klab-data/results/upstream-reconcile-2026-11-06/validation/status.tsv`
- Portable base summary: `/mnt/klab-cache/exports/klab-portable-2026-11-13.tar.zst.summary.txt`
