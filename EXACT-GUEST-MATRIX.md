# Exact guest matrix

Generated from the current KLab warehouse, packaged artifacts, formal V1 catalogs, and recorded live evidence on 2026-10-17.

Availability states:

- **validated**: exact target has recorded live or artifact-integrity validation.
- **packaged**: a complete local .klab exists and can be imported and launched.
- **cached**: the exact normalized kernel bundle exists locally and can be packaged with a selected userspace.
- **built**: an exact upstream build is recorded locally and can be packaged.

Total unique exact guest identities: **114**. Architectures: aarch64, armv7, i386, mips, mipsel, riscv64, x86_64. Families: dragonfly, freebsd, linux, netbsd, openbsd.

| State | Count |
|---|---:|
| validated | 31 |
| packaged | 43 |
| cached | 4 |
| built | 36 |

The userspace column describes an existing packaged artifact when available. Distro targets pair the exact distribution kernel with a KLab-selected userspace; they do not imply a complete native distribution installation. “optional on repack” means KLab can generate an SSH-enabled Buildroot userspace, while the existing artifact is serial-console-first.

## Validated exact guests

| Target | Arch | Exact guest release/kernel | Userspace | Interactive access | Evidence |
|---|---|---|---|---|---|
| dragonfly:6.2.2:x86_64 | x86_64 | 6.2.2 | catalog/default | not established | USERSPACE_PASS; USERSPACE_PASS; formal BSD catalog |
| dragonfly:6.4.2:x86_64 | x86_64 | 6.4.2 | catalog/default | not established | USERSPACE_PASS; USERSPACE_PASS; formal BSD catalog |
| freebsd:15.1-RELEASE:aarch64 | aarch64 | 15.1-RELEASE | not embedded | not established | MODULE_PASS; local .klab artifact |
| freebsd:14.5-RELEASE:i386 | i386 | 14.5-RELEASE | catalog/default | not established | USERSPACE_PASS; USERSPACE_PASS; formal BSD catalog |
| freebsd:14.5-RELEASE:riscv64 | riscv64 | 14.5-RELEASE | catalog/default | not established | USERSPACE_PASS; USERSPACE_PASS; formal BSD catalog |
| freebsd:14.5-RELEASE:x86_64 | x86_64 | 14.5-RELEASE | not embedded | not established | MODULE_PASS; local .klab artifact |
| freebsd:15.1-RELEASE:x86_64 | x86_64 | 15.1-RELEASE | not embedded | not established | MODULE_PASS |
| alpine:3.23:6.18.53-0-lts | x86_64 | 6.18.53-0-lts | busybox-static | optional on repack | MODULE_PASS |
| alpine:3.23:6.18.57-0-lts | x86_64 | 6.18.57-0-lts | buildroot:minimal | optional on repack | V4 deep verify + fresh import; normalized local kernel bundle; local .klab artifact |
| centos:7:3.10.0-1160.119.1.el7.x86_64 | x86_64 | 3.10.0-1160.119.1.el7.x86_64 | buildroot:minimal | optional on repack | V4 deep verify + fresh import; normalized local kernel bundle; local .klab artifact |
| debian:bookworm:6.1.0-53-amd64 | x86_64 | 6.1.0-53-amd64 | buildroot:minimal | optional on repack | V4 deep verify + fresh import; normalized local kernel bundle; local .klab artifact |
| debian:bookworm:6.12.107+deb12-amd64 | x86_64 | 6.12.107+deb12-amd64 | busybox-static | optional on repack | SMOKE_PASS; local .klab artifact |
| fedora:43:7.2.7-100.fc43.x86_64 | x86_64 | 7.2.7-100.fc43.x86_64 | busybox-static | optional on repack | SMOKE_PASS; local .klab artifact |
| fedora:44:7.2.11-200.fc44.x86_64 | x86_64 | 7.2.11-200.fc44.x86_64 | buildroot:minimal | optional on repack | V4 deep verify + fresh import; normalized local kernel bundle; local .klab artifact |
| ubuntu:12.04:3.13.0-185-generic | x86_64 | 3.13.0-185-generic | busybox-static | optional on repack | SMOKE_PASS; local .klab artifact |
| ubuntu:17.04:4.10.0-42-generic | x86_64 | 4.10.0-42-generic | busybox-static | optional on repack | V4 deep verify + fresh import; local .klab artifact |
| ubuntu:24.04:6.8.0-142-generic | x86_64 | 6.8.0-142-generic | busybox-static | optional on repack | V4 deep verify + fresh import; local .klab artifact |
| upstream:v2.0.40 | i386 | 2.0.40 | busybox-static | optional on repack | USERSPACE_PASS; local .klab artifact |
| upstream:v2.2.26 | i386 | 2.2.26 | busybox-static | optional on repack | USERSPACE_PASS; local .klab artifact |
| upstream:v2.4.37.11 | i386 | 2.4.37.11 | busybox-static | optional on repack | MODULE_PASS; local .klab artifact |
| upstream:v2.6.0 | i386 | 2.6.0 | busybox-static | optional on repack | MODULE_PASS; local .klab artifact |
| upstream:v2.6.32.71 | i386 | 2.6.32.71 | busybox-static | optional on repack | NETWORK_PASS; local .klab artifact |
| upstream:v2.6.0 | x86_64 | 2.6.0 | busybox-static | optional on repack | USERSPACE_PASS; local .klab artifact |
| upstream:v2.6.12 | x86_64 | 2.6.12 | busybox-static | optional on repack | USERSPACE_PASS; local .klab artifact |
| upstream:v2.6.18 | x86_64 | 2.6.18 | busybox-static | optional on repack | MODULE_PASS; local .klab artifact |
| upstream:v2.6.32.71 | x86_64 | 2.6.32.71 | buildroot:minimal | optional on repack | NETWORK_PASS; local .klab artifact |
| netbsd:11.0:aarch64 | aarch64 | 11.0 | catalog/default | not established | USERSPACE_PASS; USERSPACE_PASS; formal BSD catalog |
| netbsd:11.0:i386 | i386 | 11.0 | catalog/default | not established | USERSPACE_PASS; USERSPACE_PASS; formal BSD catalog |
| netbsd:11.0:x86_64 | x86_64 | 11.0 | catalog/default | not established | USERSPACE_PASS; USERSPACE_PASS; formal BSD catalog |
| openbsd:7.9:aarch64 | aarch64 | 7.9 | catalog/default | not established | USERSPACE_PASS; USERSPACE_PASS; formal BSD catalog |
| openbsd:7.9:x86_64 | x86_64 | 7.9 | catalog/default | not established | USERSPACE_PASS; USERSPACE_PASS; formal BSD catalog |

## Packaged exact guests

| Target | Arch | Exact guest release/kernel | Userspace | Interactive access | Evidence |
|---|---|---|---|---|---|
| fedora:20:3.14.9-200.fc20.x86_64 | x86_64 | 3.14.9-200.fc20.x86_64 | busybox-static | optional on repack | normalized local kernel bundle; local .klab artifact |
| fedora:23:4.4.9-300.fc23.x86_64 | x86_64 | 4.4.9-300.fc23.x86_64 | busybox-static | optional on repack | normalized local kernel bundle; local .klab artifact |
| fedora:29:4.19.15-300.fc29.x86_64 | x86_64 | 4.19.15-300.fc29.x86_64 | busybox-static | optional on repack | normalized local kernel bundle; local .klab artifact |
| fedora:32:5.10.22-100.fc32.x86_64 | x86_64 | 5.10.22-100.fc32.x86_64 | busybox-static | optional on repack | normalized local kernel bundle; local .klab artifact |
| fedora:35:5.15.18-200.fc35.x86_64 | x86_64 | 5.15.18-200.fc35.x86_64 | busybox-static | optional on repack | normalized local kernel bundle; local .klab artifact |
| fedora:40:6.8.11-300.fc40.x86_64 | x86_64 | 6.8.11-300.fc40.x86_64 | busybox-static | optional on repack | normalized local kernel bundle; local .klab artifact |
| ubuntu:12.04:3.2.0-126-generic | x86_64 | 3.2.0-126-generic | busybox-static | optional on repack | normalized local kernel bundle; local .klab artifact |
| ubuntu:12.04:3.2.0-150-generic | x86_64 | 3.2.0-150-generic | busybox-static | optional on repack | normalized local kernel bundle; local .klab artifact |
| ubuntu:16.04:4.4.0-210-generic | x86_64 | 4.4.0-210-generic | busybox-static | optional on repack |  |
| ubuntu:18.04:4.15.0-213-generic | x86_64 | 4.15.0-213-generic | busybox-static | optional on repack |  |
| ubuntu:18.04:5.4.0-1109-azure | x86_64 | 5.4.0-1109-azure | busybox-static | optional on repack |  |
| ubuntu:20.04:5.15.0-139-generic | x86_64 | 5.15.0-139-generic | busybox-static | optional on repack |  |
| ubuntu:20.04:5.4.0-1151-azure | x86_64 | 5.4.0-1151-azure | busybox-static | optional on repack |  |
| ubuntu:20.04:5.4.0-216-generic | x86_64 | 5.4.0-216-generic | busybox-static | optional on repack |  |
| ubuntu:20.04:5.4.0-216-lowlatency | x86_64 | 5.4.0-216-lowlatency | busybox-static | optional on repack |  |
| ubuntu:22.04:5.15.0-1116-aws | x86_64 | 5.15.0-1116-aws | busybox-static | optional on repack |  |
| ubuntu:22.04:5.15.0-1117-gcp | x86_64 | 5.15.0-1117-gcp | busybox-static | optional on repack |  |
| ubuntu:22.04:5.15.0-1122-azure | x86_64 | 5.15.0-1122-azure | busybox-static | optional on repack |  |
| ubuntu:22.04:5.15.0-194-generic | x86_64 | 5.15.0-194-generic | busybox-static | optional on repack |  |
| ubuntu:22.04:6.8.0-138-generic | x86_64 | 6.8.0-138-generic | busybox-static | optional on repack | normalized local kernel bundle; local .klab artifact |
| ubuntu:24.04:6.11.0-29-generic | x86_64 | 6.11.0-29-generic | busybox-static | optional on repack |  |
| ubuntu:24.04:6.14.0-37-generic | x86_64 | 6.14.0-37-generic | busybox-static | optional on repack |  |
| ubuntu:24.04:6.17.0-42-generic | x86_64 | 6.17.0-42-generic | busybox-static | optional on repack |  |
| ubuntu:24.04:6.8.0-1062-oracle | x86_64 | 6.8.0-1062-oracle | busybox-static | optional on repack |  |
| ubuntu:24.04:6.8.0-1063-aws | x86_64 | 6.8.0-1063-aws | busybox-static | optional on repack |  |
| ubuntu:24.04:6.8.0-1068-azure | x86_64 | 6.8.0-1068-azure | busybox-static | optional on repack |  |
| ubuntu:24.04:6.8.0-1069-gcp | x86_64 | 6.8.0-1069-gcp | busybox-static | optional on repack |  |
| ubuntu:24.04:6.8.0-142-lowlatency | x86_64 | 6.8.0-142-lowlatency | busybox-static | optional on repack | normalized local kernel bundle; local .klab artifact |
| ubuntu:26.04:7.0.0-1014-azure | x86_64 | 7.0.0-1014-azure | busybox-static | optional on repack |  |
| ubuntu:26.04:7.0.0-34-generic | x86_64 | 7.0.0-34-generic | busybox-static | optional on repack |  |
| upstream:v6.6 | aarch64 | 6.6.0 | buildroot:minimal | optional on repack |  |
| upstream:v5.15 | armv7 | 5.15.0 | buildroot:minimal | optional on repack |  |
| upstream:v6.6 | armv7 | 6.6.0 | buildroot:minimal | optional on repack |  |
| upstream:v5.10 | i386 | 5.10.0 | buildroot:minimal | optional on repack |  |
| upstream:v5.15 | mips | 5.15.0 | buildroot:minimal | optional on repack | local .klab artifact |
| upstream:v6.6 | mips | 6.6.0 | buildroot:minimal | optional on repack | local .klab artifact |
| upstream:v5.15 | mipsel | 5.15.0 | buildroot:minimal | optional on repack |  |
| upstream:v4.9 | x86_64 | 4.9.0 | busybox-static | optional on repack |  |
| upstream:v5.15 | x86_64 | 5.15.0 | buildroot:minimal | optional on repack |  |
| upstream:v6.1 | x86_64 | 6.1.0 | buildroot:minimal | optional on repack | local .klab artifact |
| upstream:v6.12 | x86_64 | 6.12.0 | busybox-static | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded; local .klab artifact |
| upstream:v6.6 | x86_64 | 6.6.0 | buildroot:minimal | optional on repack |  |
| upstream:v7.0 | x86_64 | 7.0.0 | busybox-static | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded; local .klab artifact |

## Cached exact guests

| Target | Arch | Exact guest release/kernel | Userspace | Interactive access | Evidence |
|---|---|---|---|---|---|
| fedora:26:4.11.8-300.fc26.x86_64 | x86_64 | 4.11.8-300.fc26.x86_64 | select-at-run | optional on repack | normalized local kernel bundle |
| fedora:26:4.14.18-200.fc26.x86_64 | x86_64 | 4.14.18-200.fc26.x86_64 | select-at-run | optional on repack | normalized local kernel bundle |
| fedora:38:6.2.15-300.fc38.x86_64 | x86_64 | 6.2.15-300.fc38.x86_64 | select-at-run | optional on repack | normalized local kernel bundle |
| fedora:42:6.14.11-300.fc42.x86_64 | x86_64 | 6.14.11-300.fc42.x86_64 | select-at-run | optional on repack | normalized local kernel bundle |

## Built exact guests

| Target | Arch | Exact guest release/kernel | Userspace | Interactive access | Evidence |
|---|---|---|---|---|---|
| upstream:v3.0 | x86_64 | 3.0 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v3.10 | x86_64 | 3.10 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v3.12 | x86_64 | 3.12 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v3.16 | x86_64 | 3.16 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v3.18 | x86_64 | 3.18 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v3.2 | x86_64 | 3.2 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v3.4 | x86_64 | 3.4 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v3.6 | x86_64 | 3.6 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v3.8 | x86_64 | 3.8 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v4.0 | x86_64 | 4.0 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v4.1 | x86_64 | 4.1 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v4.10 | x86_64 | 4.10 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |
| upstream:v4.12 | x86_64 | 4.12 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v4.14 | x86_64 | 4.14 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v4.16 | x86_64 | 4.16 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v4.19 | x86_64 | 4.19 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v4.20 | x86_64 | 4.20 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v4.4 | x86_64 | 4.4 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v4.6 | x86_64 | 4.6 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v5.0 | x86_64 | 5.0 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v5.10 | x86_64 | 5.10 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v5.12 | x86_64 | 5.12 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |
| upstream:v5.18 | x86_64 | 5.18 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |
| upstream:v5.4 | x86_64 | 5.4 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v5.5 | x86_64 | 5.5 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v5.8 | x86_64 | 5.8 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=host |
| upstream:v6.0 | x86_64 | 6.0 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |
| upstream:v6.10 | x86_64 | 6.10 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |
| upstream:v6.14 | x86_64 | 6.14 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |
| upstream:v6.18 | x86_64 | 6.18 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |
| upstream:v6.3 | x86_64 | 6.3 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |
| upstream:v6.5 | x86_64 | 6.5 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |
| upstream:v6.8 | x86_64 | 6.8 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |
| upstream:v7.1 | x86_64 | 7.1 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |
| upstream:v7.2 | x86_64 | 7.2 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |
| upstream:v7.2.7 | x86_64 | 7.2.7 | select-at-run | optional on repack | built; profile=normal; userspace=select-at-run; toolchain=recorded |

## Machine-readable companion

The complete rows, including preferred local artifact paths, are in EXACT-GUEST-MATRIX.tsv.
