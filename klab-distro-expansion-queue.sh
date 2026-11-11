#!/usr/bin/env bash
set -uo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB_ROOT="${KLAB_ROOT:-$HOME/klab-data}"; KLAB_OFFLINE_ROOT="${KLAB_OFFLINE_ROOT:-$HOME/klab-offline}"; export KLAB_ROOT KLAB_OFFLINE_ROOT
manifest="${1:-$SELF/matrix/popular-distro-expansion.tsv}"
out="${2:-$KLAB_ROOT/results/popular-distro-expansion}"
limit="${KLAB_EXPANSION_LIMIT:-0}"; floor_gib="${KLAB_EXPANSION_FREE_GIB:-100}"
workers="${KLAB_EXPANSION_WORKERS:-1}"; parallel_validate="${KLAB_EXPANSION_PARALLEL_VALIDATE:-0}"
[[ "$workers" =~ ^[1-9][0-9]*$ ]] || { echo 'KLAB_EXPANSION_WORKERS must be a positive integer' >&2; exit 2; }
[[ "$limit" =~ ^[0-9]+$ ]] || { echo 'KLAB_EXPANSION_LIMIT must be a non-negative integer' >&2; exit 2; }
mkdir -p "$out/logs" "$out/reports" "$out/discovery" "$out/locks" "$KLAB_OFFLINE_ROOT/variants"
status="$out/status.tsv"; timings="$out/timings.tsv"; queue="$out/queue.tsv"; work="$out/work.tsv"
[[ -f "$status" ]] || printf 'target\tarch\tresult\tphase\tevidence\n' >"$status"
[[ -f "$timings" ]] || printf 'target\tarch\tphase\tresult\tduration_seconds\tevidence\n' >"$timings"

status_has_pass() {
  local target="$1" arch="$2" rc
  exec {fd}<"$status"; flock -s "$fd"
  awk -F '\t' -v t="$target" -v a="$arch" 'NR>1&&$1==t&&$2==a&&$3=="PASS"{f=1}END{exit !f}' "$status"; rc=$?
  flock -u "$fd"; exec {fd}>&-; return "$rc"
}
status_append() {
  exec {fd}>>"$out/locks/status.lock"; flock "$fd"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >>"$status"
  flock -u "$fd"; exec {fd}>&-
}
timing_append() {
  exec {fd}>>"$out/locks/timings.lock"; flock "$fd"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >>"$timings"
  flock -u "$fd"; exec {fd}>&-
}
phase_run() {
  local target="$1" arch="$2" phase="$3" evidence="$4"; shift 4
  local started ended rc
  started="$(date +%s)"; "$@"; rc=$?; ended="$(date +%s)"
  if (( rc == 0 )); then timing_append "$target" "$arch" "$phase" PASS "$((ended-started))" "$evidence"
  else timing_append "$target" "$arch" "$phase" FAIL "$((ended-started))" "$evidence"; fi
  return "$rc"
}

# Discovery is intentionally single-controller: repository catalogs are shared,
# small, and should never be fetched redundantly by workers.
printf 'target\tarch\n' >"$queue.tmp"
while IFS=$'\t' read -r provider release arch pattern latest; do
  [[ "$provider" != provider && -n "$provider" ]] || continue
  key="$provider-$release-$arch"; discovered="$out/discovery/$key.tsv"; log="$out/logs/discover-$key.log"
  if [[ ! -s "$discovered" ]]; then
    if ! KLAB_ARCH="$arch" "$SELF/kernel-lab.sh" list "$provider:$release" </dev/null >"$discovered.tmp" 2>"$log"; then
      status_append "$provider:$release:*" "$arch" FAIL discover "$log"; rm -f "$discovered.tmp"; continue
    fi
    candidates="$discovered.candidates"
    if [[ "$pattern" == . ]]; then
      awk '/^[0-9][0-9A-Za-z.+_~-]*$/' "$discovered.tmp" | sort -Vu >"$candidates"
    else
      awk '/^[0-9][0-9A-Za-z.+_~-]*$/' "$discovered.tmp" | grep -E -- "$pattern" | sort -Vu >"$candidates"
    fi
    case "$latest" in
      all) cat "$candidates" >"$discovered" ;;
      ''|*[!0-9]*) printf 'invalid retention count: %s\n' "$latest" >>"$log"; rm -f "$discovered.tmp" "$candidates"; status_append "$provider:$release:*" "$arch" FAIL discover "$log"; continue ;;
      0) cat "$candidates" >"$discovered" ;;
      *) tail -n "$latest" "$candidates" >"$discovered" ;;
    esac
    rm -f "$discovered.tmp" "$candidates"
    if [[ ! -s "$discovered" ]]; then
      printf 'no kernels matched expansion filter %s\n' "$pattern" >>"$log"
      status_append "$provider:$release:*" "$arch" FAIL discover "$log"; continue
    fi
  fi
  while IFS= read -r kernel; do [[ -n "$kernel" ]] && printf '%s:%s:%s\t%s\n' "$provider" "$release" "$kernel" "$arch" >>"$queue.tmp"; done <"$discovered"
done <"$manifest"
{ head -n1 "$queue.tmp"; tail -n +2 "$queue.tmp" | sort -u; } >"$queue"; rm -f "$queue.tmp"

# Snapshot only unfinished work before launching children. This prevents two
# workers selecting the same target and gives KLAB_EXPANSION_LIMIT global rather
# than per-worker semantics.
printf 'target\tarch\n' >"$work.tmp"; selected=0
while IFS=$'\t' read -r target arch; do
  [[ "$target" != target ]] || continue
  status_has_pass "$target" "$arch" && continue
  (( limit == 0 || selected < limit )) || break
  printf '%s\t%s\n' "$target" "$arch" >>"$work.tmp"; selected=$((selected+1))
done <"$queue"
mv -f "$work.tmp" "$work"

run_target() {
  local target="$1" arch="$2" provider release kernel safe log report native bundle target_env avail floor lock_name rc
  avail="$(df -B1 --output=avail /mnt/klab-store | tail -1)"; floor=$((floor_gib*1024*1024*1024))
  if (( avail < floor )); then status_append "$target" "$arch" STOP_SPACE preflight "below $floor_gib GiB floor"; return 75; fi
  IFS=: read -r provider release kernel <<<"$target"
  safe="$(printf '%s-%s' "$target" "$arch" | tr -c 'A-Za-z0-9._-' '-')"; log="$out/logs/$safe.log"; report="$out/reports/$safe"
  native="$KLAB_ROOT/artifacts/userspaces/native/$provider/$release/$arch/rootfs.tar.zst"
  if [[ ! -s "$native" ]]; then
    lock_name="$(printf '%s-%s-%s' "$provider" "$release" "$arch" | tr -c 'A-Za-z0-9._-' '-')"
    exec {native_fd}>>"$out/locks/native-$lock_name.lock"; flock "$native_fd"
    if [[ ! -s "$native" ]] && ! phase_run "$target" "$arch" native-capture "$log" "$SELF/klab-native-rootfs.sh" capture "$provider" "$release" "$arch" </dev/null >>"$log" 2>&1; then
      flock -u "$native_fd"; exec {native_fd}>&-; status_append "$target" "$arch" FAIL native-capture "$log"; return 1
    fi
    flock -u "$native_fd"; exec {native_fd}>&-
  fi
  bundle="$KLAB_OFFLINE_ROOT/variants/$safe.klab"
  target_env="$KLAB_ROOT/targets/kernels/$provider/$release/$arch/$kernel/bundle.env"
  if [[ ! -f "$target_env" ]] || [[ ! -s "$bundle" ]]; then
    if ! phase_run "$target" "$arch" prepare "$log" "$SELF/kernel-lab.sh" prepare "$target" --arch "$arch" --userspace buildroot:minimal --with-sdk --distro-toolchain -o "$bundle" </dev/null >>"$log" 2>&1; then
      status_append "$target" "$arch" FAIL prepare "$log"; return 1
    fi
  fi
  # Preparation runs concurrently. Full QEMU validation defaults to one-at-a-time
  # because two native guests can exceed this laptop's RAM; opt in only on a host
  # sized for it. Interrupted validations may leave SSH keys and partial gate
  # output, so discard only reports that never recorded a final PASS.
  if [[ -d "$report" && "$(cat "$report/RESULT" 2>/dev/null || true)" != PASS ]]; then rm -rf "$report"; fi
  exec {validate_fd}>>"$out/locks/validate.lock"
  [[ "$parallel_validate" == 1 ]] || flock "$validate_fd"
  if phase_run "$target" "$arch" full "$report" timeout 3600 "$SELF/klab" validate "$target" --arch "$arch" --level full --report-dir "$report" </dev/null >>"$log" 2>&1; then
    status_append "$target" "$arch" PASS full "$report"; rc=0
  else
    status_append "$target" "$arch" FAIL full "$report"; rc=1
  fi
  [[ "$parallel_validate" == 1 ]] || flock -u "$validate_fd"
  exec {validate_fd}>&-; return "$rc"
}

run_worker() {
  local index="$1" row=0 target arch rc=0
  while IFS=$'\t' read -r target arch; do
    [[ "$target" != target ]] || continue
    if (( row % workers == index )); then run_target "$target" "$arch" || { [[ $? == 75 ]] && return 75; rc=1; }; fi
    row=$((row+1))
  done <"$work"
  return "$rc"
}

pids=(); for ((i=0; i<workers; i++)); do run_worker "$i" & pids+=("$!"); done
rc=0; for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
cat "$status"
exit "$rc"
