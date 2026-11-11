#!/usr/bin/env bash
# KLab multi-guest coordinated topology/fault scenario runner v2.

klab_mg_now_ms(){ python3 - <<'PY'
import time
print(time.time_ns()//1_000_000)
PY
}
klab_mg_auto_bus(){
  local seed="$1" h a b port
  h="$(printf '%s' "$seed" | sha256sum | awk '{print $1}')"
  a=$((16#${h:0:2} % 250 + 1)); b=$((16#${h:2:2} % 250 + 1)); port=$((20000 + 16#${h:4:4} % 20000))
  printf '239.192.%d.%d:%d\n' "$a" "$b" "$port"
}
klab_mg_event(){ local event="$1" value="${2:-}"; printf '%s\t%s\t%s\n' "$(klab_mg_now_ms)" "$event" "$value" >> "$KLAB_MG_REPORT/host-events.tsv"; }

klab_mg_panic_since(){
  local log="$1" before="$2" start
  start=$((before+1))
  [[ -f "$log" ]] || return 1
  tail -c "+$start" "$log" 2>/dev/null | grep -Eqi 'Kernel panic|not syncing:|PANIC: double fault|(^|[[:space:]])panic:|Fatal trap [0-9]+'
}

klab_mg_cleanup(){
  [[ "${KLAB_MG_KEEP_SESSIONS:-0}" == 1 ]] && return 0
  [[ -n "${KLAB_MG_REPORT:-}" && -f "$KLAB_MG_REPORT/sessions.tsv" ]] || return 0
  local gid sess
  while IFS=$'\t' read -r gid sess; do
    [[ -n "$sess" ]] || continue
    if [[ -f "$(session_dir "$sess")/pid" ]] && kill -0 "$(cat "$(session_dir "$sess")/pid")" 2>/dev/null; then cmd_stop_session "$sess" >/dev/null 2>&1 || true; fi
  done < "$KLAB_MG_REPORT/sessions.tsv"
}

klab_mg_finalize(){
  local rc="$1" result=FAIL report="${KLAB_MG_REPORT:-}"; [[ "$rc" == 0 ]] && result=PASS
  klab_mg_cleanup || true
  [[ -n "$report" && -d "$report" ]] || return "$rc"
  printf '%s\n' "$result" > "$report/RESULT"; printf '%s\n' "${KLAB_MG_STAGE:-unknown}" > "$report/LAST_STAGE"
  [[ "$rc" != 0 ]] || rm -f "$report/error-context.txt"
  if [[ -f "$report/scenario.normalized.json" ]]; then
    python3 - "$report" "$result" "$rc" "${KLAB_MG_STAGE:-unknown}" <<'PY'
import csv,json,os,sys
root,result,rc,stage=sys.argv[1:]
with open(os.path.join(root,'scenario.normalized.json')) as f: scenario=json.load(f)
def rows(name):
 p=os.path.join(root,name)
 if not os.path.exists(p): return []
 with open(p,newline='') as f: return list(csv.DictReader(f,delimiter='\t'))
procs=rows('process-results.tsv'); mods_load=rows('module-load-results.tsv'); mods_unload=rows('module-unload-results.tsv'); acts=rows('action-results.tsv'); guest_losses=rows('guest-loss-results.tsv')
for r in acts:
 for k in ('started_ms','completed_ms','duration_ms'):
  if r.get(k,'').lstrip('-').isdigit(): r[k]=int(r[k])
for r in guest_losses:
 if r.get('observed_ms','').isdigit(): r['observed_ms']=int(r['observed_ms'])
 if r.get('expected') in ('0','1'): r['expected']=r['expected']=='1'
for r in procs:
 for k in ('expected_exit','expected_signal','actual_exit','signal','wait_rc'):
  if r.get(k,'').lstrip('-').isdigit(): r[k]=int(r[k])
 gid,pid=r.get('guest',''),r.get('id','')
 r['stdout_path']=f'guests/{gid}/processes/{pid}.stdout' if os.path.exists(os.path.join(root,'guests',gid,'processes',pid+'.stdout')) else None
 r['stderr_path']=f'guests/{gid}/processes/{pid}.stderr' if os.path.exists(os.path.join(root,'guests',gid,'processes',pid+'.stderr')) else None
mods={}
for r in mods_load:
 key=(r.get('guest'),r.get('id')); mods.setdefault(key,{}).update(r)
for r in mods_unload:
 key=(r.get('guest'),r.get('id')); mods.setdefault(key,{}).update(r)
networks=rows('networks.tsv'); interfaces=rows('interfaces.tsv')
for r in networks:
 if r.get('delay_us','').isdigit():r['delay_us']=int(r['delay_us'])
 if r.get('capture') in ('0','1'):r['capture']=r['capture']=='1'
for r in interfaces:
 if r.get('delay_us','').isdigit():r['delay_us']=int(r['delay_us'])
 if r.get('capture') in ('0','1'):r['capture']=r['capture']=='1'
events=[]
for g in scenario.get('guests',[]):
 gid=g['id']; p=os.path.join(root,'guests',gid,'events.tsv')
 if os.path.exists(p):
  with open(p,errors='replace') as f:
   for line in f:
    q=line.rstrip('\n').split('\t',3)
    if len(q)>=3: events.append({'time_ms':int(q[0]) if q[0].isdigit() else q[0],'source':gid,'pid':int(q[1]) if q[1].isdigit() else q[1],'name':q[2],'value':q[3] if len(q)>3 else ''})
hp=os.path.join(root,'host-events.tsv')
if os.path.exists(hp):
 with open(hp,errors='replace') as f:
  for line in f:
   q=line.rstrip('\n').split('\t',2)
   if len(q)>=2: events.append({'time_ms':int(q[0]) if q[0].isdigit() else q[0],'source':'host','name':q[1],'value':q[2] if len(q)>2 else ''})
events.sort(key=lambda x: (x['time_ms'] if isinstance(x['time_ms'],int) else 0, x.get('source','')))
sessions={}
sp=os.path.join(root,'sessions.tsv')
if os.path.exists(sp):
 with open(sp) as f:
  for line in f:
   q=line.rstrip('\n').split('\t');
   if len(q)>=2:sessions[q[0]]=q[1]
guests=[]
for g in scenario.get('guests',[]):
 x=dict(g); gid=g['id']; x['session']=sessions.get(gid); x['dmesg_path']=f'guests/{gid}/dmesg.txt' if os.path.exists(os.path.join(root,'guests',gid,'dmesg.txt')) else None; x['console_path']=f'guests/{gid}/console.log' if os.path.exists(os.path.join(root,'guests',gid,'console.log')) else None; guests.append(x)
import hashlib
artifacts=[]
for gid in [g['id'] for g in scenario.get('guests',[])]:
 for sub in ('builds','modules','network'):
  d=os.path.join(root,'guests',gid,sub)
  if not os.path.isdir(d):continue
  for fn in sorted(os.listdir(d)):
   p=os.path.join(d,fn)
   if not os.path.isfile(p) or fn.endswith(('.txt','.tsv')):continue
   h=hashlib.sha256()
   with open(p,'rb') as f:
    for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
   artifacts.append({'guest':gid,'kind':sub.rstrip('s'),'path':os.path.relpath(p,root),'bytes':os.path.getsize(p),'sha256':h.hexdigest()})
obj={'schema':'klab-multiguest-report-v2','result':result,'rc':int(rc),'last_stage':stage,'topology':{'networks':networks,'interfaces':interfaces},'scenario':scenario,'guests':guests,'processes':procs,'modules':list(mods.values()),'actions':acts,'guest_losses':guest_losses,'artifacts':artifacts,'timeline':events}
with open(os.path.join(root,'report.json'),'w') as f: json.dump(obj,f,indent=2,sort_keys=True); f.write('\n')
with open(os.path.join(root,'summary.txt'),'w') as f:
 f.write(f'KLab multi-guest scenario: {result}\nlast_stage={stage}\n')
 for n in networks:f.write(f"network {n.get('id')}: {n.get('cidr')} bus={n.get('bus')} delay_us={n.get('delay_us')}\n")
 for g in guests:f.write(f"guest {g['id']}: {g['target']} {g['arch']} session={g.get('session')}\n")
 for p in procs:f.write(f"process {p.get('guest')}/{p.get('id')}: status={p.get('status')} expected={p.get('expected_exit')}/{p.get('expected_signal')} actual={p.get('actual_exit')}/{p.get('signal')}\n")
 for a in acts:f.write(f"action {a.get('id')}: {a.get('type')} status={a.get('status')} trigger={a.get('trigger','')} duration_ms={a.get('duration_ms','')} detail={a.get('detail','')}\n")
 for x in guest_losses:f.write(f"guest-loss {x.get('guest')}: cause={x.get('cause')} expected={x.get('expected')} status={x.get('status')} action={x.get('action')} detail={x.get('detail','')}\n")
PY
  fi
  return "$rc"
}

klab_mg_impl(){
  (($# >= 1)) || die "usage: $0 multiguest-run SCENARIO.json [--report-dir DIR] [--keep-sessions] [--dry-run]"
  local scenario="$1"; shift; local report='' keep=0 dry=0
  while (($#)); do case "$1" in
    --report-dir) [[ $# -ge 2 ]] || die "--report-dir needs a directory"; report="$2"; shift 2;;
    --keep-sessions) keep=1; shift;;
    --dry-run) dry=1; shift;;
    *) die "unknown multiguest-run option '$1'";;
  esac; done
  [[ -f "$scenario" ]] || die "multiguest scenario not found: $scenario"
  local planner="$SELF_DIR/lib/multiguest_plan.py"; [[ -x "$planner" ]] || die "multiguest planner missing: $planner"
  local run_id base; run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"; base="$(CDPATH= cd -- "$(dirname -- "$scenario")" && pwd)"
  [[ -n "$report" ]] || report="$KLAB_RESULTS/multiguest/$run_id"
  mkdir -p "$report/guests" "$report/network"; : > "$report/sessions.tsv"; : > "$report/host-events.tsv"
  KLAB_MG_REPORT="$report"; KLAB_MG_KEEP_SESSIONS="$keep"; KLAB_MG_STAGE=validate
  trap 'rc=$?; printf "rc=%s\nstage=%s\nline=%s\ncommand=%s\n" "$rc" "${KLAB_MG_STAGE:-unknown}" "${BASH_LINENO[0]:-unknown}" "$BASH_COMMAND" > "${KLAB_MG_REPORT}/error-context.txt"' ERR
  "$planner" validate "$scenario" > "$report/scenario.normalized.json"
  local default_timeout; default_timeout="$($planner meta "$scenario")"

  local -A MG_NET_BUS=() MG_NET_CIDR=() MG_NET_CAPTURE=() MG_NET_DELAY=()
  local nid cidr capture delay
  printf 'id\tcidr\tbus\tcapture\tdelay_us\n' > "$report/networks.tsv"
  while IFS=$'\t' read -r nid cidr capture delay; do
    MG_NET_BUS[$nid]="${KLAB_MULTIGUEST_BUS:-$(klab_mg_auto_bus "$run_id|$scenario|$nid")}"; MG_NET_CIDR[$nid]="$cidr"; MG_NET_CAPTURE[$nid]="$capture"; MG_NET_DELAY[$nid]="$delay"
    printf '%s\t%s\t%s\t%s\t%s\n' "$nid" "$cidr" "${MG_NET_BUS[$nid]}" "$capture" "$delay" >> "$report/networks.tsv"
  done < <("$planner" networks "$scenario")

  local -A MG_SESSION=() MG_SOCK=() MG_QMP=() MG_TARGET=() MG_ARCH=() MG_PROFILE=() MG_USERSPACE=() MG_TIMEOUT=() MG_FORWARD=() MG_EXPECTED_DOWN=()
  local gid target arch profile userspace ip mac timeout forward gdir agent bundle
  KLAB_MG_STAGE=plan
  while IFS=$'\t' read -r gid target arch profile userspace ip mac timeout forward; do
    gdir="$report/guests/$gid"; mkdir -p "$gdir/processes" "$gdir/builds" "$gdir/modules" "$gdir/network"
    arch="$(canonical_arch "$arch")"; set_active_arch "$arch"; validate_profile "$profile"
    if [[ "$target" == upstream:* ]]; then
      klab_arch_kernel_supported "$ARCH" "${target#upstream:}" || die "guest $gid kernel ${target#upstream:} unsupported by $ARCH"
    fi
    klab_arch_e2e_assert_enabled "$ARCH" || die "guest $gid architecture $ARCH is not enabled for E2E"
    klab_arch_plan_json "$ARCH" "$(host_arch)" > "$gdir/architecture-plan.json"
    MG_TARGET[$gid]="$target"; MG_ARCH[$gid]="$ARCH"; MG_PROFILE[$gid]="$profile"; MG_USERSPACE[$gid]="$userspace"; MG_TIMEOUT[$gid]="$timeout"; MG_FORWARD[$gid]="$forward"; MG_EXPECTED_DOWN[$gid]=0
  done < <("$planner" guests "$scenario")

  printf 'guest\tid\tnetwork\tip\tmac\tguest_ifname\tqdev\tcapture\tdelay_us\tpcap\n' > "$report/interfaces.tsv"
  local ifid ifnet ifip ifmac ifname ifcap ifdelay qdev pcap
  while IFS=$'\t' read -r gid ifid ifnet ifip ifmac ifname ifcap ifdelay; do
    qdev="klabnic$(sed -n "/^$gid\t/=" "$report/interfaces.tsv" 2>/dev/null | tail -n1 || true)" # overwritten at boot/report below
    pcap=''; [[ "$ifcap" == 1 ]] && pcap="guests/$gid/network/$ifid.pcap"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$gid" "$ifid" "$ifnet" "$ifip" "$ifmac" "$ifname" "" "$ifcap" "$ifdelay" "$pcap" >> "$report/interfaces.tsv"
  done < <("$planner" interfaces "$scenario")
  klab_mg_event plan "guests=${#MG_TARGET[@]} networks=${#MG_NET_BUS[@]}"
  if (( dry == 1 )); then KLAB_MG_STAGE=complete; printf 'scenario=%s\nreport=%s\n' "$scenario" "$report"; cat "$report/networks.tsv"; "$planner" guests "$scenario"; return 0; fi

  KLAB_MG_STAGE=prepare
  for gid in "${!MG_TARGET[@]}"; do
    target="${MG_TARGET[$gid]}"; arch="${MG_ARCH[$gid]}"; profile="${MG_PROFILE[$gid]}"; userspace="${MG_USERSPACE[$gid]}"; gdir="$report/guests/$gid"; set_active_arch "$arch"
    bundle="$gdir/target.klab"; cmd_prepare "$target" --arch "$arch" --profile "$profile" --userspace "$userspace" --with-sdk -o "$bundle" >/dev/null; bundle_tool verify "$bundle" > "$gdir/bundle-verify.txt"
    agent="$gdir/klab-agent"; cmd_build_user "$target" --source "$SELF_DIR/guest-agent/klab-agent.c" --arch "$arch" --profile "$profile" --userspace "$userspace" -o "$agent" -- -O2 -std=c11 >/dev/null
    file "$agent" > "$gdir/agent-file.txt" || true; klab_arch_e2e_file_matches "$arch" "$(cat "$gdir/agent-file.txt")" || die "guest $gid agent does not match $arch"
  done

  KLAB_MG_STAGE=builds
  local bid src64 remote64 static flags64 src remote flags_json out; local -a cflags bcmd
  while IFS=$'\t' read -r gid bid src64 remote64 static flags64; do
    [[ -n "$gid" ]] || continue; target="${MG_TARGET[$gid]}"; arch="${MG_ARCH[$gid]}"; profile="${MG_PROFILE[$gid]}"; userspace="${MG_USERSPACE[$gid]}"; gdir="$report/guests/$gid"
    src="$(klab_scenario_b64dec "$src64")"; remote="$(klab_scenario_b64dec "$remote64")"; flags_json="$(klab_scenario_b64dec "$flags64")"; src="$(klab_scenario_resolve "$base" "$src")"; out="$gdir/builds/$bid"
    mapfile -t cflags < <(python3 - "$flags_json" <<'PY'
import json,sys
for x in json.loads(sys.argv[1]): print(x)
PY
)
    bcmd=(cmd_build_user "$target" --source "$src" --arch "$arch" --profile "$profile" --userspace "$userspace" -o "$out"); [[ "$static" == 1 ]] || bcmd+=(--no-static); ((${#cflags[@]})) && bcmd+=(-- "${cflags[@]}"); "${bcmd[@]}" >/dev/null
    file "$out" > "$gdir/builds/$bid.file.txt" || true; klab_arch_e2e_file_matches "$arch" "$(cat "$gdir/builds/$bid.file.txt")" || die "guest $gid build $bid does not match $arch"
    printf '%s\t%s\t%s\n' "$bid" "$out" "$remote" >> "$gdir/build-map.tsv"
  done < <("$planner" builds "$scenario")

  KLAB_MG_STAGE=module-builds
  local mid msrc64 margs64 munload mname msrc margs mko
  while IFS=$'\t' read -r gid mid msrc64 margs64 munload mname; do
    [[ -n "$gid" ]] || continue; target="${MG_TARGET[$gid]}"; arch="${MG_ARCH[$gid]}"; profile="${MG_PROFILE[$gid]}"; gdir="$report/guests/$gid"; set_active_arch "$arch"
    msrc="$(klab_scenario_b64dec "$msrc64")"; margs="$(klab_scenario_b64dec "$margs64")"; msrc="$(klab_scenario_resolve "$base" "$msrc")"; stable_build_module "$target" "$profile" "$msrc"; ((${#MODULE_FILES[@]})) || die "guest $gid module $mid produced no .ko"
    mko="$gdir/modules/$mid.ko"; cp "${MODULE_FILES[0]}" "$mko"; file "$mko" > "$gdir/modules/$mid.file.txt" || true; klab_arch_e2e_file_matches "$arch" "$(cat "$gdir/modules/$mid.file.txt")" || die "guest $gid module $mid does not match $arch"
    printf '%s\t%s\t%s\t%s\t%s\n' "$mid" "$mko" "$margs" "$munload" "$mname" >> "$gdir/module-map.tsv"
  done < <("$planner" modules "$scenario")

  KLAB_MG_STAGE=boot
  # Replace interface report with authoritative QEMU qdev identities.
  printf 'guest\tid\tnetwork\tip\tmac\tguest_ifname\tqdev\tcapture\tdelay_us\tpcap\n' > "$report/interfaces.tsv"
  for gid in "${!MG_TARGET[@]}"; do
    target="${MG_TARGET[$gid]}"; arch="${MG_ARCH[$gid]}"; profile="${MG_PROFILE[$gid]}"; userspace="${MG_USERSPACE[$gid]}"; gdir="$report/guests/$gid"
    local shash sess idx=0; shash="$(printf '%s' "$run_id|$gid" | sha256sum | cut -c1-10)"; sess="mg-${gid:0:20}-$shash"; sess="${sess:0:40}"; MG_SESSION[$gid]="$sess"
    local -a bootcmd=(cmd_boot_session "$target" --arch "$arch" --profile "$profile" --userspace "$userspace" --name "$sess")
    while IFS=$'\t' read -r xgid ifid ifnet ifip ifmac ifname ifcap ifdelay; do
      [[ "$xgid" == "$gid" ]] || continue; pcap=''; [[ "$ifcap" == 1 ]] && pcap="$gdir/network/$ifid.pcap"
      bootcmd+=(--net-link "$ifid" "${MG_NET_BUS[$ifnet]}" "$ifip" "$ifmac" "$ifname"); [[ -n "$pcap" ]] && bootcmd+=(--net-capture "$pcap"); (( ifdelay > 0 )) && bootcmd+=(--net-delay-us "$ifdelay")
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$gid" "$ifid" "$ifnet" "$ifip" "$ifmac" "$ifname" "klabnic$idx" "$ifcap" "$ifdelay" "${pcap#$report/}" >> "$report/interfaces.tsv"; idx=$((idx+1))
    done < <("$planner" interfaces "$scenario")
    "${bootcmd[@]}" >/dev/null
    load_session_env "$sess"; MG_SOCK[$gid]="$SESSION_CONTROL"; MG_QMP[$gid]="$SESSION_QMP"; cp "$(session_dir "$sess")/session.env" "$gdir/session.env"; cp "$(session_dir "$sess")/console.log" "$gdir/console.log" 2>/dev/null || true; printf '%s\t%s\n' "$gid" "$sess" >> "$report/sessions.tsv"; klab_mg_event guest_ready "$gid"
    if [[ "${MG_FORWARD[$gid]}" == 1 ]]; then session_rpc_exec "${MG_SOCK[$gid]}" 'echo 1 > /proc/sys/net/ipv4/ip_forward; cat /proc/sys/net/ipv4/ip_forward' > "$gdir/ip-forward.txt" || die "guest $gid failed to enable IPv4 forwarding"; fi
  done
  local rdest rvia
  while IFS=$'\t' read -r gid rdest rvia; do [[ -n "$gid" ]] || continue; configure_guest_route "${MG_SOCK[$gid]}" "$rdest" "$rvia" >> "$report/guests/$gid/network/routes.txt" || die "guest $gid failed to install route $rdest via $rvia"; done < <("$planner" routes "$scenario")

  KLAB_MG_STAGE=agent-deploy
  for gid in "${!MG_TARGET[@]}"; do
    gdir="$report/guests/$gid"; sess="${MG_SESSION[$gid]}"; cmd_push_session "$sess" "$gdir/klab-agent" /tmp/klab-agent >/dev/null; session_rpc_exec "${MG_SOCK[$gid]}" '/tmp/klab-agent --socket /tmp/klab-agent.sock --state /tmp/klab-agent-state start' > "$gdir/agent-start.txt"; session_rpc_exec "${MG_SOCK[$gid]}" '/tmp/klab-agent ping' > "$gdir/agent-ping.txt"
    if [[ -f "$gdir/build-map.tsv" ]]; then while IFS=$'\t' read -r bid out remote; do cmd_push_session "$sess" "$out" "$remote" >/dev/null; session_rpc_exec "${MG_SOCK[$gid]}" "chmod 0755 '$remote'" >/dev/null; done < "$gdir/build-map.tsv"; fi
  done
  local fsrc64 frem64 fmode fsrc frem
  while IFS=$'\t' read -r gid fsrc64 frem64 fmode; do [[ -n "$gid" ]] || continue; fsrc="$(klab_scenario_b64dec "$fsrc64")"; frem="$(klab_scenario_b64dec "$frem64")"; fsrc="$(klab_scenario_resolve "$base" "$fsrc")"; cmd_push_session "${MG_SESSION[$gid]}" "$fsrc" "$frem" >/dev/null; session_rpc_exec "${MG_SOCK[$gid]}" "chmod $fmode '$frem'" >/dev/null; done < <("$planner" files "$scenario")

  KLAB_MG_STAGE=module-load; local failures=0 mrc mstatus; local -a margarr loadargs
  printf 'guest\tid\tname\tload_rc\tstatus\n' > "$report/module-load-results.tsv"
  for gid in "${!MG_TARGET[@]}"; do gdir="$report/guests/$gid"; [[ -f "$gdir/module-map.tsv" ]] || continue; while IFS=$'\t' read -r mid mko margs munload mname; do loadargs=("${MG_SESSION[$gid]}" "$mko"); if [[ -n "$margs" ]]; then margarr=(); read -r -a margarr <<<"$margs"; loadargs+=("${margarr[@]}"); fi; set +e; cmd_load_module_session "${loadargs[@]}" > "$gdir/modules/$mid.load.txt" 2>&1; mrc=$?; set -e; if ((mrc==0));then mstatus=PASS;else mstatus=FAIL;failures=$((failures+1));fi; printf '%s\t%s\t%s\t%s\t%s\n' "$gid" "$mid" "$mname" "$mrc" "$mstatus" >> "$report/module-load-results.tsv"; done < "$gdir/module-map.tsv"; done

  # Cache process specifications for dependency/readiness/fault orchestration.
  local -A P_GUEST=() P_ID=() P_CMD=() P_TIMEOUT=() P_EXPECT=() P_EXSIG=() P_GATE=() P_GTIMEOUT=() P_READY=() P_RTIMEOUT=() P_ONDEP=() P_SPAWNED=() P_READY_DONE=() P_WAITED=() P_ACTUAL=() P_SIG=() P_WAITRC=() P_STATUS=()
  local pid cmd64 timeout_ms expected exsig gate gtimeout ready64 rtimeout ondep key command wrapped enc participant
  while IFS=$'\t' read -r gid pid cmd64 timeout_ms expected exsig gate gtimeout ready64 rtimeout ondep; do
    [[ -n "$gid" ]] || continue; [[ "$gate" == __KLAB_EMPTY__ ]] && gate=""; key="$gid/$pid"; P_GUEST[$key]="$gid"; P_ID[$key]="$pid"; P_CMD[$key]="$(klab_scenario_b64dec "$cmd64")"; P_TIMEOUT[$key]="$timeout_ms"; P_EXPECT[$key]="$expected"; P_EXSIG[$key]="$exsig"; P_GATE[$key]="$gate"; P_GTIMEOUT[$key]="$gtimeout"; P_READY[$key]="$(klab_scenario_b64dec "$ready64")"; P_RTIMEOUT[$key]="$rtimeout"; P_ONDEP[$key]="${ondep:-skip}"; P_SPAWNED[$key]=0; P_READY_DONE[$key]=0; P_WAITED[$key]=0
  done < <("$planner" processes "$scenario")
  "$planner" dependencies "$scenario" > "$report/dependencies.tsv"; "$planner" process-order "$scenario" > "$report/process-order.txt"

  # Cache actions before process execution so edge-triggered actions can fire as soon
  # as a process reaches started/ready/exited.  The old r16 loop waited until every
  # process had been spawned, which could make short-lived fault windows happen too late.
  local -a A_ORDER=()
  local -A A_TYPE=() A_JSON=() A_TRIGGER=() A_TSTATE=() A_DELAY=() A_DONE=()
  local aid atype a64 ajson trigger_key trigger_state delay_ms
  printf 'id\ttype\tstatus\ttrigger\tstarted_ms\tcompleted_ms\tduration_ms\tdetail\n' > "$report/action-results.tsv"
  printf 'guest\tcause\taction\texpected\tstatus\tobserved_ms\tdetail\n' > "$report/guest-loss-results.tsv"
  while IFS=$'\t' read -r aid atype a64; do
    [[ -n "$aid" ]] || continue; ajson="$(klab_scenario_b64dec "$a64")"
    IFS=$'\t' read -r trigger_key trigger_state delay_ms <<<"$(python3 - "$ajson" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); a=x.get('after') or {}
key=(str(a.get('guest',''))+'/'+str(a.get('process',''))) if a else '-'
print('\t'.join([key, str(a.get('state','-')) if a else '-', str(int(x.get('delay_ms',0)))]))
PY
)"
    A_ORDER+=("$aid"); A_TYPE[$aid]="$atype"; A_JSON[$aid]="$ajson"; A_TRIGGER[$aid]="$trigger_key"; A_TSTATE[$aid]="$trigger_state"; A_DELAY[$aid]="$delay_ms"; A_DONE[$aid]=0
  done < <("$planner" actions "$scenario")

  klab_mg_action_record(){
    local id="$1" status="$2" trigger="$3" started="$4" completed="$5" detail="${6:-}" duration=0
    [[ "$started" =~ ^[0-9]+$ && "$completed" =~ ^[0-9]+$ ]] && duration=$((completed-started))
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "${A_TYPE[$id]}" "$status" "$trigger" "$started" "$completed" "$duration" "$detail" >> "$report/action-results.tsv"
  }

  klab_mg_mark_guest_loss(){
    local g="$1" cause="$2" action="$3" expected="$4" detail="${5:-}" now status
    now="$(klab_mg_now_ms)"; MG_EXPECTED_DOWN[$g]=1
    if [[ "$expected" == 1 ]]; then status=EXPECTED; else status=UNEXPECTED; failures=$((failures+1)); fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$g" "$cause" "$action" "$expected" "$status" "$now" "$detail" >> "$report/guest-loss-results.tsv"
    klab_mg_event guest_loss "$g:$cause:$status"
  }

  klab_mg_action_run(){
    local id="$1" why="${2:-manual}" typ="${A_TYPE[$1]}" x="${A_JSON[$1]}" started completed
    local agid ifx down_ms sigval qdevx sessdir pidhost detail='' saw_panic=0 expected_loss=1 before_bytes=0 rpc_rc=0 console=''
    [[ "${A_DONE[$id]}" == 0 ]] || return 0
    A_DONE[$id]=1
    (( ${A_DELAY[$id]} > 0 )) && sleep "$(python3 -c "print(${A_DELAY[$id]}/1000)")"
    started="$(klab_mg_now_ms)"; klab_mg_event action_start "$id:$why"
    case "$typ" in
      link-flap)
        read -r agid ifx down_ms <<<"$(python3 - "$x" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(x['guest'],x['interface'],int(x.get('down_ms',1000)))
PY
)"
        qdevx="$(awk -F'\t' -v g="$agid" -v i="$ifx" '$1==g&&$2==i{print $7}' "$report/interfaces.tsv")"
        if [[ -z "$qdevx" ]]; then completed="$(klab_mg_now_ms)"; klab_mg_action_record "$id" FAIL "$why" "$started" "$completed" "$agid/$ifx QEMU device missing"; die "action $id cannot find QEMU device for $agid/$ifx"; fi
        if ! qmp_set_link "${MG_QMP[$agid]}" "$qdevx" false >/dev/null; then completed="$(klab_mg_now_ms)"; klab_mg_action_record "$id" FAIL "$why" "$started" "$completed" "$agid/$ifx link-down QMP failed"; die "link-flap action $id failed to set $agid/$ifx down"; fi
        klab_mg_event link_down "$agid/$ifx"; sleep "$(python3 -c "print($down_ms/1000)")"
        if ! qmp_set_link "${MG_QMP[$agid]}" "$qdevx" true >/dev/null; then completed="$(klab_mg_now_ms)"; klab_mg_action_record "$id" FAIL "$why" "$started" "$completed" "$agid/$ifx link-up QMP failed"; die "link-flap action $id failed to restore $agid/$ifx"; fi
        klab_mg_event link_up "$agid/$ifx"; detail="$agid/$ifx qdev=$qdevx down_ms=$down_ms" ;;
      signal)
        read -r agid pid sigval <<<"$(python3 - "$x" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(x['guest'],x['process'],int(x.get('signal',15)))
PY
)"
        if ! session_rpc_exec "${MG_SOCK[$agid]}" "/tmp/klab-agent signal $pid $sigval" >/dev/null; then completed="$(klab_mg_now_ms)"; klab_mg_action_record "$id" FAIL "$why" "$started" "$completed" "$agid/$pid signal=$sigval RPC failed"; die "signal action $id failed for $agid/$pid"; fi
        klab_mg_event process_signal "$agid/$pid:$sigval"; detail="$agid/$pid signal=$sigval" ;;
      guest-power-cut)
        read -r agid expected_loss <<<"$(python3 - "$x" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(x['guest'], 1 if x.get('expected',True) else 0)
PY
)"
        sessdir="$(session_dir "${MG_SESSION[$agid]}")"
        if [[ ! -f "$sessdir/pid" ]]; then completed="$(klab_mg_now_ms)"; klab_mg_action_record "$id" FAIL "$why" "$started" "$completed" "$agid session pid missing"; die "guest power-cut action $id cannot find pid for $agid"; fi
        pidhost="$(cat "$sessdir/pid")"
        if [[ ! "$pidhost" =~ ^[0-9]+$ ]] || ! kill -0 "$pidhost" 2>/dev/null; then completed="$(klab_mg_now_ms)"; klab_mg_action_record "$id" FAIL "$why" "$started" "$completed" "$agid host pid $pidhost not running before cut"; die "guest power-cut action $id found no running QEMU for $agid"; fi
        if ! kill -KILL "$pidhost" 2>/dev/null; then completed="$(klab_mg_now_ms)"; klab_mg_action_record "$id" FAIL "$why" "$started" "$completed" "$agid host pid $pidhost kill failed"; die "guest power-cut action $id could not kill $agid"; fi
        for _ in {1..50}; do kill -0 "$pidhost" 2>/dev/null || break; sleep .02; done
        if kill -0 "$pidhost" 2>/dev/null; then completed="$(klab_mg_now_ms)"; klab_mg_action_record "$id" FAIL "$why" "$started" "$completed" "$agid host pid $pidhost still running"; die "guest power-cut action $id did not stop $agid"; fi
        klab_mg_mark_guest_loss "$agid" power-cut "$id" "$expected_loss" "host_pid=$pidhost"; klab_mg_event guest_power_cut "$agid"; detail="$agid host_pid=$pidhost expected=$expected_loss" ;;
      kernel-panic)
        read -r agid expected_loss <<<"$(python3 - "$x" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); print(x['guest'], 1 if x.get('expected',True) else 0)
PY
)"
        sessdir="$(session_dir "${MG_SESSION[$agid]}")"; console="$sessdir/console.log"
        [[ -f "$console" ]] && before_bytes="$(wc -c < "$console")" || before_bytes=0
        set +e; session_rpc_exec "${MG_SOCK[$agid]}" 'echo 1 > /proc/sys/kernel/sysrq; echo c > /proc/sysrq-trigger' >/dev/null 2>&1; rpc_rc=$?; set -e
        for _ in {1..100}; do if klab_mg_panic_since "$console" "$before_bytes"; then saw_panic=1; break; fi; sleep .05; done
        if ((saw_panic==0)); then completed="$(klab_mg_now_ms)"; klab_mg_action_record "$id" FAIL "$why" "$started" "$completed" "$agid new panic marker missing after byte $before_bytes (rpc_rc=$rpc_rc)"; die "kernel panic action $id did not produce a new panic marker on $agid"; fi
        klab_mg_mark_guest_loss "$agid" kernel-panic "$id" "$expected_loss" "console_offset=$before_bytes rpc_rc=$rpc_rc"; klab_mg_event kernel_panic_injected "$agid"; detail="$agid new_panic_after=$before_bytes rpc_rc=$rpc_rc expected=$expected_loss" ;;
    esac
    completed="$(klab_mg_now_ms)"; klab_mg_action_record "$id" PASS "$why" "$started" "$completed" "$detail"; klab_mg_event action_complete "$id:$why"
  }

  klab_mg_fire_actions_for_state(){
    local k="$1" state="$2" id
    for id in "${A_ORDER[@]}"; do
      [[ "${A_DONE[$id]}" == 0 && "${A_TRIGGER[$id]}" == "$k" && "${A_TSTATE[$id]}" == "$state" ]] || continue
      klab_mg_action_run "$id" "$k:$state"
    done
  }

  klab_mg_has_pending_action_for_state(){
    local k="$1" state="$2" id
    for id in "${A_ORDER[@]}"; do
      [[ "${A_DONE[$id]}" == 0 && "${A_TRIGGER[$id]}" == "$k" && "${A_TSTATE[$id]}" == "$state" ]] || continue
      return 0
    done
    return 1
  }

  klab_mg_proc_spawn(){
    local k="$1" g="${P_GUEST[$1]}" p="${P_ID[$1]}" c="${P_CMD[$1]}" w e part
    [[ "${P_SPAWNED[$k]}" == 0 ]] || return 0; w="$c"
    if [[ -n "${P_GATE[$k]}" ]]; then part="$g.$p"; e="$(klab_scenario_b64enc "$c")"; w="/tmp/klab-agent --state /tmp/klab-agent-state gate-run64 ${P_GATE[$k]} $part ${P_GTIMEOUT[$k]} $e"; fi
    e="$(klab_scenario_b64enc "$w")"; session_rpc_exec "${MG_SOCK[$g]}" "/tmp/klab-agent --socket /tmp/klab-agent.sock --state /tmp/klab-agent-state spawn64 $p $e" > "$report/guests/$g/processes/$p.spawn.txt"; P_SPAWNED[$k]=1; klab_mg_event process_spawn "$k"; klab_mg_fire_actions_for_state "$k" started
    # A readiness-triggered action is itself a consumer of readiness. Observe it
    # immediately after spawn even when no process dependency waits on ready; this
    # prevents the action from drifting until the post-spawn action phase.
    if klab_mg_has_pending_action_for_state "$k" ready; then klab_mg_proc_ready "$k"; fi
  }
  klab_mg_proc_ready(){
    local k="$1" g="${P_GUEST[$1]}" p="${P_ID[$1]}" marker="${P_READY[$1]}" timeout="${P_RTIMEOUT[$1]}" deadline out
    [[ "${P_READY_DONE[$k]}" == 0 ]] || return 0; [[ -n "$marker" ]] || die "process $k has no readiness marker"
    deadline=$((SECONDS + (timeout+999)/1000)); while ((SECONDS<=deadline)); do out="$(session_rpc_exec "${MG_SOCK[$g]}" "/tmp/klab-agent output $p stdout" 2>/dev/null || true)"; if grep -Fq -- "$marker" <<<"$out"; then P_READY_DONE[$k]=1; klab_mg_event process_ready "$k:$marker"; klab_mg_fire_actions_for_state "$k" ready; return 0; fi; sleep .05; done; die "process $k did not become ready (marker '$marker')"
  }
  klab_mg_proc_wait(){
    local k="$1" override="${2:-}" g="${P_GUEST[$1]}" p="${P_ID[$1]}" tm="${override:-${P_TIMEOUT[$1]}}" out rc actual sig st=FAIL
    [[ "${P_WAITED[$k]}" == 0 ]] || return 0
    if [[ "${MG_EXPECTED_DOWN[$g]}" == 1 ]]; then P_ACTUAL[$k]=-1; P_SIG[$k]=0; P_WAITRC[$k]=0; P_STATUS[$k]=EXPECTED_GUEST_LOSS; P_WAITED[$k]=1; klab_mg_event process_expected_guest_loss "$k"; return 0; fi
    local rpc_timeout=$(( (tm + 999) / 1000 + 30 )); set +e; out="$(session_rpc_exec "${MG_SOCK[$g]}" "/tmp/klab-agent --socket /tmp/klab-agent.sock --state /tmp/klab-agent-state wait $p $tm" "$rpc_timeout" 2>&1)"; rc=$?; set -e; printf '%s\n' "$out" > "$report/guests/$g/processes/$p.wait.txt"; actual=-1; sig=0
    if ((rc==0)); then actual="$(printf '%s\n' "$out" | awk '$1=="OK"&&$2=="WAIT"{print $6}' | tail -n1)"; sig="$(printf '%s\n' "$out" | awk '$1=="OK"&&$2=="WAIT"{print $7}' | tail -n1)"; if [[ "$actual" == "${P_EXPECT[$k]}" && "$sig" == "${P_EXSIG[$k]}" ]]; then st=PASS; else failures=$((failures+1)); fi; else failures=$((failures+1)); session_rpc_exec "${MG_SOCK[$g]}" "/tmp/klab-agent signal $p 15" >/dev/null 2>&1 || true; fi
    P_ACTUAL[$k]="$actual"; P_SIG[$k]="$sig"; P_WAITRC[$k]="$rc"; P_STATUS[$k]="$st"; P_WAITED[$k]=1; klab_mg_event process_done "$k:$st"; klab_mg_fire_actions_for_state "$k" exited
  }
  klab_mg_wait_state(){
    local k="$1" state="$2"
    case "$state" in started) [[ "${P_SPAWNED[$k]}" == 1 ]] || die "dependency $k has not started" ;; ready) klab_mg_proc_ready "$k" ;; exited) klab_mg_proc_wait "$k" ;; esac
  }
  klab_mg_state_observed(){
    local k="$1" state="$2"
    case "$state" in
      started) [[ "${P_SPAWNED[$k]:-0}" == 1 ]] ;;
      ready) [[ "${P_READY_DONE[$k]:-0}" == 1 ]] ;;
      exited) [[ "${P_WAITED[$k]:-0}" == 1 && "${P_STATUS[$k]:-}" != EXPECTED_GUEST_LOSS ]] ;;
      *) return 1 ;;
    esac
  }

  KLAB_MG_STAGE=spawn
  local dep_block dep_source dep_status
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue; dep_block=0
    while IFS=$'\t' read -r dg dp sg sp st; do
      [[ "$dg/$dp" == "$key" ]] || continue
      dep_source="$sg/$sp"; klab_mg_wait_state "$dep_source" "$st"
      if [[ "$st" == exited ]]; then
        dep_status="${P_STATUS[$dep_source]:-UNKNOWN}"
        if [[ "$dep_status" != PASS ]]; then
          case "${P_ONDEP[$key]}" in
            run) klab_mg_event dependency_failure_ignored "$key:$dep_source:$dep_status" ;;
            skip) P_ACTUAL[$key]=-1; P_SIG[$key]=0; P_WAITRC[$key]=0; P_STATUS[$key]=SKIP_DEPENDENCY; P_WAITED[$key]=1; dep_block=1; klab_mg_event process_skip "$key:dependency=$dep_source:$dep_status"; break ;;
            fail) P_ACTUAL[$key]=-1; P_SIG[$key]=0; P_WAITRC[$key]=0; P_STATUS[$key]=FAIL_DEPENDENCY; P_WAITED[$key]=1; dep_block=1; failures=$((failures+1)); klab_mg_event dependency_failure "$key:$dep_source:$dep_status"; break ;;
          esac
        fi
      fi
    done < "$report/dependencies.tsv"
    (( dep_block == 1 )) || klab_mg_proc_spawn "$key"
  done < "$report/process-order.txt"

  KLAB_MG_STAGE=gates
  local gates_file="$report/gates.tsv"; "$planner" gates "$scenario" > "$gates_file"
  local gate_name max_ms deadline all status; local -a gate_names=()
  mapfile -t gate_names < <(cut -f1 "$gates_file" | sed '/^$/d' | sort -u)
  for gate_name in "${gate_names[@]}"; do
    max_ms=0; local active_parts=0
    while IFS=$'\t' read -r gate gid pid gtimeout; do [[ "$gate" == "$gate_name" ]] || continue; [[ "${P_SPAWNED[$gid/$pid]:-0}" == 1 ]] || continue; active_parts=$((active_parts+1)); (( gtimeout > max_ms )) && max_ms=$gtimeout; done < "$gates_file"
    if ((active_parts==0)); then klab_mg_event gate_skip "$gate_name:no-active-participants"; continue; fi
    ((max_ms>0)) || max_ms=60000; deadline=$((SECONDS + (max_ms+999)/1000)); all=0
    while (( SECONDS <= deadline )); do all=1; while IFS=$'\t' read -r gate gid pid gtimeout; do [[ "$gate" == "$gate_name" ]] || continue; [[ "${P_SPAWNED[$gid/$pid]:-0}" == 1 ]] || continue; participant="$gid.$pid"; status="$(session_rpc_exec "${MG_SOCK[$gid]}" "/tmp/klab-agent --state /tmp/klab-agent-state gate-status $gate_name $participant" 2>/dev/null | tail -n1 || true)"; [[ "$status" == WAITING || "$status" == RELEASED ]] || all=0; done < "$gates_file"; ((all==1)) && break; sleep .05; done
    ((all==1)) || die "cross-guest gate '$gate_name' timed out waiting for all participants"
    local released=''; while IFS=$'\t' read -r gate gid pid gtimeout; do [[ "$gate" == "$gate_name" ]] || continue; [[ "${P_SPAWNED[$gid/$pid]:-0}" == 1 ]] || continue; case " $released " in *" $gid "*) ;; *) session_rpc_exec "${MG_SOCK[$gid]}" "/tmp/klab-agent --state /tmp/klab-agent-state gate-release $gate_name" >/dev/null; released+=" $gid";; esac; done < "$gates_file"; klab_mg_event gate_release "$gate_name"
  done

  # Resolve any trigger state that was not already observed while satisfying process
  # dependencies. This preserves readiness/exited actions even when nothing else waits
  # on that state, while started actions remain genuinely edge-triggered at spawn time.
  KLAB_MG_STAGE=actions
  for aid in "${A_ORDER[@]}"; do
    [[ "${A_DONE[$aid]}" == 0 ]] || continue
    if [[ "${A_TRIGGER[$aid]}" == - ]]; then
      klab_mg_action_run "$aid" post-spawn
    else
      klab_mg_wait_state "${A_TRIGGER[$aid]}" "${A_TSTATE[$aid]}"
      if [[ "${A_DONE[$aid]}" == 0 ]]; then
        if klab_mg_state_observed "${A_TRIGGER[$aid]}" "${A_TSTATE[$aid]}"; then
          klab_mg_fire_actions_for_state "${A_TRIGGER[$aid]}" "${A_TSTATE[$aid]}"
        else
          started="$(klab_mg_now_ms)"; A_DONE[$aid]=1
          klab_mg_action_record "$aid" FAIL "${A_TRIGGER[$aid]}:${A_TSTATE[$aid]}" "$started" "$started" "trigger state unavailable after expected guest loss"
          failures=$((failures+1)); klab_mg_event action_trigger_lost "$aid:${A_TRIGGER[$aid]}:${A_TSTATE[$aid]}"
        fi
      fi
    fi
  done

  KLAB_MG_STAGE=wait
  for key in "${!P_GUEST[@]}"; do klab_mg_proc_wait "$key"; done
  printf 'guest\tid\texpected_exit\texpected_signal\tactual_exit\tsignal\twait_rc\tstatus\n' > "$report/process-results.tsv"
  for key in "${!P_GUEST[@]}"; do gid="${P_GUEST[$key]}"; pid="${P_ID[$key]}"; if [[ "${MG_EXPECTED_DOWN[$gid]}" != 1 ]]; then session_rpc_exec "${MG_SOCK[$gid]}" "/tmp/klab-agent output $pid stdout" > "$report/guests/$gid/processes/$pid.stdout" 2>/dev/null || true; session_rpc_exec "${MG_SOCK[$gid]}" "/tmp/klab-agent output $pid stderr" > "$report/guests/$gid/processes/$pid.stderr" 2>/dev/null || true; fi; printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$gid" "$pid" "${P_EXPECT[$key]}" "${P_EXSIG[$key]}" "${P_ACTUAL[$key]:--1}" "${P_SIG[$key]:-0}" "${P_WAITRC[$key]:-0}" "${P_STATUS[$key]:-UNKNOWN}" >> "$report/process-results.tsv"; done

  KLAB_MG_STAGE=collect
  for gid in "${!MG_TARGET[@]}"; do
    gdir="$report/guests/$gid"; cp "$(session_dir "${MG_SESSION[$gid]}")/console.log" "$gdir/console.log" 2>/dev/null || true
    if [[ "${MG_EXPECTED_DOWN[$gid]}" != 1 ]]; then session_rpc_exec "${MG_SOCK[$gid]}" '/tmp/klab-agent events' > "$gdir/events.tsv" 2>/dev/null || true; session_rpc_exec "${MG_SOCK[$gid]}" 'dmesg' > "$gdir/dmesg.txt" 2>/dev/null || true; session_rpc_exec "${MG_SOCK[$gid]}" '(ip addr 2>/dev/null || ifconfig 2>/dev/null); (ip route 2>/dev/null || cat /proc/net/route 2>/dev/null || true)' > "$gdir/network-final.txt" 2>/dev/null || true; fi
  done

  KLAB_MG_STAGE=module-unload; local urc ustatus; printf 'guest\tid\tname\tunload_rc\tstatus\n' > "$report/module-unload-results.tsv"
  for gid in "${!MG_TARGET[@]}"; do
    gdir="$report/guests/$gid"; [[ -f "$gdir/module-map.tsv" ]] || continue
    while IFS=$'\t' read -r mid mko margs munload mname; do
      if [[ "${MG_EXPECTED_DOWN[$gid]}" == 1 ]]; then printf '%s\t%s\t%s\t0\tEXPECTED_GUEST_LOSS\n' "$gid" "$mid" "$mname" >> "$report/module-unload-results.tsv"; continue; fi
      if [[ "$munload" != 1 ]]; then printf '%s\t%s\t%s\t0\tSKIP\n' "$gid" "$mid" "$mname" >> "$report/module-unload-results.tsv"; continue; fi
      set +e; cmd_unload_module_session "${MG_SESSION[$gid]}" "$mname" > "$gdir/modules/$mid.unload.txt" 2>&1; urc=$?; set -e; if ((urc==0));then ustatus=PASS;else ustatus=FAIL;failures=$((failures+1));fi; printf '%s\t%s\t%s\t%s\t%s\n' "$gid" "$mid" "$mname" "$urc" "$ustatus" >> "$report/module-unload-results.tsv"
    done < "$gdir/module-map.tsv"
  done
  ((failures==0)) || die "$failures multi-guest assertion/module cleanup failure(s)"
  KLAB_MG_STAGE=complete; [[ "$keep" == 1 ]] || klab_mg_cleanup; printf '%s\n' "$report"
}

cmd_multiguest_run(){
  (
    KLAB_MG_REPORT=''; KLAB_MG_STAGE=setup; KLAB_MG_KEEP_SESSIONS=0
    trap 'rc=$?; trap - EXIT; klab_mg_finalize "$rc"; exit "$rc"' EXIT
    klab_mg_impl "$@"
  )
}
