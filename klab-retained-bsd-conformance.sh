#!/usr/bin/env bash
set -uo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"; KLAB_ROOT="${KLAB_ROOT:-$HOME/klab}"; export KLAB_ROOT
OUT="${1:?usage: klab-retained-bsd-conformance.sh OUTDIR}"; LIMIT="${KLAB_BSD_CONFORMANCE_LIMIT:-0}"; mkdir -p "$OUT/targets" "$OUT/logs"; status="$OUT/status.tsv"
[[ -f "$status" ]] || printf 'provider\trelease\tarch\tresult\tuser_passed\tmodule_smoke\treport\n' >"$status"; count=0
while IFS= read -r env; do
 relpath="${env#"$KLAB_ROOT/targets/kernels/"}"; relpath="${relpath%/bundle.env}"; IFS=/ read -r provider release arch kernel <<<"$relpath"; [[ "$provider" == freebsd ]] || continue
 awk -F '\t' -v p="$provider" -v r="$release" -v a="$arch" 'NR>1&&$1==p&&$2==r&&$3==a{f=1}END{exit !f}' "$status" && continue; ((LIMIT==0||count<LIMIT))||break
 if [[ "$arch" == aarch64 ]]; then export KLAB_QEMU="$SELF/tools/qemu10-aarch64-container"; else unset KLAB_QEMU; fi
 safe="freebsd-${release//./-}-$arch"; report="$OUT/targets/$safe"; log="$OUT/logs/$safe.log"; target="freebsd:$release:$arch"; result=FAIL_MODULE; module=FAIL; passed=0; mkdir -p "$report"; : >"$log"
 if timeout 2400 "$SELF/kernel-lab.sh" smoke "$target" --arch "$arch" >>"$log" 2>&1; then
  module=PASS; result=FAIL_BOOT; digest=$(printf %s "$target"|sha256sum|cut -c1-10); session="bsdconf-$digest"
  if timeout 600 "$SELF/kernel-lab.sh" boot "$target" --arch "$arch" --name "$session" >>"$log" 2>&1; then
   result=FAIL_CONFORMANCE; timeout 300 "$SELF/klab-bsd-guest-conformance.sh" "$session" "$report" >>"$log" 2>&1 || true
   [[ -s "$report/results.tsv" ]] && passed=$(awk -F '\t' 'NR>1&&$2=="PASS"{n++}END{print n+0}' "$report/results.tsv")
   [[ "$passed" == 9 ]] && result=PASS
  fi
  timeout 120 "$SELF/kernel-lab.sh" stop "$session" >>"$log" 2>&1 || true
 fi
 printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$provider" "$release" "$arch" "$result" "$passed" "$module" "$report" >>"$status"; count=$((count+1))
done < <(find "$KLAB_ROOT/targets/kernels/freebsd" -mindepth 4 -maxdepth 4 -name bundle.env -type f | sort -V)
cat "$status"
