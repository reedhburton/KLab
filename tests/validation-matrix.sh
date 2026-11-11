#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq '"$SELF/klab" validate' "$ROOT/klab-validation-matrix.sh"
grep -Fq '&&$5=="PASS"' "$ROOT/klab-validation-matrix.sh"
grep -Fq 'rm -rf "$root"' "$ROOT/klab-image-validate.sh"


tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp "$ROOT/klab-validation-matrix.sh" "$tmp/klab-validation-matrix.sh"
cat >"$tmp/klab" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
report=
while (($#)); do
  if [[ "$1" == --report-dir ]]; then report="$2"; shift 2; else shift; fi
done
mkdir -p "$report"; printf 'PASS\n' >"$report/RESULT"
EOF
chmod +x "$tmp/klab" "$tmp/klab-validation-matrix.sh"
for spec in 'one/1/x86_64/1.0' 'two/2/x86_64/2.0' 'three/3/x86_64/3.0'; do
  mkdir -p "$tmp/root/targets/kernels/$spec"; : >"$tmp/root/targets/kernels/$spec/bundle.env"
done
KLAB_ROOT="$tmp/root" "$tmp/klab-validation-matrix.sh" "$tmp/out" full </dev/null >/dev/null
[[ "$(awk -F '\t' 'NR>1&&$5=="PASS"{n++}END{print n+0}' "$tmp/out/status.tsv")" == 3 ]]
echo 'resumable all-imported-target validation matrix: PASS'
