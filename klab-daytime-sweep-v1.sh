#!/usr/bin/env bash
# KLab daytime compatibility sweep v1
# Runs targeted regressions from the 0.0.0b audit, exercises Fedora's direct
# Koji package-build fallback, then launches the broad cross-distro queue.
# All failures are logged and the sweep continues.
set -uo pipefail

SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB="${KLAB_DAY_KLAB:-$SELF_DIR/klab}"
[[ -x "$KLAB" ]] || KLAB="$SELF_DIR/kernel-lab.sh"
[[ -x "$KLAB" ]] || { echo "ERROR: KLab CLI not found in $SELF_DIR" >&2; exit 2; }

KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"
export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"
ARCH="${KLAB_DAY_ARCH:-x86_64}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ROOT="${KLAB_DAY_LOG_DIR:-$KLAB_ROOT/results/logs/daytime-sweep}/$RUN_ID"
ARTIFACT_DIR="${KLAB_DAY_ARTIFACT_DIR:-$KLAB_ROOT/transfer/exports/daytime-sweep}"
SUMMARY="$RUN_ROOT/summary.tsv"
MASTER="$RUN_ROOT/master.log"
RESULT_TAR="$KLAB_ROOT/results/daytime-sweep-${RUN_ID}-results.tar.gz"
FORCE_FEDORA="${KLAB_DAY_FORCE_FEDORA_FALLBACK:-29,44}"
FEDORA_REFETCH="${KLAB_DAY_FEDORA_REFETCH:-1}"
DO_UBUNTU="${KLAB_DAY_UBUNTU:-1}"
DO_FEDORA="${KLAB_DAY_FEDORA:-1}"
DO_CROSS="${KLAB_DAY_CROSS_DISTRO:-1}"
CROSS_SECTIONS="${KLAB_DAY_CROSS_SECTIONS:-mint,debian,centos,arch,manjaro,oracle,amazon,opensuse,kali,proxmox,rocky,alma,alpine}"

mkdir -p "$RUN_ROOT/logs" "$ARTIFACT_DIR" "$KLAB_ROOT/results"
printf 'time\tphase\tlabel\tstatus\trc\tlog\tnote\n' >"$SUMMARY"
exec > >(tee -a "$MASTER") 2>&1

stamp(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
sanitize(){ printf '%s' "$1" | tr -cs 'A-Za-z0-9._+-' '_'; }
record(){ printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(stamp)" "$1" "$2" "$3" "$4" "$5" "${6:-}" >>"$SUMMARY"; }

run_case(){
  local phase="$1" label="$2" note="$3"; shift 3
  local log="$RUN_ROOT/logs/$(sanitize "$phase-$label").log" rc
  echo
  echo "================================================================"
  echo "[$phase] $label"
  echo "LOG: $log"
  echo "================================================================"
  printf 'COMMAND:' | tee -a "$log"
  printf ' %q' "$@" | tee -a "$log"
  printf '\n' | tee -a "$log"
  "$@" 2>&1 | tee -a "$log"
  rc=${PIPESTATUS[0]}
  if (( rc == 0 )); then record "$phase" "$label" PASS 0 "$log" "$note"; else record "$phase" "$label" FAIL "$rc" "$log" "$note"; fi
  return 0
}

run_env_case(){
  local phase="$1" label="$2" note="$3" script="$4"
  local log="$RUN_ROOT/logs/$(sanitize "$phase-$label").log" rc
  echo
  echo "================================================================"
  echo "[$phase] $label"
  echo "LOG: $log"
  echo "SHELL: $script"
  echo "================================================================"
  bash -o pipefail -c "$script" 2>&1 | tee -a "$log"
  rc=${PIPESTATUS[0]}
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
force_fedora_fallback=$FORCE_FEDORA
cross_sections=$CROSS_SECTIONS
host_uname=$(uname -a)
container_runtime=$(command -v podman || command -v docker || echo none)
INFO
df -h "$KLAB_ROOT" >>"$RUN_ROOT/system-info.txt" 2>&1 || true
free_kb="$(df -Pk "$KLAB_ROOT" 2>/dev/null | awk 'NR==2{print $4+0}')"
if [[ "${free_kb:-0}" -lt 20971520 ]]; then
  echo "WARNING: less than 20 GiB free under $KLAB_ROOT. Fedora package-build fallback plus the broad cross-distro sweep can consume substantial staging/cache space."
fi

run_case preflight init "staging initialization" "$KLAB" init --staging
run_case preflight doctor "dependency/provider sanity" "$KLAB" doctor

if [[ "$DO_UBUNTU" == 1 ]]; then
  # These are the exact three Ubuntu failures from the prior sweep.
  while IFS='|' read -r label target; do
    [[ -n "$label" ]] || continue
    run_case ubuntu-regression "$label" "retest prior Ubuntu failure" \
      "$KLAB" prepare "$target" --arch "$ARCH" --distro-toolchain \
      --artifact-dir "$ARTIFACT_DIR/ubuntu" -o "$ARTIFACT_DIR/ubuntu/${label}.klab"
  done <<'UBUNTU'
ubuntu1404-3.13.0-200-generic|ubuntu:14.04:3.13.0-200-generic
ubuntu2204-6.8.0-138-generic|ubuntu:22.04:6.8.0-138-generic
ubuntu2404-6.8.0-142-lowlatency|ubuntu:24.04:6.8.0-142-lowlatency
UBUNTU
fi

if [[ "$DO_FEDORA" == 1 ]]; then
  # Representative targets span every Fedora failure generation from the audit.
  while IFS='|' read -r rel target; do
    [[ -n "$rel" ]] || continue
    mode=auto
    case ",$FORCE_FEDORA," in *",$rel,"*) mode=always;; esac
    label="fedora${rel}-$(sanitize "${target##*:}")"
    # KLAB_REFETCH=1 ensures an older cached target cannot bypass the new
    # koji-buildroot.json capture.  'always' deliberately forces the package
    # reconstruction path even if the original Koji repo still exists.
    cmd="KLAB_ROOT=$(printf %q "$KLAB_ROOT") KLAB_HOME=$(printf %q "$KLAB_ROOT") KLAB_REFETCH=$FEDORA_REFETCH KLAB_FEDORA_KOJI_FALLBACK=$mode $(printf %q "$KLAB") prepare $(printf %q "$target") --arch $(printf %q "$ARCH") --distro-toolchain --artifact-dir $(printf %q "$ARTIFACT_DIR/fedora") -o $(printf %q "$ARTIFACT_DIR/fedora/${label}.klab")"
    run_env_case fedora-koji "$label" "fallback=$mode; exact Koji buildroot/toolchain test" "$cmd"
  done <<'FEDORA'
20|fedora:20:3.14.9-200.fc20.x86_64
23|fedora:23:4.4.9-300.fc23.x86_64
29|fedora:29:4.19.15-300.fc29.x86_64
42|fedora:42:6.14.11-300.fc42.x86_64
43|fedora:43:6.17.1-300.fc43.x86_64
44|fedora:44:7.0.14-201.fc44.x86_64
FEDORA
fi

if [[ "$DO_CROSS" == 1 ]]; then
  CROSS="$SELF_DIR/klab-cross-distro-queue-v2.sh"
  if [[ -x "$CROSS" ]]; then
    cross_log_root="$RUN_ROOT/cross-distro"
    cmd="KLAB_ROOT=$(printf %q "$KLAB_ROOT") KLAB_SRC=$(printf %q "$SELF_DIR") KLAB_CROSS_ARCH=$(printf %q "$ARCH") KLAB_CROSS_SECTIONS=$(printf %q "$CROSS_SECTIONS") KLAB_CROSS_STRICT_EXIT=0 KLAB_CROSS_LOG_DIR=$(printf %q "$cross_log_root") KLAB_CROSS_EXPORT_DIR=$(printf %q "$ARTIFACT_DIR/cross-distro") $(printf %q "$CROSS")"
    run_env_case cross-distro broad "broad distribution acquisition/registration sweep" "$cmd"
    nested_summary="$(find "$cross_log_root" -name summary.tsv -type f -print 2>/dev/null | sort | tail -n1)"
    if [[ -n "$nested_summary" && -f "$nested_summary" ]]; then
      nested_bad="$(awk -F '\t' 'NR>1 && $5 !~ /^(PASS|SKIP_VERIFIED)$/ {n++} END{print n+0}' "$nested_summary")"
      if (( nested_bad == 0 )); then
        record cross-distro-results broad PASS 0 "$nested_summary" "all nested targets passed or were verified"
      else
        record cross-distro-results broad PARTIAL "$nested_bad" "$nested_summary" "$nested_bad nested non-success result(s); inspect nested summary"
      fi
    fi
  else
    record cross-distro broad SKIP 0 "" "missing $CROSS"
  fi
fi

find "$ARTIFACT_DIR" -maxdepth 3 -type f -printf '%s\t%p\n' 2>/dev/null | sort -n >"$RUN_ROOT/artifacts.tsv" || true
printf '\nSTATUS COUNTS\n' >"$RUN_ROOT/REVIEW-ME.txt"
awk -F '\t' 'NR>1{c[$4]++}END{for(k in c)printf "%s\t%d\n",k,c[k]}' "$SUMMARY" | sort >>"$RUN_ROOT/REVIEW-ME.txt"
printf '\nFAILED TOP-LEVEL CASES\n' >>"$RUN_ROOT/REVIEW-ME.txt"
awk -F '\t' 'NR>1 && $4=="FAIL"{print $2"\t"$3"\trc="$5"\t"$6}' "$SUMMARY" >>"$RUN_ROOT/REVIEW-ME.txt"
printf '\nCross-distro summaries (if any):\n' >>"$RUN_ROOT/REVIEW-ME.txt"
while IFS= read -r nested; do
  [[ -n "$nested" ]] || continue
  printf '%s\n' "$nested" >>"$RUN_ROOT/REVIEW-ME.txt"
  awk -F '\t' 'NR>1{c[$5]++}END{for(k in c)printf "  %s\t%d\n",k,c[k]}' "$nested" | sort >>"$RUN_ROOT/REVIEW-ME.txt"
  awk -F '\t' 'NR>1 && $5 !~ /^(PASS|SKIP_VERIFIED)$/ {print "  " $2 "\t" $3 "\t" $5 "\trc=" $6}' "$nested" >>"$RUN_ROOT/REVIEW-ME.txt"
done < <(find "$RUN_ROOT/cross-distro" -name summary.tsv -type f -print 2>/dev/null | sort)

# The review bundle intentionally excludes kernel/.klab artifacts; it contains
# only logs and summaries and is therefore convenient to upload back for audit.
tar -C "$(dirname "$RUN_ROOT")" -czf "$RESULT_TAR" "$(basename "$RUN_ROOT")"
ln -sfn "$RUN_ROOT" "$(dirname "$RUN_ROOT")/latest" 2>/dev/null || true
cp -f "$SUMMARY" "$KLAB_ROOT/results/daytime-sweep-latest-summary.tsv" 2>/dev/null || true

echo
echo "################ DAYTIME SWEEP COMPLETE ################"
column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
echo
echo "Review bundle: $RESULT_TAR"
echo "Summary:       $SUMMARY"
echo "Master log:    $MASTER"
echo "Upload the review bundle when you return; it excludes the large kernel artifacts."
exit 0
