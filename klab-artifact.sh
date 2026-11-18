#!/usr/bin/env bash
set -Eeuo pipefail

# KLAB_UNIFIED_ROOT_R22
# KLAB_NATIVE_PATHS_R23
# KLAB_RESIDUAL_PATH_AUDIT_R24
_KLAB_SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [[ -f "$_KLAB_SELF_DIR/lib/klab-root.sh" ]]; then
  # shellcheck source=lib/klab-root.sh
  source "$_KLAB_SELF_DIR/lib/klab-root.sh"
  klab_root_ensure_layout
fi
unset _KLAB_SELF_DIR

FORMAT_NAME="kernel-lab-shared-artifact"
FORMAT_VERSION=1
LAB_HOME="$KLAB_ROOT"
OBJECTS="$KLAB_ARTIFACTS/objects"
TOOLCHAINS="$KLAB_TOOLCHAIN_STORE"
GUESTS="$KLAB_USERSPACE_STORE"
FIRMWARE="$KLAB_ARTIFACTS/firmware"
SOURCES_SHARED="$KLAB_SOURCE_ARTIFACT_STORE"

say(){ printf '\n==> %s\n' "$*" >&2; }
die(){ printf 'klab-artifact: ERROR: %s\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
need(){ local x; for x in tar zstd sha256sum python3; do have "$x" || die "required program not found: $x"; done; }

usage(){ cat <<'USAGE'
Usage:
  klab-artifact.sh create toolchain --from DIR [--name NAME] [--arch ARCH] [--compat-id ID] [-o FILE.klabtoolchain]
  klab-artifact.sh create rootfs    --from PATH --arch ARCH --spec SPEC [--buildroot-version VER] [--profile NAME] [-o FILE.klabrootfs]
  klab-artifact.sh create sdk       --from DIR --arch ARCH [--buildroot-version VER] [--profile NAME] [-o FILE.klabsdk]
  klab-artifact.sh create firmware  --from PATH [--name NAME] [--arch ARCH] [-o FILE.klabfirmware]
  klab-artifact.sh create source    --from PATH [--name NAME] [--arch ARCH]
                                    [--provider NAME] [--release VERSION]
                                    [--kernel-release VERSION] [--provenance TEXT]
                                    [-o FILE.klabsource]

  klab-artifact.sh thinify FILE.klab [--output FILE.klab] [--artifact-dir DIR]
  klab-artifact.sh verify  FILE
  klab-artifact.sh inspect FILE [--json]
  klab-artifact.sh id      FILE
  klab-artifact.sh import  FILE [--force]
  klab-artifact.sh list

Typed extensions:
  .klabtoolchain .klabrootfs .klabsdk .klabfirmware .klabsource

Identity is content-addressed. Re-importing the same object reuses one object-store entry.
USAGE
}

artifact_ext(){ case "$1" in toolchain) echo klabtoolchain;; rootfs) echo klabrootfs;; sdk) echo klabsdk;; firmware) echo klabfirmware;; source) echo klabsource;; *) die "unsupported artifact type '$1'";; esac; }
canonical_arch(){ case "${1:-}" in '') echo '';; x86_64|amd64) echo x86_64;; i386|i486|i586|i686|x86) echo i386;; aarch64|arm64) echo aarch64;; armv7|armv7l|armhf|arm) echo armv7;; *) echo "$1";; esac; }
sanitize(){ printf '%s' "$1" | tr -cs 'A-Za-z0-9._+-' '-'; }
sha(){ sha256sum "$1" | awk '{print $1}'; }
json_get(){ python3 - "$1" "$2" <<'PY_JSONGET'
import json,sys
p,e=sys.argv[1:]
o=json.load(open(p,encoding='utf-8'))
cur=o
for k in e.split('.'):
    if not k: continue
    cur=cur[int(k)] if isinstance(cur,list) else cur[k]
if cur is None: print('')
elif isinstance(cur,(dict,list)): print(json.dumps(cur,sort_keys=True))
else: print(cur)
PY_JSONGET
}

canonical_pack(){
  local src="$1" out="$2"
  if [[ -d "$src" ]]; then
    tar -C "$src" --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner --pax-option=delete=atime,delete=ctime -cf - . | zstd -q -T0 -6 -o "$out"
  elif [[ -f "$src" ]]; then
    local d b; d="$(dirname "$src")"; b="$(basename "$src")"
    tar -C "$d" --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner --pax-option=delete=atime,delete=ctime -cf - "$b" | zstd -q -T0 -6 -o "$out"
  else die "source path not found: $src"; fi
}

probe_toolchain(){
  local root="$1" compat_override="${2:-}" cc="" rel family ver target prefix="" compat
  cc="$(find "$root" -maxdepth 6 \( -type f -o -type l \) -perm -111 -path '*/bin/*' -name '*-gcc' -print 2>/dev/null | sort | head -n1 || true)"
  [[ -n "$cc" ]] || cc="$(find "$root" -maxdepth 6 \( -type f -o -type l \) -perm -111 -path '*/bin/gcc' -print 2>/dev/null | sort | head -n1 || true)"
  [[ -n "$cc" ]] || cc="$(find "$root" -maxdepth 6 \( -type f -o -type l \) -perm -111 -path '*/bin/*' -name 'clang*' -print 2>/dev/null | sort | head -n1 || true)"
  [[ -n "$cc" ]] || die "could not locate gcc/clang under $root"
  rel="${cc#"$root"/}"
  case "$(basename "$cc")" in
    *gcc*) family=gcc; ver="$($cc -dumpfullversion -dumpversion 2>/dev/null | head -n1)"; target="$($cc -dumpmachine 2>/dev/null | head -n1 || true)"; [[ "$(basename "$cc")" == *-gcc ]] && prefix="${rel%gcc}";;
    clang*) family=clang; ver="$($cc --version | sed -n '1s/.*clang version \([^ ]*\).*/\1/p')"; target="$($cc -dumpmachine 2>/dev/null | head -n1 || true)";;
    *) die "unsupported compiler: $cc";;
  esac
  [[ -n "$ver" ]] || die "could not determine compiler version"; [[ -n "$target" ]] || target=unknown
  compat="${compat_override:-$(sanitize "${family}-${ver}-${target}")}"
  python3 - "$rel" "$family" "$ver" "$target" "$prefix" "$compat" <<'PY_TC'
import json,sys
rel,fam,ver,target,prefix,compat=sys.argv[1:]
print(json.dumps({"cc_relpath":rel,"family":fam,"version":ver,"target":target,"cross_prefix_relpath":prefix or None,"compat_id":compat},sort_keys=True))
PY_TC
}

create(){
  need; (($#>=1)) || die "create needs an artifact type"
  local type="$1"; shift; artifact_ext "$type" >/dev/null
  local src="" name="" arch="" output="" spec="" brver="" profile="" compat_id="" tc='{}' provider="" release="" kernel_release="" provenance=""
  while (($#)); do case "$1" in
    --from) src="$2"; shift 2;; --name) name="$2"; shift 2;; --arch) arch="$(canonical_arch "$2")"; shift 2;;
    --spec) spec="$2"; shift 2;; --buildroot-version) brver="$2"; shift 2;; --profile) profile="$2"; shift 2;;
    --compat-id) compat_id="$2"; shift 2;; --provider) provider="$2"; shift 2;; --release) release="$2"; shift 2;;
    --kernel-release) kernel_release="$2"; shift 2;; --provenance) provenance="$2"; shift 2;;
    -o|--output) output="$2"; shift 2;; *) die "unknown create option '$1'";; esac; done
  [[ -n "$src" ]] || die "create requires --from PATH"; src="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$src")"; [[ -e "$src" ]] || die "source path not found: $src"
  [[ -n "$name" ]] || name="$(basename "$src")"
  local ext; ext="$(artifact_ext "$type")"; [[ -n "$output" ]] || output="$PWD/$(sanitize "$name").$ext"; [[ "$output" == *.$ext ]] || output="$output.$ext"
  output="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$output")"
  local st payload psha obj kind; st="$(mktemp -d)"; mkdir -p "$st/payload"; payload="$st/payload/content.tar.zst"
  canonical_pack "$src" "$payload"; psha="$(sha "$payload")"; obj="sha256:$psha"; [[ -d "$src" ]] && kind=directory || kind=file
  [[ "$type" == toolchain ]] && tc="$(probe_toolchain "$src" "$compat_id")"
  python3 - "$st/manifest.json" "$type" "$obj" "$name" "$arch" "$kind" "$psha" "$spec" "$brver" "$profile" "$tc" "$provider" "$release" "$kernel_release" "$provenance" <<'PY_MANIFEST'
import json,sys,datetime
out,typ,obj,name,arch,kind,psha,spec,brver,profile,tc,provider,release,kernel_release,provenance=sys.argv[1:]
m={"format":"kernel-lab-shared-artifact","format_version":1,"created_at":datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z'),"artifact_type":typ,"object_id":obj,"name":name,"arch":arch or None,"payload":{"path":"payload/content.tar.zst","sha256":psha,"source_kind":kind},"metadata":{}}
if spec:m["metadata"]["userspace_spec"]=spec
if brver:m["metadata"]["buildroot_version"]=brver
if profile:m["metadata"]["profile"]=profile
if typ=="toolchain":m["metadata"].update(json.loads(tc))
if typ=="source":
    m["metadata"].update({k:v for k,v in {"provider":provider,"release":release,"kernel_release":kernel_release,"provenance":provenance}.items() if v})
json.dump(m,open(out,'w',encoding='utf-8'),indent=2,sort_keys=True);open(out,'a').write('\n')
PY_MANIFEST
  printf '%s\n' "$FORMAT_VERSION" > "$st/FORMAT_VERSION"; (cd "$st" && sha256sum manifest.json payload/content.tar.zst > SHA256SUMS)
  mkdir -p "$(dirname "$output")"; tar -C "$st" --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -cf - FORMAT_VERSION manifest.json SHA256SUMS payload | zstd -q -T0 -6 -o "$output"
  rm -rf "$st"; say "Created $type artifact $output"; printf '%s\n' "$output"
}

extract_stage(){ local f="$1" st="$2"; zstd -dc "$f" | tar -xf - -C "$st"; }
verify(){
  need; (($#==1)) || die "verify FILE"; local f="$1" st; [[ -f "$f" ]] || die "file not found: $f"; st="$(mktemp -d)"; extract_stage "$f" "$st"
  [[ -f "$st/manifest.json" && -f "$st/SHA256SUMS" ]] || { rm -rf "$st"; die "not a typed Kernel Lab artifact"; }
  [[ "$(json_get "$st/manifest.json" format)" == "$FORMAT_NAME" ]] || { rm -rf "$st"; die "wrong artifact format"; }
  (cd "$st" && sha256sum -c SHA256SUMS >/dev/null) || { rm -rf "$st"; die "checksum verification failed"; }
  local psha oid; psha="$(sha "$st/payload/content.tar.zst")"; oid="$(json_get "$st/manifest.json" object_id)"; rm -rf "$st"
  [[ "$oid" == "sha256:$psha" ]] || die "object id does not match payload content"; printf '%s\n' "$oid"
}
inspect(){
  need; (($#>=1 && $#<=2)) || die "inspect FILE [--json]"; local f="$1" json=0; [[ "${2:-}" == --json ]] && json=1; verify "$f" >/dev/null
  local st; st="$(mktemp -d)"; extract_stage "$f" "$st"; if ((json)); then cat "$st/manifest.json"; rm -rf "$st"; return; fi
  python3 - "$st/manifest.json" <<'PY_INSPECT'
import json,sys
m=json.load(open(sys.argv[1])); print(f"Type:       {m['artifact_type']}"); print(f"Name:       {m['name']}"); print(f"Object ID:  {m['object_id']}"); print(f"Arch:       {m.get('arch') or '-'}")
for k,v in (m.get('metadata') or {}).items():
    if v is not None: print(f"{k}: {v}")
PY_INSPECT
  rm -rf "$st"
}

install_compat(){
  local typ="$1" objdir="$2" manifest="$3" content="$objdir/content" arch spec brver profile compat
  arch="$(json_get "$manifest" arch 2>/dev/null || true)"
  case "$typ" in
    toolchain) compat="$(json_get "$manifest" metadata.compat_id)"; [[ -n "$compat" ]] || return 0; mkdir -p "$TOOLCHAINS"; ln -sfn "$content" "$TOOLCHAINS/$compat";;
    rootfs)
      spec="$(json_get "$manifest" metadata.userspace_spec 2>/dev/null || true)"
      if [[ "$spec" == busybox-static ]]; then mkdir -p "$GUESTS/busybox/$arch"; local bf; bf="$(find "$content" -type f -name busybox -o -type f | head -n1 || true)"; [[ -n "$bf" ]] || die "rootfs artifact contains no BusyBox file"; ln -sfn "$bf" "$GUESTS/busybox/$arch/busybox"
      elif [[ "$spec" == buildroot:* ]]; then profile="$(json_get "$manifest" metadata.profile 2>/dev/null || true)"; [[ -n "$profile" ]] || profile="${spec#buildroot:}"; brver="$(json_get "$manifest" metadata.buildroot_version 2>/dev/null || true)"; [[ -n "$brver" ]] || brver=unknown; local gd="$GUESTS/buildroot/$brver/$profile/$arch"; mkdir -p "$gd"; local x; for x in rootfs.tar metadata.env buildroot.config busybox.fragment; do [[ -e "$content/$x" ]] && ln -sfn "$content/$x" "$gd/$x"; done; fi;;
    sdk) profile="$(json_get "$manifest" metadata.profile 2>/dev/null || true)"; brver="$(json_get "$manifest" metadata.buildroot_version 2>/dev/null || true)"; [[ -n "$profile" && -n "$brver" && -n "$arch" ]] || return 0; [[ -x "$content/relocate-sdk.sh" ]] && (cd "$content" && ./relocate-sdk.sh >/dev/null) || true; local gd="$GUESTS/buildroot/$brver/$profile/$arch"; mkdir -p "$gd"; ln -sfn "$content" "$gd/sdk";;
    firmware) mkdir -p "$FIRMWARE"; ln -sfn "$content" "$FIRMWARE/$(basename "$objdir")";;
    source) mkdir -p "$SOURCES_SHARED"; ln -sfn "$content" "$SOURCES_SHARED/$(basename "$objdir")";;
  esac
}
import_art(){
  need; (($#>=1)) || die "import FILE [--force]"; local f="$1"; shift; while (($#)); do case "$1" in --force) shift;; *) die "unknown import option '$1'";; esac; done
  local oid st typ hex objdir; oid="$(verify "$f")"; st="$(mktemp -d)"; extract_stage "$f" "$st"; typ="$(json_get "$st/manifest.json" artifact_type)"; hex="${oid#sha256:}"; objdir="$OBJECTS/$typ/$hex"
  if [[ ! -f "$objdir/manifest.json" ]]; then mkdir -p "$objdir/content"; tar --zstd -xf "$st/payload/content.tar.zst" -C "$objdir/content"; cp "$st/manifest.json" "$objdir/manifest.json"; cp "$st/SHA256SUMS" "$objdir/artifact-SHA256SUMS"; else say "Reusing installed $typ object $oid"; fi
  rm -rf "$st"; install_compat "$typ" "$objdir" "$objdir/manifest.json"; printf '%s\n' "$objdir"
}
list_objs(){
  printf '%-12s %-12s %-66s %s\n' TYPE ARCH OBJECT_ID NAME; local m t a o n
  while IFS= read -r m; do t="$(json_get "$m" artifact_type)"; a="$(json_get "$m" arch 2>/dev/null || true)"; o="$(json_get "$m" object_id)"; n="$(json_get "$m" name)"; printf '%-12s %-12s %-66s %s\n' "$t" "${a:--}" "$o" "$n"; done < <(find "$OBJECTS" -mindepth 3 -maxdepth 3 -name manifest.json -type f 2>/dev/null | sort)
}

place_artifact_file(){
  local tmp="$1" friendly="$2" ext="$3" oid="$4" dir="$5" hex final
  hex="${oid#sha256:}"
  final="$dir/$(sanitize "$friendly")--${hex:0:12}.$ext"
  if [[ -f "$final" ]]; then
    [[ "$(verify "$final")" == "$oid" ]] || die "artifact filename collision: $final"
    rm -f "$tmp"
  else
    mv "$tmp" "$final"
  fi
  printf '%s\n' "$final"
}

thinify_klab(){
  need; (($#>=1)) || die "thinify FILE.klab [--output FILE.klab] [--artifact-dir DIR]"; local in="$1"; shift; local out="" adir=""
  while (($#)); do case "$1" in -o|--output) out="$2"; shift 2;; --artifact-dir) adir="$2"; shift 2;; *) die "unknown thinify option '$1'";; esac; done
  [[ -f "$in" ]] || die "bundle not found: $in"; [[ -n "$out" ]] || out="$in"; [[ -n "$adir" ]] || adir="$(dirname "$out")"; mkdir -p "$adir" "$(dirname "$out")"
  local st; st="$(mktemp -d)"; tar --zstd -xf "$in" -C "$st"; [[ -f "$st/manifest.json" ]] || { rm -rf "$st"; die "not a .klab bundle: $in"; }
  local tool_oid="" root_oid="" sdk_oid="" apath tmpd arch spec brver profile tcid
  arch="$(json_get "$st/manifest.json" arch 2>/dev/null || true)"
  if [[ -f "$st/extras/toolchain.tar.zst" ]]; then
    tmpd="$(mktemp -d)"; tar --zstd -xf "$st/extras/toolchain.tar.zst" -C "$tmpd"; tcid="$(json_get "$st/manifest.json" toolchain.id 2>/dev/null || true)"; [[ -n "$tcid" ]] || tcid="toolchain-$arch"; apath="$adir/.tmp-toolchain-$$.klabtoolchain"; create toolchain --from "$tmpd" --name "$tcid" --arch "$arch" --compat-id "$tcid" -o "$apath" >/dev/null; tool_oid="$(verify "$apath")"; apath="$(place_artifact_file "$apath" "$tcid" klabtoolchain "$tool_oid" "$adir")"; rm -rf "$tmpd" "$st/extras/toolchain.tar.zst"; say "Shared toolchain: $apath ($tool_oid)"
  fi
  spec="$(json_get "$st/manifest.json" guest_userspace.spec 2>/dev/null || true)"
  if [[ "$spec" == busybox-static && -f "$st/extras/guest-busybox" ]]; then
    tmpd="$(mktemp -d)"; cp "$st/extras/guest-busybox" "$tmpd/busybox"; chmod 0755 "$tmpd/busybox"; apath="$adir/.tmp-rootfs-$$.klabrootfs"; create rootfs --from "$tmpd" --name "busybox-static-$arch" --arch "$arch" --spec busybox-static -o "$apath" >/dev/null; root_oid="$(verify "$apath")"; apath="$(place_artifact_file "$apath" "busybox-static-$arch" klabrootfs "$root_oid" "$adir")"; rm -rf "$tmpd" "$st/extras/guest-busybox"; say "Shared rootfs: $apath ($root_oid)"
  elif [[ "$spec" == buildroot:* && -f "$st/extras/guest-rootfs.tar" ]]; then
    profile="${spec#buildroot:}"; brver="$(json_get "$st/manifest.json" guest_userspace.buildroot_version 2>/dev/null || true)"; tmpd="$(mktemp -d)"; cp "$st/extras/guest-rootfs.tar" "$tmpd/rootfs.tar"; [[ -f "$st/extras/buildroot.config" ]] && cp "$st/extras/buildroot.config" "$tmpd/buildroot.config"; [[ -f "$st/extras/busybox.fragment" ]] && cp "$st/extras/busybox.fragment" "$tmpd/busybox.fragment"; cat > "$tmpd/metadata.env" <<EOF_META
KLAB_GUEST_USERSPACE=$spec
KLAB_GUEST_ARCH=$arch
KLAB_BUILDROOT_VERSION=$brver
EOF_META
    apath="$adir/.tmp-rootfs-$$.klabrootfs"; create rootfs --from "$tmpd" --name "buildroot-$profile-$arch-$brver" --arch "$arch" --spec "$spec" --buildroot-version "$brver" --profile "$profile" -o "$apath" >/dev/null; root_oid="$(verify "$apath")"; apath="$(place_artifact_file "$apath" "buildroot-$profile-$arch-$brver" klabrootfs "$root_oid" "$adir")"; rm -rf "$tmpd" "$st/extras/guest-rootfs.tar" "$st/extras/buildroot.config" "$st/extras/busybox.fragment"; say "Shared rootfs: $apath ($root_oid)"
    if [[ -f "$st/extras/buildroot-sdk.tar.gz" ]]; then tmpd="$(mktemp -d)"; tar -xzf "$st/extras/buildroot-sdk.tar.gz" -C "$tmpd"; apath="$adir/.tmp-sdk-$$.klabsdk"; create sdk --from "$tmpd" --name "buildroot-sdk-$profile-$arch-$brver" --arch "$arch" --buildroot-version "$brver" --profile "$profile" -o "$apath" >/dev/null; sdk_oid="$(verify "$apath")"; apath="$(place_artifact_file "$apath" "buildroot-$profile-$arch-$brver" klabsdk "$sdk_oid" "$adir")"; rm -rf "$tmpd" "$st/extras/buildroot-sdk.tar.gz"; say "Shared SDK: $apath ($sdk_oid)"; fi
  fi
  python3 - "$st/manifest.json" "$tool_oid" "$root_oid" "$sdk_oid" <<'PY_THIN'
import json,sys
p,tool,root,sdk=sys.argv[1:]; m=json.load(open(p))
if tool and m.get('toolchain'):
 t=m['toolchain']; t.pop('path',None); t['external']=True; t['artifact_type']='toolchain'; t['object_id']=tool
if root and m.get('guest_userspace'):
 g=m['guest_userspace']; [g.pop(k,None) for k in ('path','config_path','busybox_fragment_path')]; g['external']=True; g['artifact_type']='rootfs'; g['object_id']=root
 if sdk:
  x=g.get('sdk') or {}; x.pop('path',None); x['external']=True; x['artifact_type']='sdk'; x['object_id']=sdk; g['sdk']=x
 elif isinstance(g.get('sdk'),dict): g.pop('sdk',None)
m['bundle_mode']='thin'; json.dump(m,open(p,'w'),indent=2,sort_keys=True); open(p,'a').write('\n')
PY_THIN
  : > "$st/SHA256SUMS"; (cd "$st" && sha256sum manifest.json >> SHA256SUMS)
  while IFS= read -r f; do [[ "$f" == manifest.json || "$f" == SHA256SUMS || "$f" == FORMAT_VERSION ]] && continue; (cd "$st" && sha256sum "$f" >> SHA256SUMS); done < <(cd "$st" && find payload extras -type f 2>/dev/null | sort)
  sort -k2 -o "$st/SHA256SUMS" "$st/SHA256SUMS"; local tmpout="$out.tmp.$$"; tar -C "$st" --zstd -cf "$tmpout" FORMAT_VERSION manifest.json SHA256SUMS payload extras; mv "$tmpout" "$out"; rm -rf "$st"; say "Thin target bundle: $out"; printf '%s\n' "$out"
}

main(){ case "${1:-}" in create) shift; create "$@";; thinify) shift; thinify_klab "$@";; verify) shift; verify "$@";; inspect) shift; inspect "$@";; id) shift; (($#==1)) || die "id FILE"; verify "$1";; import) shift; import_art "$@";; list) shift; (($#==0)) || die "list takes no arguments"; list_objs;; -h|--help|help|'') usage;; *) usage; die "unknown command '$1'";; esac; }
main "$@"
