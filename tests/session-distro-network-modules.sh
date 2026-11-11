#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"; f="$ROOT/kernel-lab.sh"
grep -Fq 'install_session_network_modules "$root" "$target"' "$f"
grep -Fq -- "-name 'e1000.ko*'" "$f"
grep -Fq -- "-name 'virtio_net.ko*'" "$f"
grep -Fq -- "-name 'virtio.ko*'" "$f"
grep -Fq -- "-name 'virtio_ring.ko*'" "$f"
grep -Fq -- "-name 'virtio_pci.ko*'" "$f"
grep -Fq -- "-name 'virtio_pci_legacy_dev.ko*'" "$f"
grep -Fq -- "-name 'virtio_pci_modern_dev.ko*'" "$f"
grep -Fq 'zstd -dc "$src" > "$dst"' "$f"
grep -Fq 'depmod -b "$root" "$release"' "$f"
grep -Fq '[[ -n "$net_bus" || ${#net_ids[@]} -gt 0 || "$ssh_auth" != off ]] && include_network_modules=1' "$f"
echo 'distribution session network modules: PASS'
