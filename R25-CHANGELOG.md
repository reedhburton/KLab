# KLab R25 — compatibility links become opt-in

R25 is the policy flip after the R24 residual-path audit passed.

## Default behavior

Fresh roots now use only the canonical unified tree. `KLAB_COMPAT_LINKS`
defaults to `0`, so names such as `$KLAB_ROOT/builds`, `$KLAB_ROOT/logs`,
`$KLAB_ROOT/toolchains`, and `$KLAB_ROOT/MODE` are not created.

Older or external scripts can request the legacy view explicitly:

```sh
KLAB_COMPAT_LINKS=1 klab-root init
```

First-party helpers continue to use the canonical R23/R24 paths and do not
require compatibility links.

## Upgrade safety

R25 does not silently delete compatibility links that were created by R22-R24.
`klab-root doctor` reports them as leftovers while native mode remains usable.
When external users no longer need them, run:

```sh
klab-root prune-compat
```

`prune-compat` is conservative and two-phase:

1. validate every candidate;
2. remove links only if every existing candidate is a symlink to the exact
   canonical KLab target.

It refuses real legacy directories and foreign symlinks, and validation occurs
before any removal so a failure does not leave a partially-pruned view.

## Other changes

- `MODE` is now part of the same compatibility-link policy as the other legacy
  names.
- `klab-root doctor` distinguishes a clean native root from an upgraded root
  that still has compatibility links.
- `normalize` and `migrate` do not recreate compatibility links unless
  `KLAB_COMPAT_LINKS=1` is explicitly selected.
- Added `tests/compat-default-off.sh` and expanded root-layout coverage for
  opt-in creation, safe pruning, foreign-link refusal, migration, and
  normalization.

## Validation boundary

R25 inherits the R24 residual-path validation boundary: retained raw
runner/bundle/Buildroot-helper sources are exercised directly; newer R21 helper
path forms are covered by the synthetic regression fixtures. No live historical
repository or QEMU compatibility claim is made by this root-layout pass.
