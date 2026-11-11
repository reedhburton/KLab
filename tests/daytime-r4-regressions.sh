#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
die(){ echo "daytime-r4-regressions: ERROR: $*" >&2; exit 1; }

# Reconstructed Fedora repos must be consumable by vintage yum/dnf clients.
grep -Fq -- 'createrepo_c --quiet --compatibility --database --general-compress-type=gz /out/repo' "$ROOT/providers/fedora.sh" || die 'Fedora fallback repo is not generated in legacy-compatible mode'
grep -Fq 'REPODATA-COMPAT-V2' "$ROOT/providers/fedora.sh" || die 'existing Fedora fallback repo caches are not upgraded in place'
grep -Fq 'repo_args="--disablerepo=klab-koji-buildroot --disablerepo=klab-koji-package-fallback"' "$ROOT/providers/fedora.sh" || die 'Fedora release fallback still leaves failed Koji repos enabled'

# Fedora buildenv only needs the development-facing kernel RPMs, not kernel
# runtime/selftest payloads whose dependencies are irrelevant to module builds.
grep -Fq 'kernel-devel|kernel-headers|kernel-rpm-macros|kernel-srpm-macros' "$ROOT/providers/fedora.sh" || die 'Fedora kernel RPM filtering missing'
if grep -Fq 'install /pkgs/*.rpm' "$ROOT/providers/fedora.sh"; then
  die 'Fedora buildenv still installs every captured kernel RPM'
fi

# The captured buildenv must provide the conservative host-tool baseline.
# Fedora uses coreutils; minimal CentOS images may satisfy it with coreutils-single.
grep -A22 'klab_backend_dnf_capture_buildenv' "$ROOT/lib/backends/rpm.sh" | grep -Eq 'coreutils|coreutils-single' ||
  die 'DNF buildenv does not provide a coreutils host-tool baseline'

# Setup/install failures must stop before Kbuild/vermagic diagnostics.
grep -Fq '/bin/sh -lc "set -e' "$ROOT/lib/buildenv-capture.sh" || die 'buildenv setup/install is not fail-fast'
grep -Fq 'set +e' "$ROOT/lib/buildenv-capture.sh" || die 'Kbuild rc preservation missing after fail-fast setup'

# Family matching must distinguish 6.1 from 6.12 while accepting Debian +deb.
match_family(){ local pattern="$1" value="$2"; printf '%s\n' "$value" | grep -Eq "^${pattern//./\\.}([.+~-]|$)"; }
match_family 6.1 6.1.0-53-amd64 || die '6.1 family rejected'
! match_family 6.1 6.12.107+deb12-amd64 || die '6.1 family incorrectly matches 6.12'
match_family 6.12 6.12.107+deb13-amd64 || die '6.12 +deb family rejected'
grep -Fq '([.+~-]|$)' "$ROOT/klab-cross-distro-queue-v2.sh" || die 'cross-distro family boundary missing'

echo 'daytime-r4-regressions: PASS'
