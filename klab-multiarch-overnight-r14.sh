#!/usr/bin/env bash
# KLab r14 multi-architecture E2E + coordinated scenario overnight matrix.
# Intended for the NEXT overnight cycle after the current x86/provider sweep.
# Exercises the shared arch-smoke harness across x86_64/i386/aarch64/armv7 and opt-in experimental mipsel/Malta.
set -uo pipefail

SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB="${KLAB_MULTIARCH_KLAB:-$SELF_DIR/kernel-lab.sh}"
[[ -x "$KLAB" ]] || { echo "ERROR: KLab CLI not found: $KLAB" >&2; exit 2; }
KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"; export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"
ARCHES="${KLAB_MULTIARCH_ARCHES:-x86_64 i386 aarch64 armv7}"
ENABLE_MIPS="${KLAB_MULTIARCH_ENABLE_MIPS:-0}"
if [[ "$ENABLE_MIPS" == 1 ]]; then
  [[ " $ARCHES " == *" mipsel "* ]] || ARCHES="$ARCHES mipsel"
  [[ " $ARCHES " == *" mips "* ]] || ARCHES="$ARCHES mips"
fi
USERSPACE="${KLAB_MULTIARCH_USERSPACE:-buildroot:minimal}"
PROFILE="${KLAB_MULTIARCH_PROFILE:-normal}"
TIMEOUT="${KLAB_MULTIARCH_CASE_TIMEOUT:-10800}"
RESUME="${KLAB_MULTIARCH_RESUME_RUN_ID:-}"

latest_run(){
  local base="$KLAB_ROOT/results/logs/multiarch-e2e"
  [[ -d "$base" ]] || return 1
  find "$base" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%f\n' 2>/dev/null | sort -nr | head -n1 | cut -f2-
}
if [[ "$RESUME" == latest ]]; then RESUME="$(latest_run || true)"; fi
if [[ -n "$RESUME" ]]; then RUN_ID="$RESUME"; else RUN_ID="${KLAB_MULTIARCH_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"; fi
RUN_ROOT="$KLAB_ROOT/results/logs/multiarch-e2e/$RUN_ID"
REPORT_ROOT="$KLAB_ROOT/results/multiarch-e2e/$RUN_ID"
SUMMARY="$RUN_ROOT/summary.tsv"
RESULT_TAR="$KLAB_ROOT/results/multiarch-e2e-${RUN_ID}-results.tar.gz"
mkdir -p "$RUN_ROOT" "$REPORT_ROOT"
if [[ ! -f "$SUMMARY" ]]; then printf 'arch\ttarget\trc\tstatus\treport\n' > "$SUMMARY"; fi

case_done(){
  local arch="$1" target="$2"
  awk -F '\t' -v a="$arch" -v t="$target" 'NR>1 && $1==a && $2==t {found=1} END{exit found?0:1}' "$SUMMARY"
}
record(){ printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$SUMMARY"; }

versions_for_arch(){
  local arch="$1" var value
  case "$arch" in
    x86_64) var=KLAB_X86_64_E2E_VERSIONS ;;
    i386) var=KLAB_I386_E2E_VERSIONS ;;
    aarch64) var=KLAB_AARCH64_E2E_VERSIONS ;;
    armv7) var=KLAB_ARMV7_E2E_VERSIONS ;;
    mipsel) var=KLAB_MIPSEL_E2E_VERSIONS ;;
    mips) var=KLAB_MIPS_E2E_VERSIONS ;;
    *) var='' ;;
  esac
  if [[ -n "$var" ]]; then eval 'value="${'"$var"':-}"'; fi
  if [[ -n "${value:-}" ]]; then printf '%s\n' "$value"; return; fi
  # Keep x86_64 as a control lane; the main heavy x86 overnight already covers it deeply.
  case "$arch" in
    x86_64) echo 'v6.6' ;;
    *)
      local vals=''
      vals="$(grep -E '^E2E_DEFAULT_VERSIONS=' "$SELF_DIR/architectures/$arch.conf" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d "'\"")"
      [[ -n "$vals" ]] && echo "$vals" || echo 'v6.6'
      ;;
  esac
}

qemu_for_arch(){
  local arch="$1"
  "$KLAB" arch-plan "$arch" --kernel v6.6 --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["execution"]["qemu_binary"] or "")' 2>/dev/null
}

run_one(){
  local arch="$1" v="$2" target="upstream:$v" safe log report rc status
  if case_done "$arch" "$target"; then
    echo "SKIP completed: $target [$arch]"
    return 0
  fi
  safe="${v//[^A-Za-z0-9._-]/_}"; log="$RUN_ROOT/${arch}-${safe}.log"; report="$REPORT_ROOT/${arch}-${safe}"
  mkdir -p "$report"
  echo "===== $target [$arch] =====" | tee "$log"
  set +e
  local -a launch=("$KLAB" arch-smoke "$target" --arch "$arch" --profile "$PROFILE" --userspace "$USERSPACE" --artifact-dir "$report")
  if [[ "$arch" == mipsel || "$arch" == mips ]]; then
    launch=(env KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 KLAB_ENABLE_EXPERIMENTAL_E2E=1 "${launch[@]}")
  fi
  timeout --signal=TERM --kill-after=30 "$TIMEOUT" "${launch[@]}" >>"$log" 2>&1
  rc=$?
  set -e
  if (( rc==0 )); then status=PASS
  elif (( rc==124 || rc==137 )); then status=TIMEOUT
  else status=FAIL
  fi
  record "$arch" "$target" "$rc" "$status" "$report"
}

# Architecture planning/E2E capability and QEMU preflight.
for arch in $ARCHES; do
  plan_target="__preflight__"
  if ! case_done "$arch" "$plan_target"; then
    log="$RUN_ROOT/${arch}-preflight.log"
    set +e
    "$KLAB" arch-plan "$arch" --kernel v6.6 --json >"$RUN_ROOT/${arch}-plan.json" 2>"$log"
    plan_rc=$?
    set -e
    if (( plan_rc != 0 )); then
      record "$arch" "$plan_target" "$plan_rc" MODEL_FAIL "$RUN_ROOT/${arch}-plan.json"
      continue
    fi
    qemu="$(qemu_for_arch "$arch")"
    if [[ -z "$qemu" || ! -x "$(command -v "$qemu" 2>/dev/null || true)" ]]; then
      printf 'missing qemu binary: %s\n' "${qemu:-unknown}" >> "$log"
      record "$arch" "$plan_target" 127 QEMU_MISSING "$RUN_ROOT/${arch}-plan.json"
    else
      "$qemu" --version 2>/dev/null | head -n1 > "$RUN_ROOT/${arch}-qemu-version.txt" || true
      record "$arch" "$plan_target" 0 PASS "$RUN_ROOT/${arch}-plan.json"
    fi
  fi

done

# Capability sanity: ARM64 must reject pre-3.7 kernel before acquisition.
if ! case_done aarch64 upstream:v3.6; then
  set +e
  "$KLAB" arch-smoke upstream:v3.6 --arch aarch64 --dry-run >"$RUN_ROOT/aarch64-pre37.log" 2>&1
  rc=$?
  set -e
  if (( rc != 0 )); then record aarch64 upstream:v3.6 "$rc" EXPECTED_REJECT "$RUN_ROOT/aarch64-pre37.log"
  else record aarch64 upstream:v3.6 0 REGRESSION "$RUN_ROOT/aarch64-pre37.log"
  fi
fi

for arch in $ARCHES; do
  # If this architecture preflight recorded QEMU_MISSING/MODEL_FAIL, don't repeat the same environmental failure for every version.
  pre_status="$(awk -F '\t' -v a="$arch" 'NR>1 && $1==a && $2=="__preflight__" {s=$4} END{print s}' "$SUMMARY")"
  case "$pre_status" in QEMU_MISSING|MODEL_FAIL) echo "Skipping $arch E2E cases: preflight=$pre_status"; continue;; esac
  versions="$(versions_for_arch "$arch")"
  for v in $versions; do run_one "$arch" "$v"; done
done

{
  echo "KLab multi-arch E2E run: $RUN_ID"
  echo "Architectures: $ARCHES"
  echo "Userspace: $USERSPACE"
  echo "Profile: $PROFILE"
  echo "Experimental MIPS endian lanes enabled: $ENABLE_MIPS"
  echo
  echo "Status counts:"
  awk -F '\t' 'NR>1{c[$4]++} END{for(k in c) print "  " k, c[k]}' "$SUMMARY" | sort
  echo
  echo "By architecture:"
  awk -F '\t' 'NR>1{c[$1 FS $4]++} END{for(k in c){split(k,a,FS); print "  " a[1], a[2], c[k]}}' "$SUMMARY" | sort
  echo
  echo "Failures/timeouts:"
  awk -F '\t' 'NR>1 && ($4=="FAIL" || $4=="TIMEOUT" || $4=="MODEL_FAIL" || $4=="QEMU_MISSING" || $4=="REGRESSION"){print "  " $1, $2, $4, "rc=" $3, $5}' "$SUMMARY"
} > "$RUN_ROOT/REVIEW-ME.txt"

# Archive logs/reports only; large .klab payloads live inside report dirs today, so exclude them from the review tar.
TMP_LIST="$RUN_ROOT/archive-list.txt"
(
  cd "$KLAB_ROOT/results" || exit 1
  find "logs/multiarch-e2e/$RUN_ID" -type f -print
  find "multiarch-e2e/$RUN_ID" -type f ! -name '*.klab' -print
) > "$TMP_LIST"
tar -czf "$RESULT_TAR" -C "$KLAB_ROOT/results" -T "$TMP_LIST" 2>/dev/null || true
printf 'Results: %s\n' "$RESULT_TAR"
exit 0
