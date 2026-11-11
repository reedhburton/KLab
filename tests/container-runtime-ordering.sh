#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAKE="$T/fake-docker"
LOG="$T/args"
cat >"$FAKE" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$KLAB_FAKE_LOG"
EOS
chmod +x "$FAKE"
# Source only the launcher slice; provide the tiny dependencies it needs.
have(){ command -v "$1" >/dev/null 2>&1; }
die(){ echo "TEST-DIE: $*" >&2; exit 99; }
CONTAINER_RUNTIME="$FAKE"
export KLAB_FAKE_LOG="$LOG"
eval "$(sed -n '/^container_runtime() {/,/^validate_token() {/p' "$ROOT/kernel-lab.sh" | sed '$d')"
run_container_root ubuntu:17.04 -v /host:/out bash -lc 'command -v apt-get'
mapfile -t a <"$LOG"
[[ "${a[0]}" == run && "${a[1]}" == --rm ]]
[[ "${a[2]}" == -v && "${a[3]}" == /host:/out ]]
[[ "${a[4]}" == ubuntu:17.04 ]]
[[ "${a[5]}" == bash && "${a[6]}" == -lc && "${a[7]}" == 'command -v apt-get' ]]
run_container_user ubuntu:17.04 -v /host:/out sh -c true
mapfile -t a <"$LOG"
[[ "${a[0]}" == run && "${a[1]}" == --rm && "${a[2]}" == --user ]]
# Locate image and prove command follows it.
pos=-1
for i in "${!a[@]}"; do [[ "${a[$i]}" == ubuntu:17.04 ]] && pos=$i; done
(( pos >= 0 ))
[[ "${a[$((pos+1))]}" == sh ]]
echo 'PASS: container runtime argument ordering'
