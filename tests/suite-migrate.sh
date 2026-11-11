#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
D="$T/root/suites/old"; mkdir -p "$D/module"; printf 'obj-m += x.o\n' > "$D/module/Makefile"; printf '#!/bin/sh\nexit 0\n' > "$D/test.sh"; chmod +x "$D/test.sh"
cat > "$D/suite.json" <<'JSON'
{"schema":"klab-suite-v1","name":"old","kind":"module","module":"module","script":"test.sh","architectures":["*"],"capabilities":["module"]}
JSON
KLAB_ROOT="$T/root" "$ROOT/klab" suite migrate old >/dev/null
[[ -f "$D/suite.v1.json" && -f "$D/scenario.json" ]]
grep -q 'klab-suite-v2' "$D/suite.json"
python3 "$ROOT/lib/suite_plan.py" validate "$D/suite.json" >/dev/null
echo 'PASS: legacy local suite migrates once to unified schema'
