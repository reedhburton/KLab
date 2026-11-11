#!/usr/bin/env bash
# KLab r17 major overnight: regression fixes + architecture/kernel matrix.
set -uo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"; export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"
RUN_BASE="$KLAB_ROOT/results/logs/major-overnight-r17"
RESUME="${KLAB_R17_RESUME_RUN_ID:-}"
TIMEOUT="${KLAB_R17_PHASE_TIMEOUT:-28800}"
mkdir -p "$RUN_BASE"
[[ "$RESUME" != latest ]] || RESUME="$(find "$RUN_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null|sort|tail -n1)"
RUN_ID="${RESUME:-$(date -u +%Y%m%dT%H%M%SZ)}"; R="$RUN_BASE/$RUN_ID"; mkdir -p "$R/phases"
S="$R/summary.tsv"; [[ -f "$S" ]] || printf 'phase\tresult\trc\tnote\n' >"$S"

tree_fingerprint(){
 { sha256sum "$SELF/kernel-lab.sh" "$SELF/lib/backends/apt.sh" "$SELF/lib/backends/rpm.sh" 2>/dev/null
   find "$SELF/providers" -maxdepth 1 -type f -name '*.sh' -print0 2>/dev/null|sort -z|xargs -0 sha256sum 2>/dev/null || true
 } | sha256sum | awk '{print $1}'
}
capabilities(){
 printf 'custom-core=%s\n' "$(grep -q 'cmd_register_linux' "$SELF/kernel-lab.sh" && echo 1 || echo 0)"
 printf 'rpm-coreutils=%s\n' "$(grep -q 'coreutils findutils' "$SELF/lib/backends/rpm.sh" && echo 1 || echo 0)"
 printf 'freebsd-iso-preflight=%s\n' "$(grep -q 'iso_builder >/dev/null' "$SELF/kernel-lab.sh" && echo 1 || echo 0)"
 printf 'mixed-kernel-matrix=%s\n' "$([[ -f "$SELF/examples/multiguest/mixed-matrix-r16/matrix.json" ]] && echo 1 || echo 0)"
}
FP="$(tree_fingerprint)"; CAP="$(capabilities)"
if [[ -f "$R/source.fingerprint" ]]; then
 old="$(cat "$R/source.fingerprint")"
 if [[ "$old" != "$FP" && "${KLAB_R17_ALLOW_SOURCE_CHANGE:-0}" != 1 ]]; then
   echo "Resume refused: KLab source fingerprint changed ($old -> $FP)." >&2
   echo "Set KLAB_R17_ALLOW_SOURCE_CHANGE=1 only after reviewing capability diff." >&2; exit 72
 fi
 if [[ -f "$R/capabilities.txt" ]]; then
   oldcap="$(cat "$R/capabilities.txt")"
   [[ "$oldcap" == "$CAP" ]] || { echo "Resume refused: capability set changed." >&2; diff -u "$R/capabilities.txt" <(printf '%s\n' "$CAP") >&2 || true; exit 73; }
 fi
else
 printf '%s\n' "$FP" >"$R/source.fingerprint"; printf '%s\n' "$CAP" >"$R/capabilities.txt"
fi
done_phase(){ awk -F'\t' -v p="$1" 'NR>1&&$1==p&&$2!="RUNNING"{f=1}END{exit !f}' "$S" 2>/dev/null; }
run_phase(){
 local n="$1"; shift; done_phase "$n" && { echo "SKIP completed $n"; return; }
 printf '%s\tRUNNING\t0\tstarted\n' "$n" >>"$S"
 set +e; timeout --signal=TERM --kill-after=30 "$TIMEOUT" "$@" >"$R/phases/$n.stdout" 2>"$R/phases/$n.stderr"; rc=$?; set -e
 if ((rc==0)); then result=PASS; note=completed; elif ((rc==124||rc==137)); then result=TIMEOUT; note=timeout; else result=FAIL; note="rc=$rc"; fi
 printf '%s\t%s\t%s\t%s\n' "$n" "$result" "$rc" "$note" >>"$S"
}
set -e
# Cheap gates first. These catch the old overnight's infrastructure regressions before downloads.
run_phase syntax bash -n "$SELF/kernel-lab.sh"
run_phase rpm-baseline "$SELF/tests/distro-native-host-tool-baseline.sh"
run_phase mixed-model "$SELF/tests/r16-mixed-arch-matrix.sh"
# The kernel-version test can be expensive in constrained sandboxes, but belongs in the real host gate.
run_phase kernel-version-model "$SELF/tests/r16-kernel-version-matrix.sh"

# Existing broad acquisition/regression queue reuses KLAB_ROOT caches and skips already-successful work.
if [[ "${KLAB_R17_RUN_BROAD:-1}" == 1 ]]; then
  run_phase broad-regression env KLAB_HOME="$KLAB_ROOT" "$SELF/klab-overnight-regression-v6-resume.sh"
fi

# New routed architecture x kernel matrix. QEMU-missing cases are recorded by its own summary.
if [[ "${KLAB_R17_RUN_MATRIX:-1}" == 1 ]]; then
  run_phase routed-arch-kernel env KLAB_ROOT="$KLAB_ROOT" KLAB_R16_MIXED_MATRIX=1 KLAB_R16_KERNEL_MATRIX=1 KLAB_R16_EXPERIMENTAL_MATRIX="${KLAB_R17_EXPERIMENTAL:-0}" "$SELF/klab-fault-overnight-r16.sh"
fi

# Focused postmortem repros can be added without invalidating completed phases.
if [[ "${KLAB_R17_UPSTREAM49_REPRO:-1}" == 1 ]]; then
  mkdir -p "$R/upstream49"
  run_phase upstream-4.9 "$SELF/kernel-lab.sh" test upstream:v4.9 --module "$SELF/examples/hello-module" --script "$SELF/examples/hello-module/test.sh" --profile normal
fi
awk -F'\t' 'NR==1||$2!="RUNNING"' "$S" >"$R/summary.final.tsv"
tar -czf "$KLAB_ROOT/results/major-overnight-r17-${RUN_ID}-results.tar.gz" -C "$R" .
echo "$KLAB_ROOT/results/major-overnight-r17-${RUN_ID}-results.tar.gz"
