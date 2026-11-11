# KLab R24 live fix

R24 is R23 plus the first live-validation fix.

## Fixed

Ubuntu 17.04 distro-native toolchain capture reached the new APT package-metadata provenance block and failed before compiler capture with a generated-shell quoting error. The R23 block mixed unescaped double quotes into a larger double-quoted `bash -lc` program. R24 escapes that complete block at the generation layer.

## Regression

`tests/apt-capture-script-quoting.sh` now captures the exact generated container script and runs `bash -n` against it, so the static suite exercises the quoting boundary that the R23 provenance semantic test did not cover.

## Live validation status

No claim is made yet that Ubuntu 17.04 toolchain capture, module build, QEMU boot, or module load passes. R24 should be used to resume the same live test and stop at the next failure if any.
