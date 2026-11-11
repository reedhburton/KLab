# R26 live-validation fix

Ubuntu 17.04 live validation in R25 reached buildenv capture and failed under `set -u` because the Ubuntu buildenv provider wrapper referenced an undeclared `compiler_version` variable. The Debian wrapper contained the same latent defect.

R26 removes that stray argument from both buildenv wrappers. The APT buildenv backend does not accept a compiler-version parameter; compiler-version selection remains correctly scoped to distro-toolchain capture.

Regression: `tests/apt-buildenv-provider-arity.sh`.
