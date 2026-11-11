#!/usr/bin/env bash
klab_test_api_key(){ printf '%s' "$1" | tr '[:lower:].-' '[:upper:]__' | tr -cd 'A-Z0-9_'; }
klab_test_session_for_node(){ local key="KLAB_TEST_NODE_${1//[^A-Za-z0-9_]/_}"; [[ -n "${!key:-}" ]] || { echo "klab: unknown test node: $1" >&2; return 2; }; printf '%s\n' "${!key}"; }
klab_test_quote(){ python3 - "$@" <<'PY'
import shlex,sys
print(shlex.join(sys.argv[1:]))
PY
}
klab_test_expect_rc(){ local a="$1" e="$2" x; [[ "$e" == any ]] && return 0; IFS=, read -r -a xs <<<"$e"; for x in "${xs[@]}"; do [[ "$a" == "$x" ]] && return 0; done; return 1; }
klab_test_exec_api(){
  (($#>=2)) || { echo "usage: klab exec NODE [expectation] [--timeout SEC] 'GUEST SHELL' | -- COMMAND..." >&2; return 2; }
  local node="$1" expected=0 seconds=0 argv_mode=0; shift
  while (($#)); do case "$1" in
    --expect-exit) [[ $# -ge 2 ]] || return 2; expected="$2"; shift 2;;
    --expect-failure) expected=any-failure; shift;;
    --expect-timeout) expected=124; shift;;
    --timeout) [[ $# -ge 2 ]] || return 2; seconds="$2"; shift 2;;
    --) argv_mode=1; shift; break;;
    *) break;;
  esac; done
  (($#)) || { echo 'klab: exec needs a guest command' >&2; return 2; }
  local session command rc out err; session="$(klab_test_session_for_node "$node")" || return
  if ((argv_mode)); then command="$(klab_test_quote "$@")"; else (($#==1)) || { echo "klab: quote a guest shell command, or put argv after --" >&2; return 2; }; command="$1"; fi
  out="$(mktemp)"; err="$(mktemp)"
  set +e; if ((seconds>0)); then timeout --foreground "$seconds" "$KLAB_TEST_RUNNER" exec "$session" "$command" >"$out" 2>"$err"; rc=$?; else "$KLAB_TEST_RUNNER" exec "$session" "$command" >"$out" 2>"$err"; rc=$?; fi; set -e
  cat "$out"; cat "$err" >&2; rm -f "$out" "$err"
  if [[ "$expected" == any-failure ]]; then ((rc!=0)) && return 0; echo 'klab: command unexpectedly succeeded' >&2; return 1; fi
  klab_test_expect_rc "$rc" "$expected" || { echo "klab: command exit $rc; expected $expected" >&2; return 1; }
}

klab_test_process_api(){
  local action="${1:-}"; (($#)) && shift
  case "$action" in
    start) (($#>=3)) || { echo 'usage: klab process start NODE NAME -- COMMAND...' >&2; return 2; }; local node="$1" name="$2" argv_mode=0; shift 2; [[ "${1:-}" == -- ]] && { argv_mode=1; shift; }; [[ "$name" =~ ^[A-Za-z][A-Za-z0-9_.-]*$ ]] || return 2; (($#)) || return 2; local session cmd q base="/tmp/klab-test-processes/$name"; session="$(klab_test_session_for_node "$node")" || return; if ((argv_mode)); then cmd="$(klab_test_quote "$@")"; else (($#==1)) || { echo "klab: quote a guest process command, or put argv after --" >&2; return 2; }; cmd="sh -c $(klab_test_quote "$1")"; fi; q="$(klab_test_quote "$base")"; "$KLAB_TEST_RUNNER" exec "$session" "mkdir -p /tmp/klab-test-processes; rm -f $q.exit $q.stdout $q.stderr; ( $cmd >$q.stdout 2>$q.stderr; echo \$? >$q.exit ) & echo \$! >$q.pid" >/dev/null; printf '%s\n' "$name";;
    output) (($#>=2)) || return 2; local session; session="$(klab_test_session_for_node "$1")" || return; "$KLAB_TEST_RUNNER" exec "$session" "cat /tmp/klab-test-processes/$2.${3:-stdout} 2>/dev/null || true";;
    wait) (($#>=2)) || return 2; local node="$1" name="$2" seconds=30 expected=0 session deadline rc; shift 2; while (($#)); do case "$1" in --timeout) seconds="$2"; shift 2;; --expect-exit) expected="$2"; shift 2;; --expect-failure) expected=any-failure; shift;; *) return 2;; esac; done; session="$(klab_test_session_for_node "$node")" || return; deadline=$((SECONDS+seconds)); rc=''; while ((SECONDS<=deadline)); do rc="$($KLAB_TEST_RUNNER exec "$session" "cat /tmp/klab-test-processes/$name.exit 2>/dev/null" 2>/dev/null || true)"; [[ "$rc" =~ ^[0-9]+$ ]] && break; sleep .1; done; [[ "$rc" =~ ^[0-9]+$ ]] || { echo "klab: process $name timed out" >&2; return 1; }; if [[ "$expected" == any-failure ]]; then ((rc!=0)) && return 0; echo "klab: process $name unexpectedly succeeded" >&2; return 1; fi; klab_test_expect_rc "$rc" "$expected" || { echo "klab: process $name exit $rc; expected $expected" >&2; return 1; };;
    ready) (($#>=4)) || return 2; local node="$1" name="$2" kind="$3" value="$4" seconds=30 session deadline text; shift 4; [[ "${1:-}" != --timeout ]] || { seconds="$2"; shift 2; }; (($#==0)) || return 2; session="$(klab_test_session_for_node "$node")" || return; deadline=$((SECONDS+seconds)); while ((SECONDS<=deadline)); do case "$kind" in stdout|stderr) text="$($KLAB_TEST_RUNNER exec "$session" "cat /tmp/klab-test-processes/$name.$kind 2>/dev/null || true" 2>/dev/null || true)"; [[ "$text" == *"$value"* ]] && return 0;; file) "$KLAB_TEST_RUNNER" exec "$session" "test -e $(klab_test_quote "$value")" >/dev/null 2>&1 && return 0;; *) echo 'klab: readiness kind must be stdout, stderr, or file' >&2; return 2;; esac; sleep .1; done; echo "klab: process $name did not become ready" >&2; return 1;;
    signal|stop) (($#>=2)) || return 2; local node="$1" name="$2" sig=TERM session; [[ "$action" == signal ]] && { [[ $# -eq 3 ]] || return 2; sig="$3"; }; session="$(klab_test_session_for_node "$node")" || return; "$KLAB_TEST_RUNNER" exec "$session" "kill -$sig \$(cat /tmp/klab-test-processes/$name.pid)" >/dev/null;;
    *) echo 'usage: klab process <start|ready|output|wait|signal|stop> ...' >&2; return 2;;
  esac
}
klab_test_expect_api(){
  (($#>=3)) || return 2
  local op="$1" text="$2" pattern="$3" ok=1
  case "$op" in
    contains) [[ "$text" == *"$pattern"* ]] && ok=0 ;;
    not-contains) [[ "$text" != *"$pattern"* ]] && ok=0 ;;
    matches) [[ "$text" =~ $pattern ]] && ok=0 ;;
    *) return 2 ;;
  esac
  ((ok==0)) || { echo "klab: expectation failed: $op $pattern" >&2; return 1; }
}

klab_test_api(){ case "${1:-}" in exec) shift; klab_test_exec_api "$@";; process) shift; klab_test_process_api "$@";; expect) shift; klab_test_expect_api "$@";; push|copy) shift; local s node local_file remote; node="$1"; shift; (($#==1 || $#==2)) || { echo 'usage: klab copy NODE LOCAL [REMOTE]' >&2; return 2; }; local_file="$1"; remote="${2:-}"; [[ "$local_file" == /* ]] || local_file="$KLAB_TEST_DIR/$local_file"; [[ -f "$local_file" ]] || { echo "klab: transfer file not found: $local_file" >&2; return 2; }; s="$(klab_test_session_for_node "$node")" || return; if [[ -n "$remote" ]]; then "$KLAB_TEST_RUNNER" push "$s" "$local_file" "$remote"; else "$KLAB_TEST_RUNNER" push "$s" "$local_file"; fi;; module) local action="${2:-}" node="${3:-}" name="${4:-}" session key remote command; session="$(klab_test_session_for_node "$node")" || return; key="KLAB_MODULE_$(klab_test_api_key "$name")"; remote="${!key:-}"; [[ -n "$remote" ]] || { echo "klab: unknown module: $name" >&2; return 2; }; case "$action" in load) shift 4; command="insmod $(klab_test_quote "$remote")"; (($#==0)) || command+=" $(klab_test_quote "$@")"; "$KLAB_TEST_RUNNER" exec "$session" "$command";; unload) "$KLAB_TEST_RUNNER" exec "$session" "rmmod $(klab_test_quote "$name")";; *) return 2;; esac;; *) echo 'klab: inside test.sh use exec, process, expect, copy, module, or push' >&2; return 2;; esac; }
