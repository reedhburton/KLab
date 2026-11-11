#!/usr/bin/env bash
# KLab focused Fedora vintage retry r7
# Reruns only Fedora 20 and Fedora 23. It reuses the fetched kernel target and
# reconstructed Koji buildroot RPM cache, and deliberately forces that fallback
# so no expired original Koji repo is used.
set -uo pipefail

SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB="${KLAB_DAY_KLAB:-$SELF_DIR/klab}"
[[ -x "$KLAB" ]] || KLAB="$SELF_DIR/kernel-lab.sh"
[[ -x "$KLAB" ]] || { echo "ERROR: KLab CLI not found in $SELF_DIR" >&2; exit 2; }

KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"
export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"
ARCH="${KLAB_DAY_ARCH:-x86_64}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ROOT="${KLAB_DAY_LOG_DIR:-$KLAB_ROOT/results/logs/daytime-retry-r7}/$RUN_ID"
ARTIFACT_DIR="${KLAB_DAY_ARTIFACT_DIR:-$KLAB_ROOT/transfer/exports/daytime-retry-r7}"
SUMMARY="$RUN_ROOT/summary.tsv"
MASTER="$RUN_ROOT/master.log"
RESULT_TAR="$KLAB_ROOT/results/daytime-retry-r7-${RUN_ID}-results.tar.gz"

mkdir -p "$RUN_ROOT/logs" "$ARTIFACT_DIR/fedora" "$KLAB_ROOT/results"
printf 'time\tphase\tlabel\tstatus\trc\tlog\tnote\n' >"$SUMMARY"
exec > >(tee -a "$MASTER") 2>&1

stamp(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
sanitize(){ printf '%s' "$1" | tr -cs 'A-Za-z0-9._+-' '_'; }
record(){ printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(stamp)" "$1" "$2" "$3" "$4" "$5" "${6:-}" >>"$SUMMARY"; }

run_case(){
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
fedora_fallback=always
fedora_strict_buildroot_repo=1
targets=fedora20,fedora23
INFO

echo "KLab focused Fedora vintage retry r7"
echo "  source: $SELF_DIR"
echo "  root:   $KLAB_ROOT"
echo "  note:   reuses kernel + Koji fallback caches; does not rerun Fedora 29+ or CentOS"

"$KLAB" init --staging >/dev/null 2>&1 || true

while IFS='|' read -r rel target; do
  [[ -n "$rel" ]] || continue
  label="fedora${rel}-${target#fedora:${rel}:}"
  out="$ARTIFACT_DIR/fedora/${label}.klab"
  script="KLAB_ROOT=$(printf %q "$KLAB_ROOT") KLAB_HOME=$(printf %q "$KLAB_ROOT") KLAB_REFETCH=0 KLAB_FEDORA_KOJI_FALLBACK=always KLAB_FEDORA_STRICT_BUILDROOT_REPO=1 $(printf %q "$KLAB") prepare $(printf %q "$target") --arch $(printf %q "$ARCH") --distro-toolchain --artifact-dir $(printf %q "$ARTIFACT_DIR/fedora") -o $(printf %q "$out") && $(printf %q "$KLAB") verify $(printf %q "$out")"
  run_case fedora-vintage "$label" "reuse fetched target + reconstructed Koji buildroot; targeted historical ABI/toolchain runtime sync + exact Koji buildroot; no release-repo auxiliary injection" "$script"
done <<'FEDORA'
20|fedora:20:3.14.9-200.fc20.x86_64
23|fedora:23:4.4.9-300.fc23.x86_64
FEDORA

find "$ARTIFACT_DIR" -maxdepth 2 -type f -printf '%s\t%p\n' 2>/dev/null | sort -n >"$RUN_ROOT/artifacts.tsv" || true
cat >"$RUN_ROOT/REVIEW-ME.txt" <<EOF_REVIEW
STATUS COUNTS
$(awk -F '\t' 'NR>1{c[$4]++} END{for(k in c) print k"\t"c[k]}' "$SUMMARY" | sort)

FAILED CASES
$(awk -F '\t' 'NR>1 && $4!="PASS"{print $2"\t"$3"\t"$4"\trc="$5"\t"$6}' "$SUMMARY")
EOF_REVIEW

parent="$(dirname "$RUN_ROOT")"; base="$(basename "$RUN_ROOT")"
tar -C "$parent" -czf "$RESULT_TAR" "$base"
echo; echo "Vintage Fedora retry complete. Upload:"; echo "  $RESULT_TAR"
echo "Summary:"; cat "$SUMMARY"
