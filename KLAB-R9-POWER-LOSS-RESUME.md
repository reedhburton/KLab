# KLab r9 — Fedora 20 positional fix + power-loss-resumable overnight regression

## Uploaded r8 result

The supplied `daytime-retry-r8-20260926T064302Z-results.tar.gz` is not the overnight-heavy run. It contains only the focused Fedora 20 r8 retry.

That retry reached a successful vintage module smoke:

- `KLAB_VINTAGE_STATUS=pass`
- `KLAB_VINTAGE_AUTHORITY=heuristic`
- relocations: `R_X86_64_32,R_X86_64_64`

It then failed in final read-only distro-native validation with:

`distro-native assembler mismatch: expected 2.23.88.0.1 got: GNU assembler version 2.23.2`

## r8 bug identified

The intended Fedora-specific RPM ownership/version validation was present in `klab-buildenv.sh`, but its POSIX-shell condition used:

`if [ "$11" = fedora ]; then`

In POSIX/Bourne shell syntax, `$11` expands as `$1` followed by the literal character `1`; positional parameters above 9 require braces. Therefore the Fedora branch was never entered and validation fell through to the legacy executable-banner comparison.

r9 changes that condition to:

`if [ "${11}" = fedora ]; then`

A regression test now verifies both the source spelling and the actual `/bin/sh` positional-parameter behavior.

## Overnight resume support

`klab-overnight-regression-v6-resume.sh` can resume either a v5 or v6 overnight run in place.

Use:

```bash
KLAB_ROOT="$HOME/klab" \
KLAB_OVERNIGHT_RESUME_RUN_ID=latest \
./klab-overnight-regression-v6-resume.sh
```

or specify the exact interrupted run ID.

Resume behavior:

- reuses the original run log directory and regression artifact directory;
- preserves the existing `summary.tsv` and saves a pre-resume copy;
- skips cases already recorded with terminal results;
- if prepare passed but its artifact is missing, that prepare is rerun;
- if a case was in progress at power loss and therefore has no summary row, it is rerun;
- if prepare finished but verify/smoke did not, prepare is skipped and the missing later stage continues;
- Ubuntu dynamic discovery files are reused when present;
- cross-distro work that was interrupted may restart its queue, but it uses the same staged-root/artifact caches;
- `KLAB_OVERNIGHT_RESUME_RETRY_FAILED=1` optionally retries completed `FAIL`, `TIMEOUT`, and `PROBE_FAIL` cases.

## Collecting logs from an interrupted run

The old v5 runner only creates its normal review archive at the very end. For a power-loss run use:

```bash
export KLAB_ROOT="$HOME/klab"
./klab-overnight-collect-partial.sh
```

It prints the path to a logs/metadata-only tarball for the latest overnight run.

## Local validation

- Fedora positional-parameter regression: PASS
- Existing Fedora binutils runtime validation: PASS
- Resume dry-run: initial summary 56 cases; resumed run skipped all 56 without adding duplicate result rows: PASS
- shell syntax: PASS
- Python source compilation: PASS
