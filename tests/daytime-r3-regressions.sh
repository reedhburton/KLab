#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
die(){ echo "daytime-r3-regressions: ERROR: $*" >&2; exit 1; }

# Fedora fallback: the reconstructed repository function is used in command
# substitution, so all progress must stay off stdout. Exercise that property
# without network/container access by mocking the container runner.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/manifest.json" <<'JSON'
{"package_inventory_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
JSON
(
  SELF_DIR="$ROOT"
  KLAB_CACHE="$tmp/cache"
  say(){ printf 'SAY:%s\n' "$*" >&2; }
  die(){ printf 'DIE:%s\n' "$*" >&2; return 1; }
  klab_provider_bind_output_owner(){ printf '%s:%s\n' "$(id -u)" "$(id -g)"; }
  klab_buildenv_owner_fix(){ :; }
  run_container_root(){
    local a host=""
    while (($#)); do
      a="$1"; shift
      if [[ "$a" == -v && $# -gt 0 ]]; then
        case "$1" in *:/out) host="${1%:/out}";; esac
        shift
      fi
    done
    [[ -n "$host" ]] || return 9
    mkdir -p "$host/repo/repodata"
    : >"$host/repo/repodata/repomd.xml"
    printf '{}\n' >"$host/fallback-plan.json"
    printf 'container-progress-that-must-not-enter-command-substitution\n'
  }
  # shellcheck disable=SC1090
  source "$ROOT/providers/fedora.sh"
  out="$(klab_provider_fedora_build_fallback_repo "$tmp/manifest.json" x86_64 https://hub.invalid/ https://top.invalid/)"
  [[ "$out" == "$tmp/cache/fedora-koji-fallback/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-x86_64/repo" ]] || die "Fedora fallback stdout was polluted: $out"
)

grep -Fq 'chown -R '\''$owner'\'' /out" >&2; then' "$ROOT/providers/fedora.sh" || die 'Fedora fallback container output is not redirected away from stdout'

# RPM buildenv capture must not replay the entire dependency closure into a
# minimal CentOS/RHEL-family container.
grep -Fq 'kernel-devel|kernel-headers|kernel-rpm-macros|kernel-srpm-macros)' "$ROOT/lib/backends/rpm.sh" || die 'DNF buildenv RPM filtering missing'
if grep -F 'klab_backend_dnf_capture_buildenv' "$ROOT/lib/backends/rpm.sh" | grep -Fq '/pkgs/*.rpm >/dev/null'; then
  die 'DNF buildenv still installs the entire RPM closure'
fi

# Debian 13 packages use +deb13[.N] release syntax.
regex='[0-9]+\.[0-9]+\.[0-9]+(\+deb[0-9]+(\.[0-9]+)?|-[0-9]+)-(amd64|cloud-amd64|rt-amd64)'
for k in 6.12.107+deb13-amd64 6.12.107+deb13.1-cloud-amd64 6.12.107+deb13-rt-amd64 6.1.0-53-amd64; do
  printf '%s\n' "$k" | grep -Eq "^${regex}$" || die "Debian release regex rejects $k"
done
grep -Fq '\+deb[0-9]+' "$ROOT/klab-cross-distro-queue-v2.sh" || die 'cross-distro Debian regex was not updated'

# Queue fixes learned from the daytime sweep.
grep -Fq 'ol8_UEKR7' "$ROOT/klab-cross-distro-queue-v2.sh" || die 'Oracle Linux 8 UEK repo enable missing'
grep -Fq 'ol9_UEKR8' "$ROOT/klab-cross-distro-queue-v2.sh" || die 'Oracle Linux 9 UEK repo enable missing'
grep -Fq 'ol10_UEKR8' "$ROOT/klab-cross-distro-queue-v2.sh" || die 'Oracle Linux 10 UEK repo enable missing'
grep -Fq "dnf -y install tar kernel6.12 kernel6.12-devel" "$ROOT/klab-cross-distro-queue-v2.sh" || die 'Amazon capture tar dependency missing'
grep -Fq "zypper -n install --no-recommends tar kernel-default" "$ROOT/klab-cross-distro-queue-v2.sh" || die 'openSUSE capture tar dependency missing'
grep -Fq 'rockylinux/rockylinux:10' "$ROOT/klab-cross-distro-queue-v2.sh" || die 'Rocky 10 vendor image fix missing'
grep -Fq 'apk add linux-lts linux-lts-dev' "$ROOT/klab-cross-distro-queue-v2.sh" || die 'Alpine LTS development package fix missing'
grep -Fq 'apk add linux-virt linux-virt-dev' "$ROOT/klab-cross-distro-queue-v2.sh" || die 'Alpine virt development package fix missing'
grep -Fq 'KLAB_CROSS_RECAPTURE' "$ROOT/klab-cross-distro-queue-v2.sh" || die 'selective external recapture control missing'

# Optional dangling links in kernel.org crosstools are pruned before sealing.
grep -Fq '.klab-pruned-dangling-symlinks.txt' "$ROOT/kernel-lab.sh" || die 'kernel.org dangling-tool symlink pruning missing'
grep -Fq 'Heal caches created by older KLab revisions' "$ROOT/kernel-lab.sh" || die 'cached kernel.org toolchains are not healed'
grep -Fq 'find "$dest" -xtype l -delete' "$ROOT/kernel-lab.sh" || die 'kernel.org dangling symlinks are not removed'

# The wrapper must no longer report a nested partial sweep as only PASS.
grep -Fq 'cross-distro-results' "$ROOT/klab-daytime-sweep-v1.sh" || die 'nested cross-distro status propagation missing'
grep -Fq 'PARTIAL' "$ROOT/klab-daytime-sweep-v1.sh" || die 'nested partial status missing'

echo 'daytime-r3-regressions: PASS'
