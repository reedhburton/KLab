# Fedora Koji package-build fallback

KLab normally prefers the exact Koji repository that backed the architecture-specific buildroot which produced a Fedora kernel. Koji may eventually garbage-collect that generated repository even though the individual package builds remain available.

The r2 fallback reconstructs that buildroot package source from retained Koji builds.

## Modes

Set `KLAB_FEDORA_KOJI_FALLBACK` to:

- `auto` (default): use the original Koji repo when it exists; reconstruct a local package repo only if it has expired.
- `always`: force reconstruction even when the original repo still exists. This is the recommended validation mode for the daytime sweep.
- `never`: do not reconstruct; non-strict mode may fall back to release repositories for auxiliary dependencies.

`KLAB_FEDORA_STRICT_BUILDROOT_REPO=1` now means strict historical dependency provenance: either the original Koji repo or the exact reconstructed package-build repo must be available. It will not silently accept the current Fedora release repository.

## Reconstruction flow

1. Read the `koji-buildroot.json` captured with the exact kernel build.
2. Use its recorded NEVRA inventory and Koji hub to resolve every native/noarch buildroot RPM back to an exact RPM ID and source build NVR.
3. Download those retained builds with a modern Koji client.
4. Prune unrelated subpackages so the local repository contains exactly the native/noarch RPMs recorded in the buildroot inventory.
5. Generate repository metadata with `createrepo_c`.
6. Cache the result under:

   `$KLAB_ROOT/cache/fedora-koji-fallback/<inventory-sha256>-<arch>/`

7. Mount the cached repo read-only into buildenv capture and use it before any release-repository fallback.

The cache contains `fallback-plan.json`, `FALLBACK-RPMS.sha256`, `fallback.env`, and the generated repo.

## Forced smoke test

For a single target:

```bash
export KLAB_ROOT="$HOME/klab"
export KLAB_FEDORA_KOJI_FALLBACK=always
./klab prepare fedora:29:4.19.15-300.fc29.x86_64 \
  --arch x86_64 \
  --distro-toolchain \
  --artifact-dir "$KLAB_ROOT/transfer/exports/fedora-fallback-test" \
  -o "$KLAB_ROOT/transfer/exports/fedora-fallback-test/f29.klab"
```

The captured buildenv records its dependency source in `/var/lib/klab/fedora-repo-source`. A forced fallback should begin with `koji-package-fallback:`. If KLab has to supplement only KLab-specific auxiliary tooling from release repositories in non-strict mode, `+release-aux` is appended.
