#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TARGET="${1:-upstream:v2.6.32.71}"
ARCH="${2:-x86_64}"
RUNNER="$SELF/kernel-lab.sh"
PORT=$((26000 + ($$ % 1000)))
BUS="230.77.32.1:$PORT"
TAG="$(printf '%s-%s-%s' "$TARGET" "$ARCH" "$$" | sha256sum | cut -c1-8)"
A="legacynet-a-$TAG"; B="legacynet-b-$TAG"
AIP=10.77.32.31; BIP=10.77.32.32
cleanup() {
  local n d
  for n in "$A" "$B"; do
    d="$KLAB_ROOT/work/sessions/$n"
    if [[ -f "$d/pid" ]]; then kill "$(cat "$d/pid")" 2>/dev/null || true; fi
    if [[ -f "$d/session.env" ]]; then
      unset SESSION_CONTROL_RELAY_PID
      # shellcheck disable=SC1090
      source "$d/session.env"
      [[ -z "${SESSION_CONTROL_RELAY_PID:-}" ]] || kill "$SESSION_CONTROL_RELAY_PID" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT
"$RUNNER" boot "$TARGET" --arch "$ARCH" --name "$A" --net-bus "$BUS" --net-ip "$AIP/24" --net-mac 52:54:00:26:32:31
"$RUNNER" boot "$TARGET" --arch "$ARCH" --name "$B" --net-bus "$BUS" --net-ip "$BIP/24" --net-mac 52:54:00:26:32:32
"$RUNNER" exec "$A" "uname -r; ifconfig eth0; ping -c 3 $BIP"
"$RUNNER" exec "$B" "uname -r; ifconfig eth0; ping -c 3 $AIP"
printf 'NETWORK_PASS target=%s arch=%s peers=%s,%s\n' "$TARGET" "$ARCH" "$AIP" "$BIP"
