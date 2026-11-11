#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/out" "$T/repo" "$T/cache"
printf '[fedora]\ngpgcheck=1\n' > "$T/repo/fedora.repo"
cat > "$T/bin/rpm" <<'SH'
#!/bin/sh
case "$1" in
  -qa) printf 'base\t0:1-2\tx86_64\ngpg-pubkey\t0:dead-beef\tnoarch\n';;
  -qp) printf 'base\t0:1-2\tx86_64';;
  -K) echo 'digests OK';;
  -Kv) if [ "${KLAB_TEST_NOKEY:-0}" = 1 ]; then echo 'NOKEY'; else echo 'digests signatures OK'; fi;;
  *) exit 1;;
esac
SH
cat > "$T/bin/dnf" <<'SH'
#!/bin/sh
for arg do spec=$arg; done
[ "$spec" = 'base-1-2.x86_64' ] || exit 1
printf rpm > "${KLAB_DEPENDENCY_CAPTURE_OUT}/packages/base-1-2.x86_64.rpm"
SH
cat > "$T/bin/yumdownloader" <<'SH'
#!/bin/sh
for arg do spec=$arg; done
[ "$spec" = 'base-1-2.x86_64' ] || exit 1
printf rpm > "${KLAB_DEPENDENCY_CAPTURE_OUT}/packages/base-1-2.x86_64.rpm"
SH
cat > "$T/bin/tar" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do [ "$1" = -cf ] && { : > "$2"; exit 0; }; shift; done
exit 1
SH
chmod +x "$T/bin"/*
die(){ echo "$*" >&2; exit 1; }
# shellcheck source=lib/backends/rpm.sh
source "$ROOT/lib/backends/rpm.sh"
grep -Fq 'rpm -q coreutils-single' "$ROOT/lib/backends/rpm.sh" || die 'minimal RPM coreutils conflict handling is missing'
grep -Fq "grep -v '^gpg-pubkey[[:space:]]'" "$ROOT/lib/buildenv-capture.sh" || die 'generic RPM inventory does not safely exclude key pseudo-packages'
grep -Fq 'requested_sha=$(sha256sum' "$ROOT/lib/backends/rpm.sh" || die 'RPM closure comparison still depends on optional cmp'
script="$(klab_backend_dnf_dependency_capture_script)"
env_common=(PATH="$T/bin:$PATH" KLAB_DEPENDENCY_CAPTURE_OUT="$T/out" KLAB_RPM_REPOSITORY_CONFIG_DIR="$T/repo" KLAB_RPM_DNF_CONFIG_DIR="$T/missing" KLAB_RPM_DNF_CACHE_DIR="$T/cache" KLAB_RPM_YUM_CACHE_DIR="$T/missing")
env "${env_common[@]}" sh -c "$script"
printf 'base\t0:1-2\tx86_64\n' | cmp -s - "$T/out/requested.tsv"
cmp -s "$T/out/requested.tsv" "$T/out/archives.tsv"
[[ -f "$T/out/packages/base-1-2.x86_64.rpm" && -f "$T/out/repository-state.tar" ]]
rm -rf "$T/bad"; mkdir -p "$T/bad"
if env "${env_common[@]}" KLAB_DEPENDENCY_CAPTURE_OUT="$T/bad" KLAB_TEST_NOKEY=1 sh -c "$script" >/dev/null 2>&1; then
  die 'RPM dependency closure accepted an untrusted signature'
fi
printf '[bad]\ngpgcheck=0\n' > "$T/repo/bad.repo"
rm -rf "$T/insecure"; mkdir -p "$T/insecure"
if env "${env_common[@]}" KLAB_DEPENDENCY_CAPTURE_OUT="$T/insecure" sh -c "$script" >/dev/null 2>&1; then
  die 'RPM dependency closure accepted gpgcheck=0'
fi
printf 'koji-buildroot-proof\n' > "$T/koji.json"
rm -rf "$T/koji"; mkdir -p "$T/koji"
env "${env_common[@]}" KLAB_DEPENDENCY_CAPTURE_OUT="$T/koji" KLAB_RPM_TRUST_MODE=koji KLAB_RPM_KOJI_METADATA_FILE="$T/koji.json" KLAB_TEST_NOKEY=1 sh -c "$script"
cmp -s "$T/koji/requested.tsv" "$T/koji/archives.tsv" || die 'Koji closure identity mismatch'
rm -rf "$T/koji-missing"; mkdir -p "$T/koji-missing"
if env "${env_common[@]}" KLAB_DEPENDENCY_CAPTURE_OUT="$T/koji-missing" KLAB_RPM_TRUST_MODE=koji KLAB_RPM_KOJI_METADATA_FILE="$T/missing.json" sh -c "$script" >/dev/null 2>&1; then
  die 'Koji closure accepted missing buildroot metadata'
fi
klab_buildenv_capture_container(){
  [[ "${KLAB_BUILDENV_DEPENDENCY_REPOSITORY_URL:-}" == rpm://fedora/44 ]] || die 'DNF buildenv did not bind repository provenance URL'
  [[ "${KLAB_BUILDENV_DEPENDENCY_CAPTURE_COMMAND:-}" == *'rpm -Kv'* ]] || die 'DNF buildenv did not bind signed closure capture'
  [[ "$8" == *dnf-plugins-core* ]] || die 'DNF download plugin is not installed before inventory capture'
}
klab_backend_dnf_capture_buildenv fedora 44 6.0.0-1.fc44.x86_64 /bundle fedora:44 : /tmp/out x86_64
klab_buildenv_capture_container(){
  [[ "${KLAB_BUILDENV_DEPENDENCY_REPOSITORY_URL:-}" == rpm://centos/7 ]] || die 'YUM buildenv did not bind repository provenance URL'
  [[ "${KLAB_BUILDENV_DEPENDENCY_CAPTURE_COMMAND:-}" == *'KLAB_RPM_DEPENDENCY_DOWNLOADER=yumdownloader'* ]] || die 'YUM buildenv did not bind exact signed closure capture'
  [[ "$8" == *yum-utils* ]] || die 'YUM downloader is not installed before inventory capture'
}
rm -f "$T/repo/bad.repo"
klab_backend_yum_capture_buildenv centos 7 3.10.0-1160.119.1.el7.x86_64 /bundle centos:7 : /tmp/out x86_64
rm -rf "$T/yum"; mkdir -p "$T/yum"
env "${env_common[@]}" KLAB_DEPENDENCY_CAPTURE_OUT="$T/yum" KLAB_RPM_DEPENDENCY_DOWNLOADER=yumdownloader sh -c "$script"
cmp -s "$T/yum/requested.tsv" "$T/yum/archives.tsv" || die 'YUM closure identity mismatch'
echo 'RPM buildenv dependency closure: PASS'
