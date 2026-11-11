#!/usr/bin/env bash
# Generic APT repository backend, provider API v2.

klab_backend_deb_arch(){ case "${1:-${ARCH:-x86_64}}" in x86_64|amd64) echo amd64;; i386|x86) echo i386;; aarch64|arm64) echo arm64;; armv7|armhf) echo armhf;; *) die "no Debian architecture mapping for $1";; esac; }
klab_backend_fix_owner(){ local p="$1"; [[ -e "$p" ]] || return 0; [[ "$(id -u)" == 0 ]] && return 0; chown -R "$(id -u):$(id -g)" "$p" 2>/dev/null || true; }
klab_backend_host_owner(){ klab_provider_bind_output_owner; }
klab_backend_package_manifest(){ local dir="$1"; (cd "$dir" && for f in *.deb; do [[ -f "$f" ]] || continue; sha256sum -- "$f"; done | LC_ALL=C sort -k2) >"$dir/PACKAGES.sha256"; }

klab_backend_apt_list(){
  local provider="$1" image="$2" setup="$3" regex="$4" pattern="${5:-}" qregex qpattern filter=''
  printf -v qregex '%q' "$regex"
  if [[ -n "$pattern" ]]; then printf -v qpattern '%q' "$pattern"; filter=" | grep -F -- $qpattern"; fi
  klab_provider_run_container "$provider" "$image" bash -lc "$setup
# dumpavail lists only repository-backed package records and avoids one
# apt-cache subprocess per historical ABI package.
apt-cache dumpavail | awk -v RS= -F '\\n' '{ for (i=1; i<=NF; i++) if (\$i ~ /^Package: /) { print substr(\$i,10); break } }' | grep -E -- $qregex | sed 's/^linux-image-//' | sort -V$filter | tail -n 2000"
}

klab_backend_apt_verify_arch(){ local provider="$1" image="$2" packages="$3" expected; expected="$(klab_backend_deb_arch "${ARCH:-x86_64}")"; klab_provider_run_container "$provider" "$image" -v "$packages:/pkgs:ro" bash -lc "set -eu; for p in /pkgs/*.deb; do [ -e \"\$p\" ] || continue; a=\$(dpkg-deb -f \"\$p\" Architecture); case \"\$a\" in all|$expected) ;; *) echo \"wrong package architecture: \$p -> \$a (expected $expected)\" >&2; exit 44;; esac; done"; }
klab_backend_apt_verify_kernel_identity(){
  local provider="$1" image="$2" packages="$3" krel="$4"
  klab_provider_run_container "$provider" "$image" -v "$packages:/pkgs:ro" bash -lc "set -eu
found=0
for p in /pkgs/*.deb; do
  [ -e \"\$p\" ] || continue
  n=\$(dpkg-deb -f \"\$p\" Package)
  case \"\$n\" in
    linux-image-$krel|linux-image-unsigned-$krel) found=1 ;;
  esac
done
[ \"\$found\" = 1 ] || { echo 'downloaded DEBs do not contain the exact requested kernel image $krel' >&2; exit 46; }"
}


klab_backend_apt_fetch(){
  local provider="$1" release="$2" krel="$3" bundle="$4" image="$5" setup="$6" packages="$bundle/packages" root="$bundle/root" owner; owner="$(klab_backend_host_owner)"
  mkdir -p "$packages"; rm -f "$packages"/*.deb "$packages/PACKAGES.sha256" 2>/dev/null || true
  say "Downloading $provider $release kernel $krel"
  klab_provider_run_container "$provider" "$image" -v "$packages:/out" bash -lc "$setup
mkdir -p /out/partial
pkgs=''
have_candidate() {
  c=\$(apt-cache policy \"\$1\" | sed -n 's/^[[:space:]]*Candidate:[[:space:]]*//p' | head -n1)
  [ -n \"\$c\" ] && [ \"\$c\" != '(none)' ]
}
# Signed and unsigned image packages for the same ABI conflict. Prefer the
# signed image and use unsigned only when it has an installable candidate.
if have_candidate \"linux-image-$krel\"; then
  pkgs=\"\$pkgs linux-image-$krel\"
elif have_candidate \"linux-image-unsigned-$krel\"; then
  pkgs=\"\$pkgs linux-image-unsigned-$krel\"
else
  echo 'no installable kernel image candidate for $krel' >&2; exit 40
fi
# The exact flavour headers are required for external-module testing.
have_candidate \"linux-headers-$krel\" || { echo 'no installable exact headers candidate for $krel' >&2; exit 40; }
pkgs=\"\$pkgs linux-headers-$krel\"
# Modules and modules-extra are optional split packages.
for p in linux-modules-$krel linux-modules-extra-$krel; do have_candidate \"\$p\" && pkgs=\"\$pkgs \$p\" || true; done
if [ '${ARCH:-x86_64}' = aarch64 ]; then
  base='${krel%-generic}'
  have_candidate \"linux-headers-\$base\" && pkgs=\"\$pkgs linux-headers-\$base\" || true
  specs=''
  for p in \$pkgs; do
    a=\$(apt-cache show \"\$p\" 2>/dev/null | sed -n 's/^Architecture:[[:space:]]*//p' | head -n1)
    case \"\$a\" in arm64) specs=\"\$specs \$p:arm64\";; all) specs=\"\$specs \$p\";; *) echo \"unsupported ARM64 package architecture: \$p -> \${a:-missing}\" >&2; exit 44;; esac
  done
  (cd /out && apt-get download \$specs)
else
  DEBIAN_FRONTEND=noninteractive apt-get -y --download-only --no-install-recommends -o Dir::Cache::archives=/out install \$pkgs
fi
rm -rf /out/lock /out/partial
chown -R '$owner' /out"
  compgen -G "$packages/*.deb" >/dev/null || die "no .deb files were downloaded"
  klab_backend_fix_owner "$packages"; klab_backend_apt_verify_arch "$provider" "$image" "$packages"; klab_backend_apt_verify_kernel_identity "$provider" "$image" "$packages" "$krel"; klab_backend_package_manifest "$packages"
  write_package_manifest "$bundle" 2>/dev/null || true
  extract_debs "$packages" "$root" "$image"; normalize_bundle "$provider" "$release" "$krel" "$bundle" "$image"
}

klab_backend_apt_build_module(){ local provider="$1" image="$2" setup="$3" packages="$4" krel="$5" module_dir="$6" jobs="$7"; klab_provider_run_container "$provider" "$image" -v "$packages:/pkgs:ro" -v "$module_dir:/module" bash -lc "$setup
modpkg=kmod; apt-cache policy kmod | grep -q 'Candidate: (none)' && modpkg=module-init-tools || true
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential bc \"\$modpkg\" libelf-dev libssl-dev flex bison >/dev/null
files=''; for p in /pkgs/*.deb; do [ -e \"\$p\" ] || continue; b=\$(basename \"\$p\"); case \"\$b\" in linux-image-*|linux-modules-*) ;; *) files=\"\$files \$p\";; esac; done
[ -n \"\$files\" ] || { echo 'no kernel header/build packages available' >&2; exit 41; }
dpkg -i \$files >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get -f install -y -qq >/dev/null
kdir=/usr/src/linux-headers-$krel; [ -d \"\$kdir\" ] || kdir=/lib/modules/$krel/build; [ -e \"\$kdir\" ] || { echo 'kernel header build tree not installed' >&2; exit 41; }
make -C \"\$kdir\" M=/module -j$jobs modules
ko=\$(find /module -name '*.ko' -print -quit); [ -n \"\$ko\" ] || { echo 'module build produced no .ko' >&2; exit 43; }
vm=\$(modinfo -F vermagic \"\$ko\" 2>/dev/null || true); case \"\$vm\" in '$krel '*) ;; *) echo \"module vermagic mismatch: \${vm:-missing} != $krel\" >&2; exit 42;; esac
chown -R $(id -u):$(id -g) /module"; }

# Foreign-architecture Ubuntu headers ship target-native Kbuild helpers. Work
# on a temporary copy and rebuild only those helpers for the host.
klab_backend_apt_cross_build_module(){
  local krel="$1" module_dir="$2" jobs="$3" build_dir="$4" arch="$5"
  local sdk cc prefix tmp common copied_build ko vm obj src
  [[ "$arch" == aarch64 ]] || die "unsupported APT host cross-module architecture: $arch"
  [[ -d "$build_dir" ]] || die "cross-module kernel build tree is missing: $build_dir"
  declare -F cross_sdk_for_arch >/dev/null || die "cross-module SDK resolver is unavailable"
  sdk="$(cross_sdk_for_arch "$arch" minimal)"
  cc="$(sdk_compiler "$sdk")"; prefix="${cc%gcc}"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/klab-cross-module.XXXXXX")"
  common="$(readlink -f "$build_dir/scripts/basic/fixdep.c")"
  common="${common%/scripts/basic/fixdep.c}"
  if [[ "$common" == "$build_dir" ]]; then
    cp -a --reflink=auto "$build_dir" "$tmp/"
  else
    cp -a --reflink=auto "$common" "$build_dir" "$tmp/"
  fi
  copied_build="$tmp/$(basename "$build_dir")"
  if (
    cd "$copied_build"
    gcc -O2 -Wall -Wmissing-prototypes -Wstrict-prototypes -o scripts/basic/fixdep scripts/basic/fixdep.c
    if [[ -f scripts/recordmcount.c ]]; then
      gcc -O2 -Wall -Wmissing-prototypes -Wstrict-prototypes -o scripts/recordmcount scripts/recordmcount.c
    fi
    local -a modpost_objects=()
    while IFS= read -r obj; do modpost_objects+=("scripts/mod/$obj"); done < <(
      sed -n 's/^modpost-objs[[:space:]]*:=[[:space:]]*//p' scripts/mod/Makefile | tr ' ' '\n' | sed '/^$/d'
    )
    ((${#modpost_objects[@]} > 0)) || die "cannot determine modpost objects for $krel"
    for obj in "${modpost_objects[@]}"; do
      src="${obj%.o}.c"
      gcc -O2 -Wall -Wmissing-prototypes -Wstrict-prototypes -I scripts/mod -c "$src" -o "$obj"
    done
    gcc -o scripts/mod/modpost "${modpost_objects[@]}"
    PATH="$sdk/bin:$PATH" make -C "$copied_build" ARCH=arm64 CROSS_COMPILE="$prefix" CC="$cc" HOSTCC=gcc M="$module_dir" -j"$jobs" modules
  ); then
    :
  else
    local rc=$?
    rm -rf "$tmp"
    return "$rc"
  fi
  ko="$(find "$module_dir" -name '*.ko' -print -quit)"
  [[ -n "$ko" ]] || { rm -rf "$tmp"; die "cross-module build produced no .ko"; }
  vm="$(modinfo -F vermagic "$ko" 2>/dev/null || true)"
  case "$vm" in "$krel "*) ;; *) rm -rf "$tmp"; die "module vermagic mismatch: ${vm:-missing} != $krel";; esac
  rm -rf "$tmp"
}

klab_backend_apt_capture_buildenv(){
  local provider="$1" release="$2" krel="$3" bundle="$4" image="$5" setup="$6" output="$7" arch="$8"
  local build="/usr/src/linux-headers-$krel" compiler_version="${KLAB_BUILDENV_REQUIRED_GCC_VERSION:-}" cc_pkg=gcc cc_bin=gcc install
  if [[ -n "$compiler_version" ]]; then
    local major="${compiler_version%%.*}" minor="" candidate
    [[ "$compiler_version" == *.* ]] && minor="${compiler_version#*.}" && minor="${minor%%.*}"
    if [[ -n "$minor" ]]; then cc_pkg="gcc-$major.$minor"; else cc_pkg="gcc-$major"; fi
    cc_bin="$cc_pkg"
    # Some historical Ubuntu/Debian releases package compilers as gcc-X.Y,
    # while others expose only gcc-X or the default gcc. Resolve at runtime.
  fi
  install="DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dpkg >/dev/null; DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -qq >/dev/null; modpkg=kmod; apt-cache policy kmod | grep -q 'Candidate: (none)' && modpkg=module-init-tools || true; cc_pkg='$cc_pkg'; cc_bin='$cc_bin'; reqver='$compiler_version'; major='${compiler_version%%.*}'; minor=''; case \"\$reqver\" in *.*) minor=\${reqver#*.}; minor=\${minor%%.*};; esac; if [ -n \"\$reqver\" ]; then for candidate in \"gcc-\$major.\$minor\" \"gcc-\$major\" gcc; do c=\$(apt-cache policy \"\$candidate\" | sed -n 's/^[[:space:]]*Candidate:[[:space:]]*//p' | head -n1); if [ -n \"\$c\" ] && [ \"\$c\" != '(none)' ]; then cc_pkg=\$candidate; cc_bin=\$candidate; break; fi; done; fi; c=\$(apt-cache policy \"\$cc_pkg\" | sed -n 's/^[[:space:]]*Candidate:[[:space:]]*//p' | head -n1); [ -n \"\$c\" ] && [ \"\$c\" != '(none)' ] || { echo \"required compiler package has no candidate: \$cc_pkg\" >&2; exit 48; }; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential \"\$cc_pkg\" bc \$modpkg libelf-dev libssl-dev flex bison pahole >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential \"\$cc_pkg\" bc \$modpkg libelf-dev libssl-dev flex bison >/dev/null; dpkg -i /pkgs/*.deb >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get -f install -y -qq >/dev/null; if [ -d /klab-distro-toolchain-packages ]; then dpkg -i /klab-distro-toolchain-packages/*.deb >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get -f install -y -qq >/dev/null; fi; resolved_cc=; for candidate in \"\$cc_bin\" \"gcc-\$major.\$minor\" \"gcc-\$major\" gcc; do [ -n \"\$candidate\" ] || continue; candidate_path=\$(command -v \"\$candidate\" 2>/dev/null || true); if [ -n \"\$candidate_path\" ] && [ -x \"\$candidate_path\" ]; then resolved_cc=\$candidate_path; break; fi; done; [ -n \"\$resolved_cc\" ] || { echo 'installed GCC executable could not be resolved' >&2; exit 49; }; mkdir -p /usr/local/bin; ln -sf \"\$resolved_cc\" /usr/local/bin/klab-native-cc"
  KLAB_BUILDENV_NATIVE_CC="/usr/local/bin/klab-native-cc" \
  KLAB_BUILDENV_DEPENDENCY_CAPTURE_COMMAND="$(klab_backend_apt_dependency_capture_script)" \
  KLAB_BUILDENV_DEPENDENCY_REPOSITORY_URL="apt://$provider/$release" \
    klab_buildenv_capture_container "$provider" "$release" "$krel" "$arch" "$image" "$setup" "$bundle/packages" "$install" "$build" "$output"
}

klab_backend_apt_capture_toolchain(){
  local provider="$1" release="$2" image="$3" setup="$4" out="$5" arch="$6" compiler_version="${7:-}" owner cc_pkg=gcc cc_bin=gcc
  if [[ -n "$compiler_version" ]]; then cc_pkg="gcc-${compiler_version%%.*}"; cc_bin="$cc_pkg"; fi
  owner="$(klab_backend_host_owner)"; mkdir -p "$out/packages"; rm -f "$out/packages"/*.deb "$out"/*.tsv "$out"/*.json 2>/dev/null || true
  klab_provider_run_container "$provider" "$image" -v "$out:/out" bash -lc "$setup
set -eu
# EOL repositories may require disabling Release-file expiry checks, but that
# must never be conflated with disabling APT authentication. Fail closed if
# the provider/setup layer has enabled a known insecure repository/package
# bypass before capturing compiler provenance.
aptcfg=\$(apt-config dump 2>/dev/null || true)
printf '%s\n' "\$aptcfg" | tr -d '\"' | grep -Eiq 'APT::Get::AllowUnauthenticated[[:space:]]+true|Acquire::AllowInsecureRepositories[[:space:]]+true|Acquire::AllowDowngradeToInsecureRepositories[[:space:]]+true' && { echo 'insecure APT authentication override is forbidden for distro-toolchain capture' >&2; exit 45; } || true
cc_pkg='$cc_pkg'; cc_bin='$cc_bin'
apt-cache show "\$cc_pkg" >/dev/null 2>&1 || { cc_pkg=gcc; cc_bin=gcc; }
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "\$cc_pkg" binutils make python3 >/dev/null
# Resolve the package dependency graph using the historical distribution's own
# APT metadata. Package headings emitted by apt-cache are concrete packages;
# virtual-only nodes are ignored by apt-cache show below.
pkgs=\$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "\$cc_pkg" binutils make 2>/dev/null | awk '/^[^ <>][^ ]*$/ {print \$1}' | sort -u)
: > /out/packages.tsv
for p in \$pkgs; do
  apt-cache show \"\$p\" >/dev/null 2>&1 || continue
  # Prefer the authenticated repository candidate over stale installed-only versions.
  v=\$(apt-cache policy \"\$p\" | sed -n 's/^[[:space:]]*Candidate:[[:space:]]*//p' | head -n1)
  [ -n \"\$v\" ] && [ \"\$v\" != '(none)' ] || v=\$(dpkg-query -W -f='\${Version}' \"\$p\" 2>/dev/null || true)
  a=\$(apt-cache show \"\$p=\$v\" 2>/dev/null | sed -n 's/^Architecture:[[:space:]]*//p' | head -n1)
  [ -n \"\$a\" ] || a=\$(dpkg-query -W -f='\${Architecture}' \"\$p\" 2>/dev/null || true)
  native=\$(dpkg --print-architecture)
  case \"\$a\" in \"\$native\"|all) ;; *) continue;; esac
  [ -n \"\$v\" ] && [ \"\$v\" != '(none)' ] || continue
  printf '%s\\t%s\\t%s\\n' \"\$p\" \"\$v\" \"\$a\" >> /out/packages.tsv
done
sort -u -o /out/packages.tsv /out/packages.tsv
# Force exact installed versions into the download cache, including packages
# already present in the provider image.
while IFS=\$(printf '\\t') read -r p v a; do
  DEBIAN_FRONTEND=noninteractive apt-get -y -qq --download-only --reinstall -o Dir::Cache::archives=/out/packages install \"\$p=\$v\" >/dev/null 2>&1 || \
    (cd /out/packages && apt-get download \"\$p=\$v\" >/dev/null 2>&1)
done < /out/packages.tsv
rm -rf /out/packages/partial /out/packages/lock
: > /out/archives.tsv
for f in /out/packages/*.deb; do
  [ -e "\$f" ] || continue
  p=\$(dpkg-deb -f "\$f" Package); v=\$(dpkg-deb -f "\$f" Version); a=\$(dpkg-deb -f "\$f" Architecture)
  printf '%s\t%s\t%s\n' "\$p" "\$v" "\$a" >> /out/archives.tsv
done
LC_ALL=C sort -u -o /out/archives.tsv /out/archives.tsv
# APT may add concrete dependencies that older apt-cache depends output omits.
# No requested package may disappear, and every additional archive becomes part
# of the authenticated captured closure rather than being ignored.
missing=\$(comm -23 /out/packages.tsv /out/archives.tsv)
[ -z "\$missing" ] || { echo 'requested APT closure packages are missing from downloaded archives' >&2; printf '%s\n' "\$missing" >&2; exit 44; }
cp /out/archives.tsv /out/packages.tsv
# Bind every retained DEB to the SHA-256 advertised by the exact APT package
# stanza selected for its name/version/architecture. apt-get update has already
# authenticated the Release/InRelease chain; this records the final Packages ->
# archive link rather than merely remembering that some repository metadata was
# present during capture.
: > /out/apt-package-metadata.tsv
while IFS=\$(printf '\t') read -r p v a; do
  stanza=\$(apt-cache show \"\$p=\$v\" 2>/dev/null | awk -v a=\"\$a\" 'BEGIN{RS=\"\";FS=\"\\n\"} {ok=0; for(i=1;i<=NF;i++) if(\$i==\"Architecture: \" a) ok=1; if(ok){print; exit}}')
  [ -n \"\$stanza\" ] || { echo \"APT metadata stanza missing for \$p=\$v [\$a]\" >&2; exit 46; }
  # Prefer the strongest digest advertised by the authenticated Packages
  # stanza. Very old distributions may predate SHA256 package fields.
  malg=; mdigest=
  for candidate in SHA256 SHA1 MD5sum; do
    value=\$(printf '%s\\n' \"\$stanza\" | sed -n \"s/^\$candidate:[[:space:]]*//p\" | head -n1)
    [ -n \"\$value\" ] || continue
    malg=\$candidate; mdigest=\$value; break
  done
  case \"\$malg:\${#mdigest}\" in SHA256:64|SHA1:40|MD5sum:32) ;; *) echo \"APT metadata digest missing or malformed for \$p=\$v [\$a]\" >&2; exit 46;; esac
  f=\$(find /out/packages -maxdepth 1 -type f -name '*.deb' -print | while read q; do
    qp=\$(dpkg-deb -f \"\$q\" Package); qv=\$(dpkg-deb -f \"\$q\" Version); qa=\$(dpkg-deb -f \"\$q\" Architecture)
    [ \"\$qp\" = \"\$p\" ] && [ \"\$qv\" = \"\$v\" ] && [ \"\$qa\" = \"\$a\" ] && { basename \"\$q\"; break; }
  done)
  [ -n \"\$f\" ] || { echo \"retained DEB missing for \$p=\$v [\$a]\" >&2; exit 46; }
  asha=\$(sha256sum \"/out/packages/\$f\" | awk '{print \$1}')
  case \"\$malg\" in
    SHA256) actual=\$asha ;;
    SHA1) actual=\$(sha1sum \"/out/packages/\$f\" | awk '{print \$1}') ;;
    MD5sum) actual=\$(md5sum \"/out/packages/\$f\" | awk '{print \$1}') ;;
  esac
  [ \"\$actual\" = \"\$mdigest\" ] || { echo \"APT metadata/archive \$malg mismatch for \$p=\$v [\$a]\" >&2; exit 47; }
  # Record the authenticated link and an independent KLab SHA256 binding.
  printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"\$p\" \"\$v\" \"\$a\" \"\$f\" \"\$malg\" \"\$mdigest\" \"\$asha\" >> /out/apt-package-metadata.tsv
done < /out/packages.tsv
LC_ALL=C sort -u -o /out/apt-package-metadata.tsv /out/apt-package-metadata.tsv
if ! cmp -s /out/packages.tsv /out/archives.tsv; then
  echo 'captured DEB archive closure does not exactly match resolved installed package inventory' >&2
  diff -u /out/packages.tsv /out/archives.tsv >&2 || true
  exit 44
fi
KLAB_CC_BIN="\$cc_bin" python3 - <<'PY' >/out/compiler.json
import json,os,subprocess
devnull=open(os.devnull,'wb')
def one(*a): return subprocess.check_output(a,universal_newlines=True,stderr=devnull).splitlines()[0].strip()
def ver(tool):
 s=one(tool,'--version')
 import re
 m=re.search(r'([0-9]+(?:\\.[0-9]+){1,3})',s)
 return m.group(1) if m else s
def ccver(tool):
 import re
 try: full=one(tool,'-dumpfullversion')
 except Exception: full=''
 if re.match(r'^[0-9]+(?:\\.[0-9]+){2,3}$',full): return full
 banner=one(tool,'--version'); m=re.search(r'([0-9]+(?:\\.[0-9]+){2,3})',banner)
 return m.group(1) if m else one(tool,'-dumpversion')
cc=os.environ.get('KLAB_CC_BIN','gcc')
print(json.dumps({'cc_path':'/usr/bin/'+cc,'cc_version':ccver(cc),'cc_target':one(cc,'-dumpmachine'),'as_path':'/usr/bin/as','as_version':ver('as'),'ld_path':'/usr/bin/ld','ld_version':ver('ld')},sort_keys=True))
PY
python3 - <<'PYPROV' >/out/provenance.json
import glob,hashlib,json,subprocess
files=['/etc/apt/sources.list']+sorted(glob.glob('/etc/apt/sources.list.d/*.list'))+sorted(glob.glob('/etc/apt/sources.list.d/*.sources'))
repo=''.join('### '+f+'\n'+open(f,errors='replace').read()+'\n' for f in files if __import__('os').path.isfile(f))
try: keys=subprocess.check_output(['apt-key','finger'],stderr=subprocess.STDOUT,universal_newlines=True)
except Exception: keys=''
h=lambda s:hashlib.sha256(s.encode()).hexdigest()
meta=[]
for f in sorted(glob.glob('/var/lib/apt/lists/*')):
 if __import__('os').path.isfile(f):
  b=open(f,'rb').read(); meta.append([__import__('os').path.basename(f),hashlib.sha256(b).hexdigest()])
aptpk=[]
for line in open('/out/apt-package-metadata.tsv'):
 n,v,a,f,alg,d,sha=line.rstrip('\n').split('\t'); aptpk.append({'name':n,'version':v,'arch':a,'file':f,'metadata_digest_algorithm':alg,'metadata_digest':d,'sha256':sha})
print(json.dumps({'schema':'klab-repository-provenance-v1','provider':'$provider','release':'$release','repository_config_sha256':h(repo),'key_inventory_sha256':h(keys),'repository_metadata_sha256':h(json.dumps(meta,separators=(',',':'))),'repository_config':repo,'key_inventory':keys,'repository_metadata':meta,'apt_package_metadata':aptpk},sort_keys=True))
PYPROV
chown -R '$owner' /out"
  compgen -G "$out/packages/*.deb" >/dev/null || die "distro toolchain capture produced no DEBs"
  klab_backend_fix_owner "$out"; klab_backend_package_manifest "$out/packages"
}

klab_backend_apt_dependency_capture_script(){ cat <<'EOS'
set -eu
out=${KLAB_DEPENDENCY_CAPTURE_OUT:-/klab-dependency-capture}
mkdir -p "$out/packages"
rm -f "$out/packages"/*.deb "$out/packages/PACKAGES.sha256" "$out/requested.tsv" "$out/archives.tsv" "$out/repository-state.tar" 2>/dev/null || true
aptcfg=$(apt-config dump 2>/dev/null || true)
printf '%s\n' "$aptcfg" | tr -d '"' | grep -Eiq 'APT::Get::AllowUnauthenticated[[:space:]]+true|Acquire::AllowInsecureRepositories[[:space:]]+true|Acquire::AllowDowngradeToInsecureRepositories[[:space:]]+true' && {
  echo 'insecure APT authentication override is forbidden for dependency closure capture' >&2; exit 45;
} || true
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort -u > "$out/requested.tsv"
while IFS=$(printf '\t') read -r package version arch; do
  [ -n "$package" ] && [ -n "$version" ] && [ -n "$arch" ] || { echo 'malformed installed package row' >&2; exit 46; }
  case "$arch" in all) spec="$package=$version";; *) spec="$package:$arch=$version";; esac
  DEBIAN_FRONTEND=noninteractive apt-get -y -qq --download-only --reinstall --no-install-recommends \
    -o Dir::Cache::archives="$out/packages" install "$spec" >/dev/null 2>&1 || true
  found=0
  for candidate in "$out/packages"/*.deb; do
    [ -f "$candidate" ] || continue
    [ "$(dpkg-deb -f "$candidate" Package)" = "$package" ] || continue
    [ "$(dpkg-deb -f "$candidate" Version)" = "$version" ] || continue
    [ "$(dpkg-deb -f "$candidate" Architecture)" = "$arch" ] || continue
    found=1; break
  done
  if [ "$found" != 1 ]; then
    for source_dir in /pkgs /klab-distro-toolchain-packages; do
      [ -d "$source_dir" ] || continue
      for candidate in "$source_dir"/*.deb; do
        [ -f "$candidate" ] || continue
        [ "$(dpkg-deb -f "$candidate" Package)" = "$package" ] || continue
        [ "$(dpkg-deb -f "$candidate" Version)" = "$version" ] || continue
        [ "$(dpkg-deb -f "$candidate" Architecture)" = "$arch" ] || continue
        cp "$candidate" "$out/packages/"
        found=1
        break 2
      done
    done
  fi
  if [ "$found" != 1 ]; then
    (cd "$out/packages" && apt-get download "$spec" >/dev/null 2>&1) || {
      echo "exact installed dependency archive unavailable: $package=$version [$arch]" >&2; exit 47;
    }
  fi
done < "$out/requested.tsv"
rm -rf "$out/packages/partial" "$out/packages/lock"
: > "$out/archives.tsv"
for archive in "$out/packages"/*.deb; do
  [ -f "$archive" ] || continue
  package=$(dpkg-deb -f "$archive" Package)
  version=$(dpkg-deb -f "$archive" Version)
  arch=$(dpkg-deb -f "$archive" Architecture)
  printf '%s\t%s\t%s\n' "$package" "$version" "$arch" >> "$out/archives.tsv"
done
LC_ALL=C sort -u -o "$out/archives.tsv" "$out/archives.tsv"
if ! cmp -s "$out/requested.tsv" "$out/archives.tsv"; then
  echo 'downloaded APT dependency closure differs from installed inventory' >&2
  diff -u "$out/requested.tsv" "$out/archives.tsv" >&2 || true
  exit 48
fi
set --
[ -f /etc/apt/sources.list ] && set -- "$@" etc/apt/sources.list
[ -d /etc/apt/sources.list.d ] && set -- "$@" etc/apt/sources.list.d
[ -d /var/lib/apt/lists ] && set -- "$@" var/lib/apt/lists
[ "$#" -gt 0 ] || { echo 'APT repository state is unavailable' >&2; exit 49; }
tar -C / -cf "$out/repository-state.tar" "$@" 2>/dev/null
EOS
}
