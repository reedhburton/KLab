# NetBSD/OpenBSD three-mode validation — 2026-10-23

KLab exposes `klab run TARGET --mode minimal|ssh|full` for retained BSD targets.

BSD kernels and their base userlands are coupled releases. Therefore `minimal` is the smallest supported native base runtime with networking disabled, rather than Linux BusyBox/Buildroot. `ssh` uses that native base with restricted QEMU user networking and an ephemeral Ed25519 key. `full` boots the complete captured native release. Derived installed disks are checksum-verified and boot only through disposable overlays.

| Target | minimal | SSH host login | full native |
|---|---|---|---|
| NetBSD 11.0 amd64 | PASS | PASS | PASS |
| NetBSD 11.0 i386 | PASS | PASS | PASS |
| NetBSD 11.0 arm64 | PASS | PASS | PASS |
| OpenBSD 7.9 amd64 | PASS | PASS | PASS |
| OpenBSD 7.9 arm64 | PASS | PASS | PASS |

The SSH gate requires the host OpenSSH client to execute `uname -s; printf KLAB_BSD_SSH_OK` inside the guest. A serial marker alone is insufficient. Full and minimal logs are stored under `/home/reed/klab/results/bsd/TARGET/{full,minimal}`; SSH serial and client logs are under the corresponding `ssh` directory.

The first-generation smoke harness booted three derived installed disks directly, allowing boot-time filesystem repair to change their content. They were explicitly re-pinned and recorded in `/home/reed/klab-offline/bsd/DERIVED-DISK-REPINS-2026-10-23.txt`. All current harness paths use disposable overlays, and post-sweep hashes still match the pinned metadata.
