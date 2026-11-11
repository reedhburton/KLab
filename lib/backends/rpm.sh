#!/usr/bin/env bash
# Generic RPM repository backend, provider API v2.

klab_backend_rpm_arch(){ case "${1:-${ARCH:-x86_64}}" in x86_64|amd64) echo x86_64;; i386|x86) echo i686;; aarch64|arm64) echo aarch64;; armv7|armhf) echo armv7hl;; *) die "no RPM architecture mapping for $1";; esac; }
klab_backend_rpm_kernel_release(){ local krel="$1" rpm_arch; rpm_arch="$(klab_backend_rpm_arch "${2:-${ARCH:-x86_64}}")"; case "$krel" in *.$rpm_arch) printf '%s\n' "$krel";; *) printf '%s.%s\n' "$krel" "$rpm_arch";; esac; }
klab_backend_rpm_fix_owner(){ local p="$1"; [[ -e "$p" ]] || return 0; [[ "$(id -u)" == 0 ]] && return 0; chown -R "$(id -u):$(id -g)" "$p" 2>/dev/null || true; }
klab_backend_rpm_host_owner(){ klab_provider_bind_output_owner; }
klab_backend_rpm_manifest(){ local dir="$1"; (cd "$dir" && for f in *.rpm; do [[ -f "$f" ]] || continue; sha256sum -- "$f"; done | LC_ALL=C sort -k2) >"$dir/PACKAGES.sha256"; }
klab_backend_rpm_verify_arch(){ local provider="$1" image="$2" packages="$3" expected; expected="$(klab_backend_rpm_arch "${ARCH:-x86_64}")"; klab_provider_run_container "$provider" "$image" -v "$packages:/pkgs:ro" bash -lc "set -eu; for p in /pkgs/*.rpm; do [ -e \"\$p\" ] || continue; a=\$(rpm -qp --qf '%{ARCH}' \"\$p\"); case \"\$a\" in noarch|$expected) ;; *) echo \"wrong RPM architecture: \$p -> \$a (expected $expected)\" >&2; exit 44;; esac; done"; }
klab_backend_rpm_verify_kernel_identity(){
  local provider="$1" image="$2" packages="$3" krel="$4"
  klab_provider_run_container "$provider" "$image" -v "$packages:/pkgs:ro" bash -lc "set -eu
found=0
for p in /pkgs/*.rpm; do
  [ -e \"\$p\" ] || continue
  n=\$(rpm -qp --qf '%{NAME}' \"\$p\")
  case \"\$n\" in kernel|kernel-core)
    vr=\$(rpm -qp --qf '%{VERSION}-%{RELEASE}.%{ARCH}' \"\$p\")
    [ \"\$vr\" = '$krel' ] && found=1
  ;; esac
done
[ \"\$found\" = 1 ] || { echo 'downloaded RPMs do not contain exact requested kernel identity $krel' >&2; exit 46; }"
}


klab_backend_dnf_list_kernel_core(){ local provider="$1" image="$2" setup="$3" pattern="${4:-}" filter=cat qpattern; if [[ -n "$pattern" ]]; then printf -v qpattern '%q' "$pattern"; filter="grep -F -- $qpattern"; fi; klab_provider_run_container "$provider" "$image" bash -lc "$setup
dnf -qy install dnf-plugins-core >/dev/null
dnf -q repoquery --available --show-duplicates --qf '%{version}-%{release}.%{arch}' kernel-core | sort -V | $filter | tail -n 200"; }
klab_backend_dnf_fetch_kernel_core(){ local provider="$1" release="$2" krel="$3" bundle="$4" image="$5" setup="${6:-:}" owner; owner="$(klab_backend_rpm_host_owner)"; mkdir -p "$bundle/packages"; rm -f "$bundle/packages"/*.rpm "$bundle/packages/PACKAGES.sha256" 2>/dev/null || true; say "Downloading $provider $release kernel $krel"; klab_provider_run_container "$provider" "$image" -v "$bundle/packages:/out" bash -lc "$setup
dnf -qy install dnf-plugins-core >/dev/null
pkgs=''; for p in kernel-core-$krel kernel-modules-core-$krel kernel-modules-$krel kernel-modules-extra-$krel kernel-devel-$krel kernel-headers-$krel; do dnf -q repoquery \"\$p\" | grep -q . && pkgs=\"\$pkgs \$p\" || true; done
[ -n \"\$pkgs\" ] || { echo 'no matching RPMs found' >&2; exit 40; }
dnf -qy download --resolve --alldeps --destdir /out \$pkgs
chown -R '$owner' /out"; compgen -G "$bundle/packages/*.rpm" >/dev/null || die "no RPMs were downloaded"; klab_backend_rpm_fix_owner "$bundle/packages"; klab_backend_rpm_verify_arch "$provider" "$image" "$bundle/packages"; klab_backend_rpm_verify_kernel_identity "$provider" "$image" "$bundle/packages" "$krel"; klab_backend_rpm_manifest "$bundle/packages"; write_package_manifest "$bundle" 2>/dev/null || true; extract_rpms "$bundle/packages" "$bundle/root"; normalize_bundle "$provider" "$release" "$krel" "$bundle" "$image"; }

klab_backend_yum_list_kernel(){ local provider="$1" image="$2" setup="$3" pattern="${4:-}" filter=cat qpattern; if [[ -n "$pattern" ]]; then printf -v qpattern '%q' "$pattern"; filter="grep -F -- $qpattern"; fi; klab_provider_run_container "$provider" "$image" bash -lc "$setup
yum -qy install yum-utils >/dev/null
repoquery --show-duplicates --qf '%{version}-%{release}.%{arch}' kernel | sort -V | $filter | tail -n 200"; }
klab_backend_yum_fetch_kernel(){ local provider="$1" release="$2" krel="$3" bundle="$4" image="$5" setup="$6" owner; owner="$(klab_backend_rpm_host_owner)"; mkdir -p "$bundle/packages"; rm -f "$bundle/packages"/*.rpm "$bundle/packages/PACKAGES.sha256" 2>/dev/null || true; say "Downloading $provider $release kernel $krel"; klab_provider_run_container "$provider" "$image" -v "$bundle/packages:/out" bash -lc "$setup
yum -qy install yum-utils >/dev/null
pkgs=''; for p in kernel-$krel kernel-devel-$krel kernel-headers-$krel; do repoquery \"\$p\" | grep -q . && pkgs=\"\$pkgs \$p\" || true; done
[ -n \"\$pkgs\" ] || { echo 'no matching CentOS 7 kernel RPMs found' >&2; exit 40; }
cd /out; for p in \$pkgs; do yumdownloader --resolve --destdir=/out \"\$p\" || yumdownloader --destdir=/out \"\$p\"; done
chown -R '$owner' /out"; compgen -G "$bundle/packages/*.rpm" >/dev/null || die "no RPMs were downloaded"; klab_backend_rpm_fix_owner "$bundle/packages"; klab_backend_rpm_verify_arch "$provider" "$image" "$bundle/packages"; klab_backend_rpm_verify_kernel_identity "$provider" "$image" "$bundle/packages" "$krel"; klab_backend_rpm_manifest "$bundle/packages"; write_package_manifest "$bundle" 2>/dev/null || true; extract_rpms "$bundle/packages" "$bundle/root"; normalize_bundle "$provider" "$release" "$krel" "$bundle" "$image"; }

klab_backend_dnf_build_module(){ local provider="$1" image="$2" setup="$3" packages="$4" krel="$5" module_dir="$6" jobs="$7" build_override="${8:-}" qbuild default_build; default_build="/usr/src/kernels/$(klab_backend_rpm_kernel_release "$krel" "${ARCH:-x86_64}")"; printf -v qbuild '%q' "${build_override:-$default_build}"; klab_provider_run_container "$provider" "$image" -v "$packages:/pkgs:ro" -v "$module_dir:/module" bash -lc "$setup
dnf -qy install gcc make bc kmod elfutils-libelf-devel openssl-devel flex bison >/dev/null
rpms=''; for p in /pkgs/*.rpm; do [ -e \"\$p\" ] || continue; n=\$(rpm -qp --qf '%{NAME}' \"\$p\" 2>/dev/null || true); case \"\$n\" in kernel-devel|kernel-headers|kernel-rpm-macros|kernel-srpm-macros) rpms=\"\$rpms \$p\";; esac; done
[ -n \"\$rpms\" ] && dnf -qy install \$rpms >/dev/null
kdir=$qbuild; [ -d \"\$kdir\" ] || kdir=/usr/src/kernels/$krel; [ -d \"\$kdir\" ] || { echo \"kernel-devel tree missing: \$kdir\" >&2; exit 41; }
make -C \"\$kdir\" M=/module -j$jobs modules
ko=\$(find /module -name '*.ko' -print -quit); [ -n \"\$ko\" ] || { echo 'module build produced no .ko' >&2; exit 43; }
vm=\$(modinfo -F vermagic \"\$ko\" 2>/dev/null || true); case \"\$vm\" in '$krel '*) ;; *) echo \"module vermagic mismatch: \${vm:-missing} != $krel\" >&2; exit 42;; esac
chown -R $(id -u):$(id -g) /module"; }
klab_backend_yum_build_module(){ local provider="$1" image="$2" setup="$3" packages="$4" krel="$5" module_dir="$6" jobs="$7" build_override="${8:-}" qbuild; printf -v qbuild '%q' "${build_override:-/usr/src/kernels/$krel}"; klab_provider_run_container "$provider" "$image" -v "$packages:/pkgs:ro" -v "$module_dir:/module" bash -lc "$setup
yum -qy install gcc make bc kmod elfutils-libelf-devel openssl-devel >/dev/null
rpms=''; for p in /pkgs/*.rpm; do [ -e \"\$p\" ] || continue; b=\$(basename \"\$p\"); case \"\$b\" in kernel-devel-*|kernel-headers-*) rpms=\"\$rpms \$p\";; esac; done
[ -n \"\$rpms\" ] || { echo 'kernel-devel RPM missing from bundle' >&2; exit 41; }
yum -qy localinstall \$rpms >/dev/null
kdir=$qbuild; [ -d \"\$kdir\" ] || kdir=/usr/src/kernels/$krel; [ -d \"\$kdir\" ] || { echo \"kernel-devel tree missing: \$kdir\" >&2; exit 41; }
make -C \"\$kdir\" M=/module -j$jobs modules
ko=\$(find /module -name '*.ko' -print -quit); [ -n \"\$ko\" ] || { echo 'module build produced no .ko' >&2; exit 43; }
vm=\$(modinfo -F vermagic \"\$ko\" 2>/dev/null || true); case \"\$vm\" in '$krel '*) ;; *) echo \"module vermagic mismatch: \${vm:-missing} != $krel\" >&2; exit 42;; esac
chown -R $(id -u):$(id -g) /module"; }

klab_backend_dnf_dependency_capture_script(){ cat <<'EOS'
set -eu
out=${KLAB_DEPENDENCY_CAPTURE_OUT:-/klab-dependency-capture}
mkdir -p "$out/packages"
rm -f "$out/packages"/*.rpm "$out/requested.tsv" "$out/archives.tsv" "$out/archive-identities.tsv" "$out/repository-state.tar" 2>/dev/null || true
trust_mode=${KLAB_RPM_TRUST_MODE:-signed}
download_tool=${KLAB_RPM_DEPENDENCY_DOWNLOADER:-dnf}
koji_metadata=${KLAB_RPM_KOJI_METADATA_FILE:-/klab-dependency-metadata}
case "$trust_mode" in signed|koji) ;; *) echo "unsupported RPM trust mode: $trust_mode" >&2; exit 44;; esac
case "$download_tool" in dnf|yumdownloader) ;; *) echo "unsupported RPM dependency downloader: $download_tool" >&2; exit 44;; esac
[ "$trust_mode" != koji ] || [ -s "$koji_metadata" ] || { echo 'Koji RPM capture requires buildroot metadata' >&2; exit 44; }
repo_config=${KLAB_RPM_REPOSITORY_CONFIG_DIR:-/etc/yum.repos.d}
dnf_config=${KLAB_RPM_DNF_CONFIG_DIR:-/etc/dnf}
dnf_cache=${KLAB_RPM_DNF_CACHE_DIR:-/var/cache/dnf}
yum_cache=${KLAB_RPM_YUM_CACHE_DIR:-/var/cache/yum}
if [ "$trust_mode" = signed ] && grep -ERiq '^[[:space:]]*gpgcheck[[:space:]]*=[[:space:]]*(0|false|no)[[:space:]]*$' "$repo_config" "$dnf_config" 2>/dev/null; then
  echo 'insecure RPM signature configuration is forbidden for dependency closure capture' >&2; exit 45
fi
rpm -qa --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\t%{ARCH}\n' \
  | awk -F '\t' '$1 != "gpg-pubkey"' | LC_ALL=C sort -u > "$out/requested.tsv"
while IFS=$(printf '\t') read -r package evr arch; do
  [ -n "$package" ] && [ -n "$evr" ] && [ -n "$arch" ] || { echo 'malformed installed RPM row' >&2; exit 46; }
  download_evr=$evr
  case "$download_evr" in 0:*) download_evr=${download_evr#0:};; esac
  spec="$package-$download_evr.$arch"
  case "$download_tool" in
    dnf)
      if ! dnf -qy download --destdir "$out/packages" --arch "$arch" "$spec" >/dev/null 2>&1; then
        # Older DNF download plugins refuse an exact NEVRA when that package is
        # already installed. Prefer the mounted reconstructed repository, then
        # resolve a repository location. RPM identity and payload digest are
        # still verified below before sealing.
        filename_evr_hint=$download_evr
        case "$filename_evr_hint" in *:*) filename_evr_hint=${filename_evr_hint#*:};; esac
        expected_file="$package-$filename_evr_hint.$arch.rpm"
        if [ -f "/pkgs/$expected_file" ]; then
          cp "/pkgs/$expected_file" "$out/packages/"
        elif [ -f "/klab-distro-toolchain-packages/$expected_file" ]; then
          cp "/klab-distro-toolchain-packages/$expected_file" "$out/packages/"
        elif [ -f "/klab-buildenv-aux-repo/$expected_file" ]; then
          cp "/klab-buildenv-aux-repo/$expected_file" "$out/packages/"
        elif [ "$trust_mode" = koji ]; then
          koji_base=${KLAB_RPM_KOJI_PACKAGE_BASE:-https://kojipkgs.fedoraproject.org/packages}
          source_rpm=$(rpm -q --qf '%{SOURCERPM}' "$package")
          source_nvr=${source_rpm%.src.rpm}
          koji_evr=$download_evr
          case "$koji_evr" in *:*) koji_evr=${koji_evr#*:};; esac
          source_name=${source_nvr%-$koji_evr}
          [ -n "$source_name" ] && [ "$source_name" != "$source_nvr" ] || {
            echo "could not resolve Koji source package for $spec" >&2; false;
          }
          koji_version=${koji_evr%-*}
          koji_release=${koji_evr##*-}
          koji_url="$koji_base/$source_name/$koji_version/$koji_release/$arch/$expected_file"
          curl -fsSL "$koji_url" -o "$out/packages/$expected_file"
        else
          location=$(dnf -q repoquery --location "$spec" 2>/dev/null | head -n1 || true)
          case "$location" in
            file://*) cp "${location#file://}" "$out/packages/" ;;
            http://*|https://*) curl -fsSL "$location" -o "$out/packages/$(basename "$location")" ;;
            *) false ;;
          esac
        fi
      fi
      ;;
    yumdownloader) yumdownloader --quiet --destdir="$out/packages" --archlist="$arch" "$spec" >/dev/null 2>&1 ;;
  esac || {
    echo "exact installed dependency archive unavailable: $package=$evr [$arch]" >&2; exit 47;
  }
  filename_evr=$download_evr
  case "$filename_evr" in *:*) filename_evr=${filename_evr#*:};; esac
  candidate="$out/packages/$package-$filename_evr.$arch.rpm"
  [ -f "$candidate" ] || { echo "downloaded RPM archive missing: $package=$evr [$arch]" >&2; exit 48; }
  identity=$(rpm -qp --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\t%{ARCH}' "$candidate")
  expected=$(printf '%s\t%s\t%s' "$package" "$evr" "$arch")
  [ "$identity" = "$expected" ] || { echo "downloaded RPM identity mismatch: $package=$evr [$arch]" >&2; exit 48; }
done < "$out/requested.tsv"
: > "$out/archives.tsv"
: > "$out/archive-identities.tsv"
for archive in "$out/packages"/*.rpm; do
  [ -f "$archive" ] || continue
  rpm -K --nosignature "$archive" > "$out/rpm-signature.tmp" 2>&1 || { cat "$out/rpm-signature.tmp" >&2; echo "RPM payload digest verification failed: $archive" >&2; exit 49; }
  if [ "$trust_mode" = signed ]; then
    rpm -Kv "$archive" > "$out/rpm-signature.tmp" 2>&1 || { cat "$out/rpm-signature.tmp" >&2; echo "RPM signature verification failed: $archive" >&2; exit 49; }
    if grep -Eiq 'NOKEY|NOT OK|UNSIGNED' "$out/rpm-signature.tmp"; then
      cat "$out/rpm-signature.tmp" >&2; echo "RPM signature is not trusted: $archive" >&2; exit 49
    fi
  fi
  identity=$(rpm -qp --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\t%{ARCH}' "$archive")
  printf '%s\n' "$identity" >> "$out/archives.tsv"
  archive_sha=$(sha256sum "$archive" | awk '{print $1}')
  printf '%s\t%s\t%s\n' "$(basename "$archive")" "$archive_sha" "$identity" >> "$out/archive-identities.tsv"
done
rm -f "$out/rpm-signature.tmp"
LC_ALL=C sort -u -o "$out/archives.tsv" "$out/archives.tsv"
LC_ALL=C sort -u -o "$out/archive-identities.tsv" "$out/archive-identities.tsv"
requested_sha=$(sha256sum "$out/requested.tsv" | awk '{print $1}')
archives_sha=$(sha256sum "$out/archives.tsv" | awk '{print $1}')
if [ "$requested_sha" != "$archives_sha" ]; then
  echo 'downloaded RPM dependency closure differs from installed inventory' >&2
  command -v diff >/dev/null 2>&1 && diff -u "$out/requested.tsv" "$out/archives.tsv" >&2 || true
  exit 50
fi
set --
[ -d "$repo_config" ] && set -- "$@" "$repo_config"
[ -d "$dnf_config" ] && set -- "$@" "$dnf_config"
[ -d "$dnf_cache" ] && set -- "$@" "$dnf_cache"
[ -d "$yum_cache" ] && set -- "$@" "$yum_cache"
[ "$trust_mode" != koji ] || set -- "$@" "$koji_metadata"
[ "$#" -gt 0 ] || { echo 'RPM repository state is unavailable' >&2; exit 51; }
tar -cf "$out/repository-state.tar" "$@" 2>/dev/null
EOS
}

klab_backend_dnf_capture_buildenv(){
  local provider="$1" release="$2" krel="$3" bundle="$4" image="$5" setup="$6" output="$7" arch="$8" rpm_arch build install
  rpm_arch="$(klab_backend_rpm_arch "$arch")"
  build="/usr/src/kernels/$(klab_backend_rpm_kernel_release "$krel" "$arch")"
  install='coreutils_package=coreutils
rpm -q coreutils-single >/dev/null 2>&1 && coreutils_package=coreutils-single
dnf -qy install dnf-plugins-core gcc make bc kmod elfutils-libelf-devel openssl-devel flex bison bash "$coreutils_package" findutils gawk grep sed >/dev/null
rpms=""
for p in /pkgs/*.rpm; do
  [ -e "$p" ] || continue
  b=$(basename "$p")
  case "$b" in
    kernel-devel-*|kernel-headers-*|kernel-rpm-macros-*|kernel-srpm-macros-*) rpms="$rpms $p" ;;
  esac
done
[ -n "$rpms" ] || { echo "kernel-devel/header RPM missing from bundle" >&2; exit 41; }
dnf -qy install $rpms >/dev/null'
  KLAB_BUILDENV_DEPENDENCY_CAPTURE_COMMAND="$(klab_backend_dnf_dependency_capture_script)" \
  KLAB_BUILDENV_DEPENDENCY_REPOSITORY_URL="rpm://$provider/$release" \
    klab_buildenv_capture_container "$provider" "$release" "$krel" "$arch" "$image" "$setup" "$bundle/packages" "$install" "$build" "$output"
}
klab_backend_yum_capture_buildenv(){
  local provider="$1" release="$2" krel="$3" bundle="$4" image="$5" setup="$6" output="$7" arch="$8"
  local build="/usr/src/kernels/$krel" install='yum -qy install yum-utils gcc make bc kmod elfutils-libelf-devel openssl-devel bash coreutils findutils gawk grep sed >/dev/null
rpms=""
for p in /pkgs/*.rpm; do
  [ -e "$p" ] || continue
  b=$(basename "$p")
  case "$b" in kernel-devel-*|kernel-headers-*) rpms="$rpms $p" ;; esac
done
[ -n "$rpms" ] || { echo "kernel-devel/header RPM missing from bundle" >&2; exit 41; }
yum -qy localinstall $rpms >/dev/null'
  KLAB_BUILDENV_DEPENDENCY_CAPTURE_COMMAND="KLAB_RPM_DEPENDENCY_DOWNLOADER=yumdownloader
export KLAB_RPM_DEPENDENCY_DOWNLOADER
$(klab_backend_dnf_dependency_capture_script)" \
  KLAB_BUILDENV_DEPENDENCY_REPOSITORY_URL="rpm://$provider/$release" \
    klab_buildenv_capture_container "$provider" "$release" "$krel" "$arch" "$image" "$setup" "$bundle/packages" "$install" "$build" "$output"
}

klab_backend_dnf_capture_toolchain(){
  local provider="$1" release="$2" image="$3" setup="$4" out="$5" arch="$6" owner; owner="$(klab_backend_rpm_host_owner)"
  mkdir -p "$out/packages"; rm -f "$out/packages"/*.rpm "$out"/*.tsv "$out"/*.json 2>/dev/null || true
  klab_provider_run_container "$provider" "$image" -v "$out:/out" bash -lc "$setup
set -eu
dnf -qy install dnf-plugins-core gcc binutils make python3 >/dev/null
dnf -qy download --resolve --alldeps --destdir /out/packages gcc binutils make
rpm -qp --qf '%{NAME}\\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\\t%{ARCH}\\n' /out/packages/*.rpm | LC_ALL=C sort -u > /out/packages.tsv
python3 - <<'PY' >/out/compiler.json
import json,re,subprocess
def one(*a): return subprocess.check_output(a,text=True,stderr=subprocess.DEVNULL).splitlines()[0].strip()
def ver(t):
 s=one(t,'--version'); m=re.search(r'([0-9]+(?:\\.[0-9]+){1,3})',s); return m.group(1) if m else s
print(json.dumps({'cc_path':'/usr/bin/gcc','cc_version':(lambda: (one('gcc','-dumpfullversion') if subprocess.run(['gcc','-dumpfullversion'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0 else one('gcc','-dumpversion')))(),'cc_target':one('gcc','-dumpmachine'),'as_path':'/usr/bin/as','as_version':ver('as'),'ld_path':'/usr/bin/ld','ld_version':ver('ld')},sort_keys=True))
PY
python3 - <<'PYPROV' >/out/provenance.json
import glob,hashlib,json,os,subprocess
files=sorted(glob.glob('/etc/yum.repos.d/*.repo'))
repo=''.join('### '+f+'\n'+open(f).read()+'\n' for f in files if os.path.isfile(f))
try: keys=subprocess.check_output(['rpm','-qa','gpg-pubkey','--qf','%{NAME}-%{VERSION}-%{RELEASE}\n']).decode()
except Exception: keys=''
h=lambda s:hashlib.sha256(s.encode()).hexdigest()
meta=[]
for root in ('/var/cache/yum','/var/cache/dnf'):
 for dp,dn,fn in os.walk(root):
  if 'repomd.xml' in fn:
   f=os.path.join(dp,'repomd.xml'); b=open(f,'rb').read(); meta.append([f,hashlib.sha256(b).hexdigest()])
meta.sort()
sigs=[]
for f in sorted(glob.glob('/out/packages/*.rpm')):
 r=subprocess.Popen(['rpm','-Kv',f],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 out=r.communicate()[0].decode('utf-8','replace').strip()
 # rpm -Kv exits nonzero for a bad/unverifiable signature.  Preserve its
 # complete diagnostic as evidence; artifact validation refuses false status.
 sig_ok=(r.returncode==0 and ('openpgp' in out.lower() or 'pgp' in out.lower() or 'rsa' in out.lower()) and 'OK' in out and 'NOKEY' not in out and 'NOT OK' not in out)
 sigs.append({'file':os.path.basename(f),'sha256':hashlib.sha256(open(f,'rb').read()).hexdigest(),'verified':sig_ok,'evidence':out})
print(json.dumps({'schema':'klab-repository-provenance-v1','provider':'$provider','release':'$release','repository_config_sha256':h(repo),'key_inventory_sha256':h(keys),'repository_metadata_sha256':h(json.dumps(meta,separators=(',',':'))),'repository_config':repo,'key_inventory':keys,'repository_metadata':meta,'package_signatures':sigs},sort_keys=True))
PYPROV
chown -R '$owner' /out"
  compgen -G "$out/packages/*.rpm" >/dev/null || die "distro toolchain capture produced no RPMs"; klab_backend_rpm_fix_owner "$out"; klab_backend_rpm_manifest "$out/packages"
}
klab_backend_yum_capture_toolchain(){
  local provider="$1" release="$2" image="$3" setup="$4" out="$5" arch="$6" owner; owner="$(klab_backend_rpm_host_owner)"
  mkdir -p "$out/packages"; rm -f "$out/packages"/*.rpm "$out"/*.tsv "$out"/*.json 2>/dev/null || true
  klab_provider_run_container "$provider" "$image" -v "$out:/out" bash -lc "$setup
set -eu
yum -y -q install yum-utils gcc binutils make >/dev/null
cd /out/packages
yumdownloader --resolve --destdir=/out/packages gcc binutils make
rpm -qp --qf '%{NAME}\\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\\t%{ARCH}\\n' /out/packages/*.rpm | LC_ALL=C sort -u > /out/packages.tsv
py=python3; command -v python3 >/dev/null 2>&1 || py=python
"\$py" - <<'PY' >/out/compiler.json
import json,re,subprocess
def one(*a): return subprocess.check_output(a,stderr=subprocess.STDOUT).decode().splitlines()[0].strip()
def ver(t):
 s=one(t,'--version'); m=re.search(r'([0-9]+(?:\\.[0-9]+){1,3})',s); return m.group(1) if m else s
print(json.dumps({'cc_path':'/usr/bin/gcc','cc_version':(lambda: (one('gcc','-dumpfullversion') if subprocess.call(['gcc','-dumpfullversion'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)==0 else one('gcc','-dumpversion')))(),'cc_target':one('gcc','-dumpmachine'),'as_path':'/usr/bin/as','as_version':ver('as'),'ld_path':'/usr/bin/ld','ld_version':ver('ld')},sort_keys=True))
PY
"\$py" - <<'PYPROV' >/out/provenance.json
import glob,hashlib,json,os,subprocess
files=sorted(glob.glob('/etc/yum.repos.d/*.repo'))
repo=''.join('### '+f+'\n'+open(f).read()+'\n' for f in files if os.path.isfile(f))
try: keys=subprocess.check_output(['rpm','-qa','gpg-pubkey','--qf','%{NAME}-%{VERSION}-%{RELEASE}\n']).decode()
except Exception: keys=''
h=lambda s:hashlib.sha256(s.encode()).hexdigest()
meta=[]
for root in ('/var/cache/yum','/var/cache/dnf'):
 for dp,dn,fn in os.walk(root):
  if 'repomd.xml' in fn:
   f=os.path.join(dp,'repomd.xml'); b=open(f,'rb').read(); meta.append([f,hashlib.sha256(b).hexdigest()])
meta.sort()
sigs=[]
for f in sorted(glob.glob('/out/packages/*.rpm')):
 r=subprocess.Popen(['rpm','-Kv',f],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 out=r.communicate()[0].decode('utf-8','replace').strip()
 # rpm -Kv exits nonzero for a bad/unverifiable signature.  Preserve its
 # complete diagnostic as evidence; artifact validation refuses false status.
 sig_ok=(r.returncode==0 and ('openpgp' in out.lower() or 'pgp' in out.lower() or 'rsa' in out.lower()) and 'OK' in out and 'NOKEY' not in out and 'NOT OK' not in out)
 sigs.append({'file':os.path.basename(f),'sha256':hashlib.sha256(open(f,'rb').read()).hexdigest(),'verified':sig_ok,'evidence':out})
print(json.dumps({'schema':'klab-repository-provenance-v1','provider':'$provider','release':'$release','repository_config_sha256':h(repo),'key_inventory_sha256':h(keys),'repository_metadata_sha256':h(json.dumps(meta,separators=(',',':'))),'repository_config':repo,'key_inventory':keys,'repository_metadata':meta,'package_signatures':sigs},sort_keys=True))
PYPROV
chown -R '$owner' /out"
  compgen -G "$out/packages/*.rpm" >/dev/null || die "distro toolchain capture produced no RPMs"; klab_backend_rpm_fix_owner "$out"; klab_backend_rpm_manifest "$out/packages"
}
