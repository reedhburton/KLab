#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v dpkg-deb >/dev/null || { echo 'SKIP: dpkg-deb unavailable'; exit 0; }
mkdir -p "$T/pkg/DEBIAN" "$T/archives"
cat > "$T/pkg/DEBIAN/control" <<'CONTROL'
Package: klab-fixture
Version: 1.2.3-1
Architecture: amd64
Maintainer: KLab Test <test@invalid>
Description: KLab dependency closure fixture
CONTROL
dpkg-deb --build "$T/pkg" "$T/archives/klab-fixture_1.2.3-1_amd64.deb" >/dev/null
printf 'klab-fixture\t1.2.3-1\tamd64\n' > "$T/installed.tsv"
printf 'snapshot metadata\n' > "$T/InRelease"
provenance="$("$ROOT/tools/seal-dependency-closure.py" --packages "$T/archives" --installed-inventory "$T/installed.tsv" --provider debian --release 12 --repository https://snapshot.invalid/debian/12 "$T/InRelease" --output "$T/closure")"
[[ "$provenance" == "$T/closure-provenance.json" ]]
[[ -f "$provenance" && ! -e "$T/closure/dependency-provenance.json" ]]
(cd "$T/closure" && sha256sum -c PACKAGES.sha256 >/dev/null)
python3 - "$provenance" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x['provider']=='debian' and x['release']=='12'
assert x['packages'][0]['name']=='klab-fixture' and x['packages'][0]['version']=='1.2.3-1' and x['packages'][0]['arch']=='amd64'
assert x['repositories'][0]['metadata_file']=='repository-metadata/001-InRelease'
PY
printf 'missing\t9\tamd64\n' >> "$T/installed.tsv"
if "$ROOT/tools/seal-dependency-closure.py" --packages "$T/archives" --installed-inventory "$T/installed.tsv" --provider debian --release 12 --repository https://snapshot.invalid/debian/12 "$T/InRelease" --output "$T/bad" >/dev/null 2>&1; then
  echo 'FAIL: sealer accepted an incomplete archive closure' >&2; exit 1
fi

# RPM closures may be captured on an RPM guest and sealed on a host without the
# rpm command. Exercise the checksum-bound identity handoff directly.
mkdir -p "$T/rpm-archives"
printf 'synthetic rpm payload\n' > "$T/rpm-archives/klab-rpm-fixture-2.0-3.x86_64.rpm"
printf 'klab-rpm-fixture\t2.0-3\tx86_64\nklab-rpm-fixture-libs\t2.0-3\tx86_64\n' > "$T/rpm-installed.tsv"
printf 'synthetic Koji buildroot metadata\n' > "$T/koji-buildroot.json"
rpm_sha="$(sha256sum "$T/rpm-archives/klab-rpm-fixture-2.0-3.x86_64.rpm" | awk '{print $1}')"
printf 'klab-rpm-fixture-2.0-3.x86_64.rpm\t%s\tklab-rpm-fixture\t2.0-3\tx86_64\nklab-rpm-fixture-2.0-3.x86_64.rpm\t%s\tklab-rpm-fixture-libs\t2.0-3\tx86_64\n' "$rpm_sha" "$rpm_sha" > "$T/rpm-identities.tsv"
rpm_provenance="$("$ROOT/tools/seal-dependency-closure.py" --packages "$T/rpm-archives" --installed-inventory "$T/rpm-installed.tsv" --archive-identities "$T/rpm-identities.tsv" --provider fedora --release 44 --repository https://koji.invalid/buildroot "$T/koji-buildroot.json" --output "$T/rpm-closure")"
[[ "$rpm_provenance" == "$T/rpm-closure-provenance.json" ]]
(cd "$T/rpm-closure" && sha256sum -c PACKAGES.sha256 >/dev/null)
python3 - "$rpm_provenance" <<'PYRPM'
import json,sys
x=json.load(open(sys.argv[1])); rows={(p['name'],p['version'],p['arch'],p['file']) for p in x['packages']}
assert rows == {('klab-rpm-fixture','2.0-3','x86_64','klab-rpm-fixture-2.0-3.x86_64.rpm'),('klab-rpm-fixture-libs','2.0-3','x86_64','klab-rpm-fixture-2.0-3.x86_64.rpm')}
PYRPM

printf 'tampered rpm payload\n' >> "$T/rpm-archives/klab-rpm-fixture-2.0-3.x86_64.rpm"
if "$ROOT/tools/seal-dependency-closure.py" --packages "$T/rpm-archives" --installed-inventory "$T/rpm-installed.tsv" --archive-identities "$T/rpm-identities.tsv" --provider fedora --release 44 --repository https://koji.invalid/buildroot "$T/koji-buildroot.json" --output "$T/rpm-bad" >/dev/null 2>&1; then
  echo 'FAIL: sealer accepted a package that did not match the identity manifest checksum' >&2; exit 1
fi
echo 'dependency closure sealer: PASS'
