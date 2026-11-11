#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
grep -Fq 'chmod -R u+rX "$root"' "$ROOT/lib/buildenv-capture.sh" || { echo "FAIL: exported buildenv root is not normalized for unprivileged hashing" >&2; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SELF_DIR="$ROOT"; die(){ echo "TEST-DIE: $*" >&2; exit 1; }
# shellcheck disable=SC1091
source "$ROOT/lib/buildenv-capture.sh"
mkdir -p "$T/pkgs"
printf a >"$T/pkgs/a.deb"; (cd "$T/pkgs" && sha256sum a.deb >PACKAGES.sha256)
klab_buildenv_verify_package_manifest "$T/pkgs" "$T/pkgs/PACKAGES.sha256"
printf b >"$T/pkgs/b.deb"
if (klab_buildenv_verify_package_manifest "$T/pkgs" "$T/pkgs/PACKAGES.sha256") >/dev/null 2>&1; then
  echo 'FAIL F15: unmanifested dependency archive accepted' >&2; exit 1
fi
rm "$T/pkgs/b.deb"; printf x >>"$T/pkgs/a.deb"
if (klab_buildenv_verify_package_manifest "$T/pkgs" "$T/pkgs/PACKAGES.sha256") >/dev/null 2>&1; then
  echo 'FAIL F15: package checksum mutation accepted' >&2; exit 1
fi
# F17: image provenance must be an immutable canonical digest.
mock="$T/runtime"; cat >"$mock" <<'EOS'
#!/bin/sh
[ "$1" = image ] && [ "$2" = inspect ] && { echo ubuntu:latest; exit 0; }
exit 1
EOS
chmod +x "$mock"
if (klab_buildenv_require_image_id "$mock" ubuntu:latest) >/dev/null 2>&1; then
  echo 'FAIL F17: mutable/noncanonical image identity accepted' >&2; exit 1
fi
cat >"$mock" <<'EOS'
#!/bin/sh
[ "$1" = image ] && [ "$2" = inspect ] && { printf 'sha256:%064d\n' 0; exit 0; }
exit 1
EOS
chmod +x "$mock"
klab_buildenv_require_image_id "$mock" ubuntu:latest | grep -Eq '^sha256:[0-9a-f]{64}$' || { echo 'FAIL F17: canonical image ID rejected' >&2; exit 1; }
# F13: v1 buildenv capture must reject target/host execution mismatch before container use.
export KLAB_CONTAINER_RUNTIME="$mock"
mkdir -p "$T/pkgs2"; printf x >"$T/pkgs2/x.deb"; (cd "$T/pkgs2" && sha256sum x.deb >PACKAGES.sha256)
host=$(klab_buildenv_canonical_arch "$(uname -m)")
# F16: closure archive/provenance inputs are an inseparable pair and are
# rejected before any provider container is created.
mkdir -p "$T/deps"
if ( KLAB_BUILDENV_DEPENDENCY_ARCHIVES="$T/deps" KLAB_BUILDENV_DEPENDENCY_PROVENANCE= \
  klab_buildenv_capture_container test 1 k "$host" img ':' "$T/pkgs2" ':' /x "$T/outdep" ) >/dev/null 2>&1; then
  echo 'FAIL F16: unpaired dependency closure accepted' >&2; exit 1
fi
case "$host" in x86_64) foreign=aarch64;; *) foreign=x86_64;; esac
if (klab_buildenv_assert_staging_arch "$host" "$foreign" same-host-v1) >/dev/null 2>&1; then
  echo 'FAIL F13: ordinary foreign staging architecture accepted' >&2; exit 1
fi
klab_buildenv_assert_staging_arch "$host" "$foreign" provider-native-v1
if (klab_buildenv_assert_staging_arch "$host" "$foreign" arbitrary-mode) >/dev/null 2>&1; then
  echo 'FAIL F13: arbitrary foreign staging mode accepted' >&2; exit 1
fi
if (klab_buildenv_capture_container ubuntu 1 k "$foreign" img ':' "$T/pkgs2" ':' /x "$T/out") >/dev/null 2>&1; then
  echo 'FAIL F13: foreign staging architecture accepted' >&2; exit 1
fi
# F14: even with a matching staging host, verify the actual container CPU before setup/install.
cat >"$mock" <<EOS
#!/bin/sh
case "\$1" in
 image) printf 'sha256:%064d\n' 0; exit 0;;
 create|start|rm) exit 0;;
 exec) shift; [ "\$1" = dummy ] && shift; [ "\${1:-}" = uname ] && { echo "$foreign"; exit 0; }; exit 0;;
esac
exit 0
EOS
chmod +x "$mock"
# Runtime receives a generated container name, so use a simpler wrapper for exec parsing.
cat >"$mock" <<EOS
#!/bin/sh
cmd="\$1"; shift
case "\$cmd" in
 image) printf 'sha256:%064d\n' 0;;
 create|start|rm) :;;
 exec) while [ "\$#" -gt 0 ]; do case "\$1" in -e|--env) shift 2;; -*) shift;; *) break;; esac; done; shift; [ "\${1:-}" = uname ] && { echo "$foreign"; exit 0; }; :;;
 *) :;;
esac
EOS
chmod +x "$mock"
if (klab_buildenv_capture_container ubuntu 1 k "$host" img ':' "$T/pkgs2" ':' /x "$T/out2") >/dev/null 2>&1; then
  echo 'FAIL F14: provider container execution architecture mismatch accepted' >&2; exit 1
fi

echo 'buildenv-provenance-hardening: PASS'
