#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
die(){ echo "daytime-r5-regressions: FAIL: $*" >&2; exit 1; }

fed="$ROOT/providers/fedora.sh"
be="$ROOT/lib/buildenv-capture.sh"

grep -Fq 'set -- /klab-distro-toolchain-packages/*.rpm' "$fed" || die 'Fedora exact toolchain package installation is missing'
! grep -Fq 'install_aux dnf' "$fed" || die 'Fedora still installs dnf auxiliary RPM set'
! grep -Fq 'install_aux yum' "$fed" || die 'Fedora still installs yum auxiliary RPM set'
grep -Fq 'yum -y -q $repo_args localinstall $kernel_rpms' "$fed" || die 'legacy yum flags are not split for old yum compatibility'
grep -Fq 'if [ -z \"\$vm\" ] && command -v strings' "$be" || die 'native buildenv vermagic strings fallback missing'
grep -Fq '$KLAB_TC_STRINGS "$ko"' "$be" || die 'sealed-toolchain vermagic strings fallback missing'

echo 'daytime-r5-regressions: PASS'
