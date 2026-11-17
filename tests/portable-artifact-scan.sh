#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stage" "$T/repo/bsd/netbsd_11.0_x86_64"
printf 1 > "$T/stage/FORMAT_VERSION"
printf '%s\n' '{"target":"upstream:v6.6","arch":"armv7","kernel_release":"6.6.0"}' > "$T/stage/manifest.json"
tar -C "$T/stage" --zstd -cf "$T/repo/upstream.klab" FORMAT_VERSION manifest.json
printf '%s\n' 'TARGET=netbsd:11.0:x86_64' > "$T/repo/bsd/netbsd_11.0_x86_64/target.env"
python3 "$ROOT/tools/klab-scan-portable.py" "$T/repo" -o "$T/out.tsv" | grep -Fq 'artifacts=2 mapped=2 errors=0'
python3 - "$T/out.tsv" <<'PY'
import csv,sys
r={(x['target'],x['arch']):x for x in csv.DictReader(open(sys.argv[1]),delimiter='\t')}
assert ('upstream:v6.6','armv7') in r
assert ('netbsd:11.0:x86_64','x86_64') in r
PY
echo 'portable-artifact-scan: PASS'
