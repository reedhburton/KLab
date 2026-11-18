#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq '"$SELF/klab" validate' "$ROOT/klab-validation-matrix.sh"
grep -Fq '&&$5=="PASS"' "$ROOT/klab-validation-matrix.sh"
grep -Fq 'rm -rf "$root"' "$ROOT/klab-image-validate.sh"


tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp "$ROOT/klab-validation-matrix.sh" "$tmp/klab-validation-matrix.sh"
cat >"$tmp/klab" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
report=
while (($#)); do
  if [[ "$1" == --report-dir ]]; then report="$2"; shift 2; else shift; fi
done
mkdir -p "$report"; printf 'PASS\n' >"$report/RESULT"
EOF
chmod +x "$tmp/klab" "$tmp/klab-validation-matrix.sh"
write_distro(){
  local provider="$1" release="$2" arch="$3" kernel="$4" dir
  dir="$tmp/root/targets/kernels/$provider/$release/$arch/$kernel"
  mkdir -p "$dir"
  printf 'BUNDLE_PROVIDER=%q\nBUNDLE_DISTRO_RELEASE=%q\nBUNDLE_KERNEL_RELEASE=%q\nBUNDLE_ARCH=%q\nBUNDLE_DIR=%q\n' "$provider" "$release" "$kernel" "$arch" "$dir" > "$dir/bundle.env"
}
write_distro one 1 x86_64 1.0
write_distro two 2 x86_64 2.0
up="$tmp/root/targets/kernels/upstream/6.6/x86_64/normal"; mkdir -p "$up"
printf 'BUNDLE_PROVIDER=upstream\nBUNDLE_UPSTREAM_VERSION=v6.6\nBUNDLE_PROFILE=normal\nBUNDLE_ARCH=x86_64\nBUNDLE_DIR=%q\n' "$up" > "$up/bundle.env"
# A recovery snapshot may contain valid metadata, but BUNDLE_DIR points at the
# canonical target and therefore must not create a fourth matrix row.
backup="$tmp/root/targets/kernels/one.backup/1/x86_64/1.0"; mkdir -p "$backup"; cp "$tmp/root/targets/kernels/one/1/x86_64/1.0/bundle.env" "$backup/bundle.env"
KLAB_ROOT="$tmp/root" "$tmp/klab-validation-matrix.sh" "$tmp/out" full </dev/null >/dev/null
[[ "$(awk -F '\t' 'NR>1&&$5=="PASS"{n++}END{print n+0}' "$tmp/out/status.tsv")" == 3 ]]
grep -Fq $'upstream:v6.6\tlinux\tx86_64\tfull\tPASS' "$tmp/out/status.tsv"
! grep -Fq 'one.backup' "$tmp/out/status.tsv"
echo 'resumable canonical-metadata validation matrix: PASS'
