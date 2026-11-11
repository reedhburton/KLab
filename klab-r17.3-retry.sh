#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab-data}}" KLAB_HOME="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab-data}}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"; out="$KLAB_ROOT/results/logs/r17.2-retry-$stamp"; mkdir -p "$out"
summary="$out/summary.tsv"; printf 'case\tstep\tresult\trc\n' >"$summary"
run(){ local n="$1" step="$2"; shift 2; echo "=== $n / $step ==="; set +e; timeout --signal=TERM --kill-after=30 "${KLAB_R172_TIMEOUT:-14400}" "$@" > >(tee "$out/$n-$step.log") 2>&1; rc=${PIPESTATUS[0]}; set -e; [[ $rc == 0 ]]&&res=PASS||res=FAIL; printf '%s\t%s\t%s\t%s\n' "$n" "$step" "$res" "$rc"|tee -a "$summary"; return "$rc"; }
run baseline regression "$SELF/tests/distro-native-host-tool-baseline.sh" || true
run daytime-r4 regression "$SELF/tests/daytime-r4-regressions.sh" || true
run installer regression bash -x "$SELF/tests/installer-smoke.sh" || true
run resume regression bash -x "$SELF/tests/r16-overnight-resume.sh" || true

live_case(){
 local n="$1" target="$2"; shift 2
 if [[ ! -f "$SELF/examples/test.sh" || ! -f "$SELF/examples/hello/Makefile" ]]; then
   run "$n" init "$SELF/kernel-lab.sh" init || return 0
 fi
 if run "$n" prepare "$SELF/kernel-lab.sh" prepare "$target" "$@"; then
   run "$n" diagnostics "$SELF/klab-r17.3-diagnostics.sh" "$target" || true
   run "$n" test "$SELF/kernel-lab.sh" test "$target" --module "$SELF/examples/hello" --script "$SELF/examples/test.sh" "$@" || true
 else
   printf '%s\ttest\tSKIP_PREPARE_FAILED\t-\n' "$n"|tee -a "$summary"
 fi
}
if [[ "${KLAB_R172_LIVE:-1}" == 1 ]]; then
 live_case ubuntu1204 ubuntu:12.04:3.2.0-126-generic --arch x86_64
 live_case fedora26 fedora:26:4.11.8-300.fc26.x86_64 --arch x86_64
 live_case upstream49 upstream:v4.9 --arch x86_64 --profile normal
fi
tar -czf "$KLAB_ROOT/results/r17.2-retry-$stamp-results.tar.gz" -C "$out" .
echo "Results: $KLAB_ROOT/results/r17.2-retry-$stamp-results.tar.gz"
