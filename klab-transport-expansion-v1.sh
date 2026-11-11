#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${KLAB_TRANSPORT_OUT:-/home/reed/Documents/ChatGPT/Klab/library/transport-expansion-v1}"
mkdir -p "$OUT/logs"
STATUS="$OUT/status.tsv"
printf 'family\trelease\tkernel\tuserspace\tresult\tevidence\n' > "$STATUS"
cleanup_name=""
cleanup() {
  if [[ -n "$cleanup_name" ]]; then "$ROOT/kernel-lab.sh" stop "$cleanup_name" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT INT TERM
run_one() {
  local family=$1 release=$2 kernel=$3 userspace=$4
  local safe="${family}-${release}-${kernel}" name log result evidence
  safe="${safe//[^A-Za-z0-9_.-]/_}"; name="tx-${safe}"; name="${name:0:60}"
  log="$OUT/logs/${safe}.log"; cleanup_name="$name"
  "$ROOT/kernel-lab.sh" stop "$name" >/dev/null 2>&1 || true
  if KLAB_BOOT_TIMEOUT="${KLAB_BOOT_TIMEOUT:-120}" "$ROOT/kernel-lab.sh" boot "$family:$release:$kernel" --arch x86_64 --userspace "$userspace" --name "$name" >"$log" 2>&1; then
    if evidence=$("$ROOT/kernel-lab.sh" exec "$name" 'printf "TRANSPORT_OK kernel=%s\\n" "$(uname -r)"' 2>>"$log"); then
      printf '%s\n' "$evidence" >> "$log"; result=PASS
    else
      result=FAIL; evidence='RPC exec failed'
    fi
  else
    result=FAIL; evidence=$(tail -n 1 "$log" | tr '\t\r\n' '   ')
  fi
  "$ROOT/kernel-lab.sh" stop "$name" >>"$log" 2>&1 || true
  session_env="/home/reed/klab/work/sessions/$name/session.env"
  if [[ -f "$session_env" ]]; then
    initrd=$(sed -n "s/^SESSION_INITRD=//p" "$session_env")
    if [[ "$initrd" == /home/reed/klab/work/initramfs/session_tx-* ]]; then
      rm -f -- "$initrd"
      rm -rf -- "${initrd%.cpio.gz}.root" "${initrd%.ext2.gz}.root"
    fi
  fi
  cleanup_name=""
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$family" "$release" "$kernel" "$userspace" "$result" "$evidence" | tee -a "$STATUS"
}
ubuntu_cases=(
'12.04|3.2.0-23-generic' '12.04|3.13.0-185-generic'
'14.04|3.13.0-24-generic' '14.04|4.4.0-148-generic'
'16.04|4.4.0-21-generic' '16.04|4.15.0-142-generic'
'18.04|4.15.0-20-generic' '18.04|5.4.0-150-generic'
'20.04|5.4.0-26-generic' '20.04|5.15.0-139-generic'
'22.04|5.15.0-25-generic' '22.04|6.8.0-138-generic'
'24.04|6.8.0-31-generic' '24.04|6.11.0-29-generic' '24.04|6.14.0-37-generic' '24.04|6.17.0-42-generic' '24.04|7.0.0-34-generic'
)
fedora_cases=(
'20|3.14.9-200.fc20.x86_64' '23|4.4.9-300.fc23.x86_64' '26|4.14.18-200.fc26.x86_64'
'29|4.19.15-300.fc29.x86_64' '32|5.10.22-100.fc32.x86_64' '35|5.15.18-200.fc35.x86_64'
'38|6.2.15-300.fc38.x86_64' '40|6.8.11-300.fc40.x86_64' '42|6.14.11-300.fc42.x86_64'
'43|6.17.1-300.fc43.x86_64' '44|7.0.14-201.fc44.x86_64'
)
for c in "${ubuntu_cases[@]}"; do IFS='|' read -r r k <<<"$c"; run_one ubuntu "$r" "$k" "ubuntu-native:$r"; done
for c in "${fedora_cases[@]}"; do IFS='|' read -r r k <<<"$c"; run_one fedora "$r" "$k" buildroot:ssh; done
pass=$(awk -F '\t' '$5=="PASS"{n++} END{print n+0}' "$STATUS")
fail=$(awk -F '\t' '$5=="FAIL"{n++} END{print n+0}' "$STATUS")
printf 'SUMMARY\tPASS=%s\tFAIL=%s\n' "$pass" "$fail" | tee "$OUT/summary.txt"
(( fail == 0 ))
