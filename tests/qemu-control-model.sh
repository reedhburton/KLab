#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# Source the full CLI without dispatch by stopping before main is not trivial;
# exercise the model-visible contract and static command wiring instead.
for a in aarch64 armv7; do
  out="$($ROOT/kernel-lab.sh arch-plan "$a" --kernel v6.6 --json)"
  python3 - "$out" "$a" <<'PY'
import json,sys
m=json.loads(sys.argv[1]); a=sys.argv[2]
e=m['execution']
assert e['control_mode']=='virtio-serial', (a,e)
assert e['control_device']=='/dev/vport0p1', (a,e)
PY
  grep -q 'VIRTIO_CONSOLE' "$ROOT/architectures/$a.conf" || { echo "FAIL: $a lacks VIRTIO_CONSOLE" >&2; exit 1; }
done
arm_disable="$($ROOT/kernel-lab.sh arch-plan armv7 --kernel v6.6 --json >/dev/null; sed -n "s/^KERNEL_CONFIG_DISABLE=//p" "$ROOT/architectures/armv7.conf")"
[[ "$arm_disable" == *GCC_PLUGINS* && "$arm_disable" == *STACKPROTECTOR_PER_TASK* ]] || { echo 'FAIL: ARMv7 portable cross-build must disable host GCC plugins' >&2; exit 1; }
for a in x86_64 i386; do
  out="$($ROOT/kernel-lab.sh arch-plan "$a" --kernel v6.6 --json)"
  python3 - "$out" "$a" <<'PY'
import json,sys
m=json.loads(sys.argv[1]); a=sys.argv[2]
e=m['execution']
assert e['control_mode']=='serial', (a,e)
assert e['control_device'] in ('/dev/ttyS1',), (a,e)
PY
done
grep -q 'virtserialport,chardev=klabctl,name=org.klab.control' "$ROOT/kernel-lab.sh" || { echo 'FAIL: virtio serial QEMU args missing' >&2; exit 1; }
grep -q 'mapfile -t control < <(qemu_control_args' "$ROOT/kernel-lab.sh" || { echo 'FAIL: session boot does not consume control args' >&2; exit 1; }
grep -q '^session_rpc_boot_ready()' "$ROOT/kernel-lab.sh" || { echo 'FAIL: boot readiness handshake helper missing' >&2; exit 1; }
grep -Fq 'relay_pid="$(start_serial_relay "$sock" "$proxy" "$dir/control-relay.log")"' "$ROOT/kernel-lab.sh" || { echo "FAIL: Linux sessions do not preserve the QEMU control connection" >&2; exit 1; }
grep -Fq 'session_rpc_boot_ready "$proxy" "$BOOT_TIMEOUT"' "$ROOT/kernel-lab.sh" || { echo "FAIL: Linux boot readiness bypasses the persistent relay" >&2; exit 1; }
grep -Fq '/bin/busybox mknod @KLAB_CONTROL_TTY@ c 4 65' "$ROOT/kernel-lab.sh" || { echo "FAIL: pre-devtmpfs x86 serial fallback is missing" >&2; exit 1; }
[[ $(grep -Fc '( "$target" == upstream:v2.* || "$target" == upstream:v3.[0-9] || "$target" == upstream:v3.1[01] ) && ( "$ARCH" == x86_64 || "$ARCH" == i386 )' "$ROOT/kernel-lab.sh") -eq 2 ]] || { echo "FAIL: Linux 2.x conservative QEMU profile is not applied to both launch paths" >&2; exit 1; }
[[ $(grep -c 'if ! IFS= read -r line <&3; then' "$ROOT/kernel-lab.sh") -ge 2 ]] || { echo 'FAIL: Linux and FreeBSD guest control loops must recover from disconnects' >&2; exit 1; }
[[ $(grep -Fo 'session_rpc_boot_ready "$proxy" "$BOOT_TIMEOUT"' "$ROOT/kernel-lab.sh" | wc -l) -ge 2 ]]
grep -Fq 'session_rpc_boot_ready "$proxy" "$freebsd_boot_timeout"' "$ROOT/kernel-lab.sh" || { echo 'FAIL: FreeBSD boot bypasses the persistent-relay READY handshake' >&2; exit 1; }
grep -Fq '&& ! session_rpc_boot_ready "$proxy" "$BOOT_TIMEOUT"' "$ROOT/kernel-lab.sh" || { echo 'FAIL: Linux boot readiness has no transient relay retry' >&2; exit 1; } || { echo 'FAIL: Linux and FreeBSD boots must use the persistent-relay READY handshake' >&2; exit 1; }
grep -q 'session_seed,media=cdrom' "$ROOT/kernel-lab.sh" || { echo 'FAIL: FreeBSD NoCloud seed must be attached as CD-ROM media' >&2; exit 1; }
grep -q 'BUNDLE_SOURCE_ISO,media=cdrom' "$ROOT/kernel-lab.sh" || { echo 'FAIL: FreeBSD source ISO must be attached as CD-ROM media' >&2; exit 1; }
grep -q 'mkisofs -quiet -R -V' "$ROOT/kernel-lab.sh" || { echo 'FAIL: FreeBSD ISO generation must preserve Unix filenames' >&2; exit 1; }
grep -Fq "os.environ.get('KLAB_SERIAL_UPLOAD_CHUNK', '96')" "$ROOT/kernel-lab.sh" || { echo "FAIL: broad-matrix-safe 96-byte serial upload default missing" >&2; exit 1; }
grep -Fq "chunk_size = 96" "$ROOT/kernel-lab.sh" || { echo "FAIL: acknowledged non-serial upload chunk sizing missing" >&2; exit 1; }
grep -Fq '[[ "${SESSION_CONTROL_MODE:-}" == serial ]] && flow=serial' "$ROOT/kernel-lab.sh" || { echo "FAIL: session uploads ignore the recorded serial control mode" >&2; exit 1; }
grep -Fq 'session_rpc_put "$SESSION_CONTROL" "$local_file" "$remote" "$mode" "$flow"' "$ROOT/kernel-lab.sh" || { echo "FAIL: session upload flow is not passed to the PUT transport" >&2; exit 1; }
grep -Fq 'session_rpc_put_exec "$SESSION_CONTROL"' "$ROOT/kernel-lab.sh" || { echo "FAIL: FreeBSD uploads do not use EXEC transport" >&2; exit 1; }
grep -Fq '[[ "${SESSION_BACKEND:-linux}" == freebsd ]]' "$ROOT/kernel-lab.sh" || { echo "FAIL: public push does not select the FreeBSD transfer backend" >&2; exit 1; }
python3 -c 'import sys; s=open(sys.argv[1]).read(); r=s[s.index("session_rpc_exec() {"):s.index("session_rpc_boot_ready() {")]; assert "f.close()\ns.close()" in r' "$ROOT/kernel-lab.sh" || { echo "FAIL: exec RPC leaves its relay stream open" >&2; exit 1; }
python3 -c 'import sys; s=open(sys.argv[1]).read(); r=s[s.index("session_rpc_boot_ready() {"):s.index("session_rpc_put() {")]; assert "f.close()\n        s.close()" in r' "$ROOT/kernel-lab.sh" || { echo "FAIL: boot readiness leaves its relay stream open" >&2; exit 1; }
python3 -c 'import sys; s=open(sys.argv[1]).read(); r=s[s.index("start_serial_relay() {"):s.index("\nPYRELAY\n",s.index("start_serial_relay() {"))]; assert r.index("if client is not None and client in ready:") < r.index("if up in ready:"); assert "select.select(reads, [], [], 0.1)" in r' "$ROOT/kernel-lab.sh" || { echo "FAIL: relay can forward a response to a simultaneously disconnected client" >&2; exit 1; }
grep -Fq "start_serial_relay" "$ROOT/kernel-lab.sh" || { echo "FAIL: FreeBSD upload synchronization relay missing" >&2; exit 1; }
grep -Fq "Starting FreeBSD source extraction" "$ROOT/kernel-lab.sh" || { echo "FAIL: FreeBSD source extraction is not observable" >&2; exit 1; }
grep -Fq "/usr/sbin/daemon -f -o /tmp/klab-source.log" "$ROOT/kernel-lab.sh" || { echo "FAIL: FreeBSD extraction is not detached with daemon" >&2; exit 1; }
grep -Fq "start_serial_relay" "$ROOT/kernel-lab.sh" || { echo "FAIL: FreeBSD persistent serial relay missing" >&2; exit 1; }
grep -q 'if ! IFS= read -r line <&3; then' "$ROOT/kernel-lab.sh" || { echo 'FAIL: guest control loop does not recover from disconnects' >&2; exit 1; }
grep -q 'parent="${path%/\*}"' "$ROOT/kernel-lab.sh" || { echo 'FAIL: guest upload directory creation depends on dirname' >&2; exit 1; }
! grep -q "dmesg | tail" "$ROOT/lib/arch-e2e.sh" || { echo 'FAIL: architecture smoke depends on absent minimal-guest tail command' >&2; exit 1; }
out="$($ROOT/lib/multiguest_plan.py processes $ROOT/examples/multiguest/mixed-matrix-r16/x86-arm64-i386.json)"
[[ "$out" == *$'\t__KLAB_EMPTY__\t'* ]] || { echo 'FAIL: empty process fields are not framed explicitly' >&2; exit 1; }
[[ "$out" == *$'\t__KLAB_EMPTY__\t120000\tskip'* ]] || { echo 'FAIL: empty ready marker shifts process columns' >&2; exit 1; }
while IFS=$'	' read -r gid pid cmd64 timeout expected exsig gate gtimeout ready64 rtimeout ondep; do
  [[ "$gate" == __KLAB_EMPTY__ && -n "$ready64" && "$rtimeout" == 120000 && "$ondep" == skip ]] || { echo 'FAIL: empty process fields shift planner columns' >&2; exit 1; }
done <<<"$out"
grep -Fq 'local rpc_timeout=$(( (tm + 999) / 1000 + 30 ))' "$ROOT/lib/multiguest-scenario.sh" || { echo 'FAIL: process wait RPC does not cover the guest timeout' >&2; exit 1; }
grep -Fq 'for d in /sys/class/net/*' "$ROOT/kernel-lab.sh" || { echo 'FAIL: guest NIC configuration does not resolve interfaces by MAC' >&2; exit 1; }
grep -Fq '"${net_macs[$i]}"' "$ROOT/kernel-lab.sh" || { echo 'FAIL: session boot does not pass NIC MAC identity to guest configuration' >&2; exit 1; }
grep -Fq 'except (BrokenPipeError, ConnectionResetError):' "$ROOT/kernel-lab.sh" || { echo 'FAIL: relay does not preserve guest data after a client disconnect' >&2; exit 1; }
grep -Fq 'nohup python3 - "$upstream" "$proxy"' "$ROOT/kernel-lab.sh" || { echo 'FAIL: relay is not detached from the boot subshell' >&2; exit 1; }
grep -Fq 'up = connect_upstream()' "$ROOT/kernel-lab.sh" || { echo 'FAIL: relay does not reconnect after QEMU chardev EOF' >&2; exit 1; }
grep -Fq 'if os.fork() != 0:' "$ROOT/kernel-lab.sh" || { echo 'FAIL: relay does not daemonize independently of the caller' >&2; exit 1; }
grep -Fq 'with open(pidfile, "w")' "$ROOT/kernel-lab.sh" || { echo 'FAIL: daemon relay PID is not recorded for cleanup' >&2; exit 1; }
echo 'PASS: architecture-specific QEMU control transport model'

grep -Fq 'Retry the' "$ROOT/kernel-lab.sh"
grep -Fq 'POSIX read has no timeout option' "$ROOT/kernel-lab.sh"
grep -Fq "heartbeat makes readiness observable" "$ROOT/kernel-lab.sh"
grep -Fq 'f.write(f"PING {ready_tok}' "$ROOT/kernel-lab.sh"

grep -Fq "parts[0] == \"PONG\"" "$ROOT/kernel-lab.sh" 2>/dev/null || grep -Fq "parts[0] == 'PONG'" "$ROOT/kernel-lab.sh" || { echo 'FAIL: readiness does not require matching PONG' >&2; exit 1; }
! grep -Fq "parts[0] == 'READY' or" "$ROOT/kernel-lab.sh" || { echo 'FAIL: stale READY can bypass round-trip readiness' >&2; exit 1; }

grep -Fq "if parts[0] == 'READY':" "$ROOT/kernel-lab.sh"
grep -Fq 'f.write(f"PING {ready_tok}\n".encode())' "$ROOT/kernel-lab.sh"
grep -Fq 'stty -opost -echo clocal cread <@KLAB_CONTROL_TTY@' "$ROOT/kernel-lab.sh"

# Historical tty drivers retain output post-processing and emit CRLF.
test "$(grep -F -c "rstrip('\\r\\n')" "$ROOT/kernel-lab.sh")" -eq 6

grep -Fq 'command_text="$(printf '"'"'%s'"'"' "$encoded" | base64 -d 2>/dev/null)"' "$ROOT/kernel-lab.sh"

grep -Fq '( eval "$command_text" ) >"$outfile"' "$ROOT/kernel-lab.sh"
