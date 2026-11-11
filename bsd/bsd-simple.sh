#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
usage(){ echo "usage: bsd-simple.sh <supports TARGET|pull TARGET REPO|run TARGET REPO ROOT [full|minimal|ssh|module]|list>" >&2; exit 2; }
safe_id(){ printf '%s' "$1" | tr ':/' '__'; }
target_fields(){
 case "$1" in
 freebsd:14.5-RELEASE:i386) printf '%s\n' freebsd-i386 xz sha256 05763f7c70404d7084148391644ad1a8c26796acf8ebe01fa90cc6a05ad923df https://download.freebsd.org/releases/VM-IMAGES/14.5-RELEASE/i386/Latest/FreeBSD-14.5-RELEASE-i386.qcow2.xz FreeBSD-14.5-RELEASE-i386.qcow2 freebsd-i386-smoke.py;;
 freebsd:14.5-RELEASE:riscv64) printf '%s\n' freebsd-riscv64 xz sha256 74629c6a51f0e3e78d2dade406a9b179cd454ddf0b8063af155f6a0194cc3c33 https://download.freebsd.org/releases/VM-IMAGES/14.5-RELEASE/riscv64/Latest/FreeBSD-14.5-RELEASE-riscv-riscv64.qcow2.xz FreeBSD-14.5-RELEASE-riscv-riscv64.qcow2 freebsd-riscv64-smoke.py;;
 netbsd:11.0:aarch64) printf '%s\n' netbsd-arm64 gzip sha512 ce7f952173412779ed3d990c9de69e36f8440e2a6849cace8c6cd3894c894b1a48c138b5faf0d500b263f6e7ef3b962dbe52ba7f350575b3acef64fc3fd827f7 https://cdn.netbsd.org/pub/NetBSD/NetBSD-11.0/evbarm-aarch64/binary/gzimg/arm64mbr.img.gz arm64mbr.img netbsd-arm64-smoke.py;;
 netbsd:11.0:x86_64) printf '%s\n' netbsd-x86_64 gzip sha512 a7aef57bd940bfd1e6d6fd34ba7b6f7459b8ed2084fe219314d345d07eb76a4ac0776b013b34e972c76f431039bf66485bfb94e6260f3ff6d66a811e4c0df55b https://cdn.netbsd.org/pub/NetBSD/NetBSD-11.0/images/NetBSD-11.0-amd64-live.img.gz NetBSD-11.0-amd64-live.img netbsd-live-smoke.py;;
 netbsd:11.0:i386) printf '%s\n' netbsd-i386 gzip sha512 5338b008fa421068c09938c593d7de275c5a7c73b0c70a9e9dc9a364420c6e97c1a0fbdc84ca89c21f904a49275ccba37b718f96407bf7d5c58a1aca7b94ddf1 https://cdn.netbsd.org/pub/NetBSD/NetBSD-11.0/i386/installation/installimage/NetBSD-11.0-i386-install.img.gz NetBSD-11.0-i386-install.img netbsd-i386-installed-smoke.py installed.qcow2 5a906a49ebf9a3d1b70581c5790de0a303cf2f1cc6b3d38ce905ad3767b35d1a;;
 openbsd:7.9:x86_64) printf '%s\n' openbsd-x86_64 raw sha256 7a4a92e953618035097c796a90b54424a0f3ae775552e1e7d102cf8a5130449f https://cdn.openbsd.org/pub/OpenBSD/7.9/amd64/install79.iso install79.iso openbsd-installed-smoke.py installed.qcow2 fdbdffb1de773a67857e702eb8276701b47a7828f27ea5819ff07a630f64cfd0;;
 openbsd:7.9:aarch64) printf '%s\n' openbsd-aarch64 raw sha256 551e411e46739a244376592568b3e131f029aebdce63030a7a42901dac292b8c https://cdn.openbsd.org/pub/OpenBSD/7.9/arm64/install79.img install79.img openbsd-arm64-installed-smoke.py installed.qcow2 daa123b4b1d7e74ad74473a24e121a0690c434742a68348090c231c7c9dd1eae;;
 dragonfly:6.2.2:x86_64) printf '%s\n' dragonfly-x86_64 bzip2 md5 4c46d6545e58bfda7d99bbb594ef0730 https://mirror-master.dragonflybsd.org/iso-images/dfly-x86_64-6.2.2_REL.img.bz2 dfly-x86_64-6.2.2_REL.img dragonfly-live-smoke.py;;
 dragonfly:6.4.2:x86_64) printf '%s\n' dragonfly-x86_64 bzip2 md5 a23812ca816df3de1e3eab5995e29025 https://mirror-master.dragonflybsd.org/iso-images/dfly-x86_64-6.4.2_REL.img.bz2 dfly-x86_64-6.4.2_REL.img dragonfly-live-smoke.py;;
 *) return 1;; esac
}
verify_file(){
 local algo="$1" expected="$2" file="$3" actual
 case "$algo" in sha256) actual="$(sha256sum "$file"|awk '{print $1}')";; sha512) actual="$(sha512sum "$file"|awk '{print $1}')";; md5) actual="$(md5sum "$file"|awk '{print $1}')";; *) return 2;; esac
 [[ "$actual" == "$expected" ]] || { echo "klab: checksum mismatch for $file" >&2; return 1; }
}
pull_target(){
 local target="$1" repo="$2" id codec algo digest url media harness derived_media derived_digest
 mapfile -t f < <(target_fields "$target") || { echo "klab: unsupported BSD simple target: $target" >&2; return 2; }
 id="${f[0]}"; codec="${f[1]}"; algo="${f[2]}"; digest="${f[3]}"; url="${f[4]}"; media="${f[5]}"; harness="${f[6]}"; derived_media="${f[7]:-}"; derived_digest="${f[8]:-}"
 local dest archive tmp
 dest="$repo/bsd/$(safe_id "$target")"; archive="$dest/${url##*/}"; tmp="$dest/.partial"
 mkdir -p "$dest"; rm -f "$tmp"
 if [[ ! -f "$archive" ]]; then curl -fL --retry 3 -C - -o "$tmp" "$url"; mv "$tmp" "$archive"; fi
 case "$codec" in
 raw) verify_file "$algo" "$digest" "$archive";;
 xz) verify_file "$algo" "$digest" "$archive"; [[ -f "$dest/$media" ]] || { xz -dc "$archive" >"$tmp"; mv "$tmp" "$dest/$media"; };;
 gzip) [[ -f "$dest/$media" ]] || { gzip -dc "$archive" >"$tmp"; verify_file "$algo" "$digest" "$tmp"; mv "$tmp" "$dest/$media"; }; verify_file "$algo" "$digest" "$dest/$media";;
 bzip2) [[ -f "$dest/$media" ]] || { bzip2 -dc "$archive" >"$tmp"; verify_file "$algo" "$digest" "$tmp"; mv "$tmp" "$dest/$media"; }; verify_file "$algo" "$digest" "$dest/$media";;
 esac
 cat >"$dest/target.env" <<EOF
TARGET=$(printf %q "$target")
MEDIA=$(printf %q "$media")
HARNESS=$(printf %q "$harness")
SOURCE_URL=$(printf %q "$url")
DIGEST_ALGORITHM=$(printf %q "$algo")
DIGEST=$(printf %q "$digest")
DERIVED_MEDIA=$(printf %q "$derived_media")
DERIVED_SHA256=$(printf %q "$derived_digest")
EOF
 printf 'BSD target stored: %s\n' "$dest"
}
run_target(){
 local target="$1" repo="$2" root="$3" mode="${4:-full}" dest
 case "$mode" in full|minimal|ssh|module) ;; *) echo "klab: BSD mode must be full, minimal, ssh, or module" >&2; return 2;; esac
 dest="$repo/bsd/$(safe_id "$target")"
 [[ -f "$dest/target.env" ]] || { echo "klab: target absent; run: klab pull $target" >&2; return 2; }
 source "$dest/target.env"; [[ "$TARGET" == "$target" && -f "$dest/$MEDIA" ]] || return 2
 local result="$root/results/bsd/$(safe_id "$target")/$mode"; mkdir -p "$result"
 if [[ "$mode" == module ]]; then
  "$SELF/bsd/bsd-module-smoke.sh" "$target" "$repo" "$root"
  return
 fi
 if [[ "$mode" == ssh ]]; then
  case "$target" in
   freebsd:14.5-RELEASE:riscv64) docker image inspect klab-qemu10-riscv64:local >/dev/null 2>&1 || docker build -f "$SELF/containers/qemu10-riscv64.Dockerfile" -t klab-qemu10-riscv64:local "$SELF/containers"; python3 "$SELF/bsd/freebsd-riscv64-smoke.py" --image "$dest/$MEDIA" --evidence-dir "$result" --ssh;;
   freebsd:14.5-RELEASE:i386) python3 "$SELF/bsd/native-ssh-smoke.py" --family freebsd --arch i386 --disk "$dest/$MEDIA" --format qcow2 --log "$result/ssh.log";;
   dragonfly:6.2.2:x86_64|dragonfly:6.4.2:x86_64) python3 "$SELF/bsd/native-ssh-smoke.py" --family dragonfly --arch x86_64 --disk "$dest/$MEDIA" --format raw --log "$result/ssh.log";;
   netbsd:11.0:aarch64) python3 "$SELF/bsd/native-ssh-smoke.py" --family netbsd --arch aarch64 --disk "$dest/$MEDIA" --format raw --log "$result/ssh.log";;
   netbsd:11.0:x86_64) python3 "$SELF/bsd/native-ssh-smoke.py" --family netbsd --arch x86_64 --disk "$dest/$MEDIA" --format raw --log "$result/ssh.log";;
   netbsd:11.0:i386) verify_file sha256 "$DERIVED_SHA256" "$dest/$DERIVED_MEDIA"; python3 "$SELF/bsd/native-ssh-smoke.py" --family netbsd --arch i386 --disk "$dest/$DERIVED_MEDIA" --format qcow2 --password 'KLabRoot7!' --log "$result/ssh.log";;
   openbsd:7.9:x86_64) verify_file sha256 "$DERIVED_SHA256" "$dest/$DERIVED_MEDIA"; python3 "$SELF/bsd/native-ssh-smoke.py" --family openbsd --arch x86_64 --disk "$dest/$DERIVED_MEDIA" --format qcow2 --password klabroot --log "$result/ssh.log";;
   openbsd:7.9:aarch64) verify_file sha256 "$DERIVED_SHA256" "$dest/$DERIVED_MEDIA"; python3 "$SELF/bsd/native-ssh-smoke.py" --family openbsd --arch aarch64 --disk "$dest/$DERIVED_MEDIA" --format qcow2 --password klabroot --log "$result/ssh.log";;
   *) echo "klab: SSH mode is not yet supported for $target" >&2; return 2;;
  esac
  printf 'BSD SSH evidence: %s/ssh.log\n' "$result"; return
 fi
 case "$target" in
 freebsd:14.5-RELEASE:i386) python3 "$SELF/bsd/$HARNESS" --image "$dest/$MEDIA" --overlay "$result/root-overlay.qcow2" --log "$result/smoke.log";;
 freebsd:14.5-RELEASE:riscv64)
  docker image inspect klab-qemu10-riscv64:local >/dev/null 2>&1 || docker build -f "$SELF/containers/qemu10-riscv64.Dockerfile" -t klab-qemu10-riscv64:local "$SELF/containers"
  python3 "$SELF/bsd/$HARNESS" --image "$dest/$MEDIA" --evidence-dir "$result";;
 netbsd:11.0:aarch64) python3 "$SELF/bsd/$HARNESS" --image "$dest/$MEDIA" --overlay "$result/root-overlay.qcow2" --log "$result/smoke.log";;
 netbsd:11.0:x86_64) python3 "$SELF/bsd/$HARNESS" --image "$dest/$MEDIA" --overlay "$result/root-overlay.qcow2" --log "$result/smoke.log";;
 netbsd:11.0:i386)
  [[ -n "${DERIVED_MEDIA:-}" && -f "$dest/$DERIVED_MEDIA" ]] || { echo "klab: NetBSD i386 requires the verified installed disk $dest/${DERIVED_MEDIA:-installed.qcow2}" >&2; return 2; }
  verify_file sha256 "$DERIVED_SHA256" "$dest/$DERIVED_MEDIA"
  rm -f "$result/native-overlay.qcow2"; qemu-img create -q -f qcow2 -F qcow2 -b "$(readlink -f "$dest/$DERIVED_MEDIA")" "$result/native-overlay.qcow2"
  python3 "$SELF/bsd/$HARNESS" --disk "$result/native-overlay.qcow2" --log "$result/smoke.log";;
 openbsd:7.9:x86_64)
  [[ -n "${DERIVED_MEDIA:-}" && -f "$dest/$DERIVED_MEDIA" ]] || { echo "klab: OpenBSD amd64 requires the verified installed disk $dest/${DERIVED_MEDIA:-installed.qcow2}" >&2; return 2; }
  verify_file sha256 "$DERIVED_SHA256" "$dest/$DERIVED_MEDIA"
  rm -f "$result/native-overlay.qcow2"; qemu-img create -q -f qcow2 -F qcow2 -b "$(readlink -f "$dest/$DERIVED_MEDIA")" "$result/native-overlay.qcow2"
  python3 "$SELF/bsd/$HARNESS" --disk "$result/native-overlay.qcow2" --log "$result/smoke.log";;
 openbsd:7.9:aarch64)
  [[ -n "${DERIVED_MEDIA:-}" && -f "$dest/$DERIVED_MEDIA" ]] || { echo "klab: OpenBSD arm64 requires the verified installed disk $dest/${DERIVED_MEDIA:-installed.qcow2}" >&2; return 2; }
  verify_file sha256 "$DERIVED_SHA256" "$dest/$DERIVED_MEDIA"
  rm -f "$result/native-overlay.qcow2"; qemu-img create -q -f qcow2 -F qcow2 -b "$(readlink -f "$dest/$DERIVED_MEDIA")" "$result/native-overlay.qcow2"
  python3 "$SELF/bsd/$HARNESS" --disk "$result/native-overlay.qcow2" --log "$result/smoke.log";;
 dragonfly:6.2.2:x86_64|dragonfly:6.4.2:x86_64) python3 "$SELF/bsd/$HARNESS" --image "$dest/$MEDIA" --overlay "$result/root-overlay.qcow2" --log "$result/smoke.log";;
 esac
 printf 'BSD %s evidence: %s/smoke.log\n' "$mode" "$result"
}
case "${1:-}" in
 supports) [[ $# == 2 ]] || usage; target_fields "$2" >/dev/null;;
 pull) [[ $# == 3 ]] || usage; pull_target "$2" "$3";;
 run) [[ $# == 4 || $# == 5 ]] || usage; run_target "$2" "$3" "$4" "${5:-full}";;
 list) printf '%s\n' freebsd:14.5-RELEASE:i386 freebsd:14.5-RELEASE:riscv64 netbsd:11.0:aarch64 netbsd:11.0:x86_64 netbsd:11.0:i386 openbsd:7.9:x86_64 openbsd:7.9:aarch64 dragonfly:6.2.2:x86_64 dragonfly:6.4.2:x86_64;;
 *) usage;; esac
