#!/usr/bin/env bash
# KLab focused daytime retry r4
# Reuses the r3 caches and reruns only the still-failing Fedora/CentOS paths,
# plus a Debian 6.1 resolver sanity check. It intentionally does not refetch
# Fedora kernel payloads or reconstructed Koji RPM closures unless a cache is
# missing/invalid.
set -uo pipefail

SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB="${KLAB_DAY_KLAB:-$SELF_DIR/klab}"
[[ -x "$KLAB" ]] || KLAB="$SELF_DIR/kernel-lab.sh"
[[ -x "$KLAB" ]] || { echo "ERROR: KLab CLI not found in $SELF_DIR" >&2; exit 2; }

KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"
export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"
ARCH="${KLAB_DAY_ARCH:-x86_64}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ROOT="${KLAB_DAY_LOG_DIR:-$KLAB_ROOT/results/logs/daytime-retry-r4}/$RUN_ID"
ARTIFACT_DIR="${KLAB_DAY_ARTIFACT_DIR:-$KLAB_ROOT/transfer/exports/daytime-retry-r4}"
SUMMARY="$RUN_ROOT/summary.tsv"
MASTER="$RUN_ROOT/master.log"
RESULT_TAR="$KLAB_ROOT/results/daytime-retry-r4-${RUN_ID}-results.tar.gz"

mkdir -p "$RUN_ROOT/logs" "$ARTIFACT_DIR" "$KLAB_ROOT/results"
printf 'time\tphase\tlabel\tstatus\trc\tlog\tnote\n' >"$SUMMARY"
exec > >(tee -a "$MASTER") 2>&1

stamp(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
sanitize(){ printf '%s' "$1" | tr -cs 'A-Za-z0-9._+-' '_'; }
record(){ printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(stamp)" "$1" "$2" "$3" "$4" "$5" "${6:-}" >>"$SUMMARY"; }

run_case(){
  local phase="$1" label="$2" note="$3"; shift 3
  local log="$RUN_ROOT/logs/$(sanitize "$phase-$label").log" rc
  echo; echo "================================================================"; echo "[$phase] $label"; echo "LOG: $log"; echo "================================================================"
  printf 'COMMAND:' | tee -a "$log"; printf ' %q' "$@" | tee -a "$log"; printf '\n' | tee -a "$log"
  "$@" 2>&1 | tee -a "$log"; rc=${PIPESTATUS[0]}
  if (( rc == 0 )); then record "$phase" "$label" PASS 0 "$log" "$note"; else record "$phase" "$label" FAIL "$rc" "$log" "$note"; fi
  return 0
}

run_env(){
  local phase="$1" label="$2" note="$3" script="$4"
  local log="$RUN_ROOT/logs/$(sanitize "$phase-$label").log" rc
  echo; echo "================================================================"; echo "[$phase] $label"; echo "LOG: $log"; echo "SHELL: $script"; echo "================================================================"
  bash -o pipefail -c "$script" 2>&1 | tee -a "$log"; rc=${PIPESTATUS[0]}
  if (( rc == 0 )); then record "$phase" "$label" PASS 0 "$log" "$note"; else record "$phase" "$label" FAIL "$rc" "$log" "$note"; fi
  return 0
}

cat >"$RUN_ROOT/system-info.txt" <<INFO
run_id=$RUN_ID
started=$(stamp)
source=$SELF_DIR
klab=$KLAB
root=$KLAB_ROOT
arch=$ARCH
fedora_refetch=0
fedora_forced_fallback=29,44
INFO

echo "KLab focused retry r4"
echo "  source: $SELF_DIR"
echo "  root:   $KLAB_ROOT"
echo "  note:   existing Fedora target/fallback caches are reused and legacy repo metadata is upgraded in place"

run_case preflight init "staging initialization" "$KLAB" init --staging
run_case preflight doctor "dependency/provider sanity" "$KLAB" doctor

while IFS='|' read -r rel target; do
  [[ -n "$rel" ]] || continue
  mode=auto; case "$rel" in 29|44) mode=always;; esac
  label="fedora${rel}-${target#fedora:${rel}:}"
  out="$ARTIFACT_DIR/fedora/${label}.klab"; mkdir -p "$(dirname "$out")"
  script="KLAB_ROOT=$(printf %q "$KLAB_ROOT") KLAB_HOME=$(printf %q "$KLAB_ROOT") KLAB_REFETCH=0 KLAB_FEDORA_KOJI_FALLBACK=$mode $(printf %q "$KLAB") prepare $(printf %q "$target") --arch $(printf %q "$ARCH") --distro-toolchain --artifact-dir $(printf %q "$ARTIFACT_DIR/fedora") -o $(printf %q "$out")"
  run_env fedora-koji "$label" "reuse fetched target; fallback=$mode; rebuild buildenv/toolchain packaging" "$script"
done <<'FEDORA'
20|fedora:20:3.14.9-200.fc20.x86_64
23|fedora:23:4.4.9-300.fc23.x86_64
29|fedora:29:4.19.15-300.fc29.x86_64
42|fedora:42:6.14.11-300.fc42.x86_64
43|fedora:43:6.17.1-300.fc43.x86_64
44|fedora:44:7.0.14-201.fc44.x86_64
FEDORA

for target in centos:stream9:5.14.0-749.el9.x86_64 centos:stream10:6.12.0-269.el10.x86_64; do
  label="${target//:/-}"; out="$ARTIFACT_DIR/centos/${label}.klab"; mkdir -p "$(dirname "$out")"
  run_case centos "$label" "reuse cached kernel target; retest filtered/fail-fast RPM buildenv" \
    "$KLAB" prepare "$target" --arch "$ARCH" --distro-toolchain --artifact-dir "$ARTIFACT_DIR/centos" -o "$out"
done

# Resolver-only regression: 6.1 must never select 6.12.
deb_log="$RUN_ROOT/logs/debian-bookworm-6.1-resolver.log"
{
  "$KLAB" list debian:bookworm 6.1
} 2>&1 | tee "$deb_log"
rc=${PIPESTATUS[0]}
if (( rc == 0 )); then
  resolved="$({ grep -oE '[0-9]+\.[0-9]+\.[0-9]+(\+deb[0-9]+(\.[0-9]+)?|-[0-9]+)-amd64' "$deb_log" || true; } | grep -E '^6\.1([.+~-]|$)' | sort -Vu | tail -n1)"
  if [[ -n "$resolved" && ! "$resolved" =~ ^6\.12 ]]; then
    echo "Resolved Debian Bookworm 6.1 family: $resolved"
    record resolver debian-bookworm-6.1 PASS 0 "$deb_log" "resolved=$resolved; family boundary validated"
  else
    echo "ERROR: Debian 6.1 resolver selected no valid 6.1 kernel (candidate=${resolved:-none})" >&2
    record resolver debian-bookworm-6.1 FAIL 1 "$deb_log" "candidate=${resolved:-none}"
  fi
else
  record resolver debian-bookworm-6.1 FAIL "$rc" "$deb_log" "provider list failed"
fi

find "$ARTIFACT_DIR" -maxdepth 2 -type f -printf '%s\t%p\n' 2>/dev/null | sort -n >"$RUN_ROOT/artifacts.tsv" || true
cat >"$RUN_ROOT/REVIEW-ME.txt" <<EOF_REVIEW
STATUS COUNTS
$(awk -F '\t' 'NR>1{c[$4]++} END{for(k in c) print k"\t"c[k]}' "$SUMMARY" | sort)

FAILED CASES
$(awk -F '\t' 'NR>1 && $4!="PASS"{print $2"\t"$3"\t"$4"\trc="$5"\t"$6}' "$SUMMARY")
EOF_REVIEW

parent="$(dirname "$RUN_ROOT")"; base="$(basename "$RUN_ROOT")"
tar -C "$parent" -czf "$RESULT_TAR" "$base"
echo; echo "Focused retry complete. Upload this result archive:"; echo "  $RESULT_TAR"
echo "Summary:"; cat "$SUMMARY"
