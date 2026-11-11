#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat >"$T/runner" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$FAKE_CALLS"
case "$1" in
 info|smoke|test|boot|push|stop) exit 0 ;;
 build-user) while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then : >"$2"; chmod +x "$2"; exit 0; fi; shift; done; exit 1 ;;
 exec) printf '%s\n' 'KLAB_USERSPACE_SMOKE_PASS kernel=6.6-test arch=aarch64' 'CLIENT_RX ACK:klab-image-validation' 'SERVER_RX klab-image-validation' 'SERVER_DONE'; exit 0 ;;
 *) exit 0 ;;
esac
SH
chmod +x "$T/runner"
export FAKE_CALLS="$T/calls" KLAB_RUNNER="$T/runner" KLAB_ROOT="$T/root"
"$ROOT/klab" validate distro:1:6.6-test --arch aarch64 --level standard --report-dir "$T/report" >"$T/out"
grep -Fxq PASS "$T/report/RESULT"
grep -Fq $'module_process\tPASS' "$T/report/gates.tsv"
grep -Fq $'two_guest_tcp\tPASS' "$T/report/gates.tsv"
grep -Fq 'test distro:1:6.6-test --arch aarch64' "$T/calls"
grep -Fq 'build-user distro:1:6.6-test --arch aarch64' "$T/calls"
grep -Fq -- '--net-bus' "$T/calls"
python3 - "$T/report/manifest.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); assert m['schema']=='klab-image-validation-v1'; assert m['result']=='PASS'; assert len(m['gates'])==4
PY
echo 'image validation command and evidence contract: PASS'
