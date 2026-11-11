#!/usr/bin/env bash
# Build and validate every upstream major.minor API boundary on x86_64.
# The catalog is explicit for reproducibility; reruns skip PASS rows and retry failures.
set -uo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CATALOG="${1:-$SELF/catalog/upstream-x86_64-minors.tsv}"
OUT="${2:-${KLAB_ROOT:-$HOME/klab}/results/upstream-x86_64-minors}"
KLAB_ROOT="${KLAB_ROOT:-$HOME/klab}"; export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"
FLOOR_GIB="${KLAB_QUEUE_FREE_GIB:-100}"
LIMIT="${KLAB_QUEUE_LIMIT:-0}"
WORKERS="${KLAB_QUEUE_WORKERS:-1}"
TOTAL_JOBS="${KLAB_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
JOBS_PER_WORKER="${KLAB_QUEUE_JOBS_PER_WORKER:-$((TOTAL_JOBS / WORKERS))}"
(( JOBS_PER_WORKER > 0 )) || JOBS_PER_WORKER=1
[[ "$WORKERS" =~ ^[1-9][0-9]*$ ]] || { echo "KLAB_QUEUE_WORKERS must be a positive integer" >&2; exit 2; }
[[ "$JOBS_PER_WORKER" =~ ^[1-9][0-9]*$ ]] || { echo "KLAB_QUEUE_JOBS_PER_WORKER must be a positive integer" >&2; exit 2; }
mkdir -p "$OUT/logs" "$OUT/reports"
STATUS="$OUT/status.tsv"; ATTEMPTS="$OUT/attempts.tsv"
STATUS_LOCK="$OUT/.status.lock"; ATTEMPTS_LOCK="$OUT/.attempts.lock"
[[ -f "$STATUS" ]] || printf 'target\tarch\tresult\tvalidated_at_utc\tevidence\n' >"$STATUS"
[[ -f "$ATTEMPTS" ]] || printf 'attempt\ttarget\tarch\tresult\tstarted_at_utc\tfinished_at_utc\tevidence\tlog\n' >"$ATTEMPTS"

passed(){ awk -F '\t' -v t="$1" 'NR>1 && $1==t && $2=="x86_64" && $3=="PASS"{ok=1} END{exit !ok}' "$STATUS"; }

record_status(){
  (
    flock 9
    python3 - "$STATUS" "$1" "$2" "$3" <<'PY2'
import csv,os,sys,tempfile
path,target,result,evidence=sys.argv[1:]
fields=['target','arch','result','validated_at_utc','evidence']
rows=list(csv.DictReader(open(path),delimiter='\t'))
now=__import__('datetime').datetime.now(__import__('datetime').timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
for r in rows:
    if r['target']==target and r['arch']=='x86_64':
        r.update(result=result,validated_at_utc=now,evidence=evidence)
        break
else:
    rows.append(dict(target=target,arch='x86_64',result=result,validated_at_utc=now,evidence=evidence))
fd,tmp=tempfile.mkstemp(prefix='.status.',dir=os.path.dirname(path),text=True)
with os.fdopen(fd,'w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=fields,delimiter='\t',lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
os.replace(tmp,path)
PY2
  ) 9>"$STATUS_LOCK"
}

record_attempt(){
  local line="$1"
  (
    flock 9
    printf '%s\n' "$line" >>"$ATTEMPTS"
  ) 9>"$ATTEMPTS_LOCK"
}

run_target(){
  local target="$1" purpose="$2" started stamp safe attempt report log result rc finished
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  safe="${target//[:.]/-}"
  attempt="$stamp-$safe-x86_64"
  report="$OUT/reports/$attempt"
  log="$OUT/logs/$attempt.log"
  mkdir -p "$report"
  result=FAIL_PULL
  run_one(){
    echo "TARGET=$target"
    echo "ARCH=x86_64"
    echo "PURPOSE=$purpose"
    KLAB_JOBS="$JOBS_PER_WORKER" KLAB_DEFER_REPO_INDEX=1 "$SELF/klab" pull "$target" --arch x86_64 || return
    result=FAIL_MODULE_BUILD
    KLAB_JOBS="$JOBS_PER_WORKER" "$SELF/klab" build "$target" "$SELF/tests/all-five/module" --arch x86_64 -o "$report/module" || return
    result=FAIL_BOOT_INSERT
    KLAB_JOBS="$JOBS_PER_WORKER" "$SELF/kernel-lab.sh" test "$target" --arch x86_64 --module "$SELF/tests/all-five/module" --script "$SELF/tests/all-five/workload.sh" --userspace busybox-static || return
    result=PASS
  }
  run_one >"$log" 2>&1
  rc=$?
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ((rc==0)) || true
  unset -f run_one
  record_attempt "$(printf '%s\t%s\tx86_64\t%s\t%s\t%s\t%s\t%s' "$attempt" "$target" "$result" "$started" "$finished" "$report" "$log")"
  printf 'target=%s\narch=x86_64\nresult=%s\nstarted=%s\nfinished=%s\nlog=%s\n' "$target" "$result" "$started" "$finished" "$log" >"$report/result.env"
  record_status "$target" "$result" "$report"
}

count=0
active=0
echo "queue workers=$WORKERS jobs-per-worker=$JOBS_PER_WORKER"
while IFS=$'\t' read -r ordinal target arch purpose; do
  [[ "$ordinal" != ordinal && -n "$target" ]] || continue
  [[ "$arch" == x86_64 ]] || { echo "unexpected catalog architecture: $arch" >&2; exit 2; }
  passed "$target" && continue
  (( LIMIT == 0 || count < LIMIT )) || break
  avail="$(df -B1 --output=avail "$KLAB_ROOT" | tail -1)"
  floor=$((FLOOR_GIB*1024*1024*1024))
  if ((avail < floor)); then
    echo "stopping below ${FLOOR_GIB} GiB free-space floor" >&2
    break
  fi
  run_target "$target" "$purpose" &
  active=$((active+1))
  count=$((count+1))
  if (( active >= WORKERS )); then
    wait -n || true
    active=$((active-1))
  fi
done <"$CATALOG"
wait || true

# A normal interactive pull keeps the repository index immediately current.
# This batch deliberately defers that O(repository-size) scan and performs it
# once after all attempted targets, including interrupted/resumed campaigns.
"$SELF/klab" repo index >/dev/null
python3 - "$STATUS" "$OUT/SUMMARY.md" <<'PY2'
import csv,collections,sys
r=list(csv.DictReader(open(sys.argv[1]),delimiter='\t'))
c=collections.Counter(x['result'] for x in r)
open(sys.argv[2],'w').write(f"# Upstream x86_64 minor-boundary validation\n\nTotal recorded: **{len(r)}**; PASS: **{c['PASS']}**; failures: **{sum(v for k,v in c.items() if k!='PASS')}**.\n")
PY2
