#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
die(){ echo "$*" >&2; exit 1; }
source "$ROOT/lib/backends/apk.sh"
script="$(klab_backend_apk_dependency_capture_script)"
grep -Fq 'apk verify "$archive"' <<<"$script" || die 'APK closure lacks signature verification'
grep -Fq 'archive-identities.tsv' <<<"$script" || die 'APK closure lacks host-independent identities'
grep -Fq 'requested-details.tsv' <<<"$script" || die 'APK closure does not map split packages to origin archives'
grep -Fq '$4==o && $2==v' <<<"$script" || die 'APK origin archive is not mapped to every realized split package'
grep -Fq '/lib/apk/db/installed' <<<"$script" || die 'APK closure does not inventory realized packages'
! grep -Fq 'print p "\\t"' <<<"$script" || die 'APK inventory emits literal backslash-t separators'
grep -Fq '/etc/apk/keys' <<<"$script" || die 'APK closure does not retain trust keys'
klab_buildenv_capture_container(){
  [[ "${KLAB_BUILDENV_DEPENDENCY_REPOSITORY_URL:-}" == apk://alpine/3.22 ]] || die 'APK repository provenance URL not bound'
  [[ "${KLAB_BUILDENV_DEPENDENCY_CAPTURE_COMMAND:-}" == *'apk fetch --output'* ]] || die 'APK closure capture not bound'
}
klab_backend_apk_capture_buildenv alpine 3.22 6.12-test /bundle alpine:3.22 : /tmp/out x86_64
echo 'APK buildenv dependency closure: PASS'
