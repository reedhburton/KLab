#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export KLAB_ROOT="$T/lab"
base="$ROOT/examples/scenarios/multiprocess-basic.json"
for arch in x86_64 aarch64; do
  s="$T/$arch.json"
  python3 - "$base" "$s" "$arch" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]));x['arch']=sys.argv[3];json.dump(x,open(sys.argv[2],'w'))
PY
  out="$("$ROOT/kernel-lab.sh" scenario-run "$s" --dry-run --report-dir "$T/report-$arch")"
  grep -q "^arch=$arch$" <<<"$out"
  [[ -f "$T/report-$arch/report.json" ]]
done
for arch in mips; do
  s="$T/$arch.json"
  python3 - "$base" "$s" "$arch" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]));x['arch']=sys.argv[3];json.dump(x,open(sys.argv[2],'w'))
PY
  out="$(KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 KLAB_ENABLE_EXPERIMENTAL_E2E=1 "$ROOT/kernel-lab.sh" scenario-run "$s" --dry-run --report-dir "$T/report-$arch")"
  grep -q "^arch=$arch$" <<<"$out"
done
echo 'PASS: scenario dry-run architecture contract'
