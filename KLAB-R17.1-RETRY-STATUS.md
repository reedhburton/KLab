# KLab r17.1 focused retry

Purpose: repair and retest only the concrete failures/incomplete cases exposed by the r17 major overnight, while reusing KLAB_ROOT caches.

Changes:
- Vintage APT compiler selection prefers the full recorded major.minor package name before falling back.
- RPM buildenv host-tool baseline includes coreutils; corresponding stale daytime regression updated to accept the baseline.
- install-m2 carries lib/arch-model.sh when present.
- r16 resume regression disables the newly-added matrix dimensions for its narrow legacy row-count test and accepts SKIP_DISABLED.
- r17 upstream 4.9 invocation uses the current `kernel-lab.sh test upstream:v4.9 --module ... --script ...` CLI.
- Adds `klab-r17.1-retry.sh`, which runs cheap regressions followed by only Ubuntu 12.04, Fedora 26, and upstream 4.9 live reproductions.

Validation here:
- bash -n passes for modified shell files.
- distro-native-host-tool-baseline.sh passes.
- daytime-r4-regressions.sh passes.
- installer/resume aggregate tests exceeded this sandbox execution window and remain host-side retry gates.
- No live QEMU result is claimed.

Run:
  export KLAB_ROOT="$HOME/klab-data"
  ./klab-r17.1-retry.sh

Set KLAB_R171_LIVE=0 to run only the regression gates.
