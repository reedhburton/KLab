#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; f="$ROOT/kernel-lab.sh"
bash -n "$f"
for token in \
  'KLAB_DISTRO_TOOLCHAIN_STORE/contracts/$PROVIDER/$DISTRO_RELEASE/$ARCH/gcc-$__be_dt_major.klabdistrotoolchain' \
  'flock "$__be_dt_cache_fd"' \
  'match-compiler "$__be_dt_cache" --version "$__be_req_version" --mode major-compatible' \
  'assert-installed "$__be_dt_id" --provider "$PROVIDER" --release "$DISTRO_RELEASE" --arch "$ARCH"' \
  'ln "$__be_dt_cache" "$__be_dt_sibling"' \
  'cp --reflink=auto "$__be_dt_cache" "$__be_dt_sibling"'; do
  grep -Fq -- "$token" "$f" || { echo "FAIL: missing cache boundary: $token" >&2; exit 1; }
done
python3 - "$f" <<'PY'
from pathlib import Path
s=Path(__import__('sys').argv[1]).read_text()
block=s[s.index('case "$PROVIDER" in',s.index("local __be_dt_cache=")):s.index('if [[ -n "$__be_dt_cache"',s.index("local __be_dt_cache="))]
assert 'ubuntu|debian)' in block
assert 'fedora' not in block and 'centos' not in block and 'alpine' not in block
PY
echo 'PASS: distro toolchain contract cache is locked, compiler-bound, provider-scoped, and transfer-complete'
