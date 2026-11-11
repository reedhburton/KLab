# Native guest conformance contract

A native:PROVIDER:RELEASE userspace is a captured distribution filesystem.
Its metadata pins the OCI image identity, root filesystem SHA-256, exact
package inventory, and repository configuration snapshot.

KLab calls a target **full-function validated** only after the exact kernel and
native userspace pair passes:

1. kernel, distribution, release, and architecture identity;
2. writable filesystem plus /proc, /sys, and /dev;
3. concurrent processes, pipes, and a Python fork/wait child process;
4. native dynamic compilation and execution with the distribution compiler;
5. network device configuration and gateway traffic when a NIC is requested;
6. the target's exact /lib/modules/KERNEL_RELEASE tree and module resolution;
7. an SSH login when the session is started with SSH;
8. clean shutdown control; and
9. offline checksum verification and replay of the captured artifacts.

klab-guest-conformance.sh SESSION [REPORT_DIR] runs the non-destructive guest
portion and writes a TSV plus per-capability evidence. SSH and offline replay
are separate gates because they require host credentials or a fresh KLab root.

Results are PASS, FAIL, or an explicit N/A in evidence when hardware is not
requested. A boot alone does not qualify as full-function validation.

## SSH backend selection

When SSH is requested, KLab uses the native root's `/usr/sbin/sshd` when it is executable. If it is absent, KLab injects an architecture-matched static-musl Dropbear multi-call binary and records `dropbear-fallback` in the session's `ssh-backend` evidence. The fallback is checksum-pinned, cached for offline reuse, and does not add or replace native distribution libraries. Key, password, and explicitly requested passwordless authentication retain the same CLI contract.
