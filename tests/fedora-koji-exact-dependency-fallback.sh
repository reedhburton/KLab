#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/lib/backends/rpm.sh"
grep -Fq 'KLAB_RPM_KOJI_PACKAGE_BASE:-https://kojipkgs.fedoraproject.org/packages' "$F"
grep -Fq "source_rpm=\$(rpm -q --qf '%{SOURCERPM}' \"\$package\")" "$F"
grep -Fq 'case "$koji_evr" in *:*) koji_evr=${koji_evr#*:};; esac' "$F"
grep -Fq 'source_name=${source_nvr%-$koji_evr}' "$F"
grep -Fq 'koji_version=${koji_evr%-*}' "$F"
grep -Fq 'koji_release=${koji_evr##*-}' "$F"
grep -Fq 'curl -fsSL "$koji_url" -o "$out/packages/$expected_file"' "$F"
identity_line="$(grep -nF 'identity=$(rpm -qp' "$F" | head -n1 | cut -d: -f1)"
fallback_line="$(grep -nF 'koji_url="$koji_base/' "$F" | head -n1 | cut -d: -f1)"
[[ "$identity_line" -gt "$fallback_line" ]]
bash -n "$F"
echo 'PASS: Fedora Koji fallback retains exact identity and payload verification'
