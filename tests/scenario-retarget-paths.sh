#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/template/sub" "$t/output" "$t/template/mod"
printf 'int main(void){return 0;}\n' > "$t/template/worker.c"
cat > "$t/template/sub/input.json" <<JSON
{"schema":"klab-scenario-v1","target":"upstream:v1","arch":"x86_64","builds":[{"id":"w","source":"../worker.c","remote":"/tmp/w"}],"modules":[{"id":"m","source_dir":"../mod"}],"files":[{"source":"../worker.c","remote":"/tmp/input"}],"processes":[]}
JSON
"$ROOT/lib/scenario_retarget.py" "$t/template/sub/input.json" "$t/output/case.json" upstream:v6.6 aarch64
python3 - "$t/output/case.json" "$t/template/worker.c" "$t/template/mod" <<'CHECKPY'
import json,os,sys
x=json.load(open(sys.argv[1])); assert x['target']=='upstream:v6.6'; assert x['arch']=='aarch64'
assert x['builds'][0]['source']==os.path.abspath(sys.argv[2])
assert x['modules'][0]['source_dir']==os.path.abspath(sys.argv[3])
assert x['files'][0]['source']==os.path.abspath(sys.argv[2])
CHECKPY
grep -Fq 'lib/scenario_retarget.py' "$ROOT/klab-scenario-overnight-r14.sh"
echo 'PASS: generated scenario paths remain anchored to the template directory'
