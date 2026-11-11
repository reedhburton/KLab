#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SELF_DIR="$ROOT"
die(){ echo "TEST-DIE: $*" >&2; exit 1; }
say(){ :; }
run_container_root(){ :; }
provider_image(){ printf 'test:image\n'; }
release_snapshot_parts(){ RELEASE_BASE="${1%%@*}"; RELEASE_SNAPSHOT=''; [[ "$1" == *@* ]] && RELEASE_SNAPSHOT="${1#*@}"; }
apt_snapshot_setup_script(){ printf ':\n'; }
write_package_manifest(){ :; }; extract_debs(){ :; }; extract_rpms(){ :; }; normalize_bundle(){ :; }
provider_list_fedora(){ :; }; fetch_fedora_bundle(){ :; }; provider_list_rhel(){ :; }; fetch_rhel_bundle(){ :; }
# shellcheck disable=SC1091
source "$ROOT/lib/provider-core.sh"

# F06: explicit operation architecture must be checked, not only global ARCH.
export ARCH=x86_64
if (klab_provider_build_module ubuntu 22.04 6.8.0-1-generic image pkgs mod 1 '' aarch64) >/dev/null 2>&1; then
  echo 'FAIL F06: explicit aarch64 bypassed x86_64 provider capability' >&2; exit 1
fi
# F08: jobs is data, not shell syntax or zero/negative work count.
for bad in 0 -1 '1;id' 1x ''; do
  if (klab_provider_build_module ubuntu 22.04 6.8.0-1-generic image pkgs mod "$bad" '' x86_64) >/dev/null 2>&1; then
    echo "FAIL F08: invalid jobs accepted: <$bad>" >&2; exit 1
  fi
done
# F10: provider release/snapshot grammar is closed and timestamped.
klab_provider_validate_release 22.04
klab_provider_validate_release 22.04@20260922T010203Z
for bad in '../22.04' '22.04;id' '22.04@bad' '22.04@20260922' '22.04@20260922T010203Z@x'; do
  if (klab_provider_validate_release "$bad") >/dev/null 2>&1; then
    echo "FAIL F10: invalid release accepted: $bad" >&2; exit 1
  fi
done
# F11: archived Ubuntu and non-snapshot providers cannot use @timestamp syntax.
if (klab_provider_describe ubuntu 17.04@20260922T010203Z) >/dev/null 2>&1; then
  echo 'FAIL F11: archived Ubuntu accepted @snapshot target' >&2; exit 1
fi
if (klab_provider_describe centos 7@20260922T010203Z) >/dev/null 2>&1; then
  echo 'FAIL F11: CentOS accepted @snapshot target' >&2; exit 1
fi
klab_provider_describe ubuntu 22.04@20260922T010203Z >/dev/null

# F07/F09: RPM list pattern and build directory must be shell-escaped.
CAP="$T/cmd"
klab_provider_run_container(){ local provider="$1" image="$2"; shift 2; printf '%s\n' "$*" >"$CAP"; }
pat="x'; touch $T/pwn-list; echo '"
klab_backend_dnf_list_kernel_core fedora img ':' "$pat" >/dev/null
[[ ! -e "$T/pwn-list" ]] || { echo 'FAIL F07: RPM list filter executed input' >&2; exit 1; }
grep -Fq 'grep -F --' "$CAP" || { echo 'FAIL F07: fixed-string filter missing' >&2; exit 1; }
build="/tmp/k'; touch $T/pwn-build; echo '"
klab_backend_dnf_build_module fedora img ':' pkgs 6.1 mod 2 "$build" >/dev/null
[[ ! -e "$T/pwn-build" ]] || { echo 'FAIL F09: build path executed input' >&2; exit 1; }
! grep -Fq "kdir='$build'" "$CAP" || { echo 'FAIL F09: build path embedded raw' >&2; exit 1; }

echo 'overnight-hardening-02-09: PASS'
