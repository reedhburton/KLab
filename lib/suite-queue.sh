#!/usr/bin/env bash
# Resumable, evidence-preserving queue for klab-suite-v2.
klab_suite_queue(){
  local dir="$1"; shift; local manifest="$dir/suite.json" planner="$KLAB_SELF_DIR/lib/suite_plan.py"
  local output='' target_file='' resume=0 dry=0 all=0 manifest_targets=1; local -a selected=()
  while (($#)); do case "$1" in
    --target) [[ $# -ge 2 ]] || { echo 'klab: --target needs TARGET@ARCH' >&2; return 2; }; selected+=("$2"); shift 2;;
    --target-file) [[ $# -ge 2 ]] || { echo 'klab: --target-file needs a path' >&2; return 2; }; target_file="$2"; shift 2;;
    --output) [[ $# -ge 2 ]] || { echo 'klab: --output needs a directory' >&2; return 2; }; output="$2"; shift 2;;
    --only-target) [[ $# -ge 2 ]] || { echo 'klab: --only-target needs TARGET@ARCH' >&2; return 2; }; manifest_targets=0; selected=("$2"); shift 2;;
    --all) all=1; shift;; --resume) resume=1; shift;; --dry-run) dry=1; shift;;
    *) echo "klab: unknown suite queue option: $1" >&2; return 2;; esac; done
  "$planner" validate "$manifest" >/dev/null || return
  [[ -n "$output" ]] || output="$KLAB_ROOT/results/suites/$(basename "$dir")/$(date -u +%Y%m%dT%H%M%SZ)-u$(id -u)-$$-${RANDOM:-0}"
  mkdir -p "$output/scenarios" "$output/targets"
  local targets="$output/targets.tsv"; : > "$targets"; ((manifest_targets)) && "$planner" targets "$manifest" >> "$targets"
  if ((all)); then
    local env rel provider release kernel
    while IFS= read -r env; do
      rel="${env#"$KLAB_ROOT/targets/kernels/"}"; IFS=/ read -r provider release arch kernel _ <<<"$rel"
      if [[ "$provider" == freebsd ]]; then printf 'freebsd:%s:%s\t%s\n' "$release" "$arch" "$arch" >> "$targets"; else printf '%s:%s:%s\t%s\n' "$provider" "$release" "$kernel" "$arch" >> "$targets"; fi
    done < <(find "$KLAB_ROOT/targets/kernels" -mindepth 5 -maxdepth 5 -type f -name bundle.env 2>/dev/null | sort -V)
  fi
  local item target arch
  for item in "${selected[@]}"; do [[ "$item" == *@* ]] || { echo "klab: target must be TARGET@ARCH: $item" >&2; return 2; }; printf '%s\t%s\n' "${item%@*}" "${item##*@}" >> "$targets"; done
  if [[ -n "$target_file" ]]; then
    [[ -f "$target_file" ]] || { echo "klab: target file not found: $target_file" >&2; return 2; }
    while IFS= read -r item || [[ -n "$item" ]]; do [[ -z "$item" || "$item" == \#* ]] && continue; [[ "$item" == *@* ]] || { echo "klab: target must be TARGET@ARCH: $item" >&2; return 2; }; printf '%s\t%s\n' "${item%@*}" "${item##*@}" >> "$targets"; done < "$target_file"
  fi
  awk -F '\t' 'NF==2&&!seen[$0]++' "$targets" > "$targets.tmp"; mv "$targets.tmp" "$targets"
  [[ -s "$targets" ]] || { echo 'klab: suite queue has no targets; add targets to suite.json or use --target/--target-file' >&2; return 2; }
  local status="$output/status.tsv"; [[ -f "$status" ]] || printf 'target\tarch\tresult\treport\n' > "$status"
  local slug scenario report rc result failures=0
  while IFS=$'\t' read -r target arch; do
    if ((resume)) && awk -F '\t' -v t="$target" -v a="$arch" '$1==t&&$2==a&&$3=="PASS"{ok=1} END{exit !ok}' "$status"; then continue; fi
    slug="$(printf '%s-%s' "$target" "$arch" | tr -c 'A-Za-z0-9._-' '_')"; scenario="$output/scenarios/$slug.json"; report="$output/targets/$slug"
    "$planner" scenario "$manifest" "$scenario" "$target" "$arch" || return
    set +e; if ((dry)); then "$KLAB_RUNNER" scenario-run "$scenario" --report-dir "$report" --dry-run; else "$KLAB_RUNNER" scenario-run "$scenario" --report-dir "$report"; fi; rc=$?; set -e
    [[ $rc == 0 ]] && result=PASS || { result=FAIL; failures=$((failures+1)); }
    printf '%s\t%s\t%s\t%s\n' "$target" "$arch" "$result" "$report" >> "$status"
  done < "$targets"
  printf '%s\n' "$output"; ((failures==0))
}
