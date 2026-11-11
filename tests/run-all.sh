#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
per_test="${KLAB_TEST_TIMEOUT:-60}"
test_home="$(mktemp -d)"
trap 'rm -rf "$test_home"' EXIT
export HOME="$test_home"
unset KLAB_ROOT KLAB_HOME KLAB_ROOT_LIB_LOADED KLAB_COMPAT_LINKS
fail=0
mapfile -t tests < <(find "$ROOT/tests" -maxdepth 1 -type f -name '*.sh' ! -name 'run-all.sh' -printf '%f\n' | sort)
for t in "${tests[@]}"; do
  printf '\n=== %s ===\n' "$t"
  if ! timeout "$per_test" "$ROOT/tests/$t"; then
    echo "FAIL: $t" >&2; fail=1
  fi
done
printf '\n=== syntax ===\n'
while IFS= read -r -d '' f; do bash -n "$f"; done < <(find "$ROOT" -type f -name '*.sh' -print0)
python3 -m py_compile "$ROOT"/apply-*.py "$ROOT"/lib/*.py
echo 'syntax-static: PASS'
(( fail == 0 )) || exit 1
echo 'ALL M2 NETWORK-FREE TESTS: PASS'
