# KLab r17.2 focused retry
Built from r17.1 plus its returned result archive.

Fixes:
- install-m2.sh now deploys lib/arch-model.sh, not merely the temporary preflight copy.
- focused live cases perform prepare before test.
- prepare and test have separate result rows/logs.
- a failed prepare records SKIP_PREPARE_FAILED instead of generating a misleading test failure.
- installer and resume regressions run with bash -x so failures retain diagnostics.
- existing KLAB_ROOT is reused, preserving caches/acquired artifacts.

Live targets:
- ubuntu:12.04:3.2.0-126-generic x86_64
- fedora:26:4.11.8-300.fc26.x86_64 x86_64
- upstream:v4.9 x86_64 normal

Validation:
- bash -n passes for modified runner/installer and regression scripts.
- No live distro/QEMU success is claimed from the sandbox.
