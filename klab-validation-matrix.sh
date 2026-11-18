#!/usr/bin/env bash
set -uo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"; KLAB_ROOT="${KLAB_ROOT:-$HOME/klab-data}"; export KLAB_ROOT
out="${1:?usage: klab-validation-matrix.sh OUTDIR [full|standard]}"; level="${2:-full}"; case "$level" in standard|full);;*) exit 2;;esac
mkdir -p "$out/reports" "$out/logs"; status="$out/status.tsv"; [[ -f "$status" ]] || printf 'target\tbackend\tarch\tlevel\tresult\treport\n' >"$status"
# Materialize the queue before launching validators. Validators and their guests
# may read stdin; a streaming loop let the first validator consume later paths.
mapfile -t target_envs < <(find "$KLAB_ROOT/targets/kernels" -mindepth 5 -maxdepth 5 -type f -name bundle.env | sort -V)
declare -A seen_targets=()
for env in "${target_envs[@]}"; do
 # Recovery snapshots retain metadata that points to the canonical bundle.
 # Enumerate only that canonical path, and derive CLI IDs from its metadata.
 metadata="$(
   unset BUNDLE_PROVIDER BUNDLE_DISTRO_RELEASE BUNDLE_KERNEL_RELEASE BUNDLE_ARCH BUNDLE_DIR BUNDLE_UPSTREAM_VERSION BUNDLE_TARGET_ID BUNDLE_BACKEND
   # shellcheck disable=SC1090
   source "$env"
   printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "${BUNDLE_PROVIDER:-}" "${BUNDLE_DISTRO_RELEASE:-}" "${BUNDLE_KERNEL_RELEASE:-}" "${BUNDLE_ARCH:-}" "${BUNDLE_DIR:-}" "${BUNDLE_UPSTREAM_VERSION:-}" "${BUNDLE_TARGET_ID:-}" "${BUNDLE_BACKEND:-}"
 )"
 IFS='|' read -r provider release kernel arch bundle_dir upstream_version target_id metadata_backend <<<"$metadata"
 [[ -n "$provider" && -n "$arch" && -n "$bundle_dir" ]] || continue
 [[ "$(readlink -f "$env")" == "$(readlink -f "$bundle_dir/bundle.env")" ]] || continue
 backend="${metadata_backend:-linux}"
 case "$provider" in
  upstream) [[ -n "$upstream_version" ]] || continue; target="upstream:$upstream_version" ;;
  freebsd) backend=freebsd; target="${target_id:-freebsd:$release:$arch}" ;;
  *) [[ -n "$release" && -n "$kernel" ]] || continue; target="${target_id:-$provider:$release:$kernel}" ;;
 esac
 key="$target@$arch"; [[ -z "${seen_targets[$key]:-}" ]] || continue; seen_targets[$key]=1
 awk -F '\t' -v t="$target" -v a="$arch" -v l="$level" 'NR>1&&$1==t&&$3==a&&$4==l&&$5=="PASS"{f=1}END{exit !f}' "$status" && continue
 safe="$(printf '%s-%s' "$target" "$arch"|tr -c 'A-Za-z0-9._-' '-')"; report="$out/reports/$safe-$level"; log="$out/logs/$safe-$level.log"
 if [[ -f "$report/RESULT" && "$(cat "$report/RESULT")" == PASS ]]; then
  printf '%s\t%s\t%s\t%s\tPASS\t%s\n' "$target" "$backend" "$arch" "$level" "$report" >>"$status"; continue
 fi
 if timeout 3600 "$SELF/klab" validate "$target" --arch "$arch" --level "$level" --report-dir "$report" >"$log" 2>&1 </dev/null; then result=PASS; else result=FAIL; fi
 printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$target" "$backend" "$arch" "$level" "$result" "$report" >>"$status"
done
cat "$status"; awk -F '\t' 'NR>1&&$5!="PASS"{bad=1}END{exit bad}' "$status"
