#!/usr/bin/env bash
# KLab cross-distribution kernel acquisition queue v2
#
# Purpose:
#   Complement the native KLab wide sweep with kernels from additional
#   distributions and kernel families. The script is resumable, keeps per-target
#   logs, records failures, and continues through the whole queue.
#
# Native KLab provider paths used here:
#   - Ubuntu (also used for Linux Mint compatibility mappings)
#   - Debian (also used for LMDE compatibility mappings)
#   - CentOS Stream
#
# External distro path:
#   1. Start an ephemeral distro container.
#   2. Install the distro kernel + module-build headers/devel package.
#   3. Export /boot, /lib/modules, /usr/lib/modules, and /usr/src.
#   4. Locate an exact kernel image, module tree, and prepared build tree.
#   5. Register it with KLab as custom:<distro>:<exact-release>.
#   6. Prepare a portable .klab into the common export directory.
#
# If a distro package does not expose a usable external-module build tree, the
# target is retained as staged material and logged rather than falsely marked
# testable.
#
# Recommended use:
#   cd /path/to/current-klab-source
#   chmod +x klab-cross-distro-queue-v1.sh
#   ./klab-cross-distro-queue-v1.sh
#
# Useful overrides:
#   KLAB_ROOT="$HOME/klab" ./klab-cross-distro-queue-v1.sh
#   KLAB_SRC="$HOME/klab-r27" ./klab-cross-distro-queue-v1.sh
#   KLAB_CROSS_SECTIONS=arch,manjaro,oracle ./klab-cross-distro-queue-v1.sh
#   KLAB_CROSS_DRY_RUN=1 ./klab-cross-distro-queue-v1.sh
#   KLAB_CROSS_RUNTIME=podman ./klab-cross-distro-queue-v1.sh
#   KLAB_CROSS_KEEP_TARS=1 ./klab-cross-distro-queue-v1.sh
#
# Notes:
#   * Linux Mint normally consumes Ubuntu kernel packages. Mint entries are
#     therefore compatibility mappings to the exact Ubuntu kernel, not a claim
#     that Mint has a separate kernel ABI.
#   * LMDE similarly maps to Debian kernels.
#   * External distro targets do not currently capture a distro-native compiler
#     artifact. The distro's prepared header/build tree is preserved, but KLab
#     will build external modules with the host/compiler policy for custom
#     targets. This is intentionally visible in the summary.
#   * Run serially by default. Package managers and shared KLab stores are much
#     easier to reason about without concurrent writers.

set -uo pipefail

ARCH="${KLAB_CROSS_ARCH:-x86_64}"
KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"
KLAB_HOME="$KLAB_ROOT"
KLAB_SRC="${KLAB_SRC:-$PWD}"
SECTIONS="${KLAB_CROSS_SECTIONS:-mint,debian,centos,arch,manjaro,oracle,amazon,opensuse,kali,proxmox,rocky,alma,alpine}"
DRY_RUN="${KLAB_CROSS_DRY_RUN:-0}"
KEEP_TARS="${KLAB_CROSS_KEEP_TARS:-0}"
STRICT_EXIT="${KLAB_CROSS_STRICT_EXIT:-1}"
PREPARE_CUSTOM="${KLAB_CROSS_PREPARE_CUSTOM:-1}"
RECAPTURE="${KLAB_CROSS_RECAPTURE:-}"
RUNTIME="${KLAB_CROSS_RUNTIME:-}"

export KLAB_ROOT KLAB_HOME

if [[ -x "$KLAB_SRC/klab" ]]; then
    KLAB="$KLAB_SRC/klab"
elif [[ -x "$KLAB_SRC/kernel-lab.sh" ]]; then
    KLAB="$KLAB_SRC/kernel-lab.sh"
else
    echo "ERROR: cannot find executable '$KLAB_SRC/klab' or '$KLAB_SRC/kernel-lab.sh'" >&2
    echo "Set KLAB_SRC=/path/to/current-klab-source" >&2
    exit 2
fi

if [[ -z "$RUNTIME" ]]; then
    if command -v podman >/dev/null 2>&1; then
        RUNTIME=podman
    elif command -v docker >/dev/null 2>&1; then
        RUNTIME=docker
    else
        RUNTIME=""
    fi
fi

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
EXPORT_DIR="${KLAB_CROSS_EXPORT_DIR:-$KLAB_ROOT/transfer/exports/cross-distro-sweep}"
STAGE_ROOT="${KLAB_CROSS_STAGE_DIR:-$KLAB_ROOT/artifacts/external-kernels}"
LOG_ROOT="${KLAB_CROSS_LOG_DIR:-$KLAB_ROOT/results/logs/cross-distro-sweep}"
RUN_LOG_DIR="$LOG_ROOT/$RUN_ID"
DISCOVERY_DIR="$RUN_LOG_DIR/discovery"
TARGET_LOG_DIR="$RUN_LOG_DIR/targets"
CONTAINER_LOG_DIR="$RUN_LOG_DIR/containers"
MASTER_LOG="$RUN_LOG_DIR/master.log"
SUMMARY="$RUN_LOG_DIR/summary.tsv"
LATEST_SUMMARY="$LOG_ROOT/latest-summary.tsv"

mkdir -p "$EXPORT_DIR" "$STAGE_ROOT" "$DISCOVERY_DIR" "$TARGET_LOG_DIR" "$CONTAINER_LOG_DIR"
: > "$MASTER_LOG"
printf 'time\tkind\trequested\tresolved_target\tstatus\trc\toutput\tlog\tnote\n' > "$SUMMARY"
ln -sfn "$SUMMARY" "$LATEST_SUMMARY" 2>/dev/null || true

exec > >(tee -a "$MASTER_LOG") 2>&1

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

section_enabled() {
    local wanted="$1"
    case ",${SECTIONS// /,}," in
        *",all,"*|*",$wanted,"*) return 0 ;;
        *) return 1 ;;
    esac
}

sanitize() {
    printf '%s' "$1" | tr -cs 'A-Za-z0-9._+-' '_'
}

recapture_enabled() {
    local label="$1" normalized=",${RECAPTURE// /,},"
    case "$normalized" in
        *,1,*|*,all,*|*",$label,"*) return 0 ;;
        *) return 1 ;;
    esac
}

record() {
    local kind="$1" requested="$2" resolved="$3" status="$4" rc="$5"
    local output="${6:-}" log="${7:-}" note="${8:-}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(stamp)" "$kind" "$requested" "$resolved" "$status" "$rc" \
        "$output" "$log" "$note" >> "$SUMMARY"
}

print_cmd() {
    printf 'COMMAND:'
    printf ' %q' "$@"
    printf '\n'
}

run_logged() {
    local log="$1"
    shift
    mkdir -p "$(dirname "$log")"
    {
        printf '\n===== %s =====\n' "$(stamp)"
        print_cmd "$@"
    } | tee -a "$log"

    if [[ "$DRY_RUN" == 1 ]]; then
        echo "DRY-RUN: not executed" | tee -a "$log"
        return 0
    fi

    "$@" 2>&1 | tee -a "$log"
    local rc=${PIPESTATUS[0]}
    printf '===== rc=%d =====\n' "$rc" | tee -a "$log"
    return "$rc"
}

run_shell_logged() {
    local log="$1" script="$2"
    mkdir -p "$(dirname "$log")"
    {
        printf '\n===== %s =====\n' "$(stamp)"
        printf 'SHELL: %s\n' "$script"
    } | tee -a "$log"

    if [[ "$DRY_RUN" == 1 ]]; then
        echo "DRY-RUN: not executed" | tee -a "$log"
        return 0
    fi

    bash -o pipefail -c "$script" 2>&1 | tee -a "$log"
    local rc=${PIPESTATUS[0]}
    printf '===== rc=%d =====\n' "$rc" | tee -a "$log"
    return "$rc"
}

verified_output_exists() {
    local out="$1" verify_log="$2"
    [[ -s "$out" ]] || return 1
    [[ "$DRY_RUN" != 1 ]] || return 1
    run_logged "$verify_log" "$KLAB" verify "$out"
}

prepare_native_target() {
    local kind="$1" requested="$2" target="$3" label="$4" distro_toolchain="$5"
    local out="$EXPORT_DIR/${label}.klab"
    local log="$TARGET_LOG_DIR/${label}.log"
    local verify_log="$TARGET_LOG_DIR/${label}.verify.log"
    local -a cmd

    echo
    echo "================================================================"
    echo "QUEUE: $kind :: $requested"
    echo "TARGET: $target"
    echo "OUTPUT: $out"
    echo "================================================================"

    if verified_output_exists "$out" "$verify_log"; then
        record "$kind" "$requested" "$target" "SKIP_VERIFIED" 0 "$out" "$verify_log" ""
        return 0
    fi

    if [[ -e "$out" && "$DRY_RUN" != 1 ]]; then
        mv -f -- "$out" "${out}.invalid-${RUN_ID}" 2>/dev/null || true
    fi

    cmd=("$KLAB" prepare "$target" --arch "$ARCH" --artifact-dir "$EXPORT_DIR")
    [[ "$distro_toolchain" == 1 ]] && cmd+=(--distro-toolchain)
    cmd+=(-o "$out")

    run_logged "$log" "${cmd[@]}"
    local rc=$?
    if (( rc == 0 )); then
        record "$kind" "$requested" "$target" "PASS" 0 "$out" "$log" "native provider"
        return 0
    fi

    record "$kind" "$requested" "$target" "FAIL_PREPARE" "$rc" "$out" "$log" "native provider"
    echo "FAILED: $target (rc=$rc); continuing"
    return 1
}

resolve_apt_provider() {
    local provider="$1" release="$2" pattern="$3" flavor="$4"
    local id="$(sanitize "$provider-$release-$pattern-$flavor")"
    local log="$DISCOVERY_DIR/${id}.log"
    local regex krel rc

    run_logged "$log" "$KLAB" list "$provider:$release" "$pattern"
    rc=$?
    if (( rc != 0 )); then
        record "$provider-discovery" "$provider:$release:$pattern:$flavor" "" "FAIL_LIST" "$rc" "" "$log" ""
        return 1
    fi

    case "$provider" in
        ubuntu) regex='[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-(generic|lowlatency|aws|azure|gcp|oracle)' ;;
        debian) regex='[0-9]+\.[0-9]+\.[0-9]+(\+deb[0-9]+(\.[0-9]+)?|-[0-9]+)-(amd64|cloud-amd64|rt-amd64)' ;;
        *) return 1 ;;
    esac

    if [[ "$provider" == debian && "$flavor" == amd64 ]]; then
        # Do not let cloud-amd64 / rt-amd64 satisfy the plain amd64 request.
        krel="$({ grep -oE "$regex" "$log" || true; } \
            | grep -E "^${pattern//./\\.}([.+~-]|$)" \
            | grep -E '[0-9]+-amd64$' \
            | sort -Vu | tail -n1)"
    else
        krel="$({ grep -oE "$regex" "$log" || true; } \
            | grep -E "^${pattern//./\\.}([.+~-]|$)" \
            | grep -E -- "-${flavor}$" \
            | sort -Vu | tail -n1)"
    fi
    [[ -n "$krel" ]] || {
        record "$provider-discovery" "$provider:$release:$pattern:$flavor" "" "NO_MATCH" 0 "" "$log" ""
        return 1
    }
    printf '%s\n' "$krel"
}

queue_apt_probe() {
    local kind="$1" provider="$2" release="$3" pattern="$4" flavor="$5" label_prefix="$6"
    local captured krel target label requested
    requested="$kind:$release:$pattern:$flavor"
    captured="$(resolve_apt_provider "$provider" "$release" "$pattern" "$flavor")" || return 0
    krel="$(printf '%s\n' "$captured" | tail -n1)"
    [[ -n "$krel" ]] || return 0
    target="$provider:$release:$krel"
    label="$(sanitize "$label_prefix-$release-$krel")"
    prepare_native_target "$kind" "$requested" "$target" "$label" 1 || true
}

resolve_centos() {
    local release="$1" pattern="$2"
    local id="$(sanitize "centos-$release-$pattern")"
    local log="$DISCOVERY_DIR/${id}.log"
    local krel rc

    run_logged "$log" "$KLAB" list "centos:$release" "$pattern"
    rc=$?
    if (( rc != 0 )); then
        record "centos-discovery" "centos:$release:$pattern" "" "FAIL_LIST" "$rc" "" "$log" ""
        return 1
    fi

    krel="$({ grep -oE '[0-9][A-Za-z0-9._+~-]*el[0-9_\.]*\.(x86_64|aarch64)' "$log" || true; } | sort -Vu | tail -n1)"
    if [[ -z "$krel" ]]; then
        # Fallback: KLab's repoquery line is usually just EVR.arch.
        krel="$({ grep -oE '[0-9][^[:space:]]+\.(x86_64|aarch64)' "$log" || true; } | sort -Vu | tail -n1)"
    fi
    [[ -n "$krel" ]] || {
        record "centos-discovery" "centos:$release:$pattern" "" "NO_MATCH" 0 "" "$log" ""
        return 1
    }
    printf '%s\n' "$krel"
}

queue_centos_probe() {
    local release="$1" pattern="$2" captured krel target label
    captured="$(resolve_centos "$release" "$pattern")" || return 0
    krel="$(printf '%s\n' "$captured" | tail -n1)"
    [[ -n "$krel" ]] || return 0
    target="centos:$release:$krel"
    label="$(sanitize "centos-$release-$krel")"
    prepare_native_target "centos" "centos:$release:$pattern" "$target" "$label" 1 || true
}

require_runtime() {
    if [[ -n "$RUNTIME" ]]; then
        return 0
    fi
    echo "NO CONTAINER RUNTIME: install podman or docker, or set KLAB_CROSS_RUNTIME."
    return 1
}

container_archive_script() {
    local install_script="$1"
    cat <<EOF_CONTAINER
set -eu
$install_script
printf '%s\n' "image=/etc/os-release" > /out/container-provenance.txt
cat /etc/os-release >> /out/container-provenance.txt 2>/dev/null || true
paths=''
for p in boot lib/modules usr/lib/modules usr/src; do
    [ -e "/\$p" ] && paths="\$paths \$p"
done
[ -n "\$paths" ] || { echo 'No kernel paths found after package install' >&2; exit 71; }
tar -C / -cf /out/kernel-root.tar \$paths
EOF_CONTAINER
}

run_container_capture() {
    local kind="$1" label="$2" image="$3" install_script="$4"
    local stage="$STAGE_ROOT/$label"
    local tarfile="$stage/kernel-root.tar"
    local root="$stage/root"
    local marker="$stage/.capture-complete"
    local log="$CONTAINER_LOG_DIR/${label}.log"
    local script

    mkdir -p "$stage"

    if [[ -f "$marker" && -d "$root" ]]; then
        if ! recapture_enabled "$label"; then
            echo "SKIP CAPTURE: $label already staged"
            printf '%s\n' "$root"
            return 0
        fi
        echo "RECAPTURE: discarding staged external root for $label"
        rm -f "$marker" "$tarfile"
        rm -rf "$root"
    fi

    require_runtime || {
        record "$kind" "$label" "" "FAIL_NO_CONTAINER_RUNTIME" 127 "" "$log" ""
        return 1
    }

    script="$(container_archive_script "$install_script")"

    echo
    echo "--- Container capture: $label ($image) ---"
    {
        printf '\n===== %s =====\n' "$(stamp)"
        printf 'IMAGE: %s\n' "$image"
        printf 'RUNTIME: %s\n' "$RUNTIME"
        printf 'INSTALL SCRIPT:\n%s\n' "$install_script"
    } | tee -a "$log"

    if [[ "$DRY_RUN" == 1 ]]; then
        echo "DRY-RUN: container not executed" | tee -a "$log"
        record "$kind" "$label" "" "DRY_RUN_CAPTURE" 0 "$stage" "$log" "$image"
        printf '%s\n' "$root"
        return 0
    fi

    rm -f "$tarfile"
    rm -rf "$root"
    mkdir -p "$root"

    "$RUNTIME" run --rm \
        -v "$stage:/out" \
        "$image" sh -lc "$script" 2>&1 | tee -a "$log"
    local rc=${PIPESTATUS[0]}
    if (( rc != 0 )); then
        record "$kind" "$label" "" "FAIL_CONTAINER_CAPTURE" "$rc" "$stage" "$log" "$image"
        echo "FAILED CONTAINER CAPTURE: $label (rc=$rc); continuing"
        return 1
    fi

    if [[ ! -s "$tarfile" ]]; then
        record "$kind" "$label" "" "FAIL_NO_ARCHIVE" 72 "$stage" "$log" "$image"
        return 1
    fi

    tar --no-same-owner -C "$root" -xf "$tarfile" >>"$log" 2>&1
    rc=$?
    if (( rc != 0 )); then
        record "$kind" "$label" "" "FAIL_EXTRACT" "$rc" "$stage" "$log" "$image"
        return 1
    fi

    [[ "$KEEP_TARS" == 1 ]] || rm -f "$tarfile"
    touch "$marker"
    printf '%s\n' "$root"
}

resolve_root_link() {
    local root="$1" path="$2" target dir
    if [[ ! -L "$path" ]]; then
        printf '%s\n' "$path"
        return 0
    fi
    target="$(readlink "$path")"
    if [[ "$target" == /* ]]; then
        printf '%s%s\n' "$root" "$target"
    else
        dir="$(dirname "$path")"
        (cd "$dir" 2>/dev/null && readlink -f "$target") || return 1
    fi
}

find_build_tree() {
    local root="$1" krel="$2" p resolved
    for p in \
        "$root/lib/modules/$krel/build" \
        "$root/usr/lib/modules/$krel/build" \
        "$root/usr/src/kernels/$krel" \
        "$root/usr/src/linux-headers-$krel"; do
        [[ -e "$p" || -L "$p" ]] || continue
        resolved="$(resolve_root_link "$root" "$p" 2>/dev/null || true)"
        if [[ -n "$resolved" && -d "$resolved" && -f "$resolved/Makefile" ]]; then
            printf '%s\n' "$resolved"
            return 0
        fi
    done

    # SUSE and a few other distros use less direct layouts. Prefer a tree with
    # both Makefile and Module.symvers, then accept a prepared Makefile tree.
    p="$(find "$root/usr/src" -maxdepth 6 -type f -name Module.symvers -printf '%h\n' 2>/dev/null \
        | while read -r d; do [[ -f "$d/Makefile" ]] && printf '%s\n' "$d"; done \
        | head -n1)"
    [[ -n "$p" ]] && { printf '%s\n' "$p"; return 0; }

    p="$(find "$root/usr/src" -maxdepth 5 -type f -name Makefile -printf '%h\n' 2>/dev/null \
        | grep -E '(linux|kernel)' | head -n1)"
    [[ -n "$p" ]] && { printf '%s\n' "$p"; return 0; }
    return 1
}

find_kernel_image() {
    local root="$1" krel="$2" p
    for p in \
        "$root/boot/vmlinuz-$krel" \
        "$root/boot/vmlinuz" \
        "$root/usr/lib/modules/$krel/vmlinuz" \
        "$root/lib/modules/$krel/vmlinuz"; do
        [[ -f "$p" ]] && { printf '%s\n' "$p"; return 0; }
    done
    p="$(find "$root/boot" "$root/usr/lib/modules/$krel" "$root/lib/modules/$krel" \
        -maxdepth 2 -type f \( -name 'vmlinuz*' -o -name 'bzImage' -o -name 'Image' \) \
        2>/dev/null | sort | tail -n1)"
    [[ -n "$p" ]] && { printf '%s\n' "$p"; return 0; }
    return 1
}

find_module_dir() {
    local root="$1" krel="$2" p
    for p in "$root/lib/modules/$krel" "$root/usr/lib/modules/$krel"; do
        [[ -d "$p" ]] && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

candidate_releases() {
    local root="$1"
    {
        find "$root/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null || true
        find "$root/usr/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null || true
        find "$root/boot" -maxdepth 1 -type f -name 'vmlinuz-*' -printf '%f\n' 2>/dev/null \
            | sed 's/^vmlinuz-//' || true
    } | sort -Vu
}

register_external_root() {
    local kind="$1" requested="$2" label="$3" root="$4"
    local log="$TARGET_LOG_DIR/${label}.register.log"
    local krel kernel build modules name target out prep_log verify_log
    local found=0

    if [[ "$DRY_RUN" == 1 ]]; then
        record "$kind" "$requested" "custom:$label:<resolved>" "DRY_RUN_REGISTER" 0 "$root" "$log" ""
        return 0
    fi

    while read -r krel; do
        [[ -n "$krel" ]] || continue
        kernel="$(find_kernel_image "$root" "$krel" 2>/dev/null || true)"
        build="$(find_build_tree "$root" "$krel" 2>/dev/null || true)"
        modules="$(find_module_dir "$root" "$krel" 2>/dev/null || true)"
        [[ -n "$kernel" && -f "$kernel" ]] || continue
        [[ -n "$build" && -d "$build" ]] || continue
        found=1
        break
    done < <(candidate_releases "$root")

    if (( found == 0 )); then
        record "$kind" "$requested" "" "STAGED_NO_BUILD_TREE" 0 "$root" "$log" \
            "kernel payload retained; no matching image+prepared module build tree found"
        echo "STAGED ONLY: $requested; no usable image/build-tree pair found"
        return 0
    fi

    name="$(sanitize "$label")"
    target="custom:$name:$krel"

    echo "Resolved external target: $target"
    echo "  kernel:  $kernel"
    echo "  build:   $build"
    echo "  modules: ${modules:-none}"

    local -a reg=("$KLAB" register-linux "$name" --release "$krel" --kernel "$kernel" --build-dir "$build" --arch "$ARCH" --copy)
    [[ -n "$modules" ]] && reg+=(--modules-dir "$modules")

    run_logged "$log" "${reg[@]}"
    local rc=$?
    if (( rc != 0 )); then
        record "$kind" "$requested" "$target" "FAIL_REGISTER" "$rc" "$root" "$log" \
            "external target; distro-native compiler provenance not yet captured"
        return 1
    fi

    if [[ "$PREPARE_CUSTOM" != 1 ]]; then
        record "$kind" "$requested" "$target" "PASS_REGISTERED" 0 "$root" "$log" \
            "external target; distro-native compiler provenance not yet captured"
        return 0
    fi

    out="$EXPORT_DIR/${label}-${krel}.klab"
    prep_log="$TARGET_LOG_DIR/${label}.prepare.log"
    verify_log="$TARGET_LOG_DIR/${label}.verify.log"

    if verified_output_exists "$out" "$verify_log"; then
        record "$kind" "$requested" "$target" "SKIP_VERIFIED" 0 "$out" "$verify_log" \
            "external custom target; host/custom compiler policy"
        return 0
    fi

    [[ -e "$out" ]] && mv -f -- "$out" "${out}.invalid-${RUN_ID}" 2>/dev/null || true
    run_logged "$prep_log" "$KLAB" prepare "$target" --arch "$ARCH" --artifact-dir "$EXPORT_DIR" -o "$out"
    rc=$?
    if (( rc == 0 )); then
        record "$kind" "$requested" "$target" "PASS" 0 "$out" "$prep_log" \
            "external custom target; host/custom compiler policy"
    else
        record "$kind" "$requested" "$target" "FAIL_PREPARE" "$rc" "$out" "$prep_log" \
            "registration succeeded; portable prepare failed"
        return 1
    fi
}

queue_external() {
    local kind="$1" label="$2" image="$3" install_script="$4"
    local root captured
    captured="$(run_container_capture "$kind" "$label" "$image" "$install_script")" || return 0
    root="$(printf '%s\n' "$captured" | tail -n1)"
    [[ -n "$root" ]] || return 0
    register_external_root "$kind" "$label" "$label" "$root" || true
}

on_interrupt() {
    echo
    echo "INTERRUPTED: progress is preserved. Re-run the same script to resume."
    echo "Summary: $SUMMARY"
    exit 130
}
trap on_interrupt INT TERM

cat <<INFO
KLab cross-distro kernel queue
  source:       $KLAB_SRC
  cli:          $KLAB
  root:         $KLAB_ROOT
  arch:         $ARCH
  sections:     $SECTIONS
  runtime:      ${RUNTIME:-none}
  export:       $EXPORT_DIR
  staging:      $STAGE_ROOT
  run logs:     $RUN_LOG_DIR
  dry run:      $DRY_RUN
  prepare ext:  $PREPARE_CUSTOM
  recapture:    ${RECAPTURE:-none}
INFO

run_logged "$RUN_LOG_DIR/init.log" "$KLAB" init --staging
rc=$?
record "preflight" "init --staging" "" "$([[ $rc == 0 ]] && echo PASS || echo FAIL)" "$rc" "" "$RUN_LOG_DIR/init.log" ""

run_logged "$RUN_LOG_DIR/doctor.log" "$KLAB" doctor
rc=$?
record "preflight" "doctor" "" "$([[ $rc == 0 ]] && echo PASS || echo FAIL)" "$rc" "" "$RUN_LOG_DIR/doctor.log" ""

# ---------------------------------------------------------------------------
# Linux Mint compatibility matrix.
# Mint mainstream editions use Ubuntu package bases; LMDE uses Debian.
# These entries deliberately map to the corresponding native provider kernel.
# ---------------------------------------------------------------------------
if section_enabled mint; then
    echo
    echo "######################## MINT COMPAT ########################"
    while IFS='|' read -r mint provider release pattern flavor; do
        [[ -n "$mint" && "${mint:0:1}" != '#' ]] || continue
        queue_apt_probe "mint-compat-$mint" "$provider" "$release" "$pattern" "$flavor" "mint-$mint"
    done <<'MINT_MATRIX'
# mint release|provider|base release|kernel pattern|flavor
20.3|ubuntu|20.04|5.4|generic
20.3-hwe|ubuntu|20.04|5.15|generic
21.3|ubuntu|22.04|5.15|generic
21.3-hwe|ubuntu|22.04|6.8|generic
22.3|ubuntu|24.04|6.8|generic
22.3-hwe|ubuntu|24.04|6.14|generic
lmde6|debian|bookworm|6.1|amd64
lmde7|debian|trixie|6.12|amd64
MINT_MATRIX
fi

# ---------------------------------------------------------------------------
# Debian: native KLab provider. Include normal, cloud, and RT flavors.
# ---------------------------------------------------------------------------
if section_enabled debian; then
    echo
    echo "######################## DEBIAN ########################"
    while IFS='|' read -r release pattern flavor; do
        [[ -n "$release" && "${release:0:1}" != '#' ]] || continue
        queue_apt_probe "debian" "debian" "$release" "$pattern" "$flavor" "debian"
    done <<'DEBIAN_MATRIX'
# release|kernel pattern|flavor
bookworm|6.1|amd64
bookworm|6.1|cloud-amd64
bookworm|6.1|rt-amd64
trixie|6.12|amd64
trixie|6.12|cloud-amd64
trixie|6.12|rt-amd64
DEBIAN_MATRIX
fi

# ---------------------------------------------------------------------------
# CentOS Stream: native KLab provider.
# ---------------------------------------------------------------------------
if section_enabled centos; then
    echo
    echo "###################### CENTOS STREAM ######################"
    queue_centos_probe stream9 5.14
    queue_centos_probe stream10 6.12
fi

# ---------------------------------------------------------------------------
# Arch Linux: current distro kernel variants. These are materially useful
# because Arch ships separate standard, LTS, Zen, and hardened kernel builds.
# ---------------------------------------------------------------------------
if section_enabled arch; then
    echo
    echo "######################## ARCH ########################"
    queue_external arch arch-linux-current archlinux:base \
        'pacman -Syu --noconfirm && pacman -S --noconfirm --needed linux linux-headers'
    queue_external arch arch-linux-lts archlinux:base \
        'pacman -Syu --noconfirm && pacman -S --noconfirm --needed linux-lts linux-lts-headers'
    queue_external arch arch-linux-zen archlinux:base \
        'pacman -Syu --noconfirm && pacman -S --noconfirm --needed linux-zen linux-zen-headers'
    queue_external arch arch-linux-hardened archlinux:base \
        'pacman -Syu --noconfirm && pacman -S --noconfirm --needed linux-hardened linux-hardened-headers'
fi

# ---------------------------------------------------------------------------
# Manjaro: one distro intentionally exposing many simultaneous kernel series.
# Missing/EOL series simply fail and the queue continues.
# ---------------------------------------------------------------------------
if section_enabled manjaro; then
    echo
    echo "######################## MANJARO ########################"
    MANJARO_IMAGE="${KLAB_MANJARO_IMAGE:-manjarolinux/base:latest}"
    for pkg in linux61 linux66 linux612 linux618 linux72; do
        queue_external manjaro "manjaro-$pkg" "$MANJARO_IMAGE" \
            "pacman -Syu --noconfirm && pacman -S --noconfirm --needed $pkg $pkg-headers"
    done
fi

# ---------------------------------------------------------------------------
# Oracle Linux UEK. UEK is a distinct enterprise kernel line and particularly
# valuable compared with another generic RHEL rebuild.
# ---------------------------------------------------------------------------
if section_enabled oracle; then
    echo
    echo "######################## ORACLE UEK ########################"
    queue_external oracle oracle-linux-8-uek oraclelinux:8 \
        'dnf -y install dnf-plugins-core oraclelinux-release-el8 tar && dnf config-manager --set-enabled ol8_UEKR7 && dnf -y install kernel-uek kernel-uek-devel'
    queue_external oracle oracle-linux-9-uek oraclelinux:9 \
        'dnf -y install dnf-plugins-core oraclelinux-release-el9 tar && dnf config-manager --set-enabled ol9_UEKR8 && dnf -y install kernel-uek kernel-uek-devel'
    queue_external oracle oracle-linux-10-uek oraclelinux:10 \
        'dnf -y install dnf-plugins-core oraclelinux-release-el10 tar && dnf config-manager --set-enabled ol10_UEKR8 && dnf -y install kernel-uek kernel-uek-devel'
fi

# ---------------------------------------------------------------------------
# Amazon Linux 2023. Keep separate LTS kernel families because Amazon supports
# overlapping kernel generations for migration/testing.
# ---------------------------------------------------------------------------
if section_enabled amazon; then
    echo
    echo "######################## AMAZON LINUX ########################"
    queue_external amazon amazon-linux-2023-kernel61 amazonlinux:2023 \
        'dnf -y install tar kernel kernel-devel'
    queue_external amazon amazon-linux-2023-kernel612 amazonlinux:2023 \
        'dnf -y install tar kernel6.12 kernel6.12-devel'
    queue_external amazon amazon-linux-2023-kernel618 amazonlinux:2023 \
        'dnf -y install tar kernel6.18 kernel6.18-devel'
fi

# ---------------------------------------------------------------------------
# openSUSE: stable Leap plus rolling Tumbleweed.
# ---------------------------------------------------------------------------
if section_enabled opensuse; then
    echo
    echo "######################## OPENSUSE ########################"
    queue_external opensuse opensuse-leap-15.6 opensuse/leap:15.6 \
        'zypper -n refresh && zypper -n install --no-recommends tar kernel-default kernel-devel kernel-default-devel'
    queue_external opensuse opensuse-leap-16.0 opensuse/leap:16.0 \
        'zypper -n refresh && zypper -n install --no-recommends tar kernel-default kernel-devel kernel-default-devel'
    queue_external opensuse opensuse-tumbleweed opensuse/tumbleweed:latest \
        'zypper -n refresh && zypper -n install --no-recommends tar kernel-default kernel-devel kernel-default-devel'
fi

# ---------------------------------------------------------------------------
# Kali rolling: Debian family but Kali carries its own kernel build/config.
# ---------------------------------------------------------------------------
if section_enabled kali; then
    echo
    echo "######################## KALI ########################"
    queue_external kali kali-rolling kalilinux/kali-rolling:latest \
        'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends linux-image-amd64 linux-headers-amd64'
fi

# ---------------------------------------------------------------------------
# Proxmox VE: virtualization-focused Debian-derived kernel. Public
# pve-no-subscription repository; no enterprise entitlement is required.
# ---------------------------------------------------------------------------
if section_enabled proxmox; then
    echo
    echo "######################## PROXMOX ########################"
    queue_external proxmox proxmox-ve8-kernel68 debian:bookworm-slim \
        'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates wget gnupg && wget -qO /usr/share/keyrings/proxmox-archive-keyring.gpg https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg && echo "deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" >/etc/apt/sources.list.d/pve.list && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends proxmox-kernel-6.8 proxmox-headers-6.8'
    queue_external proxmox proxmox-ve9-kernel614 debian:trixie-slim \
        'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates wget gnupg && wget -qO /usr/share/keyrings/proxmox-archive-keyring.gpg https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg && echo "deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription" >/etc/apt/sources.list.d/pve.list && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends proxmox-kernel-6.14 proxmox-headers-6.14'
    queue_external proxmox proxmox-ve9-kernel617 debian:trixie-slim \
        'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates wget gnupg && wget -qO /usr/share/keyrings/proxmox-archive-keyring.gpg https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg && echo "deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription" >/etc/apt/sources.list.d/pve.list && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends proxmox-kernel-6.17 proxmox-headers-6.17'
    queue_external proxmox proxmox-ve9-kernel70 debian:trixie-slim \
        'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates wget gnupg && wget -qO /usr/share/keyrings/proxmox-archive-keyring.gpg https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg && echo "deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription" >/etc/apt/sources.list.d/pve.list && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends proxmox-kernel-7.0 proxmox-headers-7.0'
fi

# ---------------------------------------------------------------------------
# Rocky / Alma: useful exact vendor builds, though lower priority because they
# are intentionally close to RHEL/CentOS Stream.
# ---------------------------------------------------------------------------
if section_enabled rocky; then
    echo
    echo "######################## ROCKY ########################"
    queue_external rocky rocky-linux-9 rockylinux:9 \
        'dnf -y install kernel-core kernel-modules kernel-devel'
    queue_external rocky rocky-linux-10 rockylinux/rockylinux:10 \
        'dnf -y install kernel-core kernel-modules kernel-devel'
fi

if section_enabled alma; then
    echo
    echo "######################## ALMALINUX ########################"
    queue_external alma almalinux-9 almalinux:9 \
        'dnf -y install kernel-core kernel-modules kernel-devel'
    queue_external alma almalinux-10 almalinux:10 \
        'dnf -y install kernel-core kernel-modules kernel-devel'
fi

# ---------------------------------------------------------------------------
# Alpine: worth collecting because its kernel packaging/configuration differs,
# but linux-headers is normally userspace/UAPI headers rather than a complete
# prepared external-module build tree. These often end as STAGED_NO_BUILD_TREE,
# which is expected and identifies a future Alpine provider task.
# ---------------------------------------------------------------------------
if section_enabled alpine; then
    echo
    echo "######################## ALPINE ########################"
    queue_external alpine alpine-linux-lts alpine:latest \
        'apk update && apk add linux-lts linux-lts-dev'
    queue_external alpine alpine-linux-virt alpine:latest \
        'apk update && apk add linux-virt linux-virt-dev'
fi

echo
echo "######################## SUMMARY ########################"
echo "Run summary: $SUMMARY"
echo "Master log: $MASTER_LOG"
echo "Export dir: $EXPORT_DIR"
echo "External staging: $STAGE_ROOT"
echo
column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
echo

echo "Status counts:"
awk -F '\t' 'NR > 1 { count[$5]++ } END { for (s in count) printf "  %-36s %d\n", s, count[s] }' "$SUMMARY" | sort

failures="$(awk -F '\t' 'NR > 1 && $5 ~ /^FAIL/ {n++} END {print n+0}' "$SUMMARY")"
staged="$(awk -F '\t' 'NR > 1 && $5 == "STAGED_NO_BUILD_TREE" {n++} END {print n+0}' "$SUMMARY")"
no_matches="$(awk -F '\t' 'NR > 1 && $5 == "NO_MATCH" {n++} END {print n+0}' "$SUMMARY")"

echo
echo "Completed cross-distro queue. failures=$failures staged_only=$staged no_matches=$no_matches"
echo "Re-run to retry failures and reuse already captured/verified targets."

if [[ "$STRICT_EXIT" == 1 && "$failures" -gt 0 ]]; then
    exit 1
fi
exit 0
