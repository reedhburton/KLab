# KLab 0.0.0b r17.3 corrected checkpoint

Based on the r17.3 focused-retry archive found in Downloads.

- Corrects sourced klab-bundle path resolution.
- Updates the r16 resume regression for the expanded disabled matrix while retaining duplicate-row detection through invariant row counts.
- Makes the r16 kernel matrix test independent of the caller working directory.
- Removes stale Python bytecode and an accidental temporary runner copy.
- Regenerates the package SHA256SUMS manifest.
- All 102 network-free shell tests and static syntax checks pass.
