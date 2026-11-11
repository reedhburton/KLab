#!/usr/bin/env bash
set -u
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MATRIX="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OUT="${KLAB_MATRIX_OUT:?set KLAB_MATRIX_OUT}"
JOBS="${KLAB_MATRIX_JOBS:-4}"
mkdir -p "$OUT/logs" "$OUT/state"
printf 'provider\trelease\tfamily\tstatus\tlatest_kernel\treason\n' > "$OUT/discovery.tsv.tmp"
tail -n +2 "$MATRIX/releases.tsv" | while IFS=$'\t' read -r provider release family; do
  key="$(printf '%s_%s' "$provider" "$release" | tr '@/:' '____')"
  printf '%s\t%s\t%s\t%s\n' "$provider" "$release" "$family" "$key"
done > "$OUT/queue.tsv"
worker(){
  while IFS=$'\t' read -r provider release family key; do
    claim="$OUT/state/$key.claim"; donef="$OUT/state/$key.done"
    ( set -o noclobber; : > "$claim" ) 2>/dev/null || continue
    if [[ -f "$donef" ]]; then continue; fi
    log="$OUT/logs/$key.log"; raw="$OUT/state/$key.raw"
    if timeout "${KLAB_MATRIX_DISCOVERY_TIMEOUT:-900}" env KLAB_ROOT="${KLAB_MATRIX_ROOT:-/home/reed/klab-matrix}" KLAB_HOME="${KLAB_MATRIX_ROOT:-/home/reed/klab-matrix}" KLAB_COMPAT_LINKS=0 "$ROOT/klab" list "$provider:$release" >"$raw" 2>"$log"; then
      case "$provider" in
        ubuntu) latest="$(grep -E '^[0-9]+\.[0-9]+.*-generic$' "$raw" | sort -V | tail -n1 || true)" ;;
        debian) latest="$(grep -E '^[0-9]+\.[0-9]+.*-amd64$' "$raw" | grep -Ev -- '-(cloud|rt)-amd64$' | sort -V | tail -n1 || true)" ;;
        *) latest="$(grep -E '^[0-9]+\.[0-9]+' "$raw" | sort -V | tail -n1 || true)" ;;
      esac
      [[ -n "$latest" ]] || latest="$(grep -E '^[0-9]+\.[0-9]+' "$raw" | sort -V | tail -n1 || true)"
      major="${latest%%.*}"
      if [[ -n "$latest" && "$major" =~ ^[0-9]+$ && "$major" -ge 3 ]]; then printf 'listed\t%s\t\n' "$latest" > "$donef"; elif [[ -n "$latest" ]]; then printf 'ineligible\t%s\tkernel major below 3\n' "$latest" > "$donef"; else printf 'empty\t\tno eligible kernel returned\n' > "$donef"; fi
    else
      rc=$?; reason="$(tail -n 3 "$log" | tr '\t\r\n' '   ' | sed 's/  */ /g' | cut -c1-300)"
      printf 'failed\t\trc=%s %s\n' "$rc" "$reason" > "$donef"
    fi
  done < "$OUT/queue.tsv"
}
for _ in $(seq 1 "$JOBS"); do worker & done
wait
while IFS=$'\t' read -r provider release family key; do
  if [[ -f "$OUT/state/$key.done" ]]; then IFS=$'\t' read -r status latest reason < "$OUT/state/$key.done"; else status=interrupted; latest=; reason='no terminal state'; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$provider" "$release" "$family" "$status" "$latest" "$reason" >> "$OUT/discovery.tsv.tmp"
done < "$OUT/queue.tsv"
mv "$OUT/discovery.tsv.tmp" "$OUT/discovery.tsv"
