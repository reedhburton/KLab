#!/usr/bin/env bash
klab_provider_arch_setup(){
  local release="${1:-rolling}"
  if [[ "$release" == rolling ]]; then
    printf 'pacman -Sy --noconfirm >/dev/null\n'
  elif [[ "$release" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
    local date="${release//.//}"
    printf "printf 'Server = https://archive.archlinux.org/repos/%s/\\$repo/os/\\$arch\\n' > /etc/pacman.d/mirrorlist\npacman -Syy --noconfirm >/dev/null\n" "$date"
  else
    die "Arch release must be rolling or YYYY.MM.DD"
  fi
}
klab_provider_arch_list(){ local r="$1" pat="${2:-}" img="$(provider_image arch "$r")"; klab_backend_pacman_list arch "$r" "$img" "$(klab_provider_arch_setup "$r")" "$pat"; }
klab_provider_arch_fetch(){ local r="$1" k="$2" b="$3" img="$(provider_image arch "$r")"; klab_backend_pacman_fetch arch "$r" "$k" "$b" "$img" "$(klab_provider_arch_setup "$r")"; }
klab_provider_arch_build_module(){ local r="$1"; klab_backend_pacman_build_module arch "$3" "$(klab_provider_arch_setup "$r")" "$4" "$2" "$5" "$6"; }
klab_provider_arch_capture_buildenv(){ local r="$1" k="$2" b="$3" out="$4" arch="$5" img="$(provider_image arch "$r")"; klab_backend_pacman_capture_buildenv arch "$r" "$k" "$b" "$img" "$(klab_provider_arch_setup "$r")" "$out" "$arch"; }
klab_provider_arch_capture_toolchain(){ local r="$1" out="$2" arch="$3" img="$(provider_image arch "$r")"; klab_backend_pacman_capture_toolchain arch "$r" "$img" "$(klab_provider_arch_setup "$r")" "$out" "$arch"; }
klab_provider_arch_capabilities(){ printf 'list=yes fetch=yes build-module=yes buildenv=yes historical=yes snapshots=no cross-arch=no arches=x86_64\n'; }
klab_provider_arch_describe(){ printf 'arch      Pacman provider; standard, LTS, Zen, and hardened kernels with native userspace\n'; }
