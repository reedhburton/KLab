#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ROOT="${KLAB_ROOT:-/mnt/klab-store/klab-data}"
REPO="${KLAB_REPO:-/mnt/klab-store/klab-offline}"
EXPORTS="${KLAB_EXPORTS:-/mnt/klab-cache/exports}"
BASE_CATALOG="${KLAB_BASE_CATALOG:-$SELF/catalog/current-target-inventory-2026-11-04.tsv}"
RUN="${KLAB_RECONCILE_RUN:-$ROOT/results/portable-reconcile-2026-11-16}"
STATUS="$RUN/status.tsv"; QUEUE="$RUN/queue.tsv"; LOGS="$RUN/logs"
mkdir -p "$LOGS" "$EXPORTS"
if [[ ! -f "$QUEUE" ]]; then
  python3 - "$BASE_CATALOG" "$QUEUE" <<'PY'
import csv,sys
rows=list(csv.DictReader(open(sys.argv[1]),delimiter='\t'))
with open(sys.argv[2],'w',newline='') as h:
 w=csv.writer(h,delimiter='\t',lineterminator='\n'); w.writerow(['target','arch'])
 for r in rows:
  if r['offline_artifact']=='no' and r['local_target']=='yes': w.writerow([r['target'],r['arch']])
PY
fi
[[ -f "$STATUS" ]] || printf 'target\tarch\tresult\tartifact\tbytes\tsha256\n' > "$STATUS"
while IFS=$'\t' read -r target arch; do
  [[ "$target" != target ]] || continue
  grep -Fq "$target"$'\t'"$arch"$'\tPASS\t' "$STATUS" && continue
  safe="$(printf '%s' "$target" | tr ':/' '__')"
  out="$REPO/${safe}__${arch}__normal.klab"; log="$LOGS/${safe}__${arch}.log"
  if [[ -f "$out" ]]; then
    KLAB_ROOT="$ROOT" "$SELF/klab-bundle.sh" verify "$out" >"$log" 2>&1
  else
    "$SELF/beta-tools/offline-repack-klab.sh" "$target" "$out" "$ROOT" "$arch" >"$log" 2>&1
  fi
  bytes="$(stat -c %s "$out")"; sha="$(sha256sum "$out"|awk '{print $1}')"
  printf '%s\t%s\tPASS\t%s\t%s\t%s\n' "$target" "$arch" "$out" "$bytes" "$sha" >> "$STATUS"
done < "$QUEUE"
python3 "$SELF/tools/klab-scan-portable.py" "$REPO" -o "$RUN/physical-artifacts.tsv" > "$RUN/scan.log"
python3 - "$BASE_CATALOG" "$RUN/local.tsv" <<'PY'
import csv,sys
rows=list(csv.DictReader(open(sys.argv[1]),delimiter='\t'))
with open(sys.argv[2],'w',newline='') as h:
 w=csv.DictWriter(h,['target','arch','file'],delimiter='\t',lineterminator='\n'); w.writeheader()
 for r in rows:
  if r['local_target']=='yes':
   evidence=r.get('evidence',''); f=next((x for x in evidence.split(' | ') if x.endswith('/bundle.env')),'')
   w.writerow({'target':r['target'],'arch':r['arch'],'file':f})
PY
newtsv="$SELF/catalog/current-target-inventory-2026-11-16.tsv"
python3 "$SELF/tools/klab-current-inventory.py" --base "$BASE_CATALOG" --local "$RUN/local.tsv" --bundles "$RUN/physical-artifacts.tsv" --output "$newtsv" > "$RUN/inventory.log"
cp "$newtsv" "$REPO/catalog/current-target-inventory-2026-11-16.tsv"
python3 - "$REPO" "$RUN/physical-artifacts.tsv" "$REPO/.klab-releases/snapshots/klab-portable-2026-11-13.json" <<'PY_INDEX'
import csv,hashlib,json,sys
from pathlib import Path
repo,scan,snapshot=map(Path,sys.argv[1:])
old={x['path']:x for x in json.loads(snapshot.read_text())['files']}
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  while b:=f.read(8<<20): h.update(b)
 return h.hexdigest()
rows=[]
for r in csv.DictReader(scan.open(),delimiter='\t'):
 p=Path(r['file'])
 if p.suffix!='.klab' or r['error'] or not r['target']: continue
 rel=p.relative_to(repo).as_posix(); size=p.stat().st_size; prev=old.get(rel)
 sha=prev['sha256'] if prev and prev['bytes']==size else digest(p)
 rows.append((r['target'],r['arch'],str(size),sha,rel))
out=repo/'INDEX.tsv'
with out.open('w') as h:
 h.write('target\tarchitecture\tbytes\tsha256\tfile\n')
 for row in sorted(rows): h.write('\t'.join(row)+'\n')
(out.parent/(out.name+'.sha256')).write_text(f'{digest(out)}  {out.name}\n')
print(f'Indexed {len(rows)} .klab artifacts in {out}')
PY_INDEX
release=klab-portable-reconcile-2026-11-16
if [[ ! -f "$REPO/.klab-releases/snapshots/$release.json" ]]; then
  python3 "$SELF/tools/klab-repo-release.py" snapshot "$REPO" "$release" --parent klab-portable-2026-11-13 > "$RUN/snapshot.log"
fi
archive="$EXPORTS/$release.tar.zst"
checksum="$archive.sha256"
if [[ ! -f "$archive" || ! -f "$checksum" ]]; then
  python3 "$SELF/tools/klab-repo-release.py" export "$REPO" "$release" -o "$archive" > "$RUN/export.log"
fi
(cd "$EXPORTS" && sha256sum -c "$(basename "$checksum")") > "$RUN/export-verify.log"
printf 'phase=complete\nfinished_utc=%s\n' "$(date -u +%FT%TZ)" > "$RUN/final.status"
