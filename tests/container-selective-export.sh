#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
lab="$T/lab"; mkdir -p "$lab/targets/kernels/ubuntu/22.04/x86_64/k1" "$T/deps"
touch "$T/deps/a.klabbuildenv" "$T/deps/a.klabdistrotoolchain"
cat > "$lab/targets/kernels/ubuntu/22.04/x86_64/k1/bundle.env" <<EOF
BUNDLE_BUILDENV_FILE=$T/deps/a.klabbuildenv
BUNDLE_DISTRO_TOOLCHAIN_FILE=$T/deps/a.klabdistrotoolchain
EOF
cp -a "$ROOT" "$T/product"
cat > "$T/product/klab-bundle.sh" <<'EOF'
#!/bin/sh
out=
while [ "$#" -gt 0 ]; do case "$1" in -o) out=$2; shift 2;; *) shift;; esac; done
printf bundle > "$out"
EOF
chmod +x "$T/product/klab-bundle.sh"
ctx="$T/context"
KLAB_ROOT="$lab" "$T/product/klab" export container --target ubuntu:22.04:k1@x86_64 --profile build --context-only "$ctx" >/dev/null
grep -q $'ubuntu:22.04:k1@x86_64\tubuntu:22.04:k1\tx86_64' "$ctx/selection.tsv"
grep -q 'KLAB_CONTAINER_BUNDLE_PROFILE=build' "$ctx/Containerfile"
[[ -f "$ctx/transfer/ubuntu-22.04-k1-x86_64.klab" ]]
[[ -f "$ctx/transfer/a.klabbuildenv" && -f "$ctx/transfer/a.klabdistrotoolchain" ]]
[[ "$(find "$ctx/transfer" -maxdepth 1 -name '*.klab' | wc -l)" -eq 1 ]]
if KLAB_ROOT="$lab" "$T/product/klab" export container --target '../bad' --context-only "$T/bad" >/dev/null 2>&1; then echo 'unsafe selector accepted' >&2; exit 1; fi
echo 'container-selective-export: PASS'
