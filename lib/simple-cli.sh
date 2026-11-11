#!/usr/bin/env bash
# Stable, small KLab 1.0 command surface. Internal stores remain beneath KLAB_ROOT.
source "$KLAB_SELF_DIR/lib/suite-queue.sh"

klab_simple_repo() {
  local configured=""
  [[ -f "$KLAB_CONFIG/offline-repo" ]] && configured="$(cat "$KLAB_CONFIG/offline-repo")"
  printf '%s\n' "${KLAB_REPO:-${configured:-$HOME/klab-offline}}"
}

klab_simple_bsd_helper() {
  printf '%s\n' "${KLAB_BSD_HELPER:-$KLAB_SELF_DIR/bsd/bsd-simple.sh}"
}

klab_simple_bsd_supported() {
  "$(klab_simple_bsd_helper)" supports "$1" >/dev/null 2>&1
}

klab_simple_setup() {
  local repo="$(klab_simple_repo)"
  while (($#)); do
    case "$1" in
      --repo) [[ $# -ge 2 ]] || { echo 'klab: --repo needs a directory' >&2; return 2; }; repo="$2"; shift 2 ;;
      --root) shift 2 ;; # consumed before lib/klab-root.sh is loaded
      *) echo "klab: unknown setup option: $1" >&2; return 2 ;;
    esac
  done
  klab_root_ensure_layout
  "$KLAB_RUNNER" init --staging >/dev/null
  mkdir -p "$repo" "$KLAB_ROOT/suites"
  repo="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$repo")"
  printf '%s\n' "$repo" > "$KLAB_CONFIG/offline-repo"
  printf 'KLab root: %s\nOffline repository: %s\n' "$KLAB_ROOT" "$repo"
  printf 'Next: klab pull upstream:v6.6 --arch x86_64\n'
}

klab_simple_pull() {
  (($# >= 1)) || { echo 'usage: klab pull TARGET [--arch ARCH] [prepare options]' >&2; return 2; }
  local target="$1"; shift
  local repo="$(klab_simple_repo)" userspace_seen=0 sdk_seen=0 arg
  mkdir -p "$repo"
  if klab_simple_bsd_supported "$target"; then
    (($# == 0)) || { echo 'klab: BSD simple pull takes its architecture from TARGET' >&2; return 2; }
    "$(klab_simple_bsd_helper)" pull "$target" "$repo"
    return
  fi
  for arg in "$@"; do [[ "$arg" == --userspace ]] && userspace_seen=1; [[ "$arg" == --with-sdk ]] && sdk_seen=1; done
  local -a args=("$target" --artifact-dir "$repo")
  if [[ "$target" == upstream:v2.* ]]; then
    ((userspace_seen)) || args+=(--userspace busybox-static)
  elif [[ "$target" != freebsd:* ]]; then
    ((userspace_seen)) || args+=(--userspace buildroot:minimal)
    ((sdk_seen)) || args+=(--with-sdk)
  fi
  args+=("$@")
  "$KLAB_RUNNER" prepare "${args[@]}"
  if [[ "${KLAB_DEFER_REPO_INDEX:-0}" == 1 ]]; then
    printf 'Offline repository artifact added; index deferred: %s\n' "$repo"
  else
    "${KLAB_INDEXER:-$KLAB_SELF_DIR/beta-tools/index-repository.sh}" "$repo" >/dev/null
    printf 'Offline repository updated: %s\n' "$repo"
  fi
}

klab_simple_load() {
  local repo="$(klab_simple_repo)" source="${1:-$repo}"
  [[ $# -le 1 ]] || { echo 'usage: klab load [FILE.klab|REPOSITORY]' >&2; return 2; }
  [[ -e "$source" ]] || { echo "klab: offline artifact not found: $source" >&2; return 2; }
  if [[ -f "$source" ]]; then
    source="$(python3 "$KLAB_SELF_DIR/tools/klab-stage.py" stage "$source")"
  fi
  "$KLAB_RUNNER" import "$source"
}

klab_simple_build() {
  (($# >= 1)) || { echo 'usage: klab build TARGET MODULE_DIR [--arch ARCH] [-o DIR]' >&2; return 2; }
  local target="$1"; shift
  if [[ "${1:-}" == --module ]]; then
    "$KLAB_RUNNER" build-module "$target" "$@"
  else
    (($# >= 1)) || { echo 'klab: build needs a module directory' >&2; return 2; }
    local module="$1"; shift
    "$KLAB_RUNNER" build-module "$target" --module "$module" "$@"
  fi
}

klab_simple_build_user() {
  (($# >= 2)) || { echo 'usage: klab build-user TARGET SOURCE.c [--arch ARCH] [-o FILE] [-- CC_FLAGS...]' >&2; return 2; }
  local target="$1" source="$2"; shift 2
  if [[ "$source" == --source ]]; then
    (($# >= 1)) || { echo 'klab: --source needs a C source file' >&2; return 2; }
    "$KLAB_RUNNER" build-user "$target" --source "$@"
  else
    "$KLAB_RUNNER" build-user "$target" --source "$source" "$@"
  fi
}

klab_simple_start() {
  (($# >= 1)) || { echo 'usage: klab start TARGET [--name SESSION] [--arch ARCH] [--userspace SPEC] [boot options]' >&2; return 2; }
  "$KLAB_RUNNER" boot "$@"
}

klab_suite_dir() { printf '%s/suites/%s\n' "$KLAB_ROOT" "$1"; }
klab_suite_name_ok() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }

klab_suite_validate() {
  python3 "$KLAB_SELF_DIR/lib/suite_plan.py" validate "$1/suite.json"
}

klab_simple_suite() {
  local action="${1:-list}"; (($#)) && shift
  mkdir -p "$KLAB_ROOT/suites"
  case "$action" in
    create)
      (($# == 1)) || { echo 'usage: klab suite create NAME' >&2; return 2; }
      local name="$1"
      klab_suite_name_ok "$name" || { echo 'klab: suite names use letters, numbers, dot, underscore, and dash' >&2; return 2; }
      local dir="$(klab_suite_dir "$name")"
      [[ ! -e "$dir" ]] || { echo "klab: suite already exists: $1" >&2; return 2; }
      mkdir -p "$dir/hello-module"; cp "$KLAB_SELF_DIR/examples/scenarios/ordered-suite.json" "$dir/scenario.json"
      cp "$KLAB_SELF_DIR/examples/hello-module/Makefile" "$KLAB_SELF_DIR/examples/hello-module/hello.c" "$dir/hello-module/"
      cp "$KLAB_SELF_DIR/examples/scenario-worker.c" "$dir/scenario-worker.c"
      cat > "$dir/klab.toml" <<'TOML'
[test]
script = "test.sh"
timeout = 300
userspace = "auto"

[module.hello]
source = "hello-module"
unload = true
TOML
      cat > "$dir/test.sh" <<'TEST'
#!/usr/bin/env bash
set -Eeuo pipefail

klab module load target hello
kernel="$(klab exec target -- uname -r)"
klab expect matches "$kernel" '^[0-9]'
klab exec target -- dmesg
TEST
      chmod +x "$dir/test.sh"
        python3 - "$dir/suite.json" "$name" <<'PY'
import json,sys
json.dump({'schema':'klab-suite-v2','name':sys.argv[2],'description':'Ordered module and userspace compatibility suite','scenario':'scenario.json','targets':[]},open(sys.argv[1],'w'),indent=2,sort_keys=True);open(sys.argv[1],'a').write('\n')
PY
      printf 'Created suite: %s\nEdit klab.toml and test.sh, then run: klab test %s on TARGET@ARCH\nLegacy scenario queue files are also included.\n' "$dir" "$name"
      ;;
    list)
      find "$KLAB_ROOT/suites" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort ;;
    show)
      (($# == 1)) || { echo 'usage: klab suite show NAME' >&2; return 2; }
      local dir="$(klab_suite_dir "$1")"; klab_suite_validate "$dir" >/dev/null; cat "$dir/suite.json" ;;
    run)
      (($# >= 2)) || { echo 'usage: klab suite run NAME TARGET [--arch ARCH]' >&2; return 2; }
      local name="$1" target="$2" dir arch='' output='' dry_run=0; shift 2; dir="$(klab_suite_dir "$name")"; klab_suite_validate "$dir" >/dev/null || return
      while (($#)); do case "$1" in --arch) [[ $# -ge 2 ]] || { echo 'klab: --arch needs a value' >&2; return 2; }; arch="$2"; shift 2;; --output) [[ $# -ge 2 ]] || { echo 'klab: --output needs a directory' >&2; return 2; }; output="$2"; shift 2;; --dry-run) dry_run=1; shift;; *) echo "klab: unknown suite run option: $1" >&2; return 2;; esac; done
      [[ -n "$arch" ]] || { echo 'klab: unified suite run requires --arch ARCH' >&2; return 2; }
      local -a runargs=(--only-target "$target@$arch"); [[ -n "$output" ]] && runargs+=(--output "$output"); [[ "${dry_run:-0}" == 1 ]] && runargs+=(--dry-run)
      klab_suite_queue "$dir" "${runargs[@]}"
      ;;
    migrate)
      (($# == 1)) || { echo 'usage: klab suite migrate NAME' >&2; return 2; }
      local dir="$(klab_suite_dir "$1")"; [[ -d "$dir" ]] || { echo "klab: unknown suite: $1" >&2; return 2; }
      python3 "$KLAB_SELF_DIR/lib/suite_migrate.py" "$dir"
      ;;
    queue)
      (($# >= 1)) || { echo 'usage: klab suite queue NAME [--all] [--target TARGET@ARCH] [--target-file FILE] [--resume] [--dry-run]' >&2; return 2; }
      local name="$1" dir; shift; dir="$(klab_suite_dir "$name")"; [[ -d "$dir" ]] || { echo "klab: unknown suite: $name" >&2; return 2; }
      klab_suite_queue "$dir" "$@"
      ;;
    *) echo 'usage: klab suite <create|list|show|run|queue|migrate> ...' >&2; return 2 ;;
  esac
}

klab_simple_run() {
  (($# >= 1)) || { echo 'usage: klab run TARGET [--suite NAME] [--arch ARCH]' >&2; return 2; }
  local target="$1"; shift
  if [[ "${1:-}" == --suite ]]; then
    [[ $# -ge 2 ]] || { echo 'klab: --suite needs a name' >&2; return 2; }
    local suite="$2"; shift 2
    klab_simple_suite run "$suite" "$target" "$@"
  else
    if klab_simple_bsd_supported "$target"; then
      local mode=full
      while (($#)); do
        case "$1" in
          --mode) [[ $# -ge 2 ]] || { echo 'klab: --mode needs minimal, ssh, or full' >&2; return 2; }; mode="$2"; shift 2 ;;
          *) echo 'klab: BSD run accepts --mode minimal|ssh|full; architecture comes from TARGET' >&2; return 2 ;;
        esac
      done
      "$(klab_simple_bsd_helper)" run "$target" "$(klab_simple_repo)" "$KLAB_ROOT" "$mode"
    else
      "$KLAB_RUNNER" smoke "$target" "$@"
    fi
  fi
}

klab_simple_bsd() {
  local action="${1:-list}"
  case "$action" in
    list) "$(klab_simple_bsd_helper)" list ;;
    status) python3 "$KLAB_SELF_DIR/tools/bsd-v1-status.py" ;;
    *) echo 'usage: klab bsd <list|status>' >&2; return 2 ;;
  esac
}

klab_simple_repo_cmd() {
  local action="${1:-list}" repo="$(klab_simple_repo)"; (($#)) && shift
  case "$action" in
    path) printf '%s\n' "$repo" ;;
    index) mkdir -p "$repo"; "${KLAB_INDEXER:-$KLAB_SELF_DIR/beta-tools/index-repository.sh}" "$repo" ;;
    list) [[ -f "$repo/INDEX.tsv" ]] && column -t -s $'\t' "$repo/INDEX.tsv" 2>/dev/null || { [[ -f "$repo/INDEX.tsv" ]] && cat "$repo/INDEX.tsv" || printf 'Repository is empty: %s\n' "$repo"; } ;;
    volume-add) (($# == 1)) || { echo 'usage: klab repo volume-add DIR' >&2; return 2; }; python3 "$KLAB_SELF_DIR/tools/klab-stage.py" volume-add "$1" ;;
    volumes) (($# == 0)) || { echo 'usage: klab repo volumes' >&2; return 2; }; python3 "$KLAB_SELF_DIR/tools/klab-stage.py" volume-list ;;
    stage) (($# == 1)) || { echo 'usage: klab repo stage ARTIFACT' >&2; return 2; }; python3 "$KLAB_SELF_DIR/tools/klab-stage.py" stage "$1" ;;
    cache-status) python3 "$KLAB_SELF_DIR/tools/klab-stage.py" status ;;
    cache-prune) python3 "$KLAB_SELF_DIR/tools/klab-stage.py" prune "$@" ;;
    snapshot) (($# >= 1)) || { echo 'usage: klab repo snapshot NAME [--parent NAME]' >&2; return 2; }; local name="$1"; shift; python3 "$KLAB_SELF_DIR/tools/klab-repo-release.py" snapshot "$repo" "$name" "$@" ;;
    export-release) (($# >= 3 && "$2" == -o)) || { echo 'usage: klab repo export-release NAME -o FILE.tar.zst' >&2; return 2; }; python3 "$KLAB_SELF_DIR/tools/klab-repo-release.py" export "$repo" "$1" -o "$3" ;;
    apply-release) (($# >= 1)) || { echo 'usage: klab repo apply-release FILE.tar.zst [--apply-removals]' >&2; return 2; }; local archive="$1"; shift; python3 "$KLAB_SELF_DIR/tools/klab-repo-release.py" apply "$repo" "$archive" "$@" ;;
    releases) python3 "$KLAB_SELF_DIR/tools/klab-repo-release.py" list "$repo" ;;
    *) echo 'usage: klab repo <path|list|index|snapshot|export-release|apply-release|releases|volume-add|volumes|stage|cache-status|cache-prune>' >&2; return 2 ;;
  esac
}

klab_simple_legacy() {
  local action="${1:-list}" manifest="$KLAB_SELF_DIR/legacy/targets-v1.json"; (($#)) && shift
  case "$action" in
    list)
      python3 - "$manifest" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); print('ID\tTARGET\tARCH\tREQUIRED\tSTATUS')
for t in m['targets']: print('\t'.join(t[k] for k in ('id','target','arch','required_level','status')))
PY
      ;;
    plan)
      (($# == 1)) || { echo 'usage: klab legacy plan ID' >&2; return 2; }
      python3 - "$manifest" "$1" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); found=[x for x in m['targets'] if x['id']==sys.argv[2]]
if not found: raise SystemExit('unknown legacy target: '+sys.argv[2])
print(json.dumps({'schema':m['schema'],'success_levels':m['success_levels'],'target':found[0]},indent=2,sort_keys=True))
PY
      ;;
    *) echo 'usage: klab legacy <list|plan ID>' >&2; return 2 ;;
  esac
}
