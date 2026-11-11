#!/usr/bin/env bash
# KLab coordinated multi-process scenario runner v1.

klab_scenario_b64dec(){ python3 - "$1" <<'PY'
import base64,sys
value=sys.argv[1]
sys.stdout.write("" if value == "__KLAB_EMPTY__" else base64.b64decode(value).decode())
PY
}
klab_scenario_b64enc(){ python3 - "$1" <<'PY'
import base64,sys
print(base64.b64encode(sys.argv[1].encode()).decode())
PY
}
klab_scenario_resolve(){ local base="$1" p="$2"; [[ "$p" == /* ]] && printf '%s\n' "$p" || printf '%s/%s\n' "$base" "$p"; }

klab_scenario_wrap_command(){
  local command="$1" id="$2" bname="${3:-}" bcount="${4:-0}" btimeout="${5:-30000}" original64
  if [[ -n "$bname" && "$bcount" -gt 0 ]]; then
    original64="$(klab_scenario_b64enc "$command")"
    printf '/tmp/klab-agent --state /tmp/klab-agent-state barrier-run64 %s %s %s %s %s\n' "$bname" "$bcount" "$id" "$btimeout" "$original64"
  else
    printf '%s\n' "$command"
  fi
}

klab_scenario_cleanup(){
  [[ "${KLAB_SCENARIO_KEEP_SESSION:-0}" == 1 ]] && return 0
  local dir pid
  [[ -n "${KLAB_SCENARIO_SESSION:-}" ]] || return 0
  dir="$(session_dir "$KLAB_SCENARIO_SESSION")"
  [[ -f "$dir/pid" ]] || return 0
  pid="$(cat "$dir/pid" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null || return 0
  cmd_stop_session "$KLAB_SCENARIO_SESSION" >/dev/null 2>&1 || true
}

klab_scenario_finalize(){
  local rc="$1" report="${KLAB_SCENARIO_REPORT:-}" result=FAIL
  [[ "$rc" == 0 ]] && result=PASS
  if [[ -n "${SESSION_CONTROL:-}" && -S "${SESSION_CONTROL:-}" ]]; then session_rpc_exec "$SESSION_CONTROL" '/tmp/klab-agent shutdown >/dev/null 2>&1 || true' >/dev/null 2>&1 || true; fi
  klab_scenario_cleanup || true
  [[ -n "$report" ]] || return "$rc"
  mkdir -p "$report"
  printf '%s\n' "$result" > "$report/RESULT"
  printf '%s\n' "${KLAB_SCENARIO_STAGE:-unknown}" > "$report/LAST_STAGE"
  if [[ -f "$report/scenario.normalized.json" ]]; then
    python3 - "$report" "$result" "$rc" "${KLAB_SCENARIO_STAGE:-unknown}" <<'PY'
import csv,hashlib,json,os,sys
root,result,rc,stage=sys.argv[1:]
with open(os.path.join(root,'scenario.normalized.json')) as f: scenario=json.load(f)
def read_tsv(name):
    p=os.path.join(root,name)
    if not os.path.exists(p): return []
    with open(p,newline='') as f: return list(csv.DictReader(f,delimiter='\t'))
def ints(rows,keys):
    for row in rows:
        for k in keys:
            if row.get(k,'').lstrip('-').isdigit(): row[k]=int(row[k])
    return rows
procs=ints(read_tsv('process-results.tsv'),('expected_exit','actual_exit','signal','wait_rc'))
for r in procs:
    pid=r.get('id','')
    r['stdout_path']=f'processes/{pid}.stdout' if pid and os.path.exists(os.path.join(root,'processes',pid+'.stdout')) else None
    r['stderr_path']=f'processes/{pid}.stderr' if pid and os.path.exists(os.path.join(root,'processes',pid+'.stderr')) else None
loads=ints(read_tsv('module-load-results.tsv'),('load_rc',))
unloads=ints(read_tsv('module-unload-results.tsv'),('unload_rc',))
mods={}
for r in loads: mods.setdefault(r['id'],{}).update({'id':r['id'],'name':r.get('name'),'load_rc':r.get('load_rc'),'load_status':r.get('status')})
for r in unloads: mods.setdefault(r['id'],{}).update({'id':r['id'],'name':r.get('name'),'unload_rc':r.get('unload_rc'),'unload_status':r.get('status')})
events=[]
ep=os.path.join(root,'events.tsv')
if os.path.exists(ep):
    with open(ep,errors='replace') as f:
        for line in f:
            p=line.rstrip('\n').split('\t',3)
            if len(p)>=3: events.append({'time_ms':int(p[0]) if p[0].isdigit() else p[0],'pid':int(p[1]) if p[1].isdigit() else p[1],'name':p[2],'value':p[3] if len(p)>3 else ''})
def sha(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()
artifacts=[]
for relbase in ('builds','modules'):
    d=os.path.join(root,relbase)
    if os.path.isdir(d):
        for n in sorted(os.listdir(d)):
            p=os.path.join(d,n)
            if os.path.isfile(p) and not n.endswith(('.txt','.log')): artifacts.append({'path':os.path.relpath(p,root),'sha256':sha(p),'bytes':os.path.getsize(p)})
ap=os.path.join(root,'klab-agent-'+scenario.get('arch',''))
if os.path.isfile(ap): artifacts.append({'path':os.path.relpath(ap,root),'sha256':sha(ap),'bytes':os.path.getsize(ap)})
obj={'schema':'klab-scenario-report-v1','result':result,'rc':int(rc),'last_stage':stage,'scenario':scenario,'processes':procs,'modules':list(mods.values()),'events':events,'artifacts':artifacts,'dmesg_path':'dmesg.txt' if os.path.exists(os.path.join(root,'dmesg.txt')) else None}
if os.path.exists(os.path.join(root,'expected-panic.txt')):
    obj['expected_panic_path']='expected-panic.txt'
    obj['console_path']='console.log' if os.path.exists(os.path.join(root,'console.log')) else None
q=os.path.join(root,'architecture-plan.json')
if os.path.exists(q):
    try:
        with open(q) as f: obj['architecture_plan']=json.load(f)
    except Exception: pass
with open(os.path.join(root,'report.json'),'w') as f: json.dump(obj,f,indent=2,sort_keys=True);f.write('\n')
with open(os.path.join(root,'summary.txt'),'w') as f:
    f.write(f"KLab scenario: {result}\n")
    f.write(f"target={scenario.get('target')}\narch={scenario.get('arch')}\nlast_stage={stage}\n")
    for r in procs: f.write(f"process {r.get('id')}: expected={r.get('expected_exit')} actual={r.get('actual_exit')} signal={r.get('signal')} status={r.get('status')}\n")
    for m in mods.values(): f.write(f"module {m.get('id')}: load={m.get('load_status')} unload={m.get('unload_status')}\n")
PY
  fi
  return "$rc"
}

klab_scenario_impl(){
  (($# >= 1)) || die "usage: $0 scenario-run SCENARIO.json [--report-dir DIR] [--keep-session] [--dry-run]"
  local scenario="$1"; shift
  local report='' keep=0 dry=0
  while (($#)); do
    case "$1" in
      --report-dir) [[ $# -ge 2 ]] || die "--report-dir needs a directory"; report="$2"; shift 2;;
      --keep-session) keep=1; shift;;
      --dry-run) dry=1; shift;;
      *) die "unknown scenario-run option '$1'";;
    esac
  done
  [[ -f "$scenario" ]] || die "scenario file not found: $scenario"
  local planner="$SELF_DIR/lib/scenario_plan.py"; [[ -x "$planner" ]] || die "scenario planner missing: $planner"
  local run_id base; run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"; base="$(CDPATH= cd -- "$(dirname -- "$scenario")" && pwd)"
  [[ -n "$report" ]] || report="$KLAB_RESULTS/scenarios/$run_id"
  mkdir -p "$report/processes" "$report/builds"
  KLAB_SCENARIO_REPORT="$report"; KLAB_SCENARIO_KEEP_SESSION="$keep"; KLAB_SCENARIO_STAGE=validate
  "$planner" validate "$scenario" > "$report/scenario.normalized.json"
  mapfile -t meta < <("$planner" meta "$scenario")
  local target="${meta[0]}" arch="${meta[1]}" profile="${meta[2]}" userspace="${meta[3]}" default_timeout="${meta[4]}"
  arch="$(canonical_arch "$arch")"; set_active_arch "$arch"; validate_profile "$profile"
  if [[ "$target" == upstream:* ]]; then klab_arch_kernel_supported "$ARCH" "${target#upstream:}" || die "kernel ${target#upstream:} is not supported by architecture $ARCH"; fi
  klab_arch_e2e_assert_enabled "$ARCH" || die "architecture $ARCH is not enabled for scenario execution"
  klab_arch_plan_json "$ARCH" "$(host_arch)" > "$report/architecture-plan.json"
  if (( dry == 1 )); then
    printf 'scenario=%s\ntarget=%s\narch=%s\nprofile=%s\nuserspace=%s\nreport=%s\n' "$scenario" "$target" "$ARCH" "$profile" "$userspace" "$report"
    KLAB_SCENARIO_STAGE=complete; return 0
  fi

  KLAB_SCENARIO_STAGE=prepare
  local bundle="$report/target.klab"
  cmd_prepare "$target" --arch "$ARCH" --profile "$profile" --userspace "$userspace" --with-sdk -o "$bundle" >/dev/null
  bundle_tool verify "$bundle" > "$report/bundle-verify.txt"

  KLAB_SCENARIO_STAGE=agent-build
  local agent_host="$report/klab-agent-$ARCH"
  cmd_build_user "$target" --source "$SELF_DIR/guest-agent/klab-agent.c" --arch "$ARCH" --profile "$profile" --userspace "$userspace" -o "$agent_host" -- -O2 -std=c11 >/dev/null
  file "$agent_host" > "$report/agent-file.txt" || true
  klab_arch_e2e_file_matches "$ARCH" "$(cat "$report/agent-file.txt")" || die "guest agent binary does not match target architecture $ARCH"

  KLAB_SCENARIO_STAGE=builds
  local id src64 remote64 static flags64 src remote flags_json out
  while IFS=$'\t' read -r id src64 remote64 static flags64; do
    [[ -n "$id" ]] || continue
    src="$(klab_scenario_b64dec "$src64")"; remote="$(klab_scenario_b64dec "$remote64")"; flags_json="$(klab_scenario_b64dec "$flags64")"
    src="$(klab_scenario_resolve "$base" "$src")"; out="$report/builds/$id"
    mapfile -t cflags < <(python3 - "$flags_json" <<'PY'
import json,sys
for x in json.loads(sys.argv[1]): print(x)
PY
)
    local -a bcmd=(cmd_build_user "$target" --source "$src" --arch "$ARCH" --profile "$profile" --userspace "$userspace" -o "$out")
    [[ "$static" == 1 ]] || bcmd+=(--no-static)
    ((${#cflags[@]})) && bcmd+=(-- "${cflags[@]}")
    "${bcmd[@]}" >/dev/null
    file "$out" > "$report/builds/$id.file.txt" || true
    klab_arch_e2e_file_matches "$ARCH" "$(cat "$report/builds/$id.file.txt")" || die "scenario build '$id' does not match $ARCH"
    printf '%s\t%s\t%s\n' "$id" "$out" "$remote" >> "$report/build-map.tsv"
  done < <("$planner" builds "$scenario")

  KLAB_SCENARIO_STAGE=module-builds
  mkdir -p "$report/modules"
  local mid msrc64 margs64 munload mname mauto msrc margs mko mrc mstatus urc ustatus
  local -a margarr
  declare -A module_auto=()
  while IFS=$'\t' read -r mid mauto; do [[ -n "$mid" ]] && module_auto[$mid]="$mauto"; done < <("$planner" module-policies "$scenario")
  while IFS=$'\t' read -r mid msrc64 margs64 munload mname; do
    [[ -n "$mid" ]] || continue
    msrc="$(klab_scenario_b64dec "$msrc64")"; margs="$(klab_scenario_b64dec "$margs64")"; msrc="$(klab_scenario_resolve "$base" "$msrc")"
    stable_build_module "$target" "$profile" "$msrc"
    ((${#MODULE_FILES[@]} > 0)) || die "scenario module '$mid' produced no .ko"
    mko="$report/modules/$mid.ko"; cp "${MODULE_FILES[0]}" "$mko"
    file "$mko" > "$report/modules/$mid.file.txt" || true
    klab_arch_e2e_file_matches "$ARCH" "$(cat "$report/modules/$mid.file.txt")" || die "scenario module '$mid' does not match $ARCH"
    printf '%s\t%s\t%s\t%s\t%s\n' "$mid" "$mko" "$margs64" "$munload" "$mname" >> "$report/module-map.tsv"
  done < <("$planner" modules "$scenario")

  KLAB_SCENARIO_STAGE=boot
  KLAB_SCENARIO_SESSION="s${ARCH//[^A-Za-z0-9]/}${run_id//[^A-Za-z0-9]/}"; KLAB_SCENARIO_SESSION="${KLAB_SCENARIO_SESSION:0:40}"
  cmd_boot_session "$target" --arch "$ARCH" --profile "$profile" --userspace "$userspace" --name "$KLAB_SCENARIO_SESSION" >/dev/null
  load_session_env "$KLAB_SCENARIO_SESSION"

  KLAB_SCENARIO_STAGE=agent-start
  cmd_push_session "$KLAB_SCENARIO_SESSION" "$agent_host" /tmp/klab-agent >/dev/null
  session_rpc_exec "$SESSION_CONTROL" '/tmp/klab-agent --socket /tmp/klab-agent.sock --state /tmp/klab-agent-state start' > "$report/agent-start.txt"
  session_rpc_exec "$SESSION_CONTROL" '/tmp/klab-agent --socket /tmp/klab-agent.sock --state /tmp/klab-agent-state ping' > "$report/agent-ping.txt"

  KLAB_SCENARIO_STAGE=deploy
  if [[ -f "$report/build-map.tsv" ]]; then
    while IFS=$'\t' read -r id out remote; do cmd_push_session "$KLAB_SCENARIO_SESSION" "$out" "$remote" >/dev/null; session_rpc_exec "$SESSION_CONTROL" "chmod 0755 '$remote'" >/dev/null; done < "$report/build-map.tsv"
  fi
  if [[ -f "$report/module-map.tsv" ]]; then
    session_rpc_exec "$SESSION_CONTROL" 'mkdir -p /tmp/klab-modules' >/dev/null
    while IFS=$'\t' read -r mid mko margs64 munload mname; do cmd_push_session "$KLAB_SCENARIO_SESSION" "$mko" "/tmp/klab-modules/$mid.ko" >/dev/null; done < "$report/module-map.tsv"
  fi
  local fsrc64 frem64 fmode fsrc frem
  while IFS=$'\t' read -r fsrc64 frem64 fmode; do
    [[ -n "$fsrc64" ]] || continue; fsrc="$(klab_scenario_b64dec "$fsrc64")"; frem="$(klab_scenario_b64dec "$frem64")"; fsrc="$(klab_scenario_resolve "$base" "$fsrc")"
    cmd_push_session "$KLAB_SCENARIO_SESSION" "$fsrc" "$frem" >/dev/null; session_rpc_exec "$SESSION_CONTROL" "chmod $fmode '$frem'" >/dev/null
  done < <("$planner" files "$scenario")

  KLAB_SCENARIO_STAGE=module-load
  local failures=0
  local panic_mid='' panic_pattern64='' panic_timeout_ms=0 panic_pattern='' console_path=''
  IFS=$'\t' read -r panic_mid panic_pattern64 panic_timeout_ms < <("$planner" panic-expectation "$scenario") || true
  [[ -z "$panic_pattern64" ]] || panic_pattern="$(klab_scenario_b64dec "$panic_pattern64")"
  printf 'id\tname\tload_rc\tstatus\n' > "$report/module-load-results.tsv"
  if [[ -f "$report/module-map.tsv" ]]; then
    while IFS=$'\t' read -r mid mko margs64 munload mname; do
      if [[ "${module_auto[$mid]:-1}" != 1 ]]; then printf '%s\t%s\t0\tMANUAL\n' "$mid" "$mname" >> "$report/module-load-results.tsv"; continue; fi
      margs="$(klab_scenario_b64dec "$margs64")"
      local -a loadargs=("$KLAB_SCENARIO_SESSION" "$mko")
      if [[ -n "$margs" ]]; then margarr=(); read -r -a margarr <<<"$margs"; loadargs+=("${margarr[@]}"); fi
      set +e; cmd_load_module_session "${loadargs[@]}" > "$report/modules/$mid.load.txt" 2>&1; mrc=$?; set -e
      if [[ -n "$panic_mid" && "$mid" == "$panic_mid" ]]; then
        console_path="$(session_dir "$KLAB_SCENARIO_SESSION")/console.log"
        local panic_deadline=$((SECONDS + (panic_timeout_ms+999)/1000))
        while ((SECONDS <= panic_deadline)); do
          if crash_log_has_panic "$console_path" && grep -Fq -- "$panic_pattern" "$console_path"; then
            cp "$console_path" "$report/console.log"
            capture_session_crash "$KLAB_SCENARIO_SESSION" >/dev/null 2>&1 || true
            printf 'module=%s\npattern=%s\nconsole=%s\n' "$mid" "$panic_pattern" "$report/console.log" > "$report/expected-panic.txt"
            printf '%s\t%s\t%s\tEXPECTED_PANIC\n' "$mid" "$mname" "$mrc" >> "$report/module-load-results.tsv"
            KLAB_SCENARIO_STAGE=complete; return 0
          fi
          sleep .1
        done
        cp "$console_path" "$report/console.log" 2>/dev/null || true
        die "module '$mid' did not produce expected panic text '$panic_pattern'"
      fi
      if (( mrc == 0 )); then mstatus=PASS; else mstatus=FAIL; failures=$((failures+1)); fi
      printf '%s\t%s\t%s\t%s\n' "$mid" "$mname" "$mrc" "$mstatus" >> "$report/module-load-results.tsv"
    done < "$report/module-map.tsv"
    session_rpc_exec "$SESSION_CONTROL" 'dmesg | tail -n 200' > "$report/modules/dmesg-after-load.txt" 2>/dev/null || true
  fi

  KLAB_SCENARIO_STAGE=spawn
  printf 'id\texpected_exit\tactual_exit\tsignal\twait_rc\tstatus\n' > "$report/process-results.tsv"
  local cmd64 timeout_ms expected bname bcount btimeout command wrapped enc
  while IFS=$'\t' read -r id cmd64 timeout_ms expected bname bcount btimeout; do
    [[ -n "$id" ]] || continue; command="$(klab_scenario_b64dec "$cmd64")"
    wrapped="$(klab_scenario_wrap_command "$command" "$id" "$bname" "$bcount" "$btimeout")"
    enc="$(klab_scenario_b64enc "$wrapped")"
    session_rpc_exec "$SESSION_CONTROL" "/tmp/klab-agent --socket /tmp/klab-agent.sock --state /tmp/klab-agent-state spawn64 $id $enc" > "$report/processes/$id.spawn.txt"
  done < <("$planner" processes "$scenario")

  KLAB_SCENARIO_STAGE=wait
  local waitout waitrc actual sig status
  while IFS=$'\t' read -r id cmd64 timeout_ms expected bname bcount btimeout; do
    [[ -n "$id" ]] || continue
    set +e; waitout="$(session_rpc_exec "$SESSION_CONTROL" "/tmp/klab-agent --socket /tmp/klab-agent.sock --state /tmp/klab-agent-state wait $id $timeout_ms" 2>&1)"; waitrc=$?; set -e
    printf '%s\n' "$waitout" > "$report/processes/$id.wait.txt"
    actual=-1; sig=0; status=FAIL
    if (( waitrc == 0 )); then actual="$(printf '%s\n' "$waitout" | awk '$1=="OK"&&$2=="WAIT"{print $6}' | tail -n1)"; sig="$(printf '%s\n' "$waitout" | awk '$1=="OK"&&$2=="WAIT"{print $7}' | tail -n1)"; [[ "$actual" == "$expected" && "$sig" == 0 ]] && status=PASS || failures=$((failures+1))
    else
      failures=$((failures+1)); session_rpc_exec "$SESSION_CONTROL" "/tmp/klab-agent --socket /tmp/klab-agent.sock --state /tmp/klab-agent-state signal $id 15" >/dev/null 2>&1 || true
    fi
    session_rpc_exec "$SESSION_CONTROL" "/tmp/klab-agent --socket /tmp/klab-agent.sock --state /tmp/klab-agent-state output $id stdout" > "$report/processes/$id.stdout" 2>/dev/null || true
    session_rpc_exec "$SESSION_CONTROL" "/tmp/klab-agent --socket /tmp/klab-agent.sock --state /tmp/klab-agent-state output $id stderr" > "$report/processes/$id.stderr" 2>/dev/null || true
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$expected" "$actual" "$sig" "$waitrc" "$status" >> "$report/process-results.tsv"
  done < <("$planner" processes "$scenario")
  session_rpc_exec "$SESSION_CONTROL" '/tmp/klab-agent --socket /tmp/klab-agent.sock --state /tmp/klab-agent-state events' > "$report/events.tsv" 2>/dev/null || true
  session_rpc_exec "$SESSION_CONTROL" 'dmesg' > "$report/dmesg.txt" 2>/dev/null || true
  KLAB_SCENARIO_STAGE=module-unload
  printf 'id\tname\tunload_rc\tstatus\n' > "$report/module-unload-results.tsv"
  if [[ -f "$report/module-map.tsv" ]]; then
    while IFS=$'\t' read -r mid mko margs64 munload mname; do
      if [[ "${module_auto[$mid]:-1}" != 1 ]]; then printf '%s\t%s\t0\tMANUAL\n' "$mid" "$mname" >> "$report/module-unload-results.tsv"; continue; fi
      margs="$(klab_scenario_b64dec "$margs64")"
      [[ "$munload" == 1 ]] || { printf '%s\t%s\t0\tSKIP\n' "$mid" "$mname" >> "$report/module-unload-results.tsv"; continue; }
      set +e; cmd_unload_module_session "$KLAB_SCENARIO_SESSION" "$mname" > "$report/modules/$mid.unload.txt" 2>&1; urc=$?; set -e
      if (( urc == 0 )); then ustatus=PASS; else ustatus=FAIL; failures=$((failures+1)); fi
      printf '%s\t%s\t%s\t%s\n' "$mid" "$mname" "$urc" "$ustatus" >> "$report/module-unload-results.tsv"
    done < "$report/module-map.tsv"
    session_rpc_exec "$SESSION_CONTROL" 'dmesg | tail -n 200' > "$report/modules/dmesg-after-unload.txt" 2>/dev/null || true
  fi
  # Canonical dmesg is captured after module teardown so load, userspace activity,
  # and unload diagnostics all appear in the same report artifact.
  session_rpc_exec "$SESSION_CONTROL" 'dmesg' > "$report/dmesg.txt" 2>/dev/null || true
  (( failures == 0 )) || die "$failures scenario assertion/module cleanup failure(s)"
  KLAB_SCENARIO_STAGE=complete
  [[ "$keep" == 1 ]] || cmd_stop_session "$KLAB_SCENARIO_SESSION" >/dev/null 2>&1 || true
  printf '%s\n' "$report"
}

cmd_scenario_run(){
  (
    KLAB_SCENARIO_REPORT=''; KLAB_SCENARIO_SESSION=''; KLAB_SCENARIO_STAGE=setup; KLAB_SCENARIO_KEEP_SESSION=0
    trap 'rc=$?; trap - EXIT; klab_scenario_finalize "$rc"; exit "$rc"' EXIT
    klab_scenario_impl "$@"
  )
}
