#!/usr/bin/env bash
# Fedora provider: kernel payloads, compiler provenance, and historical build
# identity are all anchored to the exact Koji build that produced the kernel.
# Historical release containers are used only as execution roots; their live
# repositories are no longer the authority for compiler selection.

klab_provider_fedora_setup(){
  if klab_provider_mirror_only; then klab_provider_dnf_mirror_setup; else printf ':\n'; fi
}

klab_provider_fedora_list(){ provider_list_fedora "$@"; }
klab_provider_fedora_fetch(){ fetch_fedora_bundle "$1" "$2" "$3"; }
klab_provider_fedora_build_module(){ klab_backend_dnf_build_module fedora "$3" "$(klab_provider_fedora_setup)" "$4" "$2" "$5" "$6" "${7:-}"; }

klab_provider_fedora_koji_endpoints(){
  KLAB_FEDORA_EFFECTIVE_KOJI_HUB="${KLAB_FEDORA_KOJI_HUB:-https://koji.fedoraproject.org/kojihub}"
  KLAB_FEDORA_EFFECTIVE_KOJI_TOPURL="${KLAB_FEDORA_KOJI_TOPURL:-https://kojipkgs.fedoraproject.org/}"
  if klab_provider_mirror_only; then
    [[ -n "${KLAB_FEDORA_KOJI_HUB:-}" && -n "${KLAB_FEDORA_KOJI_TOPURL:-}" ]] || \
      die "mirror-only: Fedora Koji requires explicit KLAB_FEDORA_KOJI_HUB and KLAB_FEDORA_KOJI_TOPURL"
  fi
}

klab_provider_fedora_capture_toolchain(){
  local r="$1" out="$2" arch="$3" compiler_version="${4:-}" bundle manifest helper image hub topurl owner qhub qtop
  bundle="${KLAB_PROVIDER_TARGET_BUNDLE:-}"
  [[ -n "$bundle" && -d "$bundle" ]] || die "Fedora distro-toolchain capture requires an exact fetched kernel target (missing KLAB_PROVIDER_TARGET_BUNDLE)"
  manifest="$bundle/koji-buildroot.json"
  [[ -s "$manifest" ]] || die "Fedora target is missing Koji buildroot provenance: $manifest; re-fetch the target with this KLab version"
  helper="$SELF_DIR/lib/fedora_koji.py"; [[ -f "$helper" ]] || die "Fedora Koji metadata helper is missing: $helper"
  image="${KLAB_FEDORA_KOJI_IMAGE:-fedora:43}"
  klab_provider_fedora_koji_endpoints; hub="$KLAB_FEDORA_EFFECTIVE_KOJI_HUB"; topurl="$KLAB_FEDORA_EFFECTIVE_KOJI_TOPURL"
  printf -v qhub '%q' "$hub"; printf -v qtop '%q' "$topurl"
  owner="$(klab_provider_bind_output_owner)"
  mkdir -p "$out/packages"; rm -f "$out/packages"/*.rpm "$out"/*.tsv "$out"/*.json "$out"/*.txt 2>/dev/null || true
  python3 "$helper" toolchain-builds "$manifest" >"$out/koji-toolchain-builds.txt"
  [[ -s "$out/koji-toolchain-builds.txt" ]] || die "Koji buildroot did not resolve Fedora compiler/binutils/make builds"

  # Download the exact source-build outputs named by the kernel's own buildroot.
  # Do this with a modern Koji client, not with the historical release's DNF.
  run_container_root "$image" -v "$out:/out" bash -lc "set -eu
    dnf -qy install koji rpm >/dev/null 2>&1
    cd /out/packages
    while IFS= read -r nvr; do
      [ -n \"\$nvr\" ] || continue
      koji --server=$qhub --topurl=$qtop download-build --noprogress --arch=$arch --arch=noarch \"\$nvr\"
    done </out/koji-toolchain-builds.txt
    # Keep the executable compiler/linker suite and its same-build runtime
    # subpackages; discard language frontends/debug payloads that are unrelated
    # to external kernel-module builds.
    for f in /out/packages/*.rpm; do
      [ -e \"\$f\" ] || continue
      n=\$(rpm -qp --qf '%{NAME}' \"\$f\")
      case \"\$n\" in
        gcc|cpp|libgcc|libgomp|libstdc++|libstdc++-devel|libatomic|libquadmath|libquadmath-devel|libasan|libubsan|libtsan|libmpx|libmpx-devel|binutils|binutils-gold|make) ;;
        *) rm -f \"\$f\" ;;
      esac
    done
    compgen -G '/out/packages/*.rpm' >/dev/null
    rpm -qp --qf '%{NAME}\\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\\t%{ARCH}\\n' /out/packages/*.rpm | LC_ALL=C sort -u > /out/packages.tsv
    chown -R '$owner' /out"
  compgen -G "$out/packages/*.rpm" >/dev/null || die "Koji toolchain capture produced no RPMs"

  # Compiler identity is taken from the exact RPMs recorded in the kernel build
  # Koji buildroot.  Do not execute the old compiler in a half-assembled release
  # image here: its runtime dependency closure belongs to the buildenv assembly
  # step, where the package manager can resolve it and the smoke build proves it.
  python3 "$helper" compiler-json "$manifest" >"$out/compiler.json"

  # Preserve Koji buildroot identity as authenticated transport/provenance
  # evidence. Fedora Koji build RPMs are not assumed to carry repository GPG
  # signatures here, so package_signatures is intentionally not asserted.
  python3 - "$manifest" "$out/provenance.json" "$r" "$hub" "$topurl" <<'PY_PROV'
import hashlib,json,sys
mp,out,release,hub,topurl=sys.argv[1:]
m=json.load(open(mp)); blob=json.dumps(m,sort_keys=True,separators=(',',':'))
config=json.dumps({'koji_hub':hub,'koji_topurl':topurl,'kernel_build':m.get('kernel_build'),'buildroot':m.get('buildroot')},sort_keys=True,separators=(',',':'))
keys='Fedora Koji artifact transport over configured HTTPS endpoint; package-level RPM signatures are not asserted for raw Koji build outputs.'
meta=[['koji-buildroot.json',hashlib.sha256(open(mp,'rb').read()).hexdigest()]]
h=lambda x:hashlib.sha256(x.encode()).hexdigest()
obj={'schema':'klab-repository-provenance-v1','provider':'fedora','release':release,'repository_config_sha256':h(config),'key_inventory_sha256':h(keys),'repository_metadata_sha256':h(json.dumps(meta,separators=(',',':'))),'repository_config':config,'key_inventory':keys,'repository_metadata':meta,'koji_buildroot':m}
open(out,'w').write(json.dumps(obj,sort_keys=True)+'\n')
PY_PROV
  rm -f "$out/compiler.raw"
  klab_backend_rpm_fix_owner "$out"; klab_backend_rpm_manifest "$out/packages"
}


klab_provider_fedora_fallback_mode(){
  local mode="${KLAB_FEDORA_KOJI_FALLBACK:-auto}"
  case "$mode" in auto|always|never) printf '%s\n' "$mode";; *) die "KLAB_FEDORA_KOJI_FALLBACK must be auto, always, or never (got '$mode')";; esac
}

klab_provider_fedora_repo_retained(){
  local repo_url="$1"
  python3 - "$repo_url" <<'PY_REPO_CHECK'
import sys,urllib.request,urllib.error
url=sys.argv[1].rstrip('/')+'/repodata/repomd.xml'
try:
    req=urllib.request.Request(url,headers={'User-Agent':'KLab-Fedora-Koji/1'})
    with urllib.request.urlopen(req,timeout=15) as r:
        raise SystemExit(0 if 200 <= getattr(r,'status',200) < 400 else 1)
except Exception:
    raise SystemExit(1)
PY_REPO_CHECK
}

klab_provider_fedora_build_fallback_repo(){
  local manifest="$1" arch="$2" hub="$3" topurl="$4" helper image inv cache tmp owner qhub qtop qarch
  helper="$SELF_DIR/lib/fedora_koji.py"; [[ -f "$helper" ]] || die "Fedora Koji metadata helper is missing: $helper"
  inv="$(python3 - "$manifest" <<'PY_INV'
import json,sys
m=json.load(open(sys.argv[1])); print(m.get('package_inventory_sha256',''))
PY_INV
)"
  [[ "$inv" =~ ^[0-9a-f]{64}$ ]] || die "Fedora Koji buildroot manifest lacks a valid package inventory digest"
  cache="$KLAB_CACHE/fedora-koji-fallback/${inv}-${arch}"
  image="${KLAB_FEDORA_KOJI_IMAGE:-fedora:43}"
  owner="$(klab_provider_bind_output_owner)"
  if [[ -f "$cache/READY" && -f "$cache/repo/repodata/repomd.xml" && -s "$cache/fallback-plan.json" ]]; then
    if [[ ! -f "$cache/REPODATA-COMPAT-V2" ]]; then
      say "Upgrading cached Fedora Koji fallback metadata for legacy yum compatibility (${inv:0:16}, $arch)"
      run_container_root "$image" -v "$cache:/out" bash -lc "set -eu
        dnf -qy install createrepo_c >/dev/null 2>&1
        rm -rf /out/repo/repodata
        createrepo_c --quiet --compatibility --database --general-compress-type=gz /out/repo
        touch /out/REPODATA-COMPAT-V2
        chown -R '$owner' /out" >&2 || die "failed to upgrade cached Fedora fallback repository metadata"
    fi
    printf '%s\n' "$cache/repo"
    return 0
  fi
  mkdir -p "$(dirname "$cache")"
  tmp="${cache}.tmp.$$"; rm -rf "$tmp"; mkdir -p "$tmp/repo"
  printf -v qhub '%q' "$hub"; printf -v qtop '%q' "$topurl"; printf -v qarch '%q' "$arch"
  say "Reconstructing expired Fedora Koji buildroot repo from retained package builds (${inv:0:16}, $arch)"
  if ! run_container_root "$image" -v "$manifest:/klab/koji-buildroot.json:ro" -v "$helper:/klab/fedora_koji.py:ro" -v "$tmp:/out" bash -lc "set -eu
    dnf -qy install koji python3-koji createrepo_c rpm >/dev/null 2>&1
    python3 /klab/fedora_koji.py fallback-plan /klab/koji-buildroot.json --hub $qhub --output /out/fallback-plan.json
    cd /out/repo
    python3 /klab/fedora_koji.py fallback-builds /out/fallback-plan.json >/out/fallback-builds.txt
    while IFS= read -r nvr; do
      [ -n \"\$nvr\" ] || continue
      koji --server=$qhub --topurl=$qtop download-build --noprogress --arch=$qarch --arch=noarch \"\$nvr\"
    done </out/fallback-builds.txt
    python3 /klab/fedora_koji.py fallback-verify-dir /out/fallback-plan.json /out/repo
    createrepo_c --quiet --compatibility --database --general-compress-type=gz /out/repo
    sha256sum /out/repo/*.rpm | LC_ALL=C sort -k2 >/out/FALLBACK-RPMS.sha256
    printf '%s\\n' 'schema=klab-fedora-koji-package-fallback-v1' 'inventory=$inv' 'arch=$arch' 'hub=$hub' 'topurl=$topurl' >/out/fallback.env
    chown -R '$owner' /out" >&2; then
    rm -rf "$tmp"
    return 1
  fi
  [[ -f "$tmp/repo/repodata/repomd.xml" && -s "$tmp/fallback-plan.json" ]] || { rm -rf "$tmp"; die "Fedora Koji package fallback did not produce a repository"; }
  touch "$tmp/READY" "$tmp/REPODATA-COMPAT-V2"
  klab_buildenv_owner_fix "$tmp"
  rm -rf "$cache"; mv "$tmp" "$cache"
  printf '%s\n' "$cache/repo"
}

klab_provider_fedora_ensure_execution_supplements(){
  local repo="$1" release="$2" hub="$3" topurl="$4" image owner qhub qtop state release_image
  state="$(dirname "$repo")"
  [[ -f "$state/EXECUTION-SUPPLEMENTS-V3" ]] && return 0
  image="${KLAB_FEDORA_KOJI_IMAGE:-fedora:43}"
  release_image="$(provider_image fedora "$release")"
  owner="$(klab_provider_bind_output_owner)"
  printf -v qhub '%q' "$hub"; printf -v qtop '%q' "$topurl"
  say "Completing reconstructed Koji repo with exact Fedora $release execution-root RPMs"
  run_container_root "$release_image" -v "$state:/out" bash -lc "set -eu
    rpm -qa --qf '%{NAME}\\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\\t%{ARCH}\\t%{VERSION}\\t%{RELEASE}\\n' | LC_ALL=C sort -u >/out/execution-installed.tsv
    chown '$owner' /out/execution-installed.tsv"
  run_container_root "$image" -v "$repo:/out/repo" -v "$state:/out/state" bash -lc "set -eu
    dnf -qy install koji createrepo_c rpm python3 >/dev/null 2>&1
    python3 - $qhub <<'PY_PLAN'
import glob,koji,subprocess,sys
hub=sys.argv[1]; session=koji.ClientSession(hub)
installed=[]
for line in open('/out/state/execution-installed.tsv'):
    name,evr,arch,version,release=line.rstrip('\\n').split('\\t')
    if name != 'gpg-pubkey': installed.append((name,evr,arch,version,release))
have=set()
for f in glob.glob('/out/repo/*.rpm'):
    row=subprocess.check_output(['rpm','-qp','--qf','%{NAME}\\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\\t%{ARCH}',f],text=True)
    have.add(tuple(row.split('\\t')))
missing=[x for x in installed if x[:3] not in have]
builds=set()
for name,evr,arch,version,release in missing:
    rpm=session.getRPM({'name':name,'version':version,'release':release,'arch':arch},strict=True)
    build=session.getBuild(rpm['build_id'],strict=True)
    builds.add(build['nvr'])
open('/out/state/execution-supplement-builds.txt','w').write(''.join(nvr+'\\n' for nvr in sorted(builds)))
open('/out/state/execution-supplements.tsv','w').write(''.join('\\t'.join(x[:3])+'\\n' for x in sorted(missing)))
PY_PLAN
    rm -rf /out/state/execution-new; mkdir /out/state/execution-new
    cd /out/state/execution-new
    while IFS= read -r nvr; do
      [ -n \"\$nvr\" ] || continue
      koji --server=$qhub --topurl=$qtop download-build --noprogress --arch=x86_64 --arch=noarch \"\$nvr\"
    done </out/state/execution-supplement-builds.txt
    python3 - <<'PY_KEEP'
import glob,os,shutil,subprocess
want=set(tuple(x.rstrip('\\n').split('\\t')) for x in open('/out/state/execution-supplements.tsv'))
found=set()
for f in glob.glob('/out/state/execution-new/*.rpm'):
    row=subprocess.check_output(['rpm','-qp','--qf','%{NAME}\\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\\t%{ARCH}',f],text=True)
    ident=tuple(row.split('\\t'))
    if ident in want:
        shutil.copy2(f,'/out/repo/'+os.path.basename(f)); os.unlink(f); found.add(ident)
for f in glob.glob('/out/state/execution-new/*.rpm'): os.unlink(f)
missing=want-found
if missing: raise SystemExit('Koji execution supplements missing exact identities: '+repr(sorted(missing)))
PY_KEEP
    rm -rf /out/state/execution-new /out/repo/repodata
    createrepo_c --quiet --compatibility --database --general-compress-type=gz /out/repo
    touch /out/state/EXECUTION-SUPPLEMENTS-V3
    chown -R '$owner' /out"
}

klab_provider_fedora_capture_buildenv(){
  local r="$1" k="$2" b="$3" out="$4" arch="$5" img build install manifest helper hub topurl repo_url qrepo strict_repo
  local fallback_mode fallback_repo="" force_fallback=0 fallback_id="" qfallback_id historical_sync=0
  img="$(provider_image fedora "$r")"
  build="/usr/src/kernels/$(klab_backend_rpm_kernel_release "$k" "$arch")"
  manifest="$b/koji-buildroot.json"; [[ -s "$manifest" ]] || die "Fedora buildenv requires Koji buildroot provenance: $manifest"
  helper="$SELF_DIR/lib/fedora_koji.py"; [[ -f "$helper" ]] || die "Fedora Koji metadata helper is missing: $helper"
  klab_provider_fedora_koji_endpoints; hub="$KLAB_FEDORA_EFFECTIVE_KOJI_HUB"; topurl="$KLAB_FEDORA_EFFECTIVE_KOJI_TOPURL"
  repo_url="$(python3 "$helper" repo-url "$manifest" --topurl "$topurl")"
  printf -v qrepo '%q' "$repo_url"
  strict_repo="${KLAB_FEDORA_STRICT_BUILDROOT_REPO:-0}"
  fallback_mode="$(klab_provider_fedora_fallback_mode)"
  # Fedora 20/23 container images represent later update states than some kernel
  # build events. When reconstructing those vintage buildroots, synchronize the
  # execution root to the exact Koji repository before installing compiler and
  # kernel-devel RPMs so glibc/libgcc/libstdc++ versions remain coherent.
  if [[ "$r" =~ ^[0-9]+$ ]] && (( 10#$r <= 23 )); then historical_sync=1; fi

  case "$fallback_mode" in
    always)
      force_fallback=1
      fallback_repo="$(klab_provider_fedora_build_fallback_repo "$manifest" "$arch" "$hub" "$topurl")" || die "forced Fedora Koji package fallback reconstruction failed"
      ;;
    auto)
      if ! klab_provider_fedora_repo_retained "$repo_url"; then
        fallback_repo="$(klab_provider_fedora_build_fallback_repo "$manifest" "$arch" "$hub" "$topurl" || true)"
        if [[ -z "$fallback_repo" ]]; then
          if [[ "$strict_repo" == 1 ]]; then die "exact Koji repo expired and package-build fallback reconstruction failed"; fi
          say "WARNING: exact Koji repo expired and package-build fallback could not be reconstructed; release repositories remain the final auxiliary-dependency fallback"
        fi
      fi
      ;;
    never) ;;
  esac
  if [[ -n "$fallback_repo" ]]; then
    klab_provider_fedora_ensure_execution_supplements "$fallback_repo" "$r" "$hub" "$topurl"
    fallback_id="$(basename "$(dirname "$fallback_repo")")"
  fi
  printf -v qfallback_id '%q' "$fallback_id"

  install="repo_url=$qrepo
strict_repo=$strict_repo
fallback_mode=$fallback_mode
force_fallback=$force_fallback
fallback_id=$qfallback_id
historical_sync=$historical_sync
fedora_release=$r
"'set -eu
mkdir -p /var/lib/klab /etc/yum.repos.d
cat >/etc/yum.repos.d/klab-koji-buildroot.repo <<EOF_REPO
[klab-koji-buildroot]
name=KLab exact Fedora Koji buildroot
baseurl=$repo_url
enabled=1
gpgcheck=0
repo_gpgcheck=0
metadata_expire=never
skip_if_unavailable=False
EOF_REPO
fallback_available=0
if [ -f /klab-buildenv-aux-repo/repodata/repomd.xml ]; then
  fallback_available=1
  cat >/etc/yum.repos.d/klab-koji-package-fallback.repo <<EOF_FALLBACK
[klab-koji-package-fallback]
name=KLab reconstructed Fedora Koji buildroot package set
baseurl=file:///klab-buildenv-aux-repo
enabled=1
gpgcheck=0
repo_gpgcheck=0
metadata_expire=never
skip_if_unavailable=False
EOF_FALLBACK
fi
repo_args=
repo_source=release-fallback
select_repo(){
  pm="$1"
  if [ "$force_fallback" = 1 ]; then
    [ "$fallback_available" = 1 ] || { echo "forced Koji package fallback is not mounted" >&2; exit 50; }
    repo_args="--disablerepo=* --enablerepo=klab-koji-package-fallback"
    repo_source="koji-package-fallback:$fallback_id"
    return 0
  fi
  if "$pm" -y -q --disablerepo="*" --enablerepo=klab-koji-buildroot makecache >/dev/null 2>&1; then
    repo_args="--disablerepo=* --enablerepo=klab-koji-buildroot"
    repo_source="koji-buildroot:$repo_url"
  elif [ "$fallback_available" = 1 ] && "$pm" -y -q --disablerepo="*" --enablerepo=klab-koji-package-fallback makecache >/dev/null 2>&1; then
    repo_args="--disablerepo=* --enablerepo=klab-koji-package-fallback"
    repo_source="koji-package-fallback:$fallback_id"
  elif [ "$strict_repo" = 1 ]; then
    echo "neither exact Koji repo nor reconstructed package fallback is available" >&2; exit 49
  else
    echo "KLab Fedora: exact historical Koji dependency sources unavailable; using release repository only for auxiliary/runtime dependency resolution" >&2
    repo_args="--disablerepo=klab-koji-buildroot --disablerepo=klab-koji-package-fallback"
  fi
}
sync_historical_root(){
  pm="$1"
  case "$repo_source" in
    koji-buildroot:*|koji-package-fallback:*) ;;
    *) [ "$historical_sync" != 1 ] && return 0; echo "vintage Fedora requires an exact historical Koji dependency source before runtime synchronization" >&2; exit 51 ;;
  esac
  if [ "$historical_sync" != 1 ]; then
    # Mutable Fedora image tags can contain packages newer than both the release
    # mirrors and the recorded kernel buildroot.  Synchronize the modern staging
    # root to the retained Koji repository so every realized package has an exact
    # downloadable archive before the V4 inventory is recorded.
    echo "KLab Fedora: synchronizing modern execution root to recorded Koji buildroot" >&2
    "$pm" -y -q $repo_args distro-sync >/dev/null
    return 0
  fi

  # Do not distro-sync the whole execution image for vintage Fedora. Fedora 20 final-update
  # container carries a newer rpm/rpm-python/yum control plane than the kernel build
  # earlier Koji buildroot; downgrading rpm underneath rpm-python makes the Yum
  # own transaction unsatisfiable.  KLab only needs the ABI/runtime packages
  # used by the exact compiler plus the compiler/linker tools themselves to
  # match the historical build event.
  sync_pkgs=""
  for n in glibc glibc-common; do
    rpm -q "$n" >/dev/null 2>&1 && sync_pkgs="$sync_pkgs $n"
  done
  for p in /klab-distro-toolchain-packages/*.rpm; do
    [ -e "$p" ] || continue
    n=$(rpm -qp --qf '%{NAME}' "$p" 2>/dev/null || true)
    [ -n "$n" ] || continue
    rpm -q "$n" >/dev/null 2>&1 || continue
    case " $sync_pkgs " in *" $n "*) ;; *) sync_pkgs="$sync_pkgs $n" ;; esac
  done
  if [ -n "$sync_pkgs" ]; then
    echo "KLab Fedora: synchronizing vintage ABI/toolchain runtime packages to recorded Koji versions:$sync_pkgs" >&2
    "$pm" -y -q $repo_args distro-sync $sync_pkgs >/dev/null
  fi
}
install_kbuild_prereqs(){
  pm="$1"
  # kernel-devel does not depend on every host library needed by Kbuild. In
  # particular CONFIG_UNWINDER_ORC kernels invoke objtool, which requires the
  # libelf development headers at external-module build time. Resolve this
  # prerequisite from the same selected Koji/reconstructed repository so it is
  # captured in the sealed dependency closure rather than borrowed from the
  # host or a newer Fedora release.
  "$pm" -y -q $repo_args install elfutils-libelf-devel >/dev/null
}
kernel_rpms=""
for p in /pkgs/*.rpm; do
  [ -e "$p" ] || continue
  n=$(rpm -qp --qf '%{NAME}' "$p" 2>/dev/null || true)
  case "$n" in
    kernel-devel|kernel-headers|kernel-rpm-macros|kernel-srpm-macros) kernel_rpms="$kernel_rpms $p" ;;
  esac
done
[ -n "$kernel_rpms" ] || { echo "Fedora kernel-devel/header RPM missing from captured target" >&2; exit 41; }
if command -v dnf >/dev/null 2>&1; then
  select_repo dnf
  printf "%s\n" "$repo_source" >/var/lib/klab/fedora-repo-source
  sync_historical_root dnf
  install_kbuild_prereqs dnf
  dnf -y -q $repo_args install $kernel_rpms >/dev/null
elif command -v yum >/dev/null 2>&1; then
  select_repo yum
  printf "%s\n" "$repo_source" >/var/lib/klab/fedora-repo-source
  sync_historical_root yum
  install_kbuild_prereqs yum
  yum -y -q $repo_args localinstall $kernel_rpms >/dev/null
else
  echo "Fedora buildenv has neither dnf nor yum" >&2; exit 47
fi
# Install the exact Koji compiler/binutils/make RPMs as local packages. Their
# dependency closure now prefers the original Koji repo, then the reconstructed
# package-build fallback, and only then (non-strict mode) release repositories.
set -- /klab-distro-toolchain-packages/*.rpm
if [ -e "$1" ]; then
  if command -v dnf >/dev/null 2>&1; then
    dnf -y -q $repo_args install "$@" >/dev/null
  else
    yum -y -q $repo_args localinstall "$@" >/dev/null
  fi
fi'
  local dependency_capture
  dependency_capture="export KLAB_RPM_TRUST_MODE=koji; $(klab_backend_dnf_dependency_capture_script)"
  if [[ -n "$fallback_repo" ]]; then
    KLAB_BUILDENV_AUX_REPO_DIR="$fallback_repo" KLAB_BUILDENV_NATIVE_CC=/usr/bin/gcc \
    KLAB_BUILDENV_DEPENDENCY_CAPTURE_COMMAND="$dependency_capture" \
    KLAB_BUILDENV_DEPENDENCY_REPOSITORY_URL="koji://fedora/$r/$k" \
    KLAB_BUILDENV_DEPENDENCY_METADATA_FILE="$manifest" \
      klab_buildenv_capture_container fedora "$r" "$k" "$arch" "$img" "$(klab_provider_fedora_setup)" "$b/packages" "$install" "$build" "$out"
  else
    KLAB_BUILDENV_NATIVE_CC=/usr/bin/gcc \
    KLAB_BUILDENV_DEPENDENCY_CAPTURE_COMMAND="$dependency_capture" \
    KLAB_BUILDENV_DEPENDENCY_REPOSITORY_URL="koji://fedora/$r/$k" \
    KLAB_BUILDENV_DEPENDENCY_METADATA_FILE="$manifest" \
      klab_buildenv_capture_container fedora "$r" "$k" "$arch" "$img" "$(klab_provider_fedora_setup)" "$b/packages" "$install" "$build" "$out"
  fi
}

klab_provider_fedora_capabilities(){ printf 'list=yes fetch=yes build-module=yes buildenv=yes historical=koji-buildroot snapshots=koji cross-arch=no arches=x86_64\n'; }
klab_provider_fedora_describe(){ printf 'fedora    exact Koji kernel + buildroot provenance; Koji-pinned GCC/binutils/make\n'; }
