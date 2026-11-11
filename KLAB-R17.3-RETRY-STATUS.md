# KLab r17.3 focused retry

Based on r17.2 and its returned logs.

Confirmed r17.2:
- baseline PASS
- daytime-r4 PASS
- installer PASS
- upstream v4.9 prepare PASS and hello.ko build PASS
- upstream test failed only because retry referenced nonexistent examples/hello-module/test.sh
- Ubuntu 12.04 and Fedora 26 prepare failed before buildenv because auto mode incorrectly selected kernel.org nolibc crosstools for distro compiler patch versions not published there
- r16 resume failure was duplicate SKIP_DISABLED rows (20 rows became 35).

r17.3 changes:
- distro prepare auto toolchain policy now selects distribution-native GCC/binutils capture; upstream continues to use kernel.org toolchains.
- live retry uses the built-in examples/hello + examples/test.sh, running kernel-lab init if those examples are absent.
- adds per-target diagnostics for GCC, libelf/elfutils, buildenv/toolchain evidence and QEMU.
- r16 disabled matrix rows are not appended again on resume.
- prepare, diagnostics, and test remain separate result rows.

Validation:
- bash -n passes for all modified shell files.
- sandbox resume aggregate exceeded the local execution window; no host/QEMU PASS is claimed.
