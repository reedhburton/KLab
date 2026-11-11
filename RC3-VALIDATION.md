# KLab 1.0.0-rc3 validation

Date: 2026-10-16

RC3 retains the complete RC2 platform evidence: six modern Linux architectures pass fresh-root offline import/repack, build, boot, userspace, modules, routed networking, and coordinated-process tests; every required Linux 2.x target meets its declared gate; and the 12-row BSD matrix passes.

## Buildenv V4 dependency provenance

Buildenv V4 adds:

- exact SHA-256 coverage for every retained DEB, RPM, or APK archive;
- package name/version/architecture equality between the archive closure and realized installed inventory;
- retained repository snapshot metadata bytes with verified digests;
- artifact-ID binding for closure manifests, repository provenance, and archive-tree content;
- imported archive retention and installed-object tamper detection;
- an offline `tools/seal-dependency-closure.py` tool using real package metadata;
- backward-compatible V1–V3 verification/import and V3 creation when no closure is supplied.

A real DEB fixture and synthetic V4 artifact exercise sealing, deep verification, import, archive tampering, repository-metadata tampering, incomplete closure rejection, mismatched provenance rejection, and V3 compatibility.

## Regression result

- 121 network-free checks: PASS
- Shell and Python syntax: PASS
- Final marker: `ALL M2 NETWORK-FREE TESTS: PASS`
- Evidence: `library/releases/klab-1.0.0-rc3-f16-v4-network-free.log` in the development workspace.

## Remaining final-1.0 work

Live APT, RPM, and APK provider paths still need to download the exact complete installed closure and feed it into V4 automatically. That must be validated against representative current and historical repositories before final 1.0 can claim full from-archive reconstruction provenance for distribution build roots.
