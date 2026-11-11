#!/usr/bin/env bash
set -uo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OUT="${1:?usage: klab-all-five-linux-queue.sh OUTDIR}"
KLAB_ROOT="${KLAB_ROOT:-$HOME/klab-data}"; export KLAB_ROOT
mkdir -p "$OUT/logs"; status="$OUT/status.tsv"
[[ -f "$status" ]] || printf 'provider\trelease\tkernel\tarch\tmodule_process_minimal\tnative_ssh\tresult\n' > "$status"
key="$OUT/ssh-key"; [[ -f "$key" ]] || ssh-keygen -q -t rsa -b 3072 -N '' -f "$key"
while IFS=$'\t' read -r provider release kernel arch result passed failed report; do
 [[ "$provider" == provider ]] && continue
 awk -F '\t' -v p="$provider" -v r="$release" -v k="$kernel" '$1==p&&$2==r&&$3==k{f=1}END{exit !f}' "$status" && continue
 target="$provider:$release:$kernel"; safe=$(printf %s "$target"|tr ':@/' '___'); log="$OUT/logs/$safe.log"; mp=FAIL; ssh=FAIL
 if timeout 2400 "$SELF/kernel-lab.sh" test "$target" --arch "$arch" --module "$SELF/tests/all-five/module" --script "$SELF/tests/all-five/workload.sh" --userspace buildroot:minimal >>"$log" 2>&1 </dev/null; then mp=PASS; fi
 session="af-$(printf %s "$target"|sha256sum|cut -c1-12)"
 if timeout 600 "$SELF/kernel-lab.sh" boot "$target" --arch "$arch" --userspace "native:$provider:$release" --name "$session" --ssh-auth key --ssh-key "$key" --ssh-port 2299 >>"$log" 2>&1 </dev/null; then
   for attempt in {1..30}; do
     if timeout 15 ssh -i "$key" -p 2299 -o ConnectTimeout=5 -o BatchMode=yes -o HostkeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@127.0.0.1 'test "$(uname -r)" = '"'"$kernel"'"'; /bin/sh -c "exec uname -m"; printf KLAB_EXACT_SSH_PASS' >>"$log" 2>&1 </dev/null; then ssh=PASS; break; fi
     sleep 1
   done
 fi
 timeout 120 "$SELF/kernel-lab.sh" stop "$session" >>"$log" 2>&1 </dev/null || true
 root="$KLAB_ROOT/work/initramfs/session_${session}.session.root"; chmod -R u+w "$root" 2>/dev/null || true; rm -rf "$root" "$KLAB_ROOT/work/initramfs/session_${session}.session.cpio.gz" 2>/dev/null || true
 final=FAIL; [[ "$mp" == PASS && "$ssh" == PASS ]] && final=PASS
 printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$provider" "$release" "$kernel" "$arch" "$mp" "$ssh" "$final" >> "$status"
done < /home/reed/Documents/ChatGPT/Klab/library/retained-conformance-2026-10-18/status.tsv
cat "$status"
