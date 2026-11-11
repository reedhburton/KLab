#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
LIB="${KLAB_UBUNTU_BUNDLE_DIR:-/home/reed/Documents/ChatGPT/Klab/library/offline-repo/buildable-targets}"
OUT="${1:-/home/reed/Documents/ChatGPT/Klab/library/ubuntu-native-v1/live-matrix}"
mkdir -p "$OUT/logs"
: > "$OUT/status.tsv"
printf 'release\tkernel\tresult\tphase\tevidence\n' >> "$OUT/status.tsv"
rows=(
 '12.04|3.2.0-150-generic'
 '16.04|4.4.0-210-generic'
 '18.04|4.15.0-213-generic'
 '20.04|5.4.0-216-generic'
 '22.04|5.15.0-194-generic'
 '24.04|6.8.0-142-generic'
)
cleanup_session(){
  local name="$1" d="${KLAB_ROOT:-$HOME/klab}/work/sessions/$1" pid relay
  timeout 45s "$ROOT/kernel-lab.sh" stop "$name" >/dev/null 2>&1 && return 0
  [[ -f "$d/pid" ]] && { pid="$(cat "$d/pid")"; kill "$pid" 2>/dev/null || true; }
  if [[ -f "$d/session.env" ]]; then unset SESSION_CONTROL_RELAY_PID; source "$d/session.env"; relay="${SESSION_CONTROL_RELAY_PID:-}"; [[ -z "$relay" ]] || kill "$relay" 2>/dev/null || true; fi
}
for row in "${rows[@]}"; do
  IFS='|' read -r rel kernel <<<"$row"
  bundle="$LIB/ubuntu-$rel-$kernel.klab"; session="ubuntu-native-${rel//./}-${kernel%%-*}"; log="$OUT/logs/$rel-$kernel.log"
  : > "$log"
  if [[ ! -s "$bundle" ]]; then printf '%s\t%s\tFAIL\tbundle\tmissing bundle\n' "$rel" "$kernel" >> "$OUT/status.tsv"; continue; fi
  echo "=== $rel / $kernel ===" | tee -a "$log"
  buildenv="$(find "$LIB" -maxdepth 1 -type f -name "buildenv-ubuntu-$kernel-x86_64--*.klabbuildenv" -print -quit)"
  if [[ -z "$buildenv" ]]; then printf '%s\t%s\tFAIL\tdependency\tmissing buildenv\n' "$rel" "$kernel" >> "$OUT/status.tsv"; continue; fi
  target_dir="${KLAB_ROOT:-$HOME/klab}/targets/kernels/ubuntu/$rel/x86_64/$kernel"
  if [[ ! -f "$target_dir/bundle.env" ]]; then
    "$ROOT/kernel-lab.sh" import "$buildenv" >>"$log" 2>&1 || { printf '%s\t%s\tFAIL\tbuildenv-import\tsee log\n' "$rel" "$kernel" >> "$OUT/status.tsv"; continue; }
    "$ROOT/kernel-lab.sh" import "$bundle" >>"$log" 2>&1 || { printf '%s\t%s\tFAIL\tkernel-import\tsee log\n' "$rel" "$kernel" >> "$OUT/status.tsv"; continue; }
  else echo "Reusing installed target $target_dir" >>"$log"; fi
  if ! timeout 240s "$ROOT/kernel-lab.sh" boot "ubuntu:$rel:$kernel" --arch x86_64 --userspace "ubuntu-native:$rel" --name "$session" >>"$log" 2>&1; then cleanup_session "$session"; printf '%s\t%s\tFAIL\tboot\tsee log\n' "$rel" "$kernel" >> "$OUT/status.tsv"; continue; fi
  if output="$($ROOT/kernel-lab.sh exec "$session" 'printf "NATIVE_OK\\n"; uname -r; . /etc/os-release; printf "%s %s\\n" "$ID" "$VERSION_ID"; /usr/bin/ldd --version 2>&1 | head -1; dpkg-query -W libc6 dash coreutils 2>/dev/null | sort' 2>>"$log")"; then
    printf '%s\n' "$output" >> "$log"
    if grep -Fxq NATIVE_OK <<<"$output" && grep -Fxq "$kernel" <<<"$output" && grep -Fxq "ubuntu $rel" <<<"$output"; then
      evidence="$(printf '%s' "$output" | tr '\n' ';' | sed 's/;*$//')"
      printf '%s\t%s\tPASS\tcomplete\t%s\n' "$rel" "$kernel" "$evidence" >> "$OUT/status.tsv"
    else printf '%s\t%s\tFAIL\tidentity\tsee log\n' "$rel" "$kernel" >> "$OUT/status.tsv"; fi
  else printf '%s\t%s\tFAIL\texec\tsee log\n' "$rel" "$kernel" >> "$OUT/status.tsv"; fi
  cleanup_session "$session"
  rm -rf "${KLAB_ROOT:-$HOME/klab}/work/initramfs/session_${session}.session.root" "${KLAB_ROOT:-$HOME/klab}/work/initramfs/session_${session}.session.cpio.gz"
done
cat "$OUT/status.tsv"
! grep -q $'\tFAIL\t' "$OUT/status.tsv"
