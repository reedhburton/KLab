#!/usr/bin/env bash
klab_provider_almalinux_setup(){ if klab_provider_mirror_only; then klab_provider_dnf_mirror_setup; else printf ':\n'; fi; }
klab_provider_almalinux_list(){ local r="$1" p="${2:-}" img="$(provider_image almalinux "$r")"; klab_backend_dnf_list_kernel_core almalinux "$img" "$(klab_provider_almalinux_setup)" "$p"; }
klab_provider_almalinux_fetch(){ local r="$1" k="$2" b="$3" img="$(provider_image almalinux "$r")"; klab_backend_dnf_fetch_kernel_core almalinux "$r" "$k" "$b" "$img" "$(klab_provider_almalinux_setup)"; }
klab_provider_almalinux_build_module(){ klab_backend_dnf_build_module almalinux "$3" "$(klab_provider_almalinux_setup)" "$4" "$2" "$5" "$6" "${7:-}"; }
klab_provider_almalinux_capture_buildenv(){ local r="$1" k="$2" b="$3" out="$4" arch="$5" img="$(provider_image almalinux "$r")"; klab_backend_dnf_capture_buildenv almalinux "$r" "$k" "$b" "$img" "$(klab_provider_almalinux_setup)" "$out" "$arch"; }
klab_provider_almalinux_capabilities(){ printf 'list=experimental fetch=experimental build-module=yes buildenv=yes historical=limited snapshots=no cross-arch=no arches=x86_64\n'; }
klab_provider_almalinux_describe(){ printf 'almalinux experimental DNF adapter through unified RPM backend\n'; }
