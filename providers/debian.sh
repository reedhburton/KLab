#!/usr/bin/env bash
klab_provider_debian_setup(){
  local r="$1"
  if klab_provider_mirror_only; then
    [[ "$r" != *@* ]] || die "mirror-only: Debian @snapshot targets are disabled; mirror the desired snapshot into KLAB_DEBIAN_APT_SOURCES_FILE and use a non-@snapshot target"
    klab_provider_apt_mirror_setup
  else
    if [[ "$r" == bullseye ]]; then
      cat <<'EOF'
set -eu
snapshot=$(sed -n 's|^# deb http://snapshot.debian.org/archive/debian/\([^/[:space:]]*\)[/[:space:]].*|\1|p' /etc/apt/sources.list | head -n1)
if [ -n "$snapshot" ]; then
  cat >/etc/apt/sources.list <<EOSOURCES
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/$snapshot/ bullseye main
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/$snapshot/ bullseye-updates main
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/$snapshot/ bullseye-security main
EOSOURCES
  printf 'Acquire::Check-Valid-Until "false";\n' >/etc/apt/apt.conf.d/99klab-snapshot
  rm -rf /var/lib/apt/lists/*
fi
apt-get -o Acquire::Check-Valid-Until=false update -qq
EOF
    else
      apt_snapshot_setup_script debian "$r"
    fi
  fi
}
klab_provider_debian_list(){ local r="$1" pat="${2:-}" img="$(provider_image debian "$r")"; say "Listing Debian kernels from $r"; klab_backend_apt_list debian "$img" "$(klab_provider_debian_setup "$r")" '^linux-image-[0-9].*-(amd64|cloud-amd64|rt-amd64)$' "$pat"; }
klab_provider_debian_fetch(){ local r="$1" k="$2" b="$3" img="$(provider_image debian "$r")"; klab_backend_apt_fetch debian "$r" "$k" "$b" "$img" "$(klab_provider_debian_setup "$r")"; }
klab_provider_debian_build_module(){ klab_backend_apt_build_module debian "$3" "$(klab_provider_debian_setup "$1")" "$4" "$2" "$5" "$6"; }
klab_provider_debian_capture_buildenv(){ local r="$1" k="$2" b="$3" out="$4" arch="$5" img="$(provider_image debian "$r")"; klab_backend_apt_capture_buildenv debian "$r" "$k" "$b" "$img" "$(klab_provider_debian_setup "$r")" "$out" "$arch"; }
klab_provider_debian_capture_toolchain(){ local r="$1" out="$2" arch="$3" compiler_version="${4:-}" img="$(provider_image debian "$r")"; klab_backend_apt_capture_toolchain debian "$r" "$img" "$(klab_provider_debian_setup "$r")" "$out" "$arch" "$compiler_version"; }
klab_provider_debian_capabilities(){ local snaps=yes; klab_provider_mirror_only && snaps=no; printf 'list=yes fetch=yes build-module=yes buildenv=yes historical=yes snapshots=%s cross-arch=no arches=x86_64\n' "$snaps"; }
klab_provider_debian_describe(){ printf 'debian    apt provider; current and snapshot.debian.org releases\n'; }
