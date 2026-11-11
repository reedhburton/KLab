#!/usr/bin/env bash
set -uo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB_ROOT="${KLAB_ROOT:-$HOME/klab}"; export KLAB_ROOT
OUT="${1:?usage: klab-retained-conformance-queue.sh OUTDIR}"
LIMIT="${KLAB_CONFORMANCE_LIMIT:-0}"; BOOT_ATTEMPTS="${KLAB_CONFORMANCE_BOOT_ATTEMPTS:-3}"; KLAB_NATIVE_MEMORY="${KLAB_NATIVE_MEMORY:-8192M}"; export KLAB_NATIVE_MEMORY
mkdir -p "$OUT/targets" "$OUT/boot-logs"
status="$OUT/status.tsv"
[[ -f "$status" ]] || printf 'provider\trelease\tkernel\tarch\tresult\tpassed\tfailed\treport\n' >"$status"
count=0
while IFS= read -r env; do
  relpath="${env#"$KLAB_ROOT/targets/kernels/"}"; relpath="${relpath%/bundle.env}"
  IFS=/ read -r provider release arch kernel <<<"$relpath"
  case "$provider" in ubuntu|fedora|alpine|debian|centos) ;; *) continue;; esac
  awk -F '\t' -v p="$provider" -v r="$release" -v k="$kernel" 'NR>1 && $1==p && $2==r && $3==k {found=1} END{exit !found}' "$status" && continue
  (( LIMIT == 0 || count < LIMIT )) || break
  safe=$(printf '%s-%s-%s' "$provider" "$release" "$kernel" | tr -c 'A-Za-z0-9_-' '-')
  digest=$(printf '%s' "$provider:$release:$kernel:$arch" | sha256sum | cut -c1-12)
  session_base="conf-${provider:0:8}-${release:0:8}-$digest"; report="$OUT/targets/$safe"; log="$OUT/boot-logs/$safe.log"
  target="$provider:$release:$kernel"; result=FAIL_BOOT; passed=0; failed=9
  mkdir -p "$report"; rm -f "$report"/RESULT "$report"/results.tsv "$report"/*.log
  : >"$log"
  for ((attempt=1; attempt<=BOOT_ATTEMPTS; attempt++)); do
    session="${session_base}-a$attempt"
    session_root="$KLAB_ROOT/work/initramfs/session_${session}.session.root"
    [[ ! -d "$session_root" ]] || chmod -R u+w "$session_root" 2>/dev/null || true
    rm -rf "$KLAB_ROOT/work/sessions/$session" "$session_root" "$KLAB_ROOT/work/initramfs/session_${session}.session.cpio.gz"
    printf '=== boot attempt %s/%s ===\n' "$attempt" "$BOOT_ATTEMPTS" >>"$log"
    if timeout 360 "$SELF/kernel-lab.sh" boot "$target" --arch "$arch" --userspace "native:$provider:$release" --name "$session" >>"$log" 2>&1; then
      result=FAIL_CONFORMANCE
      timeout 240 "$SELF/klab-guest-conformance.sh" "$session" "$report" >>"$log" 2>&1 || true
      if [[ -s "$report/results.tsv" ]]; then
        passed=$(awk -F '\t' 'NR>1 && $2=="PASS"{n++} END{print n+0}' "$report/results.tsv")
        failed=$(awk -F '\t' 'NR>1 && $2=="FAIL"{n++} END{print n+0}' "$report/results.tsv")
        [[ "$failed" == 0 && "$passed" == 9 ]] && result=PASS
      fi
    fi
    timeout 90 "$SELF/kernel-lab.sh" stop "$session" >>"$log" 2>&1 || true
    [[ ! -d "$session_root" ]] || chmod -R u+w "$session_root" 2>/dev/null || true
    rm -rf "$KLAB_ROOT/work/sessions/$session" "$session_root" "$KLAB_ROOT/work/initramfs/session_${session}.session.cpio.gz"
    [[ "$result" != FAIL_BOOT ]] && break
  done
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$provider" "$release" "$kernel" "$arch" "$result" "$passed" "$failed" "$report" >>"$status"
  count=$((count+1))
done < <(find "$KLAB_ROOT/targets/kernels" -mindepth 5 -maxdepth 5 -name bundle.env -type f | LC_ALL=C sort -V)
cat "$status"
