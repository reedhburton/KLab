# CentOS 7 live Buildenv V4 validation

Date: 2026-10-17 HST

Target: `centos:7:3.10.0-1160.119.1.el7.x86_64`

The live provider used `quay.io/centos/centos:7` at image digest `sha256:e4ca2ed0202e76be184e75fb26d14bf974193579039d5573fb2348664deef76e`. Before repository use it verified the official CentOS 7 signing-key fingerprint `6341AB2753D78A78A7C27BB124C6A8A7F4A80EB5`. The primary `vault.centos.org` HTTPS endpoint returned 403 for several immutable SQLite metadata objects; yum successfully used the configured pinned HTTPS fallback at `archive.kernel.org/centos-vault/7.9.2009`.

The yum capture path now uses `yumdownloader` to retain every exact installed NEVRA, checks each RPM payload and signature with the imported pinned key, requires equality between the downloaded archive identities and the installed inventory, and retains yum repository configuration and cache metadata. The realized root contained 197 non-key package identities.

Validation results:

- exact kernel fetch and normalized target bundle: PASS
- distro-native GCC 4.8.5/binutils capture: PASS
- vintage relocation preflight (`R_X86_64_32`, `R_X86_64_64`, `R_X86_64_PC32`): PASS
- Buildenv format: V4
- Buildenv ID: `807409d5de160c1cf217bb40b4579259c4e5f20f9a53506a1365a9c6753e3693`
- Buildenv deep verification: PASS
- fresh-root import and installed-object verification: PASS
- full network-free regression suite: PASS

Artifacts and evidence are under `/home/reed/Documents/ChatGPT/Klab/library/v1-centos7-live-2026-10-17/attempt3`.

Artifact SHA-256 values:

- Buildenv: `d5eee7736a8abe91f6717859d62899dfa3c44707b504467eb04641d0605f2931`
- Target `.klab`: `8faf43f7ddf66b9a0caabe023ac601b0eaa60d6350eac4e12619d0d8b5a8ab4f`
- Distro toolchain: `737d5ab7967a608aa126ace7ae0ff7ecda5436d02cb84466dd69571489257040`
