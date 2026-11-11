#!/usr/bin/env bash
# KLab cross-architecture end-to-end validation.
# Sourced by kernel-lab.sh after the core architecture model.

klab_arch_smoke_stage() {
  local stage="$1" state="$2" detail="${3:-}" now
  KLAB_ARCH_SMOKE_CURRENT_STAGE="$stage"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ -n "${KLAB_ARCH_SMOKE_STAGES:-}" ]] || return 0
  printf '%s\t%s\t%s\t%s\n' "$now" "$stage" "$state" "$detail" >> "$KLAB_ARCH_SMOKE_STAGES"
}

klab_arch_smoke_cleanup_session() {
  local name="${KLAB_ARCH_SMOKE_SESSION:-}" dir pid sock=""
  [[ "${KLAB_ARCH_SMOKE_KEEP_SESSION:-0}" == 1 ]] && return 0
  [[ -n "$name" ]] || return 0
  dir="$(session_dir "$name")"
  [[ -d "$dir" ]] || return 0
  if [[ -f "$dir/session.env" ]]; then
    unset SESSION_CONTROL
    # shellcheck disable=SC1090
    source "$dir/session.env" 2>/dev/null || true
    sock="${SESSION_CONTROL:-}"
  fi
  if [[ -f "$dir/pid" ]]; then
    pid="$(cat "$dir/pid" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      if [[ -n "$sock" && -S "$sock" ]]; then
        session_rpc_exec "$sock" 'sync; poweroff -f 2>/dev/null || reboot -f 2>/dev/null || true' >/dev/null 2>&1 || true
        local i; for i in {1..20}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
      fi
      kill "$pid" 2>/dev/null || true
    fi
  fi
  if [[ -f "$dir/crash-watcher.pid" ]]; then kill "$(cat "$dir/crash-watcher.pid" 2>/dev/null)" 2>/dev/null || true; fi
}

klab_arch_smoke_finalize() {
  local rc="$1" result report="${KLAB_ARCH_SMOKE_REPORT_DIR:-}" stage="${KLAB_ARCH_SMOKE_CURRENT_STAGE:-unknown}"
  [[ "$rc" == 0 ]] && result=PASS || result=FAIL
  klab_arch_smoke_cleanup_session || true
  [[ -n "$report" ]] || return "$rc"
  mkdir -p "$report"
  printf '%s\n' "$result" > "$report/RESULT"
  printf '%s\n' "$stage" > "$report/LAST_STAGE"
  python3 - "$report" "$result" "$rc" "${KLAB_ARCH_SMOKE_TARGET:-}" "${KLAB_ARCH_SMOKE_ARCH:-}" "${KLAB_ARCH_SMOKE_BUILD_ARCH:-}" "${KLAB_ARCH_SMOKE_PROFILE:-}" "${KLAB_ARCH_SMOKE_USERSPACE:-}" "${KLAB_ARCH_SMOKE_BUNDLE:-}" "${KLAB_ARCH_SMOKE_USER_BIN:-}" "${KLAB_ARCH_SMOKE_MODULE:-}" "${KLAB_ARCH_SMOKE_SESSION:-}" "$stage" <<'PY'
import hashlib,json,os,sys
(report,result,rc,target,arch,build_arch,profile,userspace,bundle,userbin,module,session,last_stage)=sys.argv[1:]
def read(name):
    p=os.path.join(report,name)
    try:
        with open(p,'r',encoding='utf-8',errors='replace') as f:return f.read().strip()
    except FileNotFoundError:return ''
def sha(path):
    if not path or not os.path.isfile(path): return None
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()
plan={}
try:
    with open(os.path.join(report,'architecture-plan.json')) as f: plan=json.load(f)
except Exception: pass
stages=[]
try:
    for line in read('stages.tsv').splitlines():
        p=line.split('\t',3)
        if len(p)>=3: stages.append({'time':p[0],'stage':p[1],'state':p[2],'detail':p[3] if len(p)>3 else ''})
except Exception: pass
obj={
 'schema':'klab-arch-e2e-v2','result':result,'return_code':int(rc),'target':target,'target_arch':arch,
 'build_arch':build_arch,'profile':profile,'userspace':userspace,'last_stage':last_stage,'architecture_plan':plan,
 'session':session,'session_kept':os.environ.get('KLAB_ARCH_SMOKE_KEEP_SESSION','0')=='1','qemu_version':read('qemu-version.txt'),'uname':read('uname.txt'),'uname_machine':read('uname-machine.txt'),
 'user_output':read('user-output.txt'),'user_file':read('user-file.txt'),'module_file':read('module-file.txt'),'module_load_dmesg':read('module-load-dmesg.txt'),'module_unload_dmesg':read('module-unload-dmesg.txt'),
 'artifacts':{
   'bundle':{'path':bundle,'sha256':sha(bundle)},
   'user_binary':{'path':userbin,'sha256':sha(userbin)},
   'module':{'path':module,'sha256':sha(module)},
 },
 'stages':stages,
}
with open(os.path.join(report,'report.json'),'w') as f: json.dump(obj,f,indent=2,sort_keys=True); f.write('\n')
with open(os.path.join(report,'summary.txt'),'w') as f:
    f.write(f"KLab architecture E2E: {result}\n")
    f.write(f"target={target}\narch={arch}\nbuild_arch={build_arch}\nprofile={profile}\nuserspace={userspace}\nlast_stage={last_stage}\n")
    if obj['uname_machine']: f.write(f"guest_machine={obj['uname_machine']}\n")
    if obj['user_output']: f.write(f"user_output={obj['user_output'].replace(chr(10),' | ')}\n")
PY
  return "$rc"
}

klab_arch_e2e_file_matches() {
  local arch="$1" desc="$2" allow reject
  allow="$(arch_profile_field "$arch" BUSYBOX_FILE_MATCH 2>/dev/null || true)"
  reject="$(arch_profile_field "$arch" FILE_MATCH_REJECT 2>/dev/null || true)"
  [[ -z "$allow" ]] || printf '%s\n' "$desc" | grep -Eq "$allow" || return 1
  [[ -z "$reject" ]] || ! printf '%s\n' "$desc" | grep -Eq "$reject" || return 1
  return 0
}

# Serial consoles can occasionally lose a response frame even though the
# command completed in the guest. Only retry read-only evidence collection;
# state-changing RPCs retain exactly-once behavior.
klab_arch_e2e_read_rpc() {
  local socket="$1" command="$2" output="$3" attempt rc=1
  for attempt in 1 2 3; do
    session_rpc_exec "$socket" "$command" >"$output" && return 0
    rc=$?
    sleep 0.1
  done
  return "$rc"
}

klab_arch_smoke_impl() {
  (($# >= 1)) || die "usage: $0 arch-smoke <upstream:VERSION> [--arch ARCH] [--profile PROFILE] [--userspace buildroot:minimal|buildroot:network] [--artifact-dir DIR] [--keep-session] [--dry-run]"
  local requested="$1"; shift
  local arch=aarch64 profile=normal userspace=buildroot:minimal artifact_dir='' keep_session=0 dry_run=0
  while (($#)); do
    case "$1" in
      --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; arch="$(canonical_arch "$2")"; shift 2 ;;
      --profile|-p) [[ $# -ge 2 ]] || die "$1 needs a value"; profile="$2"; shift 2 ;;
      --userspace) [[ $# -ge 2 ]] || die "--userspace needs a value"; userspace="$(normalize_userspace_spec "$2")"; shift 2 ;;
      --artifact-dir) [[ $# -ge 2 ]] || die "--artifact-dir needs a directory"; artifact_dir="$2"; shift 2 ;;
      --keep-session) keep_session=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      *) die "unknown arch-smoke option '$1'" ;;
    esac
  done
  [[ "$requested" == upstream:* ]] || die "arch-smoke currently validates upstream Linux targets; requested '$requested'"
  [[ "$userspace" == buildroot:* ]] || die "arch-smoke requires Buildroot userspace so the matching cross SDK is available"
  validate_profile "$profile"
  set_active_arch "$arch"
  local raw="${requested#upstream:}"
  [[ -n "$raw" && "$raw" != *:* ]] || die "upstream target syntax: upstream:v6.6"
  klab_arch_kernel_supported "$ARCH" "$raw" || die "kernel $raw is not supported by architecture $ARCH"
  klab_arch_e2e_assert_enabled "$ARCH" || die "architecture $ARCH is not enabled for end-to-end smoke testing (status=$(klab_arch_e2e_status "$ARCH" 2>/dev/null || echo disabled))"

  local run_id safe qemu expected_values
  run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  safe="$(printf '%s' "$requested" | tr ':@/' '___')"
  if [[ -n "$artifact_dir" ]]; then KLAB_ARCH_SMOKE_REPORT_DIR="$artifact_dir"; else KLAB_ARCH_SMOKE_REPORT_DIR="$KLAB_RESULTS/arch-e2e/$run_id"; fi
  mkdir -p "$KLAB_ARCH_SMOKE_REPORT_DIR"
  KLAB_ARCH_SMOKE_STAGES="$KLAB_ARCH_SMOKE_REPORT_DIR/stages.tsv"
  : > "$KLAB_ARCH_SMOKE_STAGES"
  KLAB_ARCH_SMOKE_TARGET="$requested"
  KLAB_ARCH_SMOKE_ARCH="$ARCH"
  KLAB_ARCH_SMOKE_BUILD_ARCH="$(host_arch)"
  KLAB_ARCH_SMOKE_PROFILE="$profile"
  KLAB_ARCH_SMOKE_USERSPACE="$userspace"
  KLAB_ARCH_SMOKE_BUNDLE="$KLAB_ARCH_SMOKE_REPORT_DIR/${safe}__${ARCH}__${profile}.klab"
  KLAB_ARCH_SMOKE_USER_BIN="$KLAB_ARCH_SMOKE_REPORT_DIR/user-test-$ARCH"
  KLAB_ARCH_SMOKE_MODULE=''
  KLAB_ARCH_SMOKE_SESSION="e${ARCH//[^A-Za-z0-9]/}${run_id//[^A-Za-z0-9]/}"
  KLAB_ARCH_SMOKE_SESSION="${KLAB_ARCH_SMOKE_SESSION:0:40}"
  KLAB_ARCH_SMOKE_KEEP_SESSION="$keep_session"
  export KLAB_ARCH_SMOKE_KEEP_SESSION

  klab_arch_plan_json "$ARCH" "$(host_arch)" > "$KLAB_ARCH_SMOKE_REPORT_DIR/architecture-plan.json"
  qemu="$(qemu_binary_for_arch "$ARCH")"
  printf '%s\n' "$qemu" > "$KLAB_ARCH_SMOKE_REPORT_DIR/qemu-binary.txt"
  if (( dry_run == 1 )); then
    klab_arch_smoke_stage plan PASS "dry-run"
    printf 'target=%s\narch=%s\nbuild_arch=%s\nuserspace=%s\nqemu=%s\nreport=%s\n' "$requested" "$ARCH" "$(host_arch)" "$userspace" "$qemu" "$KLAB_ARCH_SMOKE_REPORT_DIR"
    KLAB_ARCH_SMOKE_CURRENT_STAGE=complete
    return 0
  fi

  klab_arch_smoke_stage preflight START "qemu=$qemu"
  qemu="$(require_qemu_arch "$ARCH")"
  "$qemu" --version 2>/dev/null | head -n1 > "$KLAB_ARCH_SMOKE_REPORT_DIR/qemu-version.txt" || true
  have file || die "arch-smoke needs the 'file' utility"
  klab_arch_smoke_stage preflight PASS "$(cat "$KLAB_ARCH_SMOKE_REPORT_DIR/qemu-version.txt" 2>/dev/null || true)"

  klab_arch_smoke_stage prepare START "$requested/$ARCH/$profile"
  cmd_prepare "$requested" --arch "$ARCH" --profile "$profile" --userspace "$userspace" --with-sdk -o "$KLAB_ARCH_SMOKE_BUNDLE" >/dev/null
  [[ -f "$KLAB_ARCH_SMOKE_BUNDLE" ]] || die "arch-smoke prepare did not create $KLAB_ARCH_SMOKE_BUNDLE"
  bundle_tool verify "$KLAB_ARCH_SMOKE_BUNDLE" > "$KLAB_ARCH_SMOKE_REPORT_DIR/bundle-verify.txt"
  klab_arch_smoke_stage prepare PASS "bundle=$(basename "$KLAB_ARCH_SMOKE_BUNDLE")"

  klab_arch_smoke_stage user-build START "$EXAMPLES/user-test.c"
  [[ -f "$EXAMPLES/user-test.c" ]] || die "built-in user test is missing; run '$0 init --staging' first"
  cmd_build_user "$requested" --source "$EXAMPLES/user-test.c" --arch "$ARCH" --profile "$profile" --userspace "$userspace" -o "$KLAB_ARCH_SMOKE_USER_BIN" >/dev/null
  file "$KLAB_ARCH_SMOKE_USER_BIN" > "$KLAB_ARCH_SMOKE_REPORT_DIR/user-file.txt"
  klab_arch_e2e_file_matches "$ARCH" "$(cat "$KLAB_ARCH_SMOKE_REPORT_DIR/user-file.txt")" || die "cross-compiled user binary does not match target architecture $ARCH: $(cat "$KLAB_ARCH_SMOKE_REPORT_DIR/user-file.txt")"
  klab_arch_smoke_stage user-build PASS "$(cat "$KLAB_ARCH_SMOKE_REPORT_DIR/user-file.txt")"

  klab_arch_smoke_stage module-build START "$EXAMPLES/hello"
  stable_build_module "$requested" "$profile" "$EXAMPLES/hello"
  ((${#MODULE_FILES[@]} > 0)) || die "arch-smoke module build produced no .ko"
  mkdir -p "$KLAB_ARCH_SMOKE_REPORT_DIR/modules"
  local module_src="${MODULE_FILES[0]}"
  KLAB_ARCH_SMOKE_MODULE="$KLAB_ARCH_SMOKE_REPORT_DIR/modules/$(basename "$module_src")"
  cp "$module_src" "$KLAB_ARCH_SMOKE_MODULE"
  file "$KLAB_ARCH_SMOKE_MODULE" > "$KLAB_ARCH_SMOKE_REPORT_DIR/module-file.txt" || true
  klab_arch_e2e_file_matches "$ARCH" "$(cat "$KLAB_ARCH_SMOKE_REPORT_DIR/module-file.txt")" || die "cross-built kernel module does not match target architecture $ARCH: $(cat "$KLAB_ARCH_SMOKE_REPORT_DIR/module-file.txt")"
  klab_arch_smoke_stage module-build PASS "$(basename "$KLAB_ARCH_SMOKE_MODULE")"

  klab_arch_smoke_stage boot START "$KLAB_ARCH_SMOKE_SESSION"
  cmd_boot_session "$requested" --arch "$ARCH" --profile "$profile" --userspace "$userspace" --name "$KLAB_ARCH_SMOKE_SESSION" >/dev/null
  load_session_env "$KLAB_ARCH_SMOKE_SESSION"
  klab_arch_smoke_stage boot PASS "$KLAB_ARCH_SMOKE_SESSION"

  klab_arch_smoke_stage user-run START "/tmp/klab-user-test"
  cmd_push_session "$KLAB_ARCH_SMOKE_SESSION" "$KLAB_ARCH_SMOKE_USER_BIN" /tmp/klab-user-test >/dev/null
  klab_arch_e2e_read_rpc "$SESSION_CONTROL" 'uname -a' "$KLAB_ARCH_SMOKE_REPORT_DIR/uname.txt"
  klab_arch_e2e_read_rpc "$SESSION_CONTROL" 'uname -m' "$KLAB_ARCH_SMOKE_REPORT_DIR/uname-machine.txt"
  klab_arch_e2e_read_rpc "$SESSION_CONTROL" '/tmp/klab-user-test' "$KLAB_ARCH_SMOKE_REPORT_DIR/user-output.txt"
  local machine="$(cat "$KLAB_ARCH_SMOKE_REPORT_DIR/uname-machine.txt")" match=0 v
  expected_values="$(arch_profile_field "$ARCH" GUEST_UNAME_MACHINE 2>/dev/null || true)"; [[ -n "$expected_values" ]] || expected_values="$ARCH"
  for v in $expected_values; do [[ "$machine" == "$v" ]] && match=1; done
  (( match == 1 )) || die "guest uname machine '$machine' does not match $ARCH expected values: $expected_values"
  grep -q "pointer_bits=$(klab_arch_bits "$ARCH")" "$KLAB_ARCH_SMOKE_REPORT_DIR/user-output.txt" || die "user-space probe reported unexpected pointer width: $(cat "$KLAB_ARCH_SMOKE_REPORT_DIR/user-output.txt")"
  klab_arch_smoke_stage user-run PASS "machine=$machine"

  klab_arch_smoke_stage module-load START "$(basename "$KLAB_ARCH_SMOKE_MODULE")"
  cmd_load_module_session "$KLAB_ARCH_SMOKE_SESSION" "$KLAB_ARCH_SMOKE_MODULE" >/dev/null
  klab_arch_e2e_read_rpc "$SESSION_CONTROL" 'dmesg' "$KLAB_ARCH_SMOKE_REPORT_DIR/module-load-dmesg.txt"
  grep -q 'kernel_lab_hello: loaded' "$KLAB_ARCH_SMOKE_REPORT_DIR/module-load-dmesg.txt" || die "module loaded but expected hello marker was not observed"
  klab_arch_smoke_stage module-load PASS "hello marker observed"

  klab_arch_smoke_stage module-unload START hello
  cmd_unload_module_session "$KLAB_ARCH_SMOKE_SESSION" hello >/dev/null
  klab_arch_e2e_read_rpc "$SESSION_CONTROL" 'dmesg' "$KLAB_ARCH_SMOKE_REPORT_DIR/module-unload-dmesg.txt"
  grep -q 'kernel_lab_hello: unloaded' "$KLAB_ARCH_SMOKE_REPORT_DIR/module-unload-dmesg.txt" || die "module unload marker was not observed"
  klab_arch_smoke_stage module-unload PASS "hello marker observed"

  klab_arch_smoke_stage complete PASS "$requested/$ARCH"
  KLAB_ARCH_SMOKE_CURRENT_STAGE=complete
  if (( keep_session == 1 )); then
    say "Keeping architecture smoke session '$KLAB_ARCH_SMOKE_SESSION' running"
  else
    cmd_stop_session "$KLAB_ARCH_SMOKE_SESSION" >/dev/null 2>&1 || true
  fi
  printf '%s\n' "$KLAB_ARCH_SMOKE_REPORT_DIR"
}

cmd_arch_smoke() {
  (
    KLAB_ARCH_SMOKE_REPORT_DIR=''; KLAB_ARCH_SMOKE_STAGES=''; KLAB_ARCH_SMOKE_CURRENT_STAGE=setup
    KLAB_ARCH_SMOKE_TARGET=''; KLAB_ARCH_SMOKE_ARCH=''; KLAB_ARCH_SMOKE_BUILD_ARCH=''; KLAB_ARCH_SMOKE_PROFILE=''; KLAB_ARCH_SMOKE_USERSPACE=''
    KLAB_ARCH_SMOKE_BUNDLE=''; KLAB_ARCH_SMOKE_USER_BIN=''; KLAB_ARCH_SMOKE_MODULE=''; KLAB_ARCH_SMOKE_SESSION=''; KLAB_ARCH_SMOKE_KEEP_SESSION=0
    trap 'rc=$?; trap - EXIT; klab_arch_smoke_finalize "$rc"; exit "$rc"' EXIT
    klab_arch_smoke_impl "$@"
  )
}
