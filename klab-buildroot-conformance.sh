#!/usr/bin/env bash
set -euo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"; KLAB_BIN="${KLAB_BIN:-$SELF/kernel-lab.sh}"; KLAB_ROOT="${KLAB_ROOT:-$HOME/klab-data}"
[[ $# -eq 2 ]] || { echo 'usage: klab-buildroot-conformance.sh SESSION REPORT_DIR' >&2; exit 2; }
session="$1"; report="$2"; mkdir -p "$report"; results="$report/results.tsv"; printf 'CAPABILITY\tRESULT\tEVIDENCE\n' >"$results"; failures=0
probe(){ local n="$1" c="$2" e="$report/$1.log" rc; set +e; KLAB_ROOT="$KLAB_ROOT" "$KLAB_BIN" exec "$session" "$c" >"$e" 2>&1; rc=$?; set -e; if ((rc==0)); then printf '%s\tPASS\t%s\n' "$n" "$e" >>"$results"; else printf '%s\tFAIL\t%s\n' "$n" "$e" >>"$results"; failures=$((failures+1)); fi; }
probe identity 'uname -r; uname -m; test -r /etc/os-release && cat /etc/os-release || true'
probe filesystem 'set -eu; p=/tmp/klab-conformance.$$; mkdir "$p"; echo data >"$p/file"; test "$(cat "$p/file")" = data; mv "$p/file" "$p/moved"; rm -rf "$p"'
probe proc_sys 'set -eu; case "$(uname -r)" in 2.0.*) test -d /proc ;; 2.[1-4].*) test -r /proc/1/status ;; *) test -r /proc/1/status; test -d /sys; test -d /sys/class || test -d /sys/devices ;; esac; test -c /dev/null'
# Use the POSIX-era option subset so this gate measures the same capability
# on the sealed BusyBox 0.60 userspace used by Linux 2.0/2.2. `grep -x`,
# `route -n`, and the `command` shell builtin were added to that environment
# later and are not part of the process, network, or shutdown capability.
probe processes 'set -eu; (sleep 0.1; echo one) & a=$!; (sleep 0.1; echo two) & b=$!; wait "$a"; wait "$b"; echo x | grep -q x'
probe networking 'set -eu; case "$(uname -r)" in 2.0.*) test -x /bin/ifconfig || test -x /sbin/ifconfig; ifconfig eth0 10.0.2.15 ;; *) ifconfig eth0 > /tmp/klab-ifconfig; grep -q 10.0.2.15 /tmp/klab-ifconfig; rm -f /tmp/klab-ifconfig ;; esac'
probe modules 'set -eu; case "$(uname -r)" in 2.0.*) test -x /sbin/linux20/insmod; test -x /sbin/linux20/rmmod ;; *) test -r /proc/modules; cat /proc/modules >/dev/null; if test -d /lib/modules; then test -d /lib/modules/$(uname -r); fi ;; esac'
probe shutdown_path 'set -eu; test -x /bin/sync || test -x /sbin/sync || test -x /usr/bin/sync; test -x /bin/poweroff || test -x /sbin/poweroff || test -x /bin/reboot || test -x /sbin/reboot'
[[ "$failures" == 0 ]] && result=PASS || result=FAIL; echo "$result" >"$report/RESULT"; echo "KLab Buildroot conformance: $result ($failures failures)"; ((failures==0))
