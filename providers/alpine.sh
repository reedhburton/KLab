#!/usr/bin/env bash
klab_provider_alpine_setup(){ printf 'apk update >/dev/null\n'; }
klab_provider_alpine_list(){ local r="$1" pat="${2:-}" img="$(provider_image alpine "$r")"; say "Listing Alpine $r kernels"; klab_backend_apk_list alpine "$img" "$(klab_provider_alpine_setup)" "$pat"; }
klab_provider_alpine_fetch(){ local r="$1" k="$2" b="$3" img="$(provider_image alpine "$r")"; klab_backend_apk_fetch alpine "$r" "$k" "$b" "$img" "$(klab_provider_alpine_setup)"; }
klab_provider_alpine_build_module(){ klab_backend_apk_build_module alpine "$3" "$(klab_provider_alpine_setup)" "$4" "$2" "$5" "$6" "${7:-}"; }
klab_provider_alpine_capture_buildenv(){ local r="$1" k="$2" b="$3" out="$4" arch="$5" img="$(provider_image alpine "$r")"; klab_backend_apk_capture_buildenv alpine "$r" "$k" "$b" "$img" "$(klab_provider_alpine_setup)" "$out" "$arch"; }
klab_provider_alpine_capture_toolchain(){ local r="$1" out="$2" arch="$3" img="$(provider_image alpine "$r")"; klab_backend_apk_capture_toolchain alpine "$r" "$img" "$(klab_provider_alpine_setup)" "$out" "$arch"; }
klab_provider_alpine_capabilities(){ printf 'list=yes fetch=yes build-module=yes buildenv=yes historical=yes snapshots=no cross-arch=no arches=x86_64\n'; }
klab_provider_alpine_describe(){ printf 'alpine    APK provider; linux-lts kernel and native musl toolchain\n'; }
