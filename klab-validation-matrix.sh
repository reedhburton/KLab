#!/usr/bin/env bash
set -uo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"; KLAB_ROOT="${KLAB_ROOT:-$HOME/klab-data}"; export KLAB_ROOT
out="${1:?usage: klab-validation-matrix.sh OUTDIR [full|standard]}"; level="${2:-full}"; case "$level" in standard|full);;*) exit 2;;esac
mkdir -p "$out/reports" "$out/logs"; status="$out/status.tsv"; [[ -f "$status" ]] || printf 'target\tbackend\tarch\tlevel\tresult\treport\n' >"$status"
# Materialize the queue before launching validators. Validators and their guests
# may read stdin; a streaming loop let the first validator consume later paths.
mapfile -t target_envs < <(find "$KLAB_ROOT/targets/kernels" -mindepth 5 -maxdepth 5 -type f -name bundle.env | sort -V)
for env in "${target_envs[@]}"; do
 rel="${env#"$KLAB_ROOT/targets/kernels/"}"; IFS=/ read -r provider release arch kernel _ <<<"$rel"
 # Recovery snapshots live beside canonical targets but retain the original
 # BUNDLE_KERNEL_RELEASE. Never promote those directories into matrix rows.
 canonical_kernel="$(sed -n 's/^BUNDLE_KERNEL_RELEASE=//p' "$env" | head -n1)"; canonical_kernel="${canonical_kernel//\\/}"; canonical_kernel="${canonical_kernel%\"}"; canonical_kernel="${canonical_kernel#\"}"; canonical_kernel="${canonical_kernel%\'}"; canonical_kernel="${canonical_kernel#\'}"
 [[ -z "$canonical_kernel" || "$kernel" == "$canonical_kernel" ]] || continue
 backend=linux; target="$provider:$release:$kernel"
 if [[ "$provider" == freebsd ]]; then backend=freebsd; target="freebsd:$release:$arch"; fi
 awk -F '\t' -v t="$target" -v a="$arch" -v l="$level" 'NR>1&&$1==t&&$3==a&&$4==l&&$5=="PASS"{f=1}END{exit !f}' "$status" && continue
 safe="$(printf '%s-%s' "$target" "$arch"|tr -c 'A-Za-z0-9._-' '-')"; report="$out/reports/$safe-$level"; log="$out/logs/$safe-$level.log"
 if [[ -f "$report/RESULT" && "$(cat "$report/RESULT")" == PASS ]]; then
  printf '%s\t%s\t%s\t%s\tPASS\t%s\n' "$target" "$backend" "$arch" "$level" "$report" >>"$status"; continue
 fi
 if timeout 3600 "$SELF/klab" validate "$target" --arch "$arch" --level "$level" --report-dir "$report" >"$log" 2>&1 </dev/null; then result=PASS; else result=FAIL; fi
 printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$target" "$backend" "$arch" "$level" "$result" "$report" >>"$status"
done
cat "$status"; awk -F '\t' 'NR>1&&$5!="PASS"{bad=1}END{exit bad}' "$status"
