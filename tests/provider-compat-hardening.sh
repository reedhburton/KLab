#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
grep -Fq 'chmod -R u+rX "$root"' "$ROOT/kernel-lab.sh" || { echo "FAIL: extracted RPM root is not normalized for unprivileged packing" >&2; exit 1; }
die(){ echo "provider-compat-hardening: ERROR: $*" >&2; exit 1; }
say(){ :; }
SELF_DIR="$ROOT"
KLAB_PROVIDER_ROOT="$ROOT/providers"
KLAB_PROVIDER_BACKEND_ROOT="$ROOT/lib/backends"
run_container_root(){ die 'container should not run in policy unit test'; }
provider_image(){ echo mock:image; }
release_snapshot_parts(){ RELEASE_SNAPSHOT=''; }
apt_snapshot_setup_script(){ echo ':'; }
provider_list_fedora(){ :; }
fetch_fedora_bundle(){ :; }
provider_list_rhel(){ :; }
fetch_rhel_bundle(){ :; }
source "$ROOT/lib/provider-core.sh"

# Non-LTS 17.04 is really archived; LTS 14.04/16.04/18.04 are still on the
# primary Ubuntu archive in 2026 and must not be redirected to old-releases.
klab_provider_load ubuntu
klab_provider_ubuntu_is_archived 17.04 || die '17.04 should use old-releases'
for r in 14.04 16.04 18.04 20.04 22.04 24.04 26.04; do
  if klab_provider_ubuntu_is_archived "$r"; then die "$r incorrectly classified as old-releases"; fi
done
klab_provider_ubuntu_is_archived 20.10 || die '20.10 should use old-releases'

# Current Ubuntu releases support authenticated ARM64 Ports staging, while
# archived releases remain x86_64-only until their ports archives are gated.
ARCH=aarch64
cap=$(klab_provider_capabilities ubuntu 24.04); grep -q 'cross-arch=yes' <<<"$cap" || die 'Ubuntu ARM64 cross-arch capability missing'
grep -q 'arches=x86_64,aarch64' <<<"$cap" || die 'Ubuntu ARM64 architecture missing'
setup=$(klab_provider_ubuntu_setup 24.04); grep -q 'ports.ubuntu.com/ubuntu-ports' <<<"$setup" || die 'Ubuntu ARM64 Ports source missing'
grep -q 'dpkg --add-architecture arm64' <<<"$setup" || die 'Ubuntu ARM64 dpkg architecture setup missing'
if ( klab_provider_call ubuntu list 17.04 '' ) >/dev/null 2>&1; then die 'archived Ubuntu accepted undeclared aarch64 provider operation'; fi
# ARM64 module builds must dispatch to the host cross-build backend with the
# normalized header tree and architecture, avoiding foreign package install.
cross_args=
klab_backend_apt_cross_build_module(){ cross_args="$*"; }
klab_provider_ubuntu_build_module 24.04 6.8.0-142-generic mock:image /packages /module 3 /headers aarch64
[[ "$cross_args" == '6.8.0-142-generic /module 3 /headers aarch64' ]] || die "Ubuntu ARM64 module build did not use host cross backend: $cross_args"
grep -Fq 'cp -a --reflink=auto' "$ROOT/lib/backends/apt.sh" || die 'cross build does not isolate packaged headers'
grep -Fq 'HOSTCC=gcc' "$ROOT/lib/backends/apt.sh" || die 'cross build does not override versioned Ubuntu host compiler'
ARCH=x86_64

# Exact kernel releases are data, never shell fragments/globs.
for bad in '6.1.0-*' '6.1.0;id' '6.1.0 $(id)' '../6.1.0'; do
  if ( klab_provider_validate_kernel_release "$bad" ) >/dev/null 2>&1; then die "unsafe kernel release accepted: $bad"; fi
done
klab_provider_validate_kernel_release '3.10.0-1160.119.1.el7.x86_64'
klab_provider_validate_kernel_release '7.0.0-31-generic'

grep -Fq 'if have rpm2cpio && have cpio; then' "$ROOT/kernel-lab.sh"
grep -Fq 'dnf -qy install cpio' "$ROOT/kernel-lab.sh"
grep -Fq 'run_container_root fedora:43' "$ROOT/kernel-lab.sh"

grep -Fq 'tail -n 2000' "$ROOT/lib/backends/apt.sh" || { echo 'FAIL: APT kernel discovery still truncates flavor coverage' >&2; exit 1; }
grep -Fq 'apt-get install -y -qq ca-certificates' "$ROOT/kernel-lab.sh" || { echo 'FAIL: Debian snapshot HTTPS lacks CA bootstrap' >&2; exit 1; }
grep -Fq 'security_suite="$suite/updates"' "$ROOT/kernel-lab.sh" || { echo 'FAIL: historical Debian security suite mapping missing' >&2; exit 1; }
grep -Fq "sed 's/^kernel-//'" "$ROOT/kernel-lab.sh" || { echo 'FAIL: Fedora Koji listing does not emit target kernel releases' >&2; exit 1; }
grep -Fq 'sed '\''s/\$/.${ARCH}/'\''' "$ROOT/kernel-lab.sh" || { echo 'FAIL: Fedora Koji listing omits the architecture from uname-r identity' >&2; exit 1; }
grep -Fq '"$bundle/packages/PACKAGES.sha256"' "$ROOT/kernel-lab.sh"
source "$ROOT/lib/backends/rpm.sh"
[[ "$(klab_backend_rpm_kernel_release 7.2.7-100.fc43 x86_64)" == 7.2.7-100.fc43.x86_64 ]] || die 'RPM kernel release did not gain architecture suffix'
[[ "$(klab_backend_rpm_kernel_release 7.2.7-100.fc43.x86_64 x86_64)" == 7.2.7-100.fc43.x86_64 ]] || die 'RPM kernel release duplicated architecture suffix'
grep -Fq 'build="/usr/src/kernels/$(klab_backend_rpm_kernel_release' "$ROOT/lib/backends/rpm.sh"
grep -Fq 'default_build="/usr/src/kernels/$(klab_backend_rpm_kernel_release' "$ROOT/lib/backends/rpm.sh"
echo 'provider-compat-hardening: PASS'
