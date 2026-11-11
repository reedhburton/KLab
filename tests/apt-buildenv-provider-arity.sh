#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# Buildenv capture does not accept a compiler-version argument. Under set -u,
# provider wrappers must not reference an undeclared compiler_version variable.
for p in ubuntu debian; do
  f="$ROOT/providers/$p.sh"
  line="$(grep "klab_provider_${p}_capture_buildenv" "$f")"
  [[ "$line" != *'compiler_version'* ]] || { echo "FAIL: $p buildenv wrapper references compiler_version" >&2; exit 1; }
done
# Toolchain capture intentionally does accept the optional compiler version.
for p in ubuntu debian; do
  grep -q "klab_provider_${p}_capture_toolchain.*compiler_version=\"\${4:-}\"" "$ROOT/providers/$p.sh" || { echo "FAIL: $p toolchain wrapper lost compiler_version" >&2; exit 1; }
done
bash -n "$ROOT/providers/ubuntu.sh" "$ROOT/providers/debian.sh"
echo 'PASS: APT buildenv provider wrappers match backend arity under set -u'
