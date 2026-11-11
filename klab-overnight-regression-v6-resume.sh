#!/usr/bin/env bash
# KLab overnight heavy all-path regression v6 (power-loss resumable)
#
# Heavy regression sweep for the r9 tree. Fedora 20 may remain a known failure; the run continues regardless.  It attempts every major path we
# have exercised during the 0.0.0b hardening cycle:
#   * network-free regression suite
#   * the complete original Ubuntu exact-target matrix
#   * all historical/modern Fedora generations from the wide sweep
#   * every upstream kernel from v3.0 through v7.2.7 used in the wide sweep
#   * FreeBSD x86_64 provider prepare/smoke
#   * the complete cross-distro queue (Mint/LMDE, Debian, CentOS, Arch,
#     Manjaro, Oracle, Amazon, openSUSE, Kali, Proxmox, Rocky, Alma, Alpine)
#   * bundle verification and QEMU smoke tests for successfully prepared targets
#
# The run is intentionally failure-tolerant and cache-aware.  Existing provider
# caches and staged external distro roots are reused, while regression artifacts
# are written to a fresh run-specific export tree.  Fedora releases that were
# never refreshed with Koji buildroot provenance are selectively refetched.
#
# Usage:
#   cd /path/to/klab-0.0.0b-r7
#   export KLAB_ROOT="$HOME/klab"
#   ./klab-overnight-regression-v6-resume.sh
#
# Useful overrides:
#   KLAB_OVERNIGHT_SMOKE=0                  # skip QEMU smoke tests
#   KLAB_OVERNIGHT_UNIT_TESTS=0             # skip tests/run-all.sh
#   KLAB_OVERNIGHT_CROSS_DISTRO=0           # skip broad cross-distro queue
#   KLAB_OVERNIGHT_FREEBSD=0                # skip FreeBSD x86_64
#   KLAB_OVERNIGHT_JOBS=4                   # kernel build jobs
#   KLAB_OVERNIGHT_CASE_TIMEOUT=7200         # seconds per prepare/smoke case
#   KLAB_OVERNIGHT_UNIT_TIMEOUT=14400        # seconds for tests/run-all.sh
#   KLAB_OVERNIGHT_FEDORA_REFETCH_ALL=1      # force refetch every Fedora target
#   KLAB_OVERNIGHT_CROSS_RECAPTURE=all       # deliberately redownload external roots
#   KLAB_OVERNIGHT_EXTRA=1                   # add dynamically sampled Ubuntu + extra upstream branches (default)
#   KLAB_OVERNIGHT_EXTRA_SMOKE=0             # do not QEMU-smoke extra cases (default)
#   KLAB_OVERNIGHT_UBUNTU_GENERIC_SAMPLES=3  # evenly-spaced generic kernels per Ubuntu release
#   KLAB_OVERNIGHT_UBUNTU_FLAVOR_SAMPLES=1   # samples per non-generic flavor/release
#   KLAB_OVERNIGHT_DRY_RUN=1                 # print/generate summaries only
#   KLAB_OVERNIGHT_RESUME_RUN_ID=latest       # resume newest interrupted run in-place
#   KLAB_OVERNIGHT_RESUME_RUN_ID=<RUN_ID>     # resume a specific run
#   KLAB_OVERNIGHT_RESUME_RETRY_FAILED=1      # on resume, retry completed FAIL/TIMEOUT/PROBE_FAIL cases
#
# Result hand-back:
#   $KLAB_ROOT/results/overnight-regression-<RUN_ID>-results.tar.gz
# This archive contains logs and summaries only; large .klab artifacts stay in
# the transfer tree.

set -uo pipefail

SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB="${KLAB_OVERNIGHT_KLAB:-$SELF_DIR/klab}"
[[ -x "$KLAB" ]] || KLAB="$SELF_DIR/kernel-lab.sh"
[[ -x "$KLAB" ]] || { echo "ERROR: KLab CLI not found in $SELF_DIR" >&2; exit 2; }

KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"
export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"
ARCH="${KLAB_OVERNIGHT_ARCH:-x86_64}"
DO_SMOKE="${KLAB_OVERNIGHT_SMOKE:-1}"
DO_UNIT="${KLAB_OVERNIGHT_UNIT_TESTS:-1}"
DO_CROSS="${KLAB_OVERNIGHT_CROSS_DISTRO:-1}"
DO_FREEBSD="${KLAB_OVERNIGHT_FREEBSD:-1}"
DRY_RUN="${KLAB_OVERNIGHT_DRY_RUN:-0}"
CASE_TIMEOUT="${KLAB_OVERNIGHT_CASE_TIMEOUT:-7200}"
UNIT_TIMEOUT="${KLAB_OVERNIGHT_UNIT_TIMEOUT:-14400}"
FEDORA_REFETCH_ALL="${KLAB_OVERNIGHT_FEDORA_REFETCH_ALL:-0}"
CROSS_RECAPTURE="${KLAB_OVERNIGHT_CROSS_RECAPTURE:-}"
DO_EXTRA="${KLAB_OVERNIGHT_EXTRA:-1}"
EXTRA_SMOKE="${KLAB_OVERNIGHT_EXTRA_SMOKE:-0}"
UBUNTU_GENERIC_SAMPLES="${KLAB_OVERNIGHT_UBUNTU_GENERIC_SAMPLES:-3}"
UBUNTU_FLAVOR_SAMPLES="${KLAB_OVERNIGHT_UBUNTU_FLAVOR_SAMPLES:-1}"
[[ -n "${KLAB_OVERNIGHT_JOBS:-}" ]] && export KLAB_JOBS="$KLAB_OVERNIGHT_JOBS"

LOG_BASE="${KLAB_OVERNIGHT_LOG_DIR:-$KLAB_ROOT/results/logs/overnight-regression}"
ARTIFACT_BASE="${KLAB_OVERNIGHT_ARTIFACT_DIR:-$KLAB_ROOT/transfer/exports/overnight-regression}"
RESUME_RUN_ID="${KLAB_OVERNIGHT_RESUME_RUN_ID:-}"
RESUME_RETRY_FAILED="${KLAB_OVERNIGHT_RESUME_RETRY_FAILED:-0}"
RESUMING=0
if [[ -n "$RESUME_RUN_ID" ]]; then
  if [[ "$RESUME_RUN_ID" == latest ]]; then
    RESUME_RUN_ID="$(find "$LOG_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | LC_ALL=C sort | tail -n1)"
    [[ -n "$RESUME_RUN_ID" ]] || { echo "ERROR: no prior overnight run exists under $LOG_BASE" >&2; exit 2; }
  fi
  RUN_ID="$RESUME_RUN_ID"
  RESUMING=1
else
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
fi
RUN_ROOT="$LOG_BASE/$RUN_ID"
ARTIFACT_ROOT="$ARTIFACT_BASE/$RUN_ID"
SUMMARY="$RUN_ROOT/summary.tsv"
MASTER="$RUN_ROOT/master.log"
RESULT_TAR="$KLAB_ROOT/results/overnight-regression-${RUN_ID}-results.tar.gz"
CROSS_LOG_ROOT="$RUN_ROOT/cross-distro"
CROSS_ARTIFACT_ROOT="$ARTIFACT_ROOT/cross-distro"

mkdir -p "$RUN_ROOT/logs" "$ARTIFACT_ROOT" "$KLAB_ROOT/results"
if (( RESUMING )); then
  [[ -s "$SUMMARY" ]] || { echo "ERROR: cannot resume $RUN_ID: missing $SUMMARY" >&2; exit 2; }
  cp -f "$SUMMARY" "$RUN_ROOT/summary.pre-resume-$(date -u +%Y%m%dT%H%M%SZ).tsv"
else
  printf 'time\tphase\tlabel\ttarget\texpected\tstatus\trc\tduration_s\toutput\tlog\tnote\n' >"$SUMMARY"
fi
exec > >(tee -a "$MASTER") 2>&1

stamp(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
sanitize(){ printf '%s' "$1" | tr -cs 'A-Za-z0-9._+-' '_'; }

classify(){
  local expected="$1" rc="$2"
  if (( rc == 0 )); then
    case "$expected" in
      KNOWN_FAIL|RC40) printf 'IMPROVEMENT\n' ;;
      *) printf 'PASS\n' ;;
    esac
    return
  fi
  if (( rc == 124 )); then printf 'TIMEOUT\n'; return; fi
  case "$expected" in
    KNOWN_FAIL) printf 'KNOWN_FAIL\n' ;;
    PROBE) printf 'PROBE_FAIL\n' ;;
    RC40) [[ "$rc" == 40 ]] && printf 'EXPECTED_FAIL\n' || printf 'FAIL\n' ;;
    *) printf 'FAIL\n' ;;
  esac
}

record(){
  local phase="$1" label="$2" target="$3" expected="$4" status="$5" rc="$6" dur="$7" output="$8" log="$9" note="${10:-}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(stamp)" "$phase" "$label" "$target" "$expected" "$status" "$rc" "$dur" "$output" "$log" "$note" >>"$SUMMARY"
}

resume_case_info(){
  local phase="$1" label="$2"
  awk -F '\t' -v p="$phase" -v l="$label" '
    NR>1 && $2==p && $3==l { rc=$7; status=$6; lg=$10; out=$9; found=1 }
    END { if(found) printf "%s\t%s\t%s\t%s\n", rc, status, lg, out }
  ' "$SUMMARY"
}

run_shell_case(){
  local phase="$1" label="$2" target="$3" expected="$4" output="$5" note="$6" script="$7" timeout_s="${8:-$CASE_TIMEOUT}"
  local log="$RUN_ROOT/logs/$(sanitize "$phase-$label").log" rc start end dur status prev prev_rc prev_status prev_log prev_output
  if (( RESUMING )); then
    prev="$(resume_case_info "$phase" "$label")"
    if [[ -n "$prev" ]]; then
      IFS=$'\t' read -r prev_rc prev_status prev_log prev_output <<<"$prev"
      retry=0
      if [[ "$RESUME_RETRY_FAILED" == 1 ]]; then
        case "$prev_status" in FAIL|TIMEOUT|PROBE_FAIL) retry=1;; esac
      fi
      if [[ "$prev_status" == DRY_RUN && "$DRY_RUN" != 1 ]]; then retry=1; fi
      # A successful prepare record is reusable only while its artifact still exists.
      case "$phase" in ubuntu|ubuntu-extra|fedora|upstream|upstream-extra|freebsd)
        if [[ "$prev_status" == PASS || "$prev_status" == IMPROVEMENT ]] && [[ -n "$output" && ! -s "$output" ]]; then retry=1; fi
        ;;
      esac
      if (( retry == 0 )); then
        echo
        echo "================================================================"
        echo "[resume-skip] $phase / $label"
        echo "previous status=$prev_status rc=$prev_rc"
        echo "previous log=${prev_log:-$log}"
        echo "================================================================"
        LAST_RC="${prev_rc:-0}"; LAST_STATUS="$prev_status"; LAST_LOG="${prev_log:-$log}"
        return 0
      fi
      echo "[resume-retry] $phase / $label previous status=$prev_status rc=$prev_rc"
    fi
  fi
  echo
  echo "================================================================"
  echo "[$phase] $label"
  echo "TARGET:   $target"
  echo "EXPECTED: $expected"
  echo "LOG:      $log"
  echo "SHELL:    $script"
  echo "================================================================"
  start="$(date +%s)"
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: not executed" | tee -a "$log"
    rc=0; note="dry-run; $note"
  else
    if command -v timeout >/dev/null 2>&1 && [[ "$timeout_s" =~ ^[0-9]+$ ]] && (( timeout_s > 0 )); then
      timeout --foreground "$timeout_s" bash -o pipefail -c "$script" 2>&1 | tee -a "$log"
      rc=${PIPESTATUS[0]}
    else
      bash -o pipefail -c "$script" 2>&1 | tee -a "$log"
      rc=${PIPESTATUS[0]}
    fi
  fi
  end="$(date +%s)"; dur=$((end-start))
  if [[ "$DRY_RUN" == 1 ]]; then status=DRY_RUN; else status="$(classify "$expected" "$rc")"; fi
  record "$phase" "$label" "$target" "$expected" "$status" "$rc" "$dur" "$output" "$log" "$note"
  LAST_RC="$rc"; LAST_STATUS="$status"; LAST_LOG="$log"
  return 0
}

verify_and_smoke(){
  local group="$1" label="$2" target="$3" output="$4"
  [[ "$DRY_RUN" == 1 ]] && return 0
  [[ -s "$output" ]] || return 0
  run_shell_case verify "$group-$label" "$target" PASS "$output" "verify freshly produced regression bundle" \
    "$(printf %q "$KLAB") verify $(printf %q "$output")"
  if [[ "$DO_SMOKE" == 1 ]]; then
    run_shell_case smoke "$group-$label" "$target" PASS "" "build built-in module, boot QEMU, insmod, execute guest test" \
      "$(printf %q "$KLAB") smoke $(printf %q "$target") --arch $(printf %q "$ARCH")"
  fi
}

if (( RESUMING )); then
  cat >>"$RUN_ROOT/system-info.txt" <<INFO

--- resume ---
resumed=$(stamp)
resume_source=$SELF_DIR
resume_retry_failed=$RESUME_RETRY_FAILED
INFO
else
cat >"$RUN_ROOT/system-info.txt" <<INFO
run_id=$RUN_ID
started=$(stamp)
source=$SELF_DIR
klab=$KLAB
root=$KLAB_ROOT
arch=$ARCH
smoke=$DO_SMOKE
unit_tests=$DO_UNIT
cross_distro=$DO_CROSS
freebsd=$DO_FREEBSD
case_timeout=$CASE_TIMEOUT
unit_timeout=$UNIT_TIMEOUT
jobs=${KLAB_JOBS:-default}
fedora_refetch_all=$FEDORA_REFETCH_ALL
cross_recapture=${CROSS_RECAPTURE:-none}
extra_matrix=$DO_EXTRA
extra_smoke=$EXTRA_SMOKE
ubuntu_generic_samples=$UBUNTU_GENERIC_SAMPLES
ubuntu_flavor_samples=$UBUNTU_FLAVOR_SAMPLES
host_uname=$(uname -a)
container_runtime=$(command -v podman || command -v docker || echo none)
INFO
fi

df -h "$KLAB_ROOT" >>"$RUN_ROOT/system-info.txt" 2>&1 || true
avail_kb="$(df -Pk "$KLAB_ROOT" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)"
if [[ "$avail_kb" =~ ^[0-9]+$ ]] && (( avail_kb < 30*1024*1024 )); then
  echo "WARNING: less than 30 GiB free under $KLAB_ROOT; overnight artifacts may exhaust space."
fi

run_shell_case preflight init "init --staging" PASS "" "staging initialization" \
  "$(printf %q "$KLAB") init --staging"
run_shell_case preflight doctor doctor PASS "" "dependency/provider sanity" \
  "$(printf %q "$KLAB") doctor"

if [[ "$DO_UNIT" == 1 && -x "$SELF_DIR/tests/run-all.sh" ]]; then
  run_shell_case unit-tests network-free-suite tests/run-all.sh PASS "" "full packaged network-free regression suite" \
    "cd $(printf %q "$SELF_DIR") && ./tests/run-all.sh" "$UNIT_TIMEOUT"
fi

# ---------------------------------------------------------------------------
# Complete Ubuntu matrix from the original wide sweep.
# All targets are expected to prepare now except the unavailable Trusty
# 3.13.0-200 exact package, where rc=40 is the expected policy result.
# ---------------------------------------------------------------------------
while IFS='|' read -r label target expected; do
  [[ -n "$label" && "${label:0:1}" != '#' ]] || continue
  out="$ARTIFACT_ROOT/ubuntu/${label}.klab"; mkdir -p "$(dirname "$out")"
  script="KLAB_ROOT=$(printf %q "$KLAB_ROOT") KLAB_HOME=$(printf %q "$KLAB_ROOT") KLAB_REFETCH=0 $(printf %q "$KLAB") prepare $(printf %q "$target") --arch $(printf %q "$ARCH") --distro-toolchain --artifact-dir $(printf %q "$(dirname "$out")") -o $(printf %q "$out")"
  run_shell_case ubuntu "$label" "$target" "$expected" "$out" "fresh regression artifact; reuse cached kernel package when available" "$script"
  [[ "$LAST_RC" == 0 ]] && verify_and_smoke ubuntu "$label" "$target" "$out"
done <<'UBUNTU_MATRIX'
ubuntu1204-3.2.0-150-generic|ubuntu:12.04:3.2.0-150-generic|PASS
ubuntu1404-3.13.0-200-generic|ubuntu:14.04:3.13.0-200-generic|RC40
ubuntu1604-4.4.0-210-generic|ubuntu:16.04:4.4.0-210-generic|PASS
ubuntu1704-4.10.0-42-generic|ubuntu:17.04:4.10.0-42-generic|PASS
ubuntu1804-4.15.0-213-generic|ubuntu:18.04:4.15.0-213-generic|PASS
ubuntu2004-5.4.0-216-generic|ubuntu:20.04:5.4.0-216-generic|PASS
ubuntu2004-5.15.0-139-generic|ubuntu:20.04:5.15.0-139-generic|PASS
ubuntu2204-5.15.0-194-generic|ubuntu:22.04:5.15.0-194-generic|PASS
ubuntu2204-6.8.0-138-generic|ubuntu:22.04:6.8.0-138-generic|PASS
ubuntu2404-6.8.0-142-generic|ubuntu:24.04:6.8.0-142-generic|PASS
ubuntu2404-6.11.0-29-generic|ubuntu:24.04:6.11.0-29-generic|PASS
ubuntu2404-6.14.0-37-generic|ubuntu:24.04:6.14.0-37-generic|PASS
ubuntu2404-6.17.0-42-generic|ubuntu:24.04:6.17.0-42-generic|PASS
ubuntu2604-7.0.0-34-generic|ubuntu:26.04:7.0.0-34-generic|PASS
ubuntu1804-5.4.0-1109-azure|ubuntu:18.04:5.4.0-1109-azure|PASS
ubuntu2004-5.4.0-1151-azure|ubuntu:20.04:5.4.0-1151-azure|PASS
ubuntu2204-5.15.0-1122-azure|ubuntu:22.04:5.15.0-1122-azure|PASS
ubuntu2404-6.8.0-1068-azure|ubuntu:24.04:6.8.0-1068-azure|PASS
ubuntu2604-7.0.0-1014-azure|ubuntu:26.04:7.0.0-1014-azure|PASS
ubuntu2004-5.4.0-216-lowlatency|ubuntu:20.04:5.4.0-216-lowlatency|PASS
ubuntu2204-5.15.0-1116-aws|ubuntu:22.04:5.15.0-1116-aws|PASS
ubuntu2204-5.15.0-1117-gcp|ubuntu:22.04:5.15.0-1117-gcp|PASS
ubuntu2404-6.8.0-1063-aws|ubuntu:24.04:6.8.0-1063-aws|PASS
ubuntu2404-6.8.0-1069-gcp|ubuntu:24.04:6.8.0-1069-gcp|PASS
ubuntu2404-6.8.0-1062-oracle|ubuntu:24.04:6.8.0-1062-oracle|PASS
ubuntu2404-6.8.0-142-lowlatency|ubuntu:24.04:6.8.0-142-lowlatency|PASS
UBUNTU_MATRIX

# ---------------------------------------------------------------------------
# Complete Fedora generation matrix.  The six r4/r5 generations reuse their
# expensive Koji provenance caches.  Five generations not refreshed during the
# focused redesign are selectively refetched once to guarantee they receive the
# new Koji buildroot metadata.
# ---------------------------------------------------------------------------
while IFS='|' read -r label target refetch fallback expected; do
  [[ -n "$label" && "${label:0:1}" != '#' ]] || continue
  [[ "$FEDORA_REFETCH_ALL" == 1 ]] && refetch=1
  expected="${expected:-PASS}"
  out="$ARTIFACT_ROOT/fedora/${label}.klab"; mkdir -p "$(dirname "$out")"
  script="KLAB_ROOT=$(printf %q "$KLAB_ROOT") KLAB_HOME=$(printf %q "$KLAB_ROOT") KLAB_REFETCH=$refetch KLAB_FEDORA_KOJI_FALLBACK=$fallback $(printf %q "$KLAB") prepare $(printf %q "$target") --arch $(printf %q "$ARCH") --distro-toolchain --artifact-dir $(printf %q "$(dirname "$out")") -o $(printf %q "$out")"
  run_shell_case fedora "$label" "$target" "$expected" "$out" "Koji-pinned distro toolchain/buildenv; refetch=$refetch fallback=$fallback" "$script"
  [[ "$LAST_RC" == 0 ]] && verify_and_smoke fedora "$label" "$target" "$out"
done <<'FEDORA_MATRIX'
fedora20-3.14.9-200|fedora:20:3.14.9-200.fc20.x86_64|0|always|KNOWN_FAIL
fedora23-4.4.9-300|fedora:23:4.4.9-300.fc23.x86_64|0|always|PASS
fedora26-4.14.18-200|fedora:26:4.14.18-200.fc26.x86_64|1|auto|PASS
fedora29-4.19.15-300|fedora:29:4.19.15-300.fc29.x86_64|0|always|PASS
fedora32-5.10.22-100|fedora:32:5.10.22-100.fc32.x86_64|1|auto|PASS
fedora35-5.15.18-200|fedora:35:5.15.18-200.fc35.x86_64|1|auto|PASS
fedora38-6.2.15-300|fedora:38:6.2.15-300.fc38.x86_64|1|auto|PASS
fedora40-6.8.11-300|fedora:40:6.8.11-300.fc40.x86_64|1|auto|PASS
fedora42-6.14.11-300|fedora:42:6.14.11-300.fc42.x86_64|0|auto|PASS
fedora43-6.17.1-300|fedora:43:6.17.1-300.fc43.x86_64|0|auto|PASS
fedora44-7.0.14-201|fedora:44:7.0.14-201.fc44.x86_64|0|always|PASS
FEDORA_MATRIX

# ---------------------------------------------------------------------------
# Upstream matrix.  Previously-good kernels are regression expectations.
# Previously-failing vintage kernels are still attempted and recorded as
# KNOWN_FAIL rather than hiding them.  A surprise pass becomes IMPROVEMENT.
# ---------------------------------------------------------------------------
while IFS='|' read -r label target expected; do
  [[ -n "$label" && "${label:0:1}" != '#' ]] || continue
  out="$ARTIFACT_ROOT/upstream/${label}.klab"; mkdir -p "$(dirname "$out")"
  run_shell_case upstream "$label" "$target" "$expected" "$out" "full current-source rebuild; source/toolchain caches may be reused" \
    "$(printf %q "$KLAB") prepare $(printf %q "$target") --arch $(printf %q "$ARCH") --artifact-dir $(printf %q "$(dirname "$out")") -o $(printf %q "$out")"
  [[ "$LAST_RC" == 0 ]] && verify_and_smoke upstream "$label" "$target" "$out"
done <<'UPSTREAM_MATRIX'
upstream-3.0|upstream:v3.0|KNOWN_FAIL
upstream-3.2|upstream:v3.2|KNOWN_FAIL
upstream-3.10|upstream:v3.10|KNOWN_FAIL
upstream-3.16|upstream:v3.16|KNOWN_FAIL
upstream-4.0|upstream:v4.0|KNOWN_FAIL
upstream-4.4|upstream:v4.4|KNOWN_FAIL
upstream-4.9|upstream:v4.9|PASS
upstream-4.14|upstream:v4.14|KNOWN_FAIL
upstream-4.19|upstream:v4.19|KNOWN_FAIL
upstream-5.4|upstream:v5.4|KNOWN_FAIL
upstream-5.10|upstream:v5.10|KNOWN_FAIL
upstream-5.15|upstream:v5.15|PASS
upstream-6.1|upstream:v6.1|PASS
upstream-6.6|upstream:v6.6|PASS
upstream-6.12|upstream:v6.12|PASS
upstream-7.0|upstream:v7.0|PASS
upstream-7.2.7|upstream:v7.2.7|PASS
UPSTREAM_MATRIX

# ---------------------------------------------------------------------------
# Heavy extra matrix.
#
# Ubuntu: discover the exact installable kernel releases exposed by each
# release's configured archive, then sample across time instead of hardcoding
# dozens of fragile ABI numbers.  This gives broad ABI/flavor coverage while
# naturally respecting EOL archive contents.  Targets already exercised above
# are skipped.
#
# Upstream: add representative minor branches between the baseline/LTS points.
# These are deliberately classified as PASS for >=4.9 except where the earlier
# audit already established a vintage-host incompatibility.  Failures continue.
# ---------------------------------------------------------------------------
if [[ "$DO_EXTRA" == 1 ]]; then
  extra_seen="$RUN_ROOT/extra-seen-targets.txt"
  : >"$extra_seen"
  awk -F '\t' 'NR>1 && $4!=""{print $4}' "$SUMMARY" | sort -u >"$extra_seen"

  sample_evenly(){
    local file="$1" n="$2"
    awk -v n="$n" '
      { a[NR]=$0 }
      END {
        if (NR==0 || n<=0) exit
        if (NR<=n) { for(i=1;i<=NR;i++) print a[i]; exit }
        if (n==1) { print a[NR]; exit }
        for(j=0;j<n;j++) {
          idx=1+int((j*(NR-1))/(n-1));
          if(!seen[idx]++) print a[idx]
        }
      }' "$file"
  }

  extra_verify_smoke(){
    local group="$1" label="$2" target="$3" output="$4"
    [[ "$DRY_RUN" == 1 ]] && return 0
    [[ -s "$output" ]] || return 0
    run_shell_case verify "$group-$label" "$target" PASS "$output" "verify extra regression bundle" \
      "$(printf %q "$KLAB") verify $(printf %q "$output")"
    if [[ "$EXTRA_SMOKE" == 1 ]]; then
      run_shell_case smoke "$group-$label" "$target" PASS "" "optional QEMU smoke of extra target" \
        "$(printf %q "$KLAB") smoke $(printf %q "$target") --arch $(printf %q "$ARCH")"
    fi
  }

  for rel in 12.04 14.04 16.04 18.04 20.04 22.04 24.04 26.04; do
    listfile="$RUN_ROOT/ubuntu-list-$rel.txt"
    if [[ "$DRY_RUN" == 1 ]]; then
      : >"$listfile"
      record discovery "ubuntu-$rel" "ubuntu:$rel" PASS DRY_RUN 0 0 "$listfile" "" "dry-run: Ubuntu dynamic list not queried"
      continue
    fi
    listlog="$RUN_ROOT/logs/discovery-ubuntu-$(sanitize "$rel").log"
    if (( RESUMING )) && [[ -s "$listfile" ]] && [[ -n "$(resume_case_info discovery "ubuntu-$rel")" ]]; then
      echo "[resume-skip] discovery / ubuntu-$rel (reusing $listfile)"
    else
      start="$(date +%s)"
      "${KLAB}" list "ubuntu:$rel" >"$listfile.tmp" 2>"$listlog"
      lrc=$?
      end="$(date +%s)"
      if (( lrc != 0 )); then
        record discovery "ubuntu-$rel" "ubuntu:$rel" PROBE PROBE_FAIL "$lrc" "$((end-start))" "$listfile" "$listlog" "kernel discovery failed; continuing"
        rm -f "$listfile.tmp"
        continue
      fi
      grep -E '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-(generic|lowlatency|aws|azure|gcp|oracle)$' "$listfile.tmp" | sort -Vu >"$listfile"
      rm -f "$listfile.tmp"
      record discovery "ubuntu-$rel" "ubuntu:$rel" PASS PASS 0 "$((end-start))" "$listfile" "$listlog" "dynamic installable kernel census"
    fi

    selected="$RUN_ROOT/ubuntu-selected-$rel.txt"
    : >"$selected"
    grep -E -- '-generic$' "$listfile" >"$selected.generic" || true
    sample_evenly "$selected.generic" "$UBUNTU_GENERIC_SAMPLES" >>"$selected"
    for flavor in lowlatency aws azure gcp oracle; do
      grep -E -- "-$flavor$" "$listfile" >"$selected.$flavor" || true
      sample_evenly "$selected.$flavor" "$UBUNTU_FLAVOR_SAMPLES" >>"$selected"
    done
    sort -Vu -o "$selected" "$selected"

    while IFS= read -r krel; do
      [[ -n "$krel" ]] || continue
      target="ubuntu:$rel:$krel"
      grep -Fxq -- "$target" "$extra_seen" && continue
      printf '%s\n' "$target" >>"$extra_seen"
      label="ubuntu${rel//./}-extra-$(sanitize "$krel")"
      out="$ARTIFACT_ROOT/ubuntu-extra/${label}.klab"; mkdir -p "$(dirname "$out")"
      script="KLAB_ROOT=$(printf %q "$KLAB_ROOT") KLAB_HOME=$(printf %q "$KLAB_ROOT") KLAB_REFETCH=0 $(printf %q "$KLAB") prepare $(printf %q "$target") --arch $(printf %q "$ARCH") --distro-toolchain --artifact-dir $(printf %q "$(dirname "$out")") -o $(printf %q "$out")"
      run_shell_case ubuntu-extra "$label" "$target" PROBE "$out" "dynamically sampled exact Ubuntu ABI/flavor; cache-aware" "$script"
      [[ "$LAST_RC" == 0 ]] && extra_verify_smoke ubuntu-extra "$label" "$target" "$out"
    done <"$selected"
  done

  while IFS='|' read -r label target expected; do
    [[ -n "$label" && "${label:0:1}" != '#' ]] || continue
    grep -Fxq -- "$target" "$extra_seen" && continue
    printf '%s\n' "$target" >>"$extra_seen"
    out="$ARTIFACT_ROOT/upstream-extra/${label}.klab"; mkdir -p "$(dirname "$out")"
    run_shell_case upstream-extra "$label" "$target" "$expected" "$out" "extra branch representative; current-source rebuild" \
      "$(printf %q "$KLAB") prepare $(printf %q "$target") --arch $(printf %q "$ARCH") --artifact-dir $(printf %q "$(dirname "$out")") -o $(printf %q "$out")"
    [[ "$LAST_RC" == 0 ]] && extra_verify_smoke upstream-extra "$label" "$target" "$out"
  done <<'UPSTREAM_EXTRA_MATRIX'
upstream-3.4|upstream:v3.4|PROBE
upstream-3.6|upstream:v3.6|PROBE
upstream-3.8|upstream:v3.8|PROBE
upstream-3.12|upstream:v3.12|PROBE
upstream-3.18|upstream:v3.18|PROBE
upstream-4.1|upstream:v4.1|PROBE
upstream-4.6|upstream:v4.6|PROBE
upstream-4.10|upstream:v4.10|PROBE
upstream-4.12|upstream:v4.12|PROBE
upstream-4.16|upstream:v4.16|PROBE
upstream-4.20|upstream:v4.20|PROBE
upstream-5.0|upstream:v5.0|PROBE
upstream-5.5|upstream:v5.5|PROBE
upstream-5.8|upstream:v5.8|PROBE
upstream-5.12|upstream:v5.12|PROBE
upstream-5.18|upstream:v5.18|PROBE
upstream-6.0|upstream:v6.0|PROBE
upstream-6.3|upstream:v6.3|PROBE
upstream-6.5|upstream:v6.5|PROBE
upstream-6.8|upstream:v6.8|PROBE
upstream-6.10|upstream:v6.10|PROBE
upstream-6.14|upstream:v6.14|PROBE
upstream-6.18|upstream:v6.18|PROBE
upstream-7.1|upstream:v7.1|PROBE
upstream-7.2|upstream:v7.2|PROBE
UPSTREAM_EXTRA_MATRIX
fi

# ---------------------------------------------------------------------------
# FreeBSD x86_64 provider.  Architecture expansion remains a later phase, so
# this overnight run does not add FreeBSD/aarch64 or Linux cross-architecture
# targets yet.
# ---------------------------------------------------------------------------
if [[ "$DO_FREEBSD" == 1 ]]; then
  fb_target="freebsd:15.1-RELEASE:x86_64"
  fb_out="$ARTIFACT_ROOT/freebsd/freebsd-15.1-x86_64.klab"; mkdir -p "$(dirname "$fb_out")"
  run_shell_case freebsd freebsd-15.1-x86_64 "$fb_target" PASS "$fb_out" "first-class FreeBSD x86_64 provider" \
    "$(printf %q "$KLAB") prepare $(printf %q "$fb_target") --arch x86_64 --artifact-dir $(printf %q "$(dirname "$fb_out")") -o $(printf %q "$fb_out")"
  [[ "$LAST_RC" == 0 ]] && verify_and_smoke freebsd freebsd-15.1-x86_64 "$fb_target" "$fb_out"
fi

# ---------------------------------------------------------------------------
# Broad distro matrix.  Use a fresh export directory so current registration /
# packaging code is exercised, while reusing previously staged external roots.
# Set KLAB_OVERNIGHT_CROSS_RECAPTURE=all to deliberately redownload them.
# ---------------------------------------------------------------------------
if [[ "$DO_CROSS" == 1 ]]; then
  cross_script="$SELF_DIR/klab-cross-distro-queue-r4.sh"
  [[ -x "$cross_script" ]] || cross_script="$SELF_DIR/klab-cross-distro-queue-v2.sh"
  if [[ -x "$cross_script" ]]; then
    cross_cmd="KLAB_ROOT=$(printf %q "$KLAB_ROOT") KLAB_HOME=$(printf %q "$KLAB_ROOT") KLAB_SRC=$(printf %q "$SELF_DIR") KLAB_CROSS_SECTIONS=all KLAB_CROSS_STRICT_EXIT=0 KLAB_CROSS_PREPARE_CUSTOM=1 KLAB_CROSS_EXPORT_DIR=$(printf %q "$CROSS_ARTIFACT_ROOT") KLAB_CROSS_LOG_DIR=$(printf %q "$CROSS_LOG_ROOT") KLAB_CROSS_RECAPTURE=$(printf %q "$CROSS_RECAPTURE") $(printf %q "$cross_script")"
    run_shell_case cross-distro all-sections cross-distro:all PASS "$CROSS_ARTIFACT_ROOT" "all configured extra distro families; cached staged roots reused unless recapture requested" "$cross_cmd" "$UNIT_TIMEOUT"

    cross_summary="$CROSS_LOG_ROOT/latest-summary.tsv"
    if [[ -f "$cross_summary" ]]; then
      cp -f "$cross_summary" "$RUN_ROOT/cross-distro-summary.tsv"
      # Record every nested result in the master summary as well.
      while IFS=$'\t' read -r t kind requested resolved status rc output log note; do
        [[ "$t" == time ]] && continue
        case "$status" in
          PASS|SKIP_VERIFIED|PASS_REGISTERED) nested=PASS ;;
          STAGED_NO_BUILD_TREE|NO_MATCH) nested=FAIL ;;
          *) nested=FAIL ;;
        esac
        record cross-result "$(sanitize "$kind-$requested")" "$resolved" PASS "$nested" "${rc:-0}" 0 "$output" "$log" "$note"
      done <"$cross_summary"

      # QEMU smoke every successfully materialized target from the broad queue.
      if [[ "$DO_SMOKE" == 1 ]]; then
        awk -F '\t' 'NR>1 && ($5=="PASS" || $5=="SKIP_VERIFIED" || $5=="PASS_REGISTERED") && $4!=""{print $4}' "$cross_summary" \
          | sort -u >"$RUN_ROOT/cross-smoke-targets.txt"
        while IFS= read -r target; do
          [[ -n "$target" ]] || continue
          run_shell_case cross-smoke "$(sanitize "$target")" "$target" PASS "" "QEMU smoke of cross-distro resolved target" \
            "$(printf %q "$KLAB") smoke $(printf %q "$target") --arch $(printf %q "$ARCH")"
        done <"$RUN_ROOT/cross-smoke-targets.txt"
      fi
    else
      record cross-result no-summary cross-distro:all PASS FAIL 2 0 "" "$LAST_LOG" "cross-distro queue returned without a readable nested summary"
    fi
  else
    record cross-distro script-missing cross-distro:all PASS FAIL 127 0 "" "" "cross-distro queue script missing from source tree"
  fi
fi

# Artifact inventory and concise review.
find "$ARTIFACT_ROOT" -type f -printf '%s\t%p\n' 2>/dev/null | sort -n >"$RUN_ROOT/artifacts.tsv" || true

{
  echo "KLab overnight heavy all-path regression"
  echo "Run: $RUN_ID"
  echo
  echo "STATUS COUNTS"
  awk -F '\t' 'NR>1{c[$6]++}END{for(k in c)printf "%s\t%d\n",k,c[k]}' "$SUMMARY" | sort
  echo
  echo "REGRESSIONS / UNEXPECTED FAILURES"
  awk -F '\t' 'NR>1 && ($6=="FAIL" || $6=="TIMEOUT"){print $2"\t"$3"\t"$4"\texpected="$5"\tstatus="$6"\trc="$7"\t"$10}' "$SUMMARY"
  echo
  echo "KNOWN/EXPECTED FAILURES"
  awk -F '\t' 'NR>1 && ($6=="KNOWN_FAIL" || $6=="EXPECTED_FAIL"){print $2"\t"$3"\t"$4"\tstatus="$6"\trc="$7}' "$SUMMARY"
  echo
  echo "EXPLORATORY FAILURES (not regressions)"
  awk -F '\t' 'NR>1 && $6=="PROBE_FAIL"{print $2"\t"$3"\t"$4"\trc="$7"\t"$10}' "$SUMMARY"
  echo
  echo "IMPROVEMENTS OVER BASELINE"
  awk -F '\t' 'NR>1 && $6=="IMPROVEMENT"{print $2"\t"$3"\t"$4}' "$SUMMARY"
  echo
  echo "PREPARE RESULTS ONLY"
  awk -F '\t' 'NR>1 && ($2=="ubuntu" || $2=="ubuntu-extra" || $2=="fedora" || $2=="upstream" || $2=="upstream-extra" || $2=="freebsd" || $2=="cross-result"){print $6"\t"$2"\t"$3"\t"$4"\trc="$7}' "$SUMMARY"
} >"$RUN_ROOT/REVIEW-ME.txt"

# Small hand-back bundle: logs, summaries and metadata only.
parent="$(dirname "$RUN_ROOT")"; base="$(basename "$RUN_ROOT")"
tar -C "$parent" -czf "$RESULT_TAR" "$base"
ln -sfn "$RUN_ROOT" "$(dirname "$RUN_ROOT")/latest" 2>/dev/null || true
cp -f "$SUMMARY" "$KLAB_ROOT/results/overnight-regression-latest-summary.tsv" 2>/dev/null || true

echo
echo "################ OVERNIGHT REGRESSION COMPLETE ################"
cat "$RUN_ROOT/REVIEW-ME.txt"
echo
echo "Upload this review bundle:"
echo "  $RESULT_TAR"
echo "Summary:    $SUMMARY"
echo "Master log: $MASTER"
echo "Large regression artifacts remain under: $ARTIFACT_ROOT"

# Unattended collector: always return success; actual failures are in summary.
exit 0
