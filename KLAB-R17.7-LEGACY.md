# KLab r17.7 legacy Linux checkpoint

Linux 2.6.32.71 x86_64 now passes the KLab module acceptance path. KLab selects a checksum-verified kernel.org GCC 4.9.4 toolchain for Linux 2.x, vendors its pinned MPFR runtime closure, adapts the obsolete timeconst Perl expression without changing the immutable kernel source, and uses a pinned BusyBox 1.21.1 guest for old-kernel compatibility.

Validated from a new offline root: import restored the kernel source/build, bound compiler, compiler runtime, and guest BusyBox; `klab run upstream:v2.6.32.71 --arch x86_64` built and loaded hello.ko and ended with `KLAB_RESULT=PASS`. Bundle SHA-256: `78cbdc0608750e2f951767b812fe649886b4bdde48a8b1890bfbd93694b4897a`.

The 1.0 matrix records MODULE_PASS for this lane. NETWORK_PASS remains required, and the i386 plus earlier 2.0/2.2/2.4/2.6 lanes remain outstanding.

All network-free regressions pass, including configuration compatibility against real 2.6.32 and modern kernel helpers, the historical compiler/Perl adapter, simple setup initialization, and Linux 2.x pull defaults.
