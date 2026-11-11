#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; c="$ROOT/catalog/upstream-x86_64-minors.tsv"; q="$ROOT/klab-upstream-minor-queue.sh"
bash -n "$q"
[[ "$(tail -n +2 "$c" | wc -l)" == 123 ]]
[[ "$(cut -f2 "$c" | tail -n +2 | sort -u | wc -l)" == 123 ]]
grep -qx $'1\tupstream:v2.6.0\tx86_64\texact upstream API boundary' "$c"
grep -q $'upstream:v2.6.39\tx86_64' "$c"
grep -q $'upstream:v3.0\tx86_64' "$c"
grep -q $'upstream:v7.2\tx86_64' "$c"
grep -Fq 'run_one(){' "$q"; grep -Fq '|| return' "$q"; grep -Fq 'FAIL_MODULE_BUILD' "$q"; grep -Fq 'FAIL_BOOT_INSERT' "$q"; grep -Fq 'tests/all-five/module' "$q"
grep -Fq 'KLAB_DEFER_REPO_INDEX=1 "$SELF/klab" pull "$target" --arch x86_64 || return' "$q"
grep -Fq '"$SELF/klab" repo index >/dev/null' "$q"; grep -Fq 'attempts.tsv' "$q"; grep -Fq 'passed "$target" && continue' "$q"
grep -Fq 'WORKERS="${KLAB_QUEUE_WORKERS:-1}"' "$q"
grep -Fq 'JOBS_PER_WORKER="${KLAB_QUEUE_JOBS_PER_WORKER:-$((TOTAL_JOBS / WORKERS))}"' "$q"
grep -Fq 'flock 9' "$q"
grep -Fq 'wait -n || true' "$q"
grep -Fq 'KLAB_JOBS="$JOBS_PER_WORKER" KLAB_DEFER_REPO_INDEX=1' "$q"
echo 'upstream x86_64 minor-boundary queue: PASS (123 exact tags)'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$q" "$tmp/klab-upstream-minor-queue.sh"
cat > "$tmp/klab" <<'STUB'
#!/usr/bin/env bash
sleep 0.05
exit 0
STUB
cat > "$tmp/kernel-lab.sh" <<'STUB'
#!/usr/bin/env bash
sleep 0.05
exit 0
STUB
chmod +x "$tmp/klab" "$tmp/kernel-lab.sh"
mkdir -p "$tmp/catalog" "$tmp/tests/all-five/module"
: > "$tmp/tests/all-five/workload.sh"
{
  printf 'ordinal\ttarget\tarch\tpurpose\n'
  for n in 1 2 3 4; do
    printf '%s\tupstream:v9.%s\tx86_64\tparallel lock regression\n' "$n" "$n"
  done
} > "$tmp/catalog.tsv"
mkdir -p "$tmp/root"
KLAB_ROOT="$tmp/root" KLAB_QUEUE_WORKERS=4 KLAB_QUEUE_JOBS_PER_WORKER=1 \
  "$tmp/klab-upstream-minor-queue.sh" "$tmp/catalog.tsv" "$tmp/out" >/dev/null
[[ "$(awk -F '\t' 'NR>1 && $3=="PASS"{n++} END{print n+0}' "$tmp/out/status.tsv")" == 4 ]]
[[ "$(tail -n +2 "$tmp/out/attempts.tsv" | wc -l)" == 4 ]]
[[ "$(cut -f1 "$tmp/out/status.tsv" | tail -n +2 | sort -u | wc -l)" == 4 ]]
echo 'upstream queue parallel evidence locking: PASS (4 workers)'
