#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
wrapper="$ROOT/tools/qemu10-aarch64-container"
grep -Fq 'case "$1" in' "$wrapper"
grep -Fq -- '-daemonize)' "$wrapper"
grep -Fq -- '-pidfile)' "$wrapper"
grep -Fq 'docker_network=(--network none)' "$wrapper"
grep -Fq 'qemu-container-tcp-relay.c' "$wrapper"
grep -Fq 'relay_container_port' "$wrapper"
grep -Fq 'control_socket=' "$wrapper"
grep -Fq '[[ -S "$control_socket" ]]' "$wrapper"
grep -Fq 'docker run -d "${docker_remove[@]}" "${docker_network[@]}"' "$wrapper"
grep -Fq 'KLAB_QEMU_CONTAINER_KEEP' "$wrapper"
grep -Fq -- '-v /mnt/klab-store:/mnt/klab-store' "$wrapper"
grep -Fq 'qemu="$SELF_DIR/tools/qemu10-aarch64-container"' "$ROOT/kernel-lab.sh"
grep -Fq "docker inspect -f '{{.State.Pid}}'" "$wrapper"
grep -Fq 'printf '\''%s\n'\'' "$host_pid" > "$pidfile"' "$wrapper"
bash -n "$wrapper"
cc -O2 "$ROOT/tools/qemu-container-tcp-relay.c" -o /tmp/klab-relay-test-$$
rm -f /tmp/klab-relay-test-$$
echo 'PASS: containerized QEMU preserves KLab daemon and host PID semantics'
