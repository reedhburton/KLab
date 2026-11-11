# F16 live provider V4 checkpoint — 2026-10-17

Target: Ubuntu 24.04, Linux 6.8.0-142-generic, x86_64. Provider image: `sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac`.

Result: PASS. Automatic APT acquisition downloaded the exact realized installed DEB inventory, retained repository state, sealed a format-V4 build environment, compiled the module smoke test, packed the target, passed deep artifact verification, and imported/verified the build environment in a fresh KLab root.

Artifacts:
- Buildenv ID: `ee1ca01b10a57b7c1ea6fb115326c0af3a7f3ab3e2ef89e689a35babf12148a7`
- Buildenv SHA-256: `f9406c34f5ca1a3f4e23971afd5300b5bdab42b26816a812c01a3de688a72064`
- Target SHA-256: `d761d70e0028f12ea47f763b90ee8a319841571e3494c8372eca02737d16a43a`
- Distro toolchain SHA-256: `993a8c8c94d3da7f8c0ea8d57585b7edbc29f187cac04b3d60658380a6f2a2d1`

Live failures fixed during validation:
1. resolve the actual installed GCC executable and bind it through `/usr/local/bin/klab-native-cc`;
2. support Ubuntu images without `/etc/apt/sources.list`;
3. detect successful APT reinstalls that do not populate the selected archive cache and force an exact direct download;
4. emit dependency provenance outside the archive directory, matching the V4 `spec/` contract.

Validation: 122 network-free checks PASS after the fixes. Logs and artifacts are under `library/v1-f16-apt-2026-10-16/ubuntu24` and `library/releases/klab-1.0.0-rc3-f16-apt-live-network-free.log`.

## Debian provider proof

Target: Debian Bookworm, Linux 6.1.0-53-amd64, x86_64. Provider image: `sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587`. Result: PASS through exact kernel acquisition, native module smoke, full exact APT closure, V4 sealing, target packaging, independent deep verification, and temporary fresh-root import/installed verification.

- Buildenv ID: `5496c08866b158926b74c7a656d6fd1b8c0cb65a659b7bfa2588e4a9a2b327f0`
- Buildenv SHA-256: `78d9df461cf6ca134c854079eda68f8a07318f9a047c3aa54f88319b11049e5e`
- Target SHA-256: `a0af086c45adf6299879ff4f85f38f634b0a5cd28456538f6d1398322a3b8c48`
- Distro toolchain SHA-256: `d776210f9d5b70aa0f69640cd640be75bde0e0fbe4c479ffd92fed6c490d9a89`


## Fedora/Koji RPM provider proof

Target: Fedora 44, Linux `7.2.11-200.fc44.x86_64`, x86_64. Provider image: `sha256:43b29f65a41eb9c35e1cd5323e3bdf3b655c2357a9f4f1ff2f9c2798e5045d80`. Result: PASS through cached exact kernel acquisition, Koji-pinned native toolchain capture, full staging-root synchronization to the recorded Koji buildroot, module smoke build, exact installed-RPM closure capture, host-independent V4 sealing, target packaging, deep verification, and temporary fresh-root import/installed verification.

- Buildenv ID: `8ca3c0ee95b30db4c38bfd0ba55f5b2dd7201648d79fd725ac2f01928037ab1b`
- Buildenv SHA-256: `f1e72c1876647bf852a8893799b02c6161b0b9f91eb633f8c98f29b804fca969`
- Target SHA-256: `931a8169382b9ef3fb3ab669de7fe4627f7fb7dcd58ee3e6f5a4333318e04af7`
- Distro toolchain ID: `333f1943bb2572573261f498bf19bba725e1e94e80dd46cf7af03ddb7f71fe1b`
- Format: V4

The Fedora path has two explicit trust modes. Normal DNF repositories require enabled signature checking and accepted RPM signatures. The exact Koji buildroot path records the retained Koji metadata and verifies every RPM payload digest; Koji buildroot RPMs are commonly unsigned, so this mode does not claim per-package GPG authentication. A checksum-bound archive identity manifest allows the RPM guest to prove NEVRA identities while an Ubuntu/Debian host seals the closure without a host `rpm` executable.

Validation: all 123 network-free tests PASS after the RPM fixes. Attempt logs, inspection, deep-verification, fresh-root evidence, and hashes are under `library/v1-f16-rpm-2026-10-16/fedora44`; the full offline-suite log is `library/releases/klab-1.0.0-rc3-f16-fedora-identity-network-free.log`.


## Alpine/APK provider proof

Target: Alpine 3.23, Linux `6.18.57-0-lts`, x86_64. Provider image: `sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0`. Result: PASS through exact kernel acquisition, native toolchain capture, module smoke build, complete signed APK origin closure, V4 sealing, target packaging, deep verification, and temporary fresh-root import/installed verification.

- Buildenv ID: `bf08df25f4dd16724c8a020afbe41a174be45f23870ea3b53b4735701ecba907`
- Buildenv SHA-256: `0098297785decfe2c54d077c994bc6007246b1208fbf9c0d11369e0041553723`
- Target SHA-256: `232468021b0059838acbb360d935f6930acb864022014bc11664300479041c6b`
- Distro toolchain ID: `e7c4a224f22d4effb3a8d21b62d3c9c0f5bbba1c91ea843d41b174a1712c2b82`
- Format: V4

apk-tools 3 records installed split identities such as `acl-libs` while serving their signed origin archive such as `acl-2.3.2-r1.apk`. KLab now records the installed identity-to-origin mapping, verifies the origin archive signature and exact version, binds its checksum, and permits one archive to reconstruct multiple installed identities. Conflicting archive checksums and duplicate package identities remain rejected.

Attempt logs, inspection, deep-verification, fresh-root evidence, and hashes are under `library/v1-f16-apk-2026-10-17/alpine323`.


## Historical Ubuntu APT provider proof

Target: Ubuntu 17.04, Linux `4.10.0-42-generic`, x86_64. Provider image: `sha256:5d41c289942008211c2964bca72800f5c9d5ea5aa4057528da617fb36463d4ab`. Result: PASS through the archived old-releases route, exact cached kernel reuse, native GCC/binutils capture, vintage relocation validation, complete 153-package exact DEB closure, V4 sealing, target packaging, deep verification, and temporary fresh-root import/installed verification.

- Buildenv ID: `70d0614a6d74e5ac3a5ccddf339890687959357746fa4dcd057474fd6df880bd`
- Buildenv SHA-256: `b051250b9bc5143a0c32a2a2f1edc9ff0749bac3fcc151d793cde7aa515e01dc`
- Target SHA-256: `a1fa5fa23c47337ef3babff045fa4af2c30297067dc1960fc23d4aa5c209f037`
- Distro toolchain ID: `939c3ebd57af93ea4ad1d7ee7c87de2392348be6cd350091907fbd6761f3079b`
- Format: V4
- Vintage relocation evidence: `R_X86_64_64` only

The retained exact DEB archive closure supplies offline reconstruction even though Ubuntu old-releases does not expose timestamp-addressed snapshots. The artifact records the authenticated repository state used during acquisition and fails closed if any exact installed version is unavailable.

Attempt log, inspection, deep verification, fresh-root evidence, and hashes are under `library/v1-f16-historical-apt-2026-10-17/ubuntu1704`.
