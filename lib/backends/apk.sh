#!/usr/bin/env bash
# Alpine APK repository backend.

klab_backend_apk_arch(){ case "${1:-${ARCH:-x86_64}}" in x86_64|amd64) echo x86_64;; aarch64|arm64) echo aarch64;; armv7|armv7l|armhf) echo armv7;; x86|i386|i486|i586|i686) echo x86;; *) die "no APK architecture mapping for $1";; esac; }
klab_backend_apk_owner(){ klab_provider_bind_output_owner; }
klab_backend_apk_manifest(){ local d="$1"; (cd "$d" && for f in *.apk; do [[ -f "$f" ]] || continue; sha256sum -- "$f"; done | LC_ALL=C sort -k2) >"$d/PACKAGES.sha256"; }
klab_backend_apk_list(){ local provider="$1" image="$2" setup="$3" pattern="${4:-}" qpattern='' filter=cat; [[ -z "$pattern" ]] || { printf -v qpattern '%q' "$pattern"; filter="grep -F -- $qpattern"; }; klab_provider_run_container "$provider" "$image" sh -lc "$setup
apk fetch --stdout linux-lts 2>/dev/null | tar -tzf - 2>/dev/null | sed -n 's#^lib/modules/\([^/]*\)/\$#\1#p' | sort -V | $filter"; }
klab_backend_apk_verify(){ local provider="$1" image="$2" packages="$3" krel="$4" expected; expected="$(klab_backend_apk_arch "${ARCH:-x86_64}")"; klab_provider_run_container "$provider" "$image" -v "$packages:/pkgs:ro" sh -lc "set -eu
found=0
for p in /pkgs/*.apk; do
  [ -e \"\$p\" ] || continue
  apk verify \"\$p\" >/dev/null
  a=\$(tar -xOf \"\$p\" .PKGINFO 2>/dev/null | sed -n 's/^arch = //p' | head -n1)
  case \"\$a\" in noarch|$expected) ;; *) echo \"wrong APK architecture: \$p -> \$a (expected $expected)\" >&2; exit 44;; esac
done
mkdir -p /tmp/klab-apk-root
for p in /pkgs/*.apk; do tar -xzf \"\$p\" -C /tmp/klab-apk-root 2>/dev/null || true; done
[ -d /tmp/klab-apk-root/lib/modules/$krel ] && found=1
[ \"\$found\" = 1 ] || { echo 'downloaded APKs do not contain exact kernel identity $krel' >&2; exit 46; }"; }
klab_backend_apk_fetch(){ local provider="$1" release="$2" krel="$3" bundle="$4" image="$5" setup="$6" packages="$bundle/packages" root="$bundle/root" owner; owner="$(klab_backend_apk_owner)"; mkdir -p "$packages" "$root"; rm -f "$packages"/*.apk "$packages/PACKAGES.sha256" 2>/dev/null || true; say "Downloading $provider $release kernel $krel"; klab_provider_run_container "$provider" "$image" -v "$packages:/out" sh -lc "$setup
set -eu
apk add --no-cache apk-tools >/dev/null
apk fetch --output /out linux-lts linux-lts-dev
chown -R '$owner' /out"; compgen -G "$packages/*.apk" >/dev/null || die "no APKs were downloaded"; klab_backend_apk_verify "$provider" "$image" "$packages" "$krel"; klab_backend_apk_manifest "$packages"; write_package_manifest "$bundle" 2>/dev/null || true; for p in "$packages"/*.apk; do tar -xzf "$p" -C "$root" 2>/dev/null || true; done; [[ ! -f "$root/boot/vmlinuz-lts" ]] || cp -f "$root/boot/vmlinuz-lts" "$root/boot/vmlinuz-$krel"; chmod -R u+rX "$root"; normalize_bundle "$provider" "$release" "$krel" "$bundle" "$image"; }
klab_backend_apk_build_module(){ local provider="$1" image="$2" setup="$3" packages="$4" krel="$5" module_dir="$6" jobs="$7" build_override="${8:-}" qbuild; printf -v qbuild '%q' "${build_override:-/usr/src/linux-headers-$krel}"; klab_provider_run_container "$provider" "$image" -v "$packages:/pkgs:ro" -v "$module_dir:/module" sh -lc "$setup
apk add --allow-untrusted /pkgs/*.apk >/dev/null
apk add --no-cache build-base bc kmod elfutils-dev openssl-dev flex bison >/dev/null
kdir=$qbuild; [ -d \"\$kdir\" ] || kdir=/lib/modules/$krel/build; [ -e \"\$kdir\" ] || { echo 'kernel header build tree not installed' >&2; exit 41; }
make -C \"\$kdir\" M=/module -j$jobs modules
ko=\$(find /module -name '*.ko' -print -quit); [ -n \"\$ko\" ] || exit 43
vm=\$(modinfo -F vermagic \"\$ko\" 2>/dev/null || true); case \"\$vm\" in '$krel '*) ;; *) echo \"module vermagic mismatch: \${vm:-missing} != $krel\" >&2; exit 42;; esac"; }
klab_backend_apk_dependency_capture_script(){ cat <<'EOS'
set -eu
out=${KLAB_DEPENDENCY_CAPTURE_OUT:-/klab-dependency-capture}
mkdir -p "$out/packages"
rm -f "$out/packages"/*.apk "$out/requested.tsv" "$out/requested-details.tsv" "$out/archives.tsv" "$out/archive-identities.tsv" "$out/repository-state.tar" 2>/dev/null || true
awk 'BEGIN{RS="";FS="\n"} {p=v=a=o=""; for(i=1;i<=NF;i++){if($i~/^P:/)p=substr($i,3);else if($i~/^V:/)v=substr($i,3);else if($i~/^A:/)a=substr($i,3);else if($i~/^o:/)o=substr($i,3)} if(p!=""&&v!=""&&a!=""){if(o=="")o=p; print p "\t" v "\t" a "\t" o}}' /lib/apk/db/installed | LC_ALL=C sort -u > "$out/requested-details.tsv"
cut -f1-3 "$out/requested-details.tsv" > "$out/requested.tsv"
cut -f2,4 "$out/requested-details.tsv" | LC_ALL=C sort -u | while IFS=$(printf '\t') read -r version origin; do
  [ -n "$origin" ] && [ -n "$version" ] || { echo 'malformed installed APK origin row' >&2; exit 46; }
  apk fetch --output "$out/packages" "$origin" >/dev/null || { echo "installed dependency origin archive unavailable: $origin=$version" >&2; exit 47; }
  found=0
  for candidate in "$out/packages"/*.apk; do
    [ -f "$candidate" ] || continue
    info=$(tar -xOf "$candidate" .PKGINFO 2>/dev/null || true)
    n=$(printf '%s\n' "$info" | sed -n 's/^pkgname = //p' | head -n1)
    v=$(printf '%s\n' "$info" | sed -n 's/^pkgver = //p' | head -n1)
    [ "$n" = "$origin" ] && [ "$v" = "$version" ] && found=1 && break
  done
  [ "$found" = 1 ] || { echo "exact installed APK origin version unavailable: $origin=$version" >&2; exit 48; }
done
: > "$out/archives.tsv"; : > "$out/archive-identities.tsv"
for archive in "$out/packages"/*.apk; do
  [ -f "$archive" ] || continue
  apk verify "$archive" >/dev/null || { echo "APK signature verification failed: $archive" >&2; exit 49; }
  info=$(tar -xOf "$archive" .PKGINFO)
  origin=$(printf '%s\n' "$info" | sed -n 's/^pkgname = //p' | head -n1)
  version=$(printf '%s\n' "$info" | sed -n 's/^pkgver = //p' | head -n1)
  digest=$(sha256sum "$archive" | awk '{print $1}')
  awk -F '\t' -v o="$origin" -v v="$version" '$4==o && $2==v {print $1 "\t" $2 "\t" $3}' "$out/requested-details.tsv" | while IFS=$(printf '\t') read -r package installed_version arch; do
    [ -n "$package" ] || continue
    printf '%s\t%s\t%s\n' "$package" "$installed_version" "$arch" >> "$out/archives.tsv"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(basename "$archive")" "$digest" "$package" "$installed_version" "$arch" >> "$out/archive-identities.tsv"
  done
done
LC_ALL=C sort -u -o "$out/archives.tsv" "$out/archives.tsv"
LC_ALL=C sort -u -o "$out/archive-identities.tsv" "$out/archive-identities.tsv"
[ "$(sha256sum "$out/requested.tsv" | awk '{print $1}')" = "$(sha256sum "$out/archives.tsv" | awk '{print $1}')" ] || { echo 'downloaded APK dependency closure differs from installed inventory' >&2; exit 50; }
set -- /etc/apk/repositories /etc/apk/keys
[ ! -d /var/cache/apk ] || set -- "$@" /var/cache/apk
tar -cf "$out/repository-state.tar" "$@" 2>/dev/null
EOS
}
klab_backend_apk_capture_buildenv(){ local provider="$1" release="$2" krel="$3" bundle="$4" image="$5" setup="$6" output="$7" arch="$8" build install; build="/usr/src/linux-headers-$krel"; install="apk add --allow-untrusted /pkgs/*.apk >/dev/null; apk upgrade --available --no-cache >/dev/null; apk add --no-cache build-base bc kmod elfutils-dev openssl-dev flex bison bash coreutils findutils gawk grep sed tar >/dev/null"; KLAB_BUILDENV_DEPENDENCY_CAPTURE_COMMAND="$(klab_backend_apk_dependency_capture_script)" KLAB_BUILDENV_DEPENDENCY_REPOSITORY_URL="apk://$provider/$release" klab_buildenv_capture_container "$provider" "$release" "$krel" "$arch" "$image" "$setup" "$bundle/packages" "$install" "$build" "$output"; }
klab_backend_apk_capture_toolchain(){ local provider="$1" release="$2" image="$3" setup="$4" out="$5" arch="$6" owner; owner="$(klab_backend_apk_owner)"; mkdir -p "$out/packages"; klab_provider_run_container "$provider" "$image" -v "$out:/out" sh -lc "$setup
set -eu
apk add --no-cache gcc binutils make python3 >/dev/null
apk fetch --recursive --output /out/packages gcc binutils make
: > /out/packages.tsv
for p in /out/packages/*.apk; do n=\$(tar -xOf \"\$p\" .PKGINFO | sed -n 's/^pkgname = //p' | head -n1); v=\$(tar -xOf \"\$p\" .PKGINFO | sed -n 's/^pkgver = //p' | head -n1); a=\$(tar -xOf \"\$p\" .PKGINFO | sed -n 's/^arch = //p' | head -n1); printf '%s\t%s\t%s\n' \"\$n\" \"\$v\" \"\$a\"; done | sort -u > /out/packages.tsv
python3 - <<'PY' >/out/compiler.json
import json,re,subprocess
def one(*a): return subprocess.check_output(a,text=True,stderr=subprocess.DEVNULL).splitlines()[0].strip()
def ver(t):
 s=one(t,'--version'); m=re.search(r'([0-9]+(?:\\.[0-9]+){1,3})',s); return m.group(1) if m else s
print(json.dumps({'cc_path':'/usr/bin/gcc','cc_version':one('gcc','-dumpfullversion'),'cc_target':one('gcc','-dumpmachine'),'as_path':'/usr/bin/as','as_version':ver('as'),'ld_path':'/usr/bin/ld','ld_version':ver('ld')},sort_keys=True))
PY
python3 - <<'PYPROV' >/out/provenance.json
import glob,hashlib,json,os
config=open('/etc/apk/repositories').read() if os.path.exists('/etc/apk/repositories') else ''
keys=''.join(os.path.basename(f)+' '+hashlib.sha256(open(f,'rb').read()).hexdigest()+'\n' for f in sorted(glob.glob('/etc/apk/keys/*')) if os.path.isfile(f))
meta=[]
h=lambda b:hashlib.sha256(b if isinstance(b,bytes) else b.encode()).hexdigest()
print(json.dumps({'schema':'klab-repository-provenance-v1','provider':'$provider','release':'$release','repository_config':config,'repository_config_sha256':h(config),'key_inventory':keys,'key_inventory_sha256':h(keys),'repository_metadata':meta,'repository_metadata_sha256':h(json.dumps(meta,separators=(',',':')))},sort_keys=True))
PYPROV
chown -R '$owner' /out"; }
