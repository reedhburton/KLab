#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/pkgs"; printf x >"$t/pkgs/gcc.deb"; printf 'gcc\t6.3.0\tamd64\n' >"$t/inv.tsv"
printf '%s\n' '{"cc_path":"/usr/bin/gcc","cc_version":"6.3.0","cc_target":"x86_64-linux-gnu","as_path":"/usr/bin/as","as_version":"2.28","ld_path":"/usr/bin/ld","ld_version":"2.28"}' >"$t/compiler.json"
python3 - "$t/prov.json" <<'PYPROV'
import hashlib,json,sys
repo='test-repo\n'; keys='test-key\n'; meta=[]
h=lambda s:hashlib.sha256(s.encode()).hexdigest()
json.dump({'schema':'klab-repository-provenance-v1','provider':'ubuntu','release':'17.04','repository_config':repo,'repository_config_sha256':h(repo),'key_inventory':keys,'key_inventory_sha256':h(keys),'repository_metadata':meta,'repository_metadata_sha256':h(json.dumps(meta,separators=(',',':')))},open(sys.argv[1],'w'))
PYPROV
"$ROOT/klab-distro-toolchain.sh" create --packages "$t/pkgs" --inventory "$t/inv.tsv" --compiler-json "$t/compiler.json" --provenance "$t/prov.json" --provider ubuntu --release 17.04 --arch x86_64 -o "$t/t.klabdistrotoolchain" >/dev/null
[[ "$(tar --zstd -xOf "$t/t.klabdistrotoolchain" FORMAT_VERSION)" == 3 ]]
"$ROOT/klab-distro-toolchain.sh" match-compiler "$t/t.klabdistrotoolchain" --version 6.3.0 --mode exact >/dev/null
if "$ROOT/klab-distro-toolchain.sh" match-compiler "$t/t.klabdistrotoolchain" --version 6.4.0 --mode exact >/dev/null 2>&1; then echo 'FAIL: compiler mismatch accepted' >&2; exit 1; fi
if "$ROOT/klab-distro-toolchain.sh" match-compiler "$t/t.klabdistrotoolchain" --version 6.3.1 --mode compatible >/dev/null 2>&1; then :; else echo 'FAIL: explicit compatible compiler policy rejected same major.minor' >&2; exit 1; fi
"$ROOT/klab-distro-toolchain.sh" match-compiler "$t/t.klabdistrotoolchain" --version 6.4.0 --mode major-compatible >/dev/null
if "$ROOT/klab-distro-toolchain.sh" match-compiler "$t/t.klabdistrotoolchain" --version 7.0.0 --mode major-compatible >/dev/null 2>&1; then echo 'FAIL: major-compatible accepted a different GCC major' >&2; exit 1; fi
echo 'PASS: provenance is identity-bound and compiler exact/compatible policies are explicit'
