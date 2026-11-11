#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mapfile -t releases < <("$ROOT/klab-ubuntu-native-rootfs.sh" matrix)
[[ "${releases[*]}" == '12.04 14.04 16.04 18.04 20.04 22.04 24.04' ]]
grep -Fq 'oci-export-tar-zstd-v1' "$ROOT/klab-ubuntu-native-rootfs.sh"
grep -Fq 'docker' "$ROOT/klab-ubuntu-native-rootfs.sh"
bash -n "$ROOT/klab-ubuntu-native-rootfs.sh"
echo 'PASS: Ubuntu native-userspace v1 LTS matrix and streamed artifact model'
grep -Fq 'ubuntu-native:[0-9]*.[0-9]*) echo "native:ubuntu:${1#ubuntu-native:}"' "$ROOT/kernel-lab.sh"
grep -Fq 'native userspace release' "$ROOT/kernel-lab.sh"
grep -Fq 'zstd -dc "$rootfs" | tar' "$ROOT/kernel-lab.sh"
# Native distro root filesystems commonly install protocol helpers in /usr/bin.
# The generated init must retain those directories or EXEC/PUT fails after READY.
[[ $(grep -c '^export PATH=/bin:/sbin:/usr/bin:/usr/sbin$' "$ROOT/kernel-lab.sh") -ge 2 ]]
