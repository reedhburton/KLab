#!/usr/bin/env bash
# Arch Linux pacman repository backend.
klab_backend_pacman_list(){
  local provider="$1" release="$2" image="$3" setup="$4" pattern="${5:-}" qpattern=''
  [[ -z "$pattern" ]] || printf -v qpattern '%q' "$pattern"
  klab_provider_run_container "$provider" "$image" sh -lc "$setup
for p in linux linux-lts linux-zen linux-hardened; do
  v=\$(pacman -Si \"\$p\" | sed -n 's/^Version[[:space:]]*: //p' | head -n1)
  base=\${v%-*}; rel=\${v##*-}
  case \$p in linux) k=\${base/.arch/-arch}-\$rel;; linux-lts) k=\$base-\$rel-lts;; linux-zen) k=\${base/.zen/-zen}-\$rel-zen;; linux-hardened) k=\${base/.hardened/-hardened}-\$rel-hardened;; esac
  printf '%s\\n' \"\$k\"
done | sort -V ${qpattern:+| grep -F -- $qpattern}"
}
klab_backend_pacman_select(){
  local provider="$1" image="$2" setup="$3" krel="$4"
  klab_provider_run_container "$provider" "$image" sh -lc "$setup
for p in linux linux-lts linux-zen linux-hardened; do
 v=\$(pacman -Si \"\$p\" | sed -n 's/^Version[[:space:]]*: //p' | head -n1); base=\${v%-*}; rel=\${v##*-}
 case \$p in linux) k=\${base/.arch/-arch}-\$rel;; linux-lts) k=\$base-\$rel-lts;; linux-zen) k=\${base/.zen/-zen}-\$rel-zen;; linux-hardened) k=\${base/.hardened/-hardened}-\$rel-hardened;; esac
 [ \"\$k\" != '$krel' ] || { printf '%s\\n' \"\$p\"; exit 0; }
done
exit 4"
}
klab_backend_pacman_manifest(){ local d="$1"; (cd "$d" && for f in *.pkg.tar.*; do [[ -f "$f" && "$f" != *.sig ]] || continue; sha256sum -- "$f"; done | LC_ALL=C sort -k2) >"$d/PACKAGES.sha256"; }
klab_backend_pacman_fetch(){
  local provider="$1" release="$2" krel="$3" bundle="$4" image="$5" setup="$6" packages="$bundle/packages" root="$bundle/root" owner pkg
  owner="$(klab_provider_bind_output_owner)"; pkg="$(klab_backend_pacman_select "$provider" "$image" "$setup" "$krel")" || die "Arch kernel release is not available: $krel"
  mkdir -p "$packages"; rm -f "$packages"/*.pkg.tar.* "$packages/PACKAGES.sha256" 2>/dev/null || true
  say "Downloading Arch $release $pkg for $krel"
  klab_provider_run_container "$provider" "$image" -v "$packages:/out" sh -lc "$setup
pacman -Sw --noconfirm --cachedir /out --nodeps '$pkg' '$pkg-headers' >/dev/null
chown -R '$owner' /out"
  compgen -G "$packages/*.pkg.tar.*" >/dev/null || die "no pacman packages were downloaded"
  klab_backend_pacman_manifest "$packages"
  rm -rf "$root"; mkdir -p "$root"; local p
  for p in "$packages"/*.pkg.tar.*; do [[ "$p" == *.sig ]] && continue; tar -xf "$p" -C "$root"; done
  [[ -f "$root/usr/lib/modules/$krel/vmlinuz" ]] || die "downloaded Arch packages do not contain exact kernel identity $krel"
  normalize_bundle "$provider" "$release" "$krel" "$bundle" "$image"
}
klab_backend_pacman_build_module(){
  local provider="$1" image="$2" setup="$3" packages="$4" krel="$5" module_dir="$6" jobs="$7" build_override="${8:-}" qbuild
  printf -v qbuild '%q' "${build_override:-/usr/lib/modules/$krel/build}"
  klab_provider_run_container "$provider" "$image" -v "$packages:/pkgs:ro" -v "$module_dir:/module" sh -lc "$setup
pacman -S --noconfirm --needed base-devel kmod bc pahole openssl flex bison >/dev/null
pacman -U --noconfirm \$(find /pkgs -maxdepth 1 -type f -name "*.pkg.tar.*" ! -name "*.sig" -print) >/dev/null
kdir=$qbuild; [ -e \"\$kdir\" ] || { echo 'kernel header build tree not installed' >&2; exit 41; }
make -C \"\$kdir\" M=/module -j$jobs modules
ko=\$(find /module -name '*.ko' -print -quit); [ -n \"\$ko\" ] || exit 43
vm=\$(modinfo -F vermagic \"\$ko\"); case \"\$vm\" in '$krel '*) ;; *) echo \"module vermagic mismatch: \$vm != $krel\" >&2; exit 42;; esac"
}
klab_backend_pacman_capture_buildenv(){
  local provider="$1" release="$2" krel="$3" bundle="$4" image="$5" setup="$6" output="$7" arch="$8"
  local build="/usr/lib/modules/$krel/build" install="pacman -S --noconfirm --needed base-devel kmod bc pahole openssl flex bison python >/dev/null; pacman -U --noconfirm \$(find /pkgs -maxdepth 1 -type f -name "*.pkg.tar.*" ! -name "*.sig" -print) >/dev/null"
  KLAB_BUILDENV_DEPENDENCY_CAPTURE_COMMAND='mkdir -p "$KLAB_DEPENDENCY_CAPTURE_OUT/packages"; pacman -Q | awk '\''{print $1 "\\t" $2 "\\tx86_64"}'\'' | sort >"$KLAB_DEPENDENCY_CAPTURE_OUT/requested.tsv"; cp "$KLAB_DEPENDENCY_CAPTURE_OUT/requested.tsv" "$KLAB_DEPENDENCY_CAPTURE_OUT/archives.tsv"; tar -C / -cf "$KLAB_DEPENDENCY_CAPTURE_OUT/repository-state.tar" etc/pacman.conf etc/pacman.d var/lib/pacman/sync' KLAB_BUILDENV_DEPENDENCY_REPOSITORY_URL="pacman://arch/$release" klab_buildenv_capture_container "$provider" "$release" "$krel" "$arch" "$image" "$setup" "$bundle/packages" "$install" "$build" "$output"
}
klab_backend_pacman_capture_toolchain(){
  local provider="$1" release="$2" image="$3" setup="$4" out="$5" arch="$6" owner
  owner="$(klab_provider_bind_output_owner)"; mkdir -p "$out/packages"
  klab_provider_run_container "$provider" "$image" -v "$out:/out" sh -lc "$setup
pacman -Sw --noconfirm --cachedir /out/packages gcc binutils make glibc >/dev/null
chown -R '$owner' /out"
}
