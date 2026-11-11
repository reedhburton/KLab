#!/usr/bin/env bash
klab_provider_centos_is_v7(){ local b="${1%%@*}"; [[ "$b" == 7 || "$b" == 7.* ]]; }
klab_provider_centos7_setup(){
  if klab_provider_mirror_only; then klab_provider_yum_mirror_setup; return; fi
  cat <<'EOS'
# Pin the historical CentOS 7 signing key before trusting Vault packages.
# gpg's human output is used because the CentOS 7 base image carries an old
# GnuPG that predates newer show-only/import inspection options.
key=/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
[ -r "$key" ] || { echo 'CentOS 7 signing key missing' >&2; exit 43; }
fp=$(gpg --quiet --with-fingerprint "$key" 2>/dev/null | sed -n 's/.*Key fingerprint = //p' | tr -d ' ' | tr '[:lower:]' '[:upper:]' | head -n1)
[ "$fp" = 6341AB2753D78A78A7C27BB124C6A8A7F4A80EB5 ] || { echo "CentOS 7 signing key fingerprint mismatch: ${fp:-missing}" >&2; exit 43; }
cat >/etc/yum.repos.d/klab-vault.repo <<'EOREPO'
[klab-base]
name=KLab CentOS 7.9.2009 Base
baseurl=https://vault.centos.org/7.9.2009/os/$basearch/
        https://archive.kernel.org/centos-vault/7.9.2009/os/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
[klab-updates]
name=KLab CentOS 7.9.2009 Updates
baseurl=https://vault.centos.org/7.9.2009/updates/$basearch/
        https://archive.kernel.org/centos-vault/7.9.2009/updates/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOREPO
for f in /etc/yum.repos.d/*.repo; do [ "$f" = /etc/yum.repos.d/klab-vault.repo ] && continue; mv "$f" "$f.klab-disabled" 2>/dev/null || true; done
yum clean all >/dev/null 2>&1 || true
yum -q makecache
EOS
}
klab_provider_centos_new_setup(){ if klab_provider_mirror_only; then klab_provider_dnf_mirror_setup; else printf ':\n'; fi; }
klab_provider_centos_image(){ provider_image centos "$1"; }
klab_provider_centos_list(){ local r="$1" pat="${2:-}" img; img="$(klab_provider_centos_image "$r")"; if klab_provider_centos_is_v7 "$r"; then [[ "${ARCH:-x86_64}" == x86_64 ]] || die 'CentOS 7 currently supports x86_64 only'; say 'Listing CentOS 7.9.2009 kernels'; klab_backend_yum_list_kernel centos "$img" "$(klab_provider_centos7_setup)" "$pat"; else say "Listing CentOS $r kernel-core builds"; klab_backend_dnf_list_kernel_core centos "$img" "$(klab_provider_centos_new_setup)" "$pat"; fi; }
klab_provider_centos_fetch(){ local r="$1" k="$2" b="$3" img="$(klab_provider_centos_image "$r")"; if klab_provider_centos_is_v7 "$r"; then klab_backend_yum_fetch_kernel centos "$r" "$k" "$b" "$img" "$(klab_provider_centos7_setup)"; else klab_backend_dnf_fetch_kernel_core centos "$r" "$k" "$b" "$img" "$(klab_provider_centos_new_setup)"; fi; }
klab_provider_centos_build_module(){ local r="$1" k="$2" img="$3" pkgs="$4" mod="$5" jobs="$6" build="${7:-}"; if klab_provider_centos_is_v7 "$r"; then klab_backend_yum_build_module centos "$img" "$(klab_provider_centos7_setup)" "$pkgs" "$k" "$mod" "$jobs" "$build"; else klab_backend_dnf_build_module centos "$img" "$(klab_provider_centos_new_setup)" "$pkgs" "$k" "$mod" "$jobs" "$build"; fi; }
klab_provider_centos_capture_buildenv(){ local r="$1" k="$2" b="$3" out="$4" arch="$5" img="$(klab_provider_centos_image "$r")"; if klab_provider_centos_is_v7 "$r"; then klab_backend_yum_capture_buildenv centos "$r" "$k" "$b" "$img" "$(klab_provider_centos7_setup)" "$out" "$arch"; else klab_backend_dnf_capture_buildenv centos "$r" "$k" "$b" "$img" "$(klab_provider_centos_new_setup)" "$out" "$arch"; fi; }
klab_provider_centos_capture_toolchain(){ local r="$1" out="$2" arch="$3" compiler_version="${4:-}" img="$(klab_provider_centos_image "$r")"; if klab_provider_centos_is_v7 "$r"; then klab_backend_yum_capture_toolchain centos "$r" "$img" "$(klab_provider_centos7_setup)" "$out" "$arch" "$compiler_version"; else klab_backend_dnf_capture_toolchain centos "$r" "$img" "$(klab_provider_centos_new_setup)" "$out" "$arch" "$compiler_version"; fi; }
klab_provider_centos_capabilities(){ local r="${1:-}"; printf 'list=yes fetch=yes build-module=yes buildenv=yes historical=%s snapshots=no cross-arch=no arches=x86_64\n' "$([[ -n "$r" ]] && klab_provider_centos_is_v7 "$r" && echo yes || echo limited)"; }
klab_provider_centos_describe(){ printf 'centos    CentOS 7.9 Vault via yum; Stream/newer releases via dnf\n'; }
