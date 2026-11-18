#!/usr/bin/env bash
set -uo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"; KLAB_BIN="${KLAB_RUNNER:-$SELF/kernel-lab.sh}"; KLAB_ROOT="${KLAB_ROOT:-$HOME/klab-data}"; export KLAB_ROOT
usage(){ cat <<'HELP'
usage: klab validate TARGET [--arch ARCH] [--level quick|standard|full]
                            [--userspace SPEC] [--report-dir DIR]
quick boots and tests the target module lifecycle. standard adds backend-native
process/userspace/network checks. full adds an interactive userspace and real SSH.
Every run writes gates.tsv, manifest.json, RESULT, and per-gate logs.
HELP
}
[[ $# -ge 1 ]] || { usage >&2; exit 2; }; target="$1"; shift
arch=x86_64; arch_seen=0; level=standard; userspace=auto; report=""
while (($#)); do case "$1" in
 --arch) [[ $# -ge 2 ]] || exit 2; arch="$2"; arch_seen=1; shift 2;;
 --level) [[ $# -ge 2 ]] || exit 2; level="$2"; shift 2;;
 --userspace) [[ $# -ge 2 ]] || exit 2; userspace="$2"; shift 2;;
 --report-dir) [[ $# -ge 2 ]] || exit 2; report="$2"; shift 2;;
 -h|--help) usage; exit 0;; *) echo "klab validate: unknown option: $1" >&2; exit 2;; esac; done
case "$level" in quick|standard|full);; *) echo "klab validate: invalid level: $level" >&2; exit 2;; esac
provider="${target%%:*}"; backend=linux; [[ "$provider" == freebsd ]] && backend=freebsd; case "$provider" in netbsd|openbsd|dragonfly) backend=bsd-simple;; esac
case "$target" in freebsd:*:i386|freebsd:*:riscv64) backend=bsd-simple;; esac
if [[ ( "$backend" == freebsd || "$backend" == bsd-simple ) && "$arch_seen" == 0 ]]; then case "${target##*:}" in x86_64|aarch64|i386|riscv64) arch="${target##*:}";; esac; fi
safe="$(printf '%s-%s' "$target" "$arch"|tr -c 'A-Za-z0-9._-' '-')"; stamp="$(date -u +%Y%m%dT%H%M%SZ)"; report="${report:-$KLAB_ROOT/results/image-validation/$safe-$stamp}"
mkdir -p "$report/logs"; gates="$report/gates.tsv"; printf 'GATE\tRESULT\tEVIDENCE\n' >"$gates"; failures=0; live_session=""
record(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$gates"; [[ "$2" == PASS ]] || failures=$((failures+1)); }
run_gate(){ local gate="$1" secs="$2"; shift 2; local log="$report/logs/$gate.log" rc; timeout "$secs" "$@" >"$log" 2>&1; rc=$?; if ((rc==0)); then record "$gate" PASS "$log"; return 0; else printf 'exit=%s\n' "$rc" >>"$log"; record "$gate" FAIL "$log"; return 1; fi; }
cleanup(){
 if [[ -n "$live_session" ]]; then
  timeout 120 "$KLAB_BIN" stop "$live_session" >>"$report/logs/session-stop.log" 2>&1 || true
  root="$KLAB_ROOT/work/initramfs/session_${live_session}.session.root"; [[ ! -d "$root" ]] || chmod -R u+w "$root" 2>/dev/null || true
  rm -rf "$root" "$KLAB_ROOT/work/initramfs/session_${live_session}.session.cpio.gz" "$KLAB_ROOT/work/sessions/$live_session" 2>/dev/null || true
 fi
}
trap cleanup EXIT INT TERM
cleanup_internal_test_sessions(){
 local log="$1" n d pid root
 [[ -f "$log" ]] || return 0
 while IFS= read -r n; do
  [[ -n "$n" ]] || continue; d="$KLAB_ROOT/work/sessions/$n"
  if [[ -f "$d/pid" ]]; then pid="$(cat "$d/pid" 2>/dev/null || true)"; [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && continue; fi
  root="$KLAB_ROOT/work/initramfs/session_${n}.session.root"; [[ ! -d "$root" ]] || chmod -R u+w "$root" 2>/dev/null || true
  rm -rf "$d" "$root" "$KLAB_ROOT/work/initramfs/session_${n}.session.cpio.gz" 2>/dev/null || true
 done < <(grep -oE "(fbld|ftst)-[a-f0-9]{8,16}" "$log" | sort -u)
}
runner=("$KLAB_BIN"); [[ "$backend:$arch" != freebsd:aarch64 ]] || runner=(env "KLAB_QEMU=$SELF/tools/qemu10-aarch64-container" "$KLAB_BIN")
if [[ "$backend" == bsd-simple ]]; then
 bsd_helper="$SELF/bsd/bsd-simple.sh"; repo="$($SELF/klab repo path)"
 run_gate target_preflight 60 "$bsd_helper" supports "$target" || true
 run_gate quick_boot 2400 "$bsd_helper" run "$target" "$repo" "$KLAB_ROOT" minimal || true
else
 run_gate target_preflight 60 "${runner[@]}" info "$target" --arch "$arch" || true
 if [[ "$backend" == linux && "$level" != quick ]]; then
  run_gate quick_boot 900 env KLAB_RUNNER="$KLAB_BIN" KLAB_ROOT="$KLAB_ROOT" "$SELF/klab-userspace-smoke.sh" "$target" "$arch" "$userspace" "$report/quick-userspace" || true
 else
  run_gate quick_boot 2400 "${runner[@]}" smoke "$target" --arch "$arch" || true
  cleanup_internal_test_sessions "$report/logs/quick_boot.log"
 fi
fi
if [[ "$level" != quick && "$backend" == bsd-simple ]]; then
 run_gate bsd_userspace 2400 "$bsd_helper" run "$target" "$repo" "$KLAB_ROOT" full || true
 if [[ "$level" == full ]]; then
  run_gate bsd_ssh 1200 "$bsd_helper" run "$target" "$repo" "$KLAB_ROOT" ssh || true
  case "$provider" in netbsd|dragonfly) run_gate bsd_module 2400 "$bsd_helper" run "$target" "$repo" "$KLAB_ROOT" module || true;; esac
 fi
fi
if [[ "$level" != quick && "$backend" == linux ]]; then
 linux_gate_userspace=buildroot:minimal
 case "$target" in upstream:v2.0.40|upstream:v2.2.26|upstream:v2.6.0) linux_gate_userspace=busybox-static;; esac
 run_gate module_process 2400 "$KLAB_BIN" test "$target" --arch "$arch" --module "$SELF/tests/all-five/module" --script "$SELF/tests/all-five/workload.sh" --userspace "$linux_gate_userspace" || true
 run_gate two_guest_tcp 1200 "$SELF/klab-image-tcp-gate.sh" "$target" "$arch" "$report/tcp-report" || true
fi
if [[ "$level" != quick && "$backend" == freebsd ]]; then
 digest="$(printf '%s' "$target-$arch-$stamp-$$"|sha256sum|cut -c1-12)"; live_session="valbsd-$digest"; boot_args=(boot "$target" --arch "$arch" --name "$live_session")
 if [[ "$level" == full ]]; then
  key="$report/ssh-key"; ssh-keygen -q -t rsa -b 3072 -N '' -f "$key"; port="$(python3 - <<'PY'
import socket
s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()
PY
)"; boot_args+=(--ssh-auth key --ssh-key "$key" --ssh-bind 127.0.0.1 --ssh-port "$port")
 fi
 if run_gate bsd_boot 900 "${runner[@]}" "${boot_args[@]}"; then
  run_gate bsd_conformance 420 env KLAB_BIN="$KLAB_BIN" KLAB_ROOT="$KLAB_ROOT" "$SELF/klab-bsd-guest-conformance.sh" "$live_session" "$report/bsd-conformance" || true
  if [[ "$level" == full ]]; then
   release="${target#*:}"; release="${release%%:*}"; run_gate bsd_ssh 120 ssh -i "$key" -p "$port" -o ConnectTimeout=10 -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@127.0.0.1 "freebsd-version -u | grep -F '${release%%-*}'; printf KLAB_BSD_SSH_PASS" || true
  fi
 else
  record bsd_conformance FAIL "$report/logs/bsd_boot.log"; [[ "$level" != full ]] || record bsd_ssh FAIL "$report/logs/bsd_boot.log"
 fi
fi
if [[ "$level" == full && "$backend" == linux ]]; then
 rest="${target#*:}"; release="${rest%%:*}"; conformance="$SELF/klab-guest-conformance.sh"
 if [[ "$userspace" == auto ]]; then
  if [[ "$target" == *:*:* && "$provider" != upstream && "$provider" != custom ]]; then
   userspace="native:$provider:$release"
  elif [[ "$target" == upstream:v2.0.40 || "$target" == upstream:v2.2.26 || "$target" == upstream:v2.6.0 ]]; then
   userspace=busybox-static; conformance="$SELF/klab-buildroot-conformance.sh"
  else
   userspace=buildroot:minimal; conformance="$SELF/klab-buildroot-conformance.sh"
  fi
 elif [[ "$userspace" != native:* ]]; then conformance="$SELF/klab-buildroot-conformance.sh"; fi
 digest="$(printf '%s' "$target-$arch-$stamp-$$"|sha256sum|cut -c1-12)"; live_session="vallinux-$digest"; key="$report/ssh-key"; ssh-keygen -q -t rsa -b 3072 -N '' -f "$key"
 port="$(python3 - <<'PY'
import socket
s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()
PY
)"
 if run_gate interactive_boot 900 "$KLAB_BIN" boot "$target" --arch "$arch" --userspace "$userspace" --name "$live_session" --ssh-auth key --ssh-key "$key" --ssh-bind 127.0.0.1 --ssh-port "$port"; then
  run_gate userspace_conformance 420 env KLAB_BIN="$KLAB_BIN" KLAB_ROOT="$KLAB_ROOT" "$conformance" "$live_session" "$report/userspace-conformance" || true
  check='uname -r; uname -m; printf KLAB_SSH_PASS'; [[ "$provider" == upstream || "$provider" == custom ]] || check="test \"\$(uname -r)\" = '${target##*:}'; uname -m; printf KLAB_SSH_PASS"
  ssh_compat=(-o HostkeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa)
  case "$target" in
   upstream:v2.0.40|upstream:v2.2.26|upstream:v2.6.0) ssh_compat=(-o HostkeyAlgorithms=ssh-rsa -o PubkeyAcceptedAlgorithms=ssh-rsa -o KexAlgorithms=diffie-hellman-group1-sha1 -o Ciphers=aes128-cbc -o MACs=hmac-sha1 -o Compression=no);;
  esac
  run_gate interactive_ssh 120 ssh -i "$key" -p "$port" -o ConnectTimeout=10 -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${ssh_compat[@]}" root@127.0.0.1 "$check" || true
 else
  record userspace_conformance FAIL "$report/logs/interactive_boot.log"; record interactive_ssh FAIL "$report/logs/interactive_boot.log"
 fi
fi
((failures==0)) && result=PASS || result=FAIL; printf '%s\n' "$result" >"$report/RESULT"
python3 - "$report/manifest.json" "$target" "$arch" "$backend" "$level" "$result" "$gates" <<'PY'
import csv,datetime,json,sys
path,target,arch,backend,level,result,gates=sys.argv[1:]
with open(gates,newline='') as f: rows=list(csv.DictReader(f,delimiter='\t'))
d={"schema":"klab-image-validation-v1","target":target,"architecture":arch,"backend":backend,"requested_level":level,"result":result,"created_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"gates":rows}
with open(path,'w') as f: json.dump(d,f,indent=2,sort_keys=True);f.write('\n')
PY
printf 'KLab image validation: %s\ntarget=%s\nbackend=%s\nlevel=%s\nreport=%s\n' "$result" "$target" "$backend" "$level" "$report"; column -t -s $'\t' "$gates" 2>/dev/null||cat "$gates"; [[ "$result" == PASS ]]
