#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat > "$T/fake-runner" <<'FAKE'
#!/usr/bin/env bash
set -eu
[[ "$1" == scenario-run ]]; scenario="$2"; shift 2
python3 - "$scenario" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); print(x['target']+'@'+x['arch'])
PY
while (($#)); do case "$1" in --report-dir) mkdir -p "$2"; printf PASS > "$2/RESULT"; shift 2;; --dry-run) shift;; *) shift;; esac; done
FAKE
chmod +x "$T/fake-runner"
KLAB_ROOT="$T/root" KLAB_RUNNER="$T/fake-runner" "$ROOT/klab" suite create ordered >/dev/null
mkdir -p "$T/root/targets/kernels/debian/12/x86_64/6.1.0"; : > "$T/root/targets/kernels/debian/12/x86_64/6.1.0/bundle.env"
python3 - "$T/root/suites/ordered/suite.json" <<'PY'
import json,sys
p=sys.argv[1];x=json.load(open(p));x['targets']=['upstream:v6.6@x86_64',{'target':'ubuntu:24.04','arch':'aarch64'}];open(p,'w').write(json.dumps(x)+'\n')
PY
out="$T/results"
KLAB_ROOT="$T/root" KLAB_RUNNER="$T/fake-runner" "$ROOT/klab" suite queue ordered --all --target alpine:3.20@x86_64 --output "$out" --dry-run >/dev/null
[[ "$(awk -F '\t' '$3=="PASS"{n++} END{print n+0}' "$out/status.tsv")" == 4 ]]
[[ "$(wc -l < "$out/targets.tsv")" == 4 ]]
before="$(wc -l < "$out/status.tsv")"
KLAB_ROOT="$T/root" KLAB_RUNNER="$T/fake-runner" "$ROOT/klab" suite queue ordered --output "$out" --resume --dry-run >/dev/null
[[ "$(wc -l < "$out/status.tsv")" == "$before" ]]
grep -q 'ubuntu:24.04' "$out/scenarios/ubuntu_24.04-aarch64.json"
echo 'PASS: resumable multi-target suite queue'
