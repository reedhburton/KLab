#!/usr/bin/env bash
set -Eeuo pipefail
unset KLAB_HOME
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null || true; rm -rf "$T"' EXIT
mkdir -p "$T/root/usr/src/linux-test/scripts" "$T/deps/repository-metadata"
printf 'all:\n\t@:\n' > "$T/root/usr/src/linux-test/Makefile"
printf '# synthetic\n' > "$T/root/usr/src/linux-test/scripts/Makefile.build"
printf 'target archive inventory\n' > "$T/target-packages.txt"
printf 'base-files\t1\tx86_64\nmake\t4.4\tx86_64\n' > "$T/installed.tsv"
printf 'deb-one\n' > "$T/deps/base-files_1_x86_64.deb"
printf 'deb-two\n' > "$T/deps/make_4.4_x86_64.deb"
printf 'snapshot metadata\n' > "$T/deps/repository-metadata/release.json"
(cd "$T/deps" && sha256sum *.deb > PACKAGES.sha256)
python3 - "$T/deps" "$T/provenance.json" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); rows=[]
for p in sorted(root.glob('*.deb')):
    name,version,arch=p.stem.split('_',2)
    rows.append({'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'name':name,'version':version,'arch':arch})
meta=root/'repository-metadata/release.json'
json.dump({'schema':'klab-buildenv-dependency-provenance-v1','provider':'test','release':'1','repositories':[{'url':'https://snapshot.invalid/test/1','metadata_file':'repository-metadata/release.json','metadata_sha256':hashlib.sha256(meta.read_bytes()).hexdigest()}],'packages':rows},open(sys.argv[2],'w'),sort_keys=True)
PY
common=(--root "$T/root" --provider test --release 1 --kernel-release test-kernel --target-arch x86_64 --exec-arch x86_64 --provider-image "sha256:$(printf '1%.0s' {1..64})" --build-dir usr/src/linux-test --package-manifest "$T/target-packages.txt" --installed-inventory "$T/installed.tsv")
out="$T/v4.klabbuildenv"
"$ROOT/klab-buildenv.sh" create "${common[@]}" --dependency-archives "$T/deps" --dependency-provenance "$T/provenance.json" -o "$out" >/dev/null
id="$("$ROOT/klab-buildenv.sh" verify "$out" --deep)"
"$ROOT/klab-buildenv.sh" inspect "$out" | python3 -c 'import json,sys; m=json.load(sys.stdin); assert m["format_version"]==4; assert m["dependency_archive_tree_sha256"]'
KLAB_ROOT="$T/home" "$ROOT/klab-buildenv.sh" import "$out" >/dev/null
KLAB_ROOT="$T/home" "$ROOT/klab-buildenv.sh" verify-installed "$id" >/dev/null
installed="$T/home/artifacts/buildenvs/sha256/$id"
cp "$installed/dependency-archives/make_4.4_x86_64.deb" "$T/original.deb"
printf tamper >> "$installed/dependency-archives/make_4.4_x86_64.deb"
if KLAB_ROOT="$T/home" "$ROOT/klab-buildenv.sh" verify-installed "$id" >/dev/null 2>&1; then
  echo 'FAIL: installed dependency archive tamper accepted' >&2; exit 1
fi
cp "$T/original.deb" "$installed/dependency-archives/make_4.4_x86_64.deb"
printf tamper >> "$installed/dependency-archives/repository-metadata/release.json"
if KLAB_ROOT="$T/home" "$ROOT/klab-buildenv.sh" verify-installed "$id" >/dev/null 2>&1; then
  echo 'FAIL: installed repository metadata tamper accepted' >&2; exit 1
fi
python3 - "$T/provenance.json" <<'PY'
import json,sys
p=sys.argv[1]; x=json.load(open(p)); x['release']='2'; json.dump(x,open(p,'w'))
PY
if "$ROOT/klab-buildenv.sh" create "${common[@]}" --dependency-archives "$T/deps" --dependency-provenance "$T/provenance.json" -o "$T/bad.klabbuildenv" >/dev/null 2>&1; then
  echo 'FAIL: mismatched dependency provenance accepted' >&2; exit 1
fi
# Restore valid provenance, then prove a closure missing one installed package is rejected.
python3 - "$T/provenance.json" <<'PY2'
import json,sys
p=sys.argv[1]; x=json.load(open(p)); x['release']='1'; json.dump(x,open(p,'w'))
PY2
printf 'extra\t9\tx86_64\n' >> "$T/installed.tsv"
if "$ROOT/klab-buildenv.sh" create "${common[@]}" --dependency-archives "$T/deps" --dependency-provenance "$T/provenance.json" -o "$T/incomplete.klabbuildenv" >/dev/null 2>&1; then
  echo 'FAIL: dependency closure missing an installed package accepted' >&2; exit 1
fi
sed -i '$d' "$T/installed.tsv"
"$ROOT/klab-buildenv.sh" create "${common[@]}" -o "$T/v3.klabbuildenv" >/dev/null
"$ROOT/klab-buildenv.sh" inspect "$T/v3.klabbuildenv" | python3 -c 'import json,sys; assert json.load(sys.stdin)["format_version"]==3'
echo 'buildenv dependency closure: PASS'
