#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAKE="$T/fake-klab"
cat > "$FAKE" <<'SH'
#!/usr/bin/env bash
set -eu
cmd="${1:-}"; shift || true
case "$cmd" in
  arch-plan)
    arch="$1"
    cat <<JSON
{"execution":{"qemu_binary":"/bin/true"},"target_arch":"$arch"}
JSON
    ;;
  arch-smoke)
    target="$1"; shift
    arch=''; report=''
    while (($#)); do
      case "$1" in --arch) arch="$2"; shift 2;; --artifact-dir) report="$2"; shift 2;; --dry-run) dry=1; shift;; *) shift;; esac
    done
    if [[ "$target" == upstream:v3.6 && "$arch" == aarch64 ]]; then exit 2; fi
    if [[ -n "$report" ]]; then mkdir -p "$report"; printf '{"result":"PASS"}\n' > "$report/report.json"; fi
    echo "$target $arch"
    ;;
  *) exit 2;;
esac
SH
chmod +x "$FAKE"
export KLAB_ROOT="$T/lab"
RUN=resume-test
KLAB_MULTIARCH_KLAB="$FAKE" KLAB_MULTIARCH_ARCHES='i386' KLAB_I386_E2E_VERSIONS='v5.4 v6.6' KLAB_MULTIARCH_RUN_ID="$RUN" "$ROOT/klab-multiarch-overnight-r12.sh" >/dev/null
S="$KLAB_ROOT/results/logs/multiarch-e2e/$RUN/summary.tsv"
rows1="$(wc -l < "$S")"
KLAB_MULTIARCH_KLAB="$FAKE" KLAB_MULTIARCH_ARCHES='i386' KLAB_I386_E2E_VERSIONS='v5.4 v6.6' KLAB_MULTIARCH_RESUME_RUN_ID="$RUN" "$ROOT/klab-multiarch-overnight-r12.sh" >/dev/null
rows2="$(wc -l < "$S")"
[[ "$rows1" == "$rows2" ]] || { echo "FAIL: resume added duplicate rows ($rows1 -> $rows2)" >&2; exit 1; }
[[ "$(awk -F '\t' '$1=="i386" && $2=="upstream:v5.4"{n++} END{print n+0}' "$S")" == 1 ]] || { echo 'FAIL: i386 v5.4 duplicated' >&2; exit 1; }
[[ "$(awk -F '\t' '$1=="i386" && $2=="upstream:v6.6"{n++} END{print n+0}' "$S")" == 1 ]] || { echo 'FAIL: i386 v6.6 duplicated' >&2; exit 1; }
echo 'PASS: r12 multiarch overnight resume'
