#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp "$ROOT/klab-distro-expansion-queue.sh" "$tmp/"
cat >"$tmp/manifest.tsv" <<'M'
provider	release	arch	pattern	latest
ubuntu	20.04	x86_64	-generic$	all
M
cat >"$tmp/kernel-lab.sh" <<'S'
#!/usr/bin/env bash
set -eu
record(){ exec 8>>"$KLAB_TEST_EVENTS.lock"; flock 8; printf '%s %s %s\n' "$1" "$2" "$(date +%s%N)" >>"$KLAB_TEST_EVENTS"; flock -u 8; }
case "$1" in
 list) printf '%s\n' 5.1.0-{1,2,3,4}-generic ;;
 prepare)
  target="$2"; shift 2; arch=x86_64; out=
  while [ "$#" -gt 0 ]; do case "$1" in --arch) arch="$2"; shift 2;; -o) out="$2"; shift 2;; *) shift;; esac; done
  record START "$target/$arch"; sleep 0.4
  IFS=: read -r p r k <<EOF2
$target
EOF2
  mkdir -p "$KLAB_ROOT/targets/kernels/$p/$r/$arch/$k" "$(dirname "$out")"
  : >"$KLAB_ROOT/targets/kernels/$p/$r/$arch/$k/bundle.env"; : >"$out"
  record END "$target/$arch" ;;
 *) exit 2;;
esac
S
cat >"$tmp/klab-native-rootfs.sh" <<'S'
#!/usr/bin/env bash
set -eu
[ "$1" = capture ]; mkdir -p "$KLAB_ROOT/artifacts/userspaces/native/$2/$3/$4"; : >"$KLAB_ROOT/artifacts/userspaces/native/$2/$3/$4/rootfs.tar.zst"
S
cat >"$tmp/klab" <<'S'
#!/usr/bin/env bash
set -eu
record(){ exec 8>>"$KLAB_TEST_EVENTS.lock"; flock 8; printf '%s %s %s\n' "$1" "$2" "$(date +%s%N)" >>"$KLAB_TEST_EVENTS"; flock -u 8; }
target="$2"; shift 2; report=
while [ "$#" -gt 0 ]; do case "$1" in --report-dir) report="$2"; shift 2;; *) shift;; esac; done
record VSTART "$target"; sleep 0.15; mkdir -p "$report"; echo PASS >"$report/RESULT"; record VEND "$target"
S
chmod +x "$tmp"/kernel-lab.sh "$tmp"/klab-native-rootfs.sh "$tmp"/klab
export KLAB_ROOT="$tmp/root" KLAB_OFFLINE_ROOT="$tmp/offline" KLAB_TEST_EVENTS="$tmp/events"
mkdir -p "$KLAB_ROOT" "$KLAB_OFFLINE_ROOT" "$tmp/out/discovery"; printf '%s\n' 5.1.0-{1,2,3,4}-generic >"$tmp/out/discovery/ubuntu-20.04-x86_64.tsv"
KLAB_EXPANSION_WORKERS=2 KLAB_EXPANSION_FREE_GIB=0 "$tmp/klab-distro-expansion-queue.sh" "$tmp/manifest.tsv" "$tmp/out" >/dev/null
[ "$(awk -F '\t' 'NR>1&&$3=="PASS"{n++}END{print n+0}' "$tmp/out/status.tsv")" = 4 ]
[ "$(awk -F '\t' 'NR>1&&$3=="prepare"&&$4=="PASS"{n++}END{print n+0}' "$tmp/out/timings.tsv")" = 4 ]
[ "$(awk -F '\t' 'NR>1&&$3=="full"&&$4=="PASS"{n++}END{print n+0}' "$tmp/out/timings.tsv")" = 4 ]
# Both preparation workers must start before either finishes.
awk 'NR==1&&$1=="START"{a=1} NR==2&&$1=="START"{b=1} END{exit !(a&&b)}' "$KLAB_TEST_EVENTS"
# Validation is deliberately serialized on memory-constrained staging hosts.
awk '$1=="VSTART"{if(active)exit 1;active=1} $1=="VEND"{if(!active)exit 1;active=0} END{exit active}' "$KLAB_TEST_EVENTS"
before="$(wc -l <"$KLAB_TEST_EVENTS")"
KLAB_EXPANSION_WORKERS=2 KLAB_EXPANSION_FREE_GIB=0 "$tmp/klab-distro-expansion-queue.sh" "$tmp/manifest.tsv" "$tmp/out" >/dev/null
after="$(wc -l <"$KLAB_TEST_EVENTS")"; [ "$before" = "$after" ]
echo 'PASS: expansion queue shards preparation, serializes validation, records timings, and resumes without duplicates'
