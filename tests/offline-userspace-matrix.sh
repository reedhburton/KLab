#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat >"$T/inventory.tsv" <<'TSV'
target	arch	family
ubuntu:24.04:test-generic	x86_64	linux
TSV
cat >"$T/klab" <<'SH'
#!/usr/bin/env bash
[[ "$1" == validate && "$2" == ubuntu:24.04:test-generic ]]
[[ "$KLAB_OFFLINE" == 1 && "$KLAB_PREFER_IMPORTED" == 1 ]]
while (($#)); do [[ "$1" == --report-dir ]] && { out="$2"; break; }; shift; done
mkdir -p "$out"; printf 'GATE\tRESULT\tEVIDENCE\nquick_boot\tPASS\tq\nmodule_process\tPASS\tm\ntwo_guest_tcp\tPASS\tn\ninteractive_boot\tPASS\ti\nuserspace_conformance\tPASS\tu\ninteractive_ssh\tPASS\ts\n' >"$out/gates.tsv"; echo PASS >"$out/RESULT"
SH
chmod +x "$T/klab"
"$ROOT/klab-offline-userspace-matrix.py" "$T/inventory.tsv" "$T/out" --klab "$T/klab" --workers 1 >/dev/null
awk -F '\t' 'NR==2{exit !($4=="PASS"&&$5=="PASS"&&$6=="PASS"&&$7=="PASS"&&$8=="PASS"&&$9=="PASS")}' "$T/out/status.tsv"
(
 cd "$T"
 "$ROOT/klab-offline-userspace-matrix.py" inventory.tsv relative-out --klab ./klab --workers 1 >/dev/null
)
awk -F '\t' 'NR==2{exit !($9=="PASS")}' "$T/relative-out/status.tsv"
"$ROOT/klab-offline-userspace-matrix.py" "$T/inventory.tsv" "$T/out" --klab "$T/klab" --workers 1 | grep -Fq 'queue=0 already_pass=1'
echo 'offline-userspace-matrix: PASS'
