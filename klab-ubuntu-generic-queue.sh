#!/usr/bin/env bash
set -uo pipefail
CATALOG="${1:?usage: klab-ubuntu-generic-queue.sh CATALOG.tsv OUTDIR}"
OUT="${2:?usage: klab-ubuntu-generic-queue.sh CATALOG.tsv OUTDIR}"
KLAB_ROOT="${KLAB_ROOT:-$HOME/klab}"; export KLAB_ROOT KLAB_NATIVE_MEMORY="${KLAB_NATIVE_MEMORY:-8192M}"
FLOOR_GIB="${KLAB_QUEUE_FREE_GIB:-20}"; LIMIT="${KLAB_QUEUE_LIMIT:-0}"; done_count=0
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"; mkdir -p "$OUT/logs"
[[ -f "$OUT/status.tsv" ]] || printf 'release\tkernel\tresult\tevidence\n' >"$OUT/status.tsv"
while IFS=$'\t' read -r rel krel flavor package warehouse; do
  [[ "$rel" != release && "$warehouse" == MISSING ]] || continue
  grep -q $'^'"$rel"$'\t'"$krel"$'\t' "$OUT/status.tsv" && continue
  (( LIMIT == 0 || done_count < LIMIT )) || break
  avail=$(df -B1 --output=avail "$KLAB_ROOT" | tail -1); floor=$((FLOOR_GIB*1024*1024*1024))
  if ((avail<floor)); then printf '%s\t%s\tSTOP_SPACE\tbelow %s GiB floor\n' "$rel" "$krel" "$FLOOR_GIB" >>"$OUT/status.tsv"; break; fi
  target="ubuntu:$rel:$krel"; safe="${rel//./-}-${krel//./-}"; log="$OUT/logs/$safe.log"; result=FAIL_FETCH; evidence=-
  # fetch accepts exactly one provider:release:kernel argument. Ubuntu resolves native x86_64 by default.
  if "$SELF/kernel-lab.sh" fetch "$target" >"$log" 2>&1; then
    result=FAIL_BOOT; name="ucatalog-$safe"
    if timeout 300 "$SELF/kernel-lab.sh" boot "$target" --arch x86_64 --userspace "native:ubuntu:$rel" --name "$name" >>"$log" 2>&1; then
      if ev=$(timeout 90 "$SELF/kernel-lab.sh" exec "$name" 'uname -r; . /etc/os-release; printf "%s %s\n" "$ID" "$VERSION_ID"; echo FUNCTIONAL_OK' 2>>"$log"); then result=PASS; evidence=$(printf %s "$ev"|tr '\n' ';'); else result=FAIL_EXEC; fi
    fi
    timeout 60 "$SELF/kernel-lab.sh" stop "$name" >>"$log" 2>&1 || true
    root="$KLAB_ROOT/work/initramfs/session_${name}.session.root"; [[ ! -d "$root" ]] || chmod -R u+w "$root" 2>/dev/null || true
    rm -rf "$KLAB_ROOT/work/sessions/$name" "$root" "$KLAB_ROOT/work/initramfs/session_${name}.session.cpio.gz"
  fi
  printf '%s\t%s\t%s\t%s\n' "$rel" "$krel" "$result" "$evidence" >>"$OUT/status.tsv"; done_count=$((done_count+1))
done <"$CATALOG"
cat "$OUT/status.tsv"
