# KLab r17 major overnight checkpoint

Combines the r16 architecture x kernel-version matrix with fixes derived from the completed Sep 26-27 old overnight.

Implemented:
- RPM captured buildenv baseline now includes coreutils. The previously failing network-free baseline regression passes.
- Custom Linux targets remain a core path; no providers/custom.sh dependency is required in this branch.
- RPM module builds/buildenvs include elfutils-libelf-devel.
- Vintage APT buildenv compiler selection now tries gcc-X.Y, gcc-X, then gcc rather than stopping at a fabricated/truncated package name.
- FreeBSD prepare checks for xorriso/genisoimage/mkisofs before entering its preparation/download path.
- New klab-major-overnight-r17.sh combines cheap regression gates, broad cached/resumable regression, routed architecture x kernel matrix, and an upstream 4.9 focused repro.
- Resume records a source-tree fingerprint and capability set and refuses accidental source/capability drift.
- Existing KLAB_ROOT caches are retained/reused.

Validation completed here:
- bash syntax: kernel-lab.sh, APT backend, RPM backend, r17 overnight runner: PASS.
- distro-native-host-tool-baseline.sh: PASS after coreutils fix.
- The aggregate mixed-architecture Python-backed tests remain host gates; this sandbox again hit its execution window while starting them. No live-QEMU success is claimed.

Recommended host launch:
  export KLAB_ROOT="$HOME/klab-data"
  ./klab-major-overnight-r17.sh

Resume:
  export KLAB_R17_RESUME_RUN_ID=latest
  ./klab-major-overnight-r17.sh

Optional:
  KLAB_R17_EXPERIMENTAL=1 enables experimental MIPS matrix cases.
  KLAB_R17_RUN_BROAD=0 skips the broad legacy regression phase.
  KLAB_R17_RUN_MATRIX=0 skips the routed architecture/kernel matrix.
  KLAB_R17_ALLOW_SOURCE_CHANGE=1 permits a reviewed source-tree change during resume; capability changes still fail closed.

The runner writes phase logs and summary.tsv under:
  $KLAB_ROOT/results/logs/major-overnight-r17/<RUN_ID>/
and packages:
  $KLAB_ROOT/results/major-overnight-r17-<RUN_ID>-results.tar.gz
