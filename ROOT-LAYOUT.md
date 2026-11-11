# KLab unified root layout (R25)

KLab 1.0 exposes two user-managed directories: `KLAB_ROOT` for all active state and `KLAB_REPO` for portable offline artifacts. Every other directory is internal to `KLAB_ROOT`. Run `klab setup` instead of creating subdirectories manually.

Normal users configure one location only:

```sh
export KLAB_ROOT="$HOME/klab"   # optional; this is the default
```

`KLAB_HOME` is retained only as an alias for compatibility and must not point to
a different location.

## Canonical tree

```text
$KLAB_ROOT/
  bin/
  config/
  artifacts/
    kernels/
    buildenvs/
    toolchains/
    distro-toolchains/
    userspaces/
    sources/
  targets/
    kernels/
  cache/
    linux/
    sources/
  work/
    builds/
    initramfs/
    jobs/
    sessions/
    buildroot/
    buildroot-cache/
  transfer/
    exports/
  results/
    logs/
    crashes/
  state/
    examples/
  suites/
```

R25 first-party helpers address these locations directly. Legacy names such as
`$KLAB_ROOT/builds`, `$KLAB_ROOT/logs`, and `$KLAB_ROOT/toolchains` remain
optional compatibility symlinks, not required runtime paths.

## Apply to the current KLab source tree

```sh
tar -xf klab-root-layout-r25-overlay.tar.gz
cd klab-root-layout-r25-overlay
./apply-root-layout.sh /path/to/current-klab
KLAB_ROOT="$HOME/klab" /path/to/current-klab/klab-root init
/path/to/current-klab/klab-root doctor
```

Use `/path/to/current-klab/klab ...` as the normal entry point. Patched helpers
also load the root contract when invoked directly.

The apply step prints a **Residual-path audit** result. A residual-path failure
is fatal: keep the source tree and audit output for review rather than disabling
compatibility links.

## Prove native operation without compatibility links

R25 uses native/no-compat mode by default:

```sh
export KLAB_ROOT="$HOME/klab"
/path/to/current-klab/klab-root init
/path/to/current-klab/klab-root doctor
/path/to/current-klab/klab status
```

No legacy top-level symlinks are created. If an older/external script still
needs the old view, opt in explicitly:

```sh
KLAB_COMPAT_LINKS=1 /path/to/current-klab/klab-root init
```

An upgraded root may still contain links created by an earlier release. Native
first-party code ignores them. Review them with `klab-root doctor`, then remove
only the recognized KLab-managed links with:

```sh
/path/to/current-klab/klab-root prune-compat
```

## Converting an existing environment

Reorganize an existing root in place:

```sh
KLAB_ROOT="/existing/klab-home" /path/to/current-klab/klab-root normalize
```

Or migrate to a new empty root:

```sh
KLAB_ROOT="$HOME/klab" /path/to/current-klab/klab-root migrate /old/klab-home
```

Recognized state is moved into canonical buckets. Unknown material is preserved
under `state/legacy-unclassified/`. Collisions are refused rather than silently
merged or overwritten.

## Cleanup model

Runtime state has one containment boundary: `$KLAB_ROOT`. The source tree stays
separate. Upgrading KLab source does not require relocating caches, artifacts,
results, or test state, and a disposable lab can be removed by deleting one
root tree.
