#!/usr/bin/env bash
# Human-readable Bash test runner. test.sh runs on the controller; only explicit
# klab exec/process/push/module operations enter the selected target.
source "$KLAB_SELF_DIR/lib/controller-test-api.sh"
klab_test_b64dec(){ python3 - "$1" <<'PY'
import base64,sys
sys.stdout.write(base64.b64decode(sys.argv[1]).decode())
PY
}
klab_test_env_name(){ printf '%s' "$1" | tr '[:lower:].-' '[:upper:]__' | tr -cd 'A-Z0-9_'; }
klab_controller_test_one(){
  local dir="$1" spec="$2" output="$3" planner="$KLAB_SELF_DIR/lib/controller_test_plan.py" manifest="$dir/klab.toml"
  KLAB_TEST_RUNNER="${KLAB_TEST_RUNNER:-$KLAB_RUNNER}"; export KLAB_TEST_RUNNER
  local target="${spec%@*}" arch="${spec##*@}"; [[ "$target" != "$spec" && -n "$target" && -n "$arch" ]] || { echo "klab: target must be TARGET@ARCH: $spec" >&2; return 2; }
  local boot_preload=1; [[ "$target" == freebsd:* ]] && boot_preload=0
  local -a meta _srcs _flags bc; local script userspace profile timeout_s run_id session report rc name src64 args64 unload src ko sources64 static flags64 remote64 flags_json remote mode key
  IFS=$'\t' read -r -a meta < <("$planner" meta "$manifest"); script="$(klab_test_b64dec "${meta[0]}")"; userspace="$(klab_test_b64dec "${meta[1]}")"; profile="$(klab_test_b64dec "${meta[2]}")"; timeout_s="${meta[3]}"
  run_id="$(date -u +%Y%m%dT%H%M%S)-$$-$RANDOM"; session="test-${run_id//[^A-Za-z0-9]/}"; session="${session:0:40}"; report="$output/${target//[:\/@]/_}__${arch}"; mkdir -p "$report/artifacts"
  printf 'target\t%s\narch\t%s\n' "$target" "$arch" >"$report/metadata.tsv"
  while IFS=$'\t' read -r name src64 args64 unload; do
    [[ -n "$name" ]] || continue; src="$(klab_test_b64dec "$src64")"; mkdir -p "$report/artifacts/module-$name"
    timeout --foreground "$timeout_s" "$KLAB_TEST_RUNNER" build-module "$target" --module "$src" --arch "$arch" --profile "$profile" -o "$report/artifacts/module-$name" >"$report/module-$name.build.log" 2>&1 || { rc=$?; echo "klab: module build $name failed or timed out (rc=$rc)" >&2; return "$rc"; }
    ko="$(find "$report/artifacts/module-$name" -type f -name '*.ko' -print -quit)"; [[ -n "$ko" ]] || { echo "klab: module $name produced no .ko" >&2; return 1; }
    key="$(klab_test_env_name "$name")"; printf -v "KLAB_MODULE_HOST_$key" %s "$ko"; export "KLAB_MODULE_HOST_$key"; printf -v "KLAB_MODULE_$key" %s "/tmp/klab-modules/$name.ko"; export "KLAB_MODULE_$key"
  done < <("$planner" modules "$manifest")
  while IFS=$'\t' read -r name sources64 static flags64 remote64; do
    [[ -n "$name" ]] || continue; flags_json="$(klab_test_b64dec "$flags64")"; remote="$(klab_test_b64dec "$remote64")"
    mapfile -t _srcs < <(python3 - "$sources64" <<'PY'
import base64,json,sys
print(*json.loads(base64.b64decode(sys.argv[1]).decode()),sep='\n')
PY
); mapfile -t _flags < <(python3 - "$flags_json" <<'PY'
import json,sys
print(*json.loads(sys.argv[1]),sep='\n')
PY
)
    bc=("$KLAB_TEST_RUNNER" build-user "$target" --arch "$arch" --profile "$profile" --userspace "$userspace" -o "$report/artifacts/$name"); for src in "${_srcs[@]}"; do bc+=(--source "$src"); done; [[ "$static" == 1 ]] || bc+=(--no-static); ((${#_flags[@]})) && bc+=(-- "${_flags[@]}"); timeout --foreground "$timeout_s" "${bc[@]}" >"$report/build-$name.log" 2>&1 || { rc=$?; echo "klab: userspace build $name failed or timed out (rc=$rc)" >&2; return "$rc"; }
    key="$(klab_test_env_name "$name")"; printf -v "KLAB_BUILD_$key" %s "$remote"; export "KLAB_BUILD_$key"
  done < <("$planner" builds "$manifest")
  local -a boot=("$KLAB_TEST_RUNNER" boot "$target" --arch "$arch" --profile "$profile" --userspace "$userspace" --name "$session")
  if ((boot_preload)); then
    while IFS=$'\t' read -r name sources64 static flags64 remote64; do [[ -n "$name" ]] || continue; remote="$(klab_test_b64dec "$remote64")"; boot+=(--preload "$report/artifacts/$name" "$remote"); done < <("$planner" builds "$manifest")
    while IFS=$'\t' read -r name src64 args64 unload; do [[ -n "$name" ]] || continue; key="KLAB_MODULE_HOST_$(klab_test_env_name "$name")"; boot+=(--preload "${!key}" "/tmp/klab-modules/$name.ko"); done < <("$planner" modules "$manifest")
    while IFS=$'\t' read -r name src64 remote64 mode; do [[ -n "$name" ]] || continue; src="$(klab_test_b64dec "$src64")"; remote="$(klab_test_b64dec "$remote64")"; boot+=(--preload "$src" "$remote"); done < <("$planner" files "$manifest")
  fi
  timeout --foreground "$timeout_s" "${boot[@]}" >"$report/boot.log" 2>&1 || { rc=$?; echo "klab: guest boot failed or timed out (rc=$rc)" >&2; return "$rc"; }
  trap '"$KLAB_TEST_RUNNER" stop "$session" >/dev/null 2>&1 || true' RETURN
  export KLAB_TEST_MODE=controller KLAB_TEST_RUNNER KLAB_TEST_NODE_target="$session" KLAB_TARGET="$target" KLAB_ARCH="$arch" KLAB_TEST_DIR="$dir" KLAB_REPORT_DIR="$report"
  if ((!boot_preload)); then
    while IFS=$'\t' read -r name sources64 static flags64 remote64; do [[ -n "$name" ]] || continue; remote="$(klab_test_b64dec "$remote64")"; "$KLAB_TEST_RUNNER" push "$session" "$report/artifacts/$name" "$remote" >/dev/null; done < <("$planner" builds "$manifest")
    while IFS=$'\t' read -r name src64 args64 unload; do [[ -n "$name" ]] || continue; key="KLAB_MODULE_HOST_$(klab_test_env_name "$name")"; "$KLAB_TEST_RUNNER" push "$session" "${!key}" "/tmp/klab-modules/$name.ko" >/dev/null; done < <("$planner" modules "$manifest")
    while IFS=$'\t' read -r name src64 remote64 mode; do [[ -n "$name" ]] || continue; src="$(klab_test_b64dec "$src64")"; remote="$(klab_test_b64dec "$remote64")"; "$KLAB_TEST_RUNNER" push "$session" "$src" "$remote" >/dev/null; done < <("$planner" files "$manifest")
  fi
  if ((boot_preload)); then "$KLAB_TEST_RUNNER" exec "$session" 'mkdir -p /tmp/klab-modules /tmp/klab-builds /tmp/klab-files /tmp/klab-test-processes' >/dev/null; fi
  while IFS=$'\t' read -r name sources64 static flags64 remote64; do [[ -n "$name" ]] || continue; remote="$(klab_test_b64dec "$remote64")"; "$KLAB_TEST_RUNNER" exec "$session" "chmod 0755 $(klab_test_quote "$remote")" >/dev/null; done < <("$planner" builds "$manifest")
  while IFS=$'\t' read -r name src64 remote64 mode; do [[ -n "$name" ]] || continue; remote="$(klab_test_b64dec "$remote64")"; "$KLAB_TEST_RUNNER" exec "$session" "chmod $mode $(klab_test_quote "$remote")" >/dev/null; key="$(klab_test_env_name "$name")"; printf -v "KLAB_FILE_$key" %s "$remote"; export "KLAB_FILE_$key"; done < <("$planner" files "$manifest")
  if PATH="$KLAB_SELF_DIR:$PATH" timeout --foreground "$timeout_s" bash "$script" > >(tee "$report/controller.stdout") 2> >(tee "$report/controller.stderr" >&2); then rc=0; else rc=$?; fi
  "$KLAB_TEST_RUNNER" stop "$session" >"$report/stop.log" 2>&1 || true; trap - RETURN; [[ $rc == 0 ]] && echo PASS >"$report/RESULT" || echo FAIL >"$report/RESULT"; return "$rc"
}
klab_controller_test(){
  (($#>=3)) || { echo 'usage: klab test SUITE on TARGET@ARCH... [--output DIR]' >&2; return 2; }; local suite="$1"; shift; [[ "$1" == on ]] || { echo "klab: expected 'on' after suite" >&2; return 2; }; shift
  local dir; [[ -d "$suite" ]] && dir="$(readlink -f "$suite")" || dir="$KLAB_ROOT/suites/$suite"; [[ -f "$dir/klab.toml" ]] || { echo "klab: suite has no klab.toml: $dir" >&2; return 2; }; "$KLAB_SELF_DIR/lib/controller_test_plan.py" validate "$dir/klab.toml" >/dev/null || return
  local output="$KLAB_RESULTS/tests/$(basename "$dir")-$(date -u +%Y%m%dT%H%M%SZ)-$$" line rc target; local -a targets=()
  while (($#)); do case "$1" in --output) [[ $# -ge 2 ]] || return 2; output="$2"; shift 2;; @*) while IFS= read -r line; do [[ -z "$line" || "$line" == \#* ]] || targets+=("$line"); done <"${1#@}"; shift;; *) targets+=("$1"); shift;; esac; done
  ((${#targets[@]})) || { echo 'klab: no targets selected' >&2; return 2; }; mkdir -p "$output"; printf 'target\tresult\trc\n' >"$output/status.tsv"; local failures=0
  for target in "${targets[@]}"; do if klab_controller_test_one "$dir" "$target" "$output"; then rc=0; else rc=$?; fi; if ((rc==0)); then printf '%s\tPASS\t0\n' "$target" >>"$output/status.tsv"; else printf '%s\tFAIL\t%s\n' "$target" "$rc" >>"$output/status.tsv"; failures=$((failures+1)); fi; done
  printf 'KLab test results: %s\n' "$output"; ((failures==0))
}
