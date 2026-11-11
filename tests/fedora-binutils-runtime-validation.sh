#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/klab-buildenv.sh"
grep -Fq 'if [ "${11}" = fedora ]; then' "$f" || { echo 'Fedora binutils runtime special-case missing' >&2; exit 1; }
grep -Fq 'rpm -qf --qf "%{NAME}" "$as"' "$f" || { echo 'Fedora assembler ownership proof missing' >&2; exit 1; }
grep -Fq 'rpm -q --qf "%{VERSION}" binutils' "$f" || { echo 'Fedora binutils RPM version proof missing' >&2; exit 1; }
grep -Fq '"$ka" "$expect_provider"' "$f" || { echo 'run-module-native does not pass provider into sealed runtime validator' >&2; exit 1; }
# Fedora metadata deliberately records Koji RPM Version for as/ld; preserve this
# contract and do not weaken the provenance source to a live release image.
grep -Fq '"as_version": bin_version' "$ROOT/lib/fedora_koji.py" || { echo 'Fedora as version is no longer Koji-derived' >&2; exit 1; }
grep -Fq '"ld_version": bin_version' "$ROOT/lib/fedora_koji.py" || { echo 'Fedora ld version is no longer Koji-derived' >&2; exit 1; }
echo 'fedora-binutils-runtime-validation: PASS'
