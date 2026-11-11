# Controller suite validation — 2026-10-21

The controller-side Bash suite interface is staged for pre-v1 review.

## Proven live matrix

- Linux: 52/52 imported targets passed the release gate, including Alpine, CentOS, Debian, Fedora 20–44, Ubuntu 12.04–26.04, x86_64, and aarch64.
- Each Linux target built and inserted a kernel module, transferred declarative and runtime files, ran quoted guest shell commands, handled expected nonzero exits, coordinated a background process through readiness and completion, and returned output for controller-side assertions.
- Evidence: `/media/reed/ESD-ISO/KLab-Verification/controller-suite-2026-10-21/all-linux-attempt4-bounded/status.tsv`.

## FreeBSD retained-image boundary

Three retained FreeBSD targets were exercised: 14.5 x86_64, 15.1 x86_64, and 15.1 aarch64. Boot succeeds and the EXEC-based transfer path can upload a declared file. A later RPC is intermittently lost by the serial control path, so the multi-command controller gate is not proven on these three images. Failure attempts and console evidence are preserved under `/media/reed/ESD-ISO/KLab-Verification/controller-suite-2026-10-21/all-freebsd-attempt*`.

The source now closes exec and boot-readiness streams explicitly, routes FreeBSD push through the existing EXEC uploader, and prevents Linux-only `--preload` use for FreeBSD. Network-free regression coverage passes, but these retained images still need a rebuilt guest agent or a persistent/transactional FreeBSD controller transport before they can be marked green for this new suite interface.

## Regression result

`./tests/run-all.sh` completed with `ALL M2 NETWORK-FREE TESTS: PASS` after the controller and transport changes.
