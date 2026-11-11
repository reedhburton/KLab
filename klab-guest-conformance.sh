#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB_BIN="${KLAB_BIN:-$SELF_DIR/kernel-lab.sh}"
KLAB_ROOT="${KLAB_ROOT:-$HOME/klab}"
[[ $# -ge 1 && $# -le 2 ]] || { echo "usage: klab-guest-conformance.sh SESSION [REPORT_DIR]" >&2; exit 2; }
session="$1"; report="${2:-$KLAB_ROOT/results/conformance/$session-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$report"; results="$report/results.tsv"
printf 'CAPABILITY\tRESULT\tEVIDENCE\n' > "$results"; failures=0
probe() {
  local name="$1" command="$2" evidence rc
  evidence="$report/$name.log"
  set +e; KLAB_ROOT="$KLAB_ROOT" "$KLAB_BIN" exec "$session" "$command" >"$evidence" 2>&1; rc=$?; set -e
  if (( rc == 0 )); then printf '%s\tPASS\t%s\n' "$name" "$evidence" >> "$results"
  else printf '%s\tFAIL\t%s\n' "$name" "$evidence" >> "$results"; failures=$((failures + 1)); fi
}
probe identity '. /etc/os-release; printf "kernel=%s os=%s:%s arch=%s\n" "$(uname -r)" "$ID" "$VERSION_ID" "$(uname -m)"'
probe filesystem 'set -eu; p=/tmp/klab-conformance.$$; mkdir -p "$p"; printf data >"$p/file"; test "$(cat "$p/file")" = data; mv "$p/file" "$p/moved"; rm -rf "$p"'
probe proc_sys 'set -eu; test -r /proc/1/status; test -d /sys/class; test -c /dev/null'
probe processes 'set -eu; (sleep 0.05; echo one) & a=$!; (sleep 0.05; echo two) & b=$!; wait "$a"; wait "$b"; printf x | grep -qx x'
probe toolchain 'set -eu; command -v gcc; command -v make; d=/tmp/klab-cc.$$; mkdir "$d"; printf "%s\n" "int main(void){return 0;}" >"$d/a.c"; gcc "$d/a.c" -o "$d/a"; "$d/a"; rm -rf "$d"'
probe runtime 'set -eu; command -v python3; python3 -c "import os; p=os.fork(); os._exit(0) if p == 0 else None; assert os.waitpid(p,0)[1] == 0"'
probe networking 'set -eu; command -v ip; ip link show; if test -d /sys/class/net/eth0; then ip addr show dev eth0; ping -c 1 -W 2 10.0.2.2; else echo N/A:no-eth0; fi'
probe modules 'set -eu; command -v modprobe; test -d /lib/modules/$(uname -r); modprobe -n e1000 2>/dev/null || modprobe -n virtio_net'
probe shutdown_path 'set -eu; command -v sync; command -v poweroff || command -v reboot'
if (( failures == 0 )); then result=PASS; else result=FAIL; fi
printf '%s\n' "$result" > "$report/RESULT"
printf 'KLab guest conformance: %s (%s failures)\nreport=%s\n' "$result" "$failures" "$report"
exit "$(( failures == 0 ? 0 : 1 ))"
