#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/out"
cat > "$T/bin/apt-config" <<'SH'
#!/bin/sh
[ "${KLAB_TEST_INSECURE:-0}" = 1 ] && echo 'APT::Get::AllowUnauthenticated "true";'
SH
cat > "$T/bin/dpkg-query" <<'SH'
#!/bin/sh
printf 'base\t1\tamd64\nmake\t2\tall\n'
SH
cat > "$T/bin/apt-get" <<'SH'
#!/bin/sh
mode=install
for arg do [ "$arg" = download ] && mode=download; spec=$arg; done
printf '%s:%s\n' "$mode" "$spec" >> "${KLAB_DEPENDENCY_CAPTURE_OUT}/apt-calls.log"
case "$spec:$mode" in
  base:amd64=1:install) exit 0;;
  base:amd64=1:download) printf base > "${KLAB_DEPENDENCY_CAPTURE_OUT}/packages/base_1_amd64.deb";;
  make=2:install) printf make > "${KLAB_DEPENDENCY_CAPTURE_OUT}/packages/make_2_all.deb";;
  *) exit 1;;
esac
SH
cat > "$T/bin/dpkg-deb" <<'SH'
#!/bin/sh
file=$2; field=$3
case "$(basename "$file"):$field" in
  base_1_amd64.deb:Package) echo base;; base_1_amd64.deb:Version) echo 1;; base_1_amd64.deb:Architecture) echo amd64;;
  make_2_all.deb:Package) echo make;; make_2_all.deb:Version) echo 2;; make_2_all.deb:Architecture) echo all;;
  *) exit 1;;
esac
SH
cat > "$T/bin/tar" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do [ "$1" = -cf ] && { : > "$2"; exit 0; }; shift; done
exit 1
SH
chmod +x "$T/bin"/*
die(){ echo "$*" >&2; exit 1; }
# shellcheck source=lib/backends/apt.sh
source "$ROOT/lib/backends/apt.sh"
script="$(klab_backend_apt_dependency_capture_script)"
PATH="$T/bin:$PATH" KLAB_DEPENDENCY_CAPTURE_OUT="$T/out" sh -c "$script"
cmp -s "$T/out/requested.tsv" "$T/out/archives.tsv"
[[ -f "$T/out/packages/base_1_amd64.deb" && -f "$T/out/packages/make_2_all.deb" && -f "$T/out/repository-state.tar" ]]
grep -Fxq 'download:base:amd64=1' "$T/out/apt-calls.log" || die 'successful cache-less reinstall did not trigger direct exact download fallback'
if PATH="$T/bin:$PATH" KLAB_DEPENDENCY_CAPTURE_OUT="$T/bad" KLAB_TEST_INSECURE=1 sh -c "$script" >/dev/null 2>&1; then
  echo 'FAIL: APT dependency closure allowed unauthenticated repositories' >&2; exit 1
fi
klab_buildenv_capture_container(){
  local install_script="$8"
  [[ "${KLAB_BUILDENV_NATIVE_CC:-}" == /usr/local/bin/klab-native-cc ]] || die 'APT buildenv did not bind the resolved compiler launcher'
  grep -Fq 'command -v "$candidate"' <<<"$install_script" || die 'APT buildenv does not validate the installed compiler executable'
  grep -Fq 'ln -sf "$resolved_cc" /usr/local/bin/klab-native-cc' <<<"$install_script" || die 'APT buildenv does not create the resolved compiler launcher'
}
KLAB_BUILDENV_REQUIRED_GCC_VERSION=13.3.0 klab_backend_apt_capture_buildenv ubuntu 24.04 6.8.0-test /unused ubuntu:24.04 : /tmp/out x86_64

echo 'APT buildenv dependency closure: PASS'
