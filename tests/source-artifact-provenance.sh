#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/src"; printf 'obj-m += example.o\n' > "$T/src/Makefile"
KLAB_ROOT="$T/root" KLAB_HOME="$T/root" "$ROOT/klab-artifact.sh" create source --from "$T/src" --name linux-6.6 --arch x86_64 --provider upstream --release v6.6 --kernel-release 6.6.0 --provenance 'kernel.org tag v6.6' -o "$T/linux.klabsource" >/dev/null
KLAB_ROOT="$T/root" KLAB_HOME="$T/root" "$ROOT/klab-artifact.sh" inspect "$T/linux.klabsource" --json > "$T/manifest.json"
python3 - "$T/manifest.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); x=m['metadata']
assert m['artifact_type']=='source' and m['object_id'].startswith('sha256:')
assert x=={'kernel_release':'6.6.0','provenance':'kernel.org tag v6.6','provider':'upstream','release':'v6.6'}
PY
obj="$(KLAB_ROOT="$T/root" KLAB_HOME="$T/root" "$ROOT/klab-artifact.sh" import "$T/linux.klabsource")"
[[ -f "$obj/content/Makefile" ]]
echo 'source artifact provenance and content-addressed import: PASS'
