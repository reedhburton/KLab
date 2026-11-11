# R28 alternatives regression checkpoint

R27 input archive SHA-256 verified: dbe03b343afe0c8b13b27b5d34c3edd5c8bf4310a6afdbbf10bacd64a4a00619.

Reproduced the failure at the RPM literal assertion. Two fixed-string assertions mistakenly required double backslashes; the production script correctly uses single backslashes. Corrected both assertions without changing production code or weakening ownership/provenance checks. Replaced the independent Python symlink model with execution of the actual capture shell block using an isolated PATH and Debian/RPM package-query stubs. Covers final-target query arguments, TSV contents, rejection of unowned targets (67), and broken executable links (66).

Validation: targeted regression PASS; all 53 network-free shell tests PASS; shell and Python syntax PASS. Full output and the original failure trace are saved beside this checkpoint. No live Ubuntu or QEMU validation was run. Target remains Ubuntu 17.04 / 4.10.0-42-generic / kernel-recorded GCC 6.3.0.

All R27 production files are preserved byte-for-byte. RELEASE.txt corrected from stale R26 to R28. The separate R25 unified-root overlay was not found in Downloads, the local project mirror, or the searched home files. It is NOT included or validated in this vintage checkpoint; recover that artifact before attempting unified-root integration. Do not confuse the vintage R25 archive with the root-layout R25 overlay.

Continuation: working source is /home/reed/Documents/ChatGPT/Klab/work/r28. Saved local library is /home/reed/Documents/ChatGPT/Klab/library/r28. Next recover the separate root overlay and validate live Ubuntu using live-validation-ubuntu1704.sh when ready. This is a local Library checkpoint; no ChatGPT Library upload was performed.
