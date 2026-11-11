# Controller-side test suites

A suite is a directory with a small `klab.toml` artifact manifest and an ordinary Bash `test.sh`. Bash runs on the controller. A command enters a target only when it begins with `klab exec`, `klab process`, `klab push`, or `klab module`. This keeps loops, variables, `grep`, `sed`, JSON parsers, and other result processing on the controller.

Create and run a suite:

```sh
klab suite create driver-test
$EDITOR "$KLAB_ROOT/suites/driver-test/klab.toml"
$EDITOR "$KLAB_ROOT/suites/driver-test/test.sh"
klab test driver-test on \
  ubuntu:22.04:5.15.0-160-generic@x86_64 \
  ubuntu:24.04:6.8.0-85-generic@x86_64
```

Put one `TARGET@ARCH` per line in `targets.txt` to run `klab test driver-test on @targets.txt`. Each target gets a fresh guest and report. A failure in one target does not prevent later targets from running.

## Manifest

```toml
[test]
script = "test.sh"
timeout = 300
userspace = "buildroot:minimal"

[module.driver]
source = "driver-project"       # a whole kbuild directory
unload = true

[build.client]
sources = ["client/main.c", "client/protocol.c"]
flags = ["-O2", "-Iclient/include"]
static = true
target = "/tmp/client"

[file.fixture]
source = "fixtures/request.bin" # copied byte-for-byte
target = "/tmp/request.bin"
mode = "0644"
```

Artifacts become target paths in `test.sh` as `KLAB_MODULE_DRIVER`, `KLAB_BUILD_CLIENT`, and `KLAB_FILE_FIXTURE`. KLab builds each module and C program for every target before booting it. Multiple C sources and vendored headers support ordinary small projects; kernel module directories retain their own Makefile and source layout.

## Commands and output

`klab exec` blocks until the target command exits. Put shell syntax in one quoted argument to pass that text to the guest shell unchanged. Single quotes keep controller variables and substitutions from expanding; double quotes deliberately expand them on the controller first:

```bash
# $HOME, *, and $(uname) are interpreted inside the target.
klab exec target 'printf "guest home=%s\n" "$HOME"; files=(*); uname -a'

# The controller substitutes $case_name, then the target runs printf.
klab exec target "printf '%s\n' '$case_name'"

# Use -- when you have an argv list and do not want guest shell syntax.
klab exec target -- /tmp/client --mode fast
```

Its stdout is normal command stdout, so controller tools can process it:

```bash
ps_output="$(klab exec target -- ps ax)"
printf '%s\n' "$ps_output" | grep '[h]ttpd'
klab expect contains "$ps_output" httpd
```

The `--` ends KLab options and makes every later argument the target command, even if an argument starts with `-`.

Expected failures are explicit:

```bash
klab exec target --expect-exit 2 -- /tmp/client --invalid
klab exec target --expect-exit 1,2 -- grep missing /tmp/data
klab exec target --expect-failure -- false
klab exec target --expect-timeout --timeout 1 -- sleep 30
```

An expected failure returns success to the test. An unexpected success or wrong exit status fails it.

## Transferring test files

Declare files that every target always needs in `klab.toml`, or copy one conditionally from `test.sh`:

```bash
klab copy target scripts/configure.sh /tmp/configure.sh
klab exec target 'chmod +x /tmp/configure.sh; /tmp/configure.sh'

if [[ "$KLAB_TARGET" == ubuntu:* ]]; then
  klab copy target packages/driver-test.deb /tmp/driver-test.deb
  klab exec target 'dpkg -i /tmp/driver-test.deb'
fi
```

Relative local paths are resolved from `KLAB_TEST_DIR`, so the suite remains portable regardless of the directory from which KLab is invoked. `klab push` is an equivalent alias. Any regular file can be transferred: scripts, precompiled binaries, packages, archives, fixtures, or configuration. Executable local files retain executable mode; `klab exec target 'chmod ...'` can set any target-specific mode.

## Processes and coordination

`process start` follows the same rule. A single quoted argument is a guest shell program; arguments following `--` are quoted into an argv-style command. It returns after launching a named target process. `ready`, `output`, `wait`, `signal`, and `stop` refer to that name:

```bash
klab process start target server -- python3 -u -m http.server 8080
klab process ready target server stderr 'Serving HTTP' --timeout 20
server_log="$(klab process output target server stderr)"
klab expect contains "$server_log" 'Serving HTTP'
klab exec target -- wget -qO- http://127.0.0.1:8080/
klab process stop target server
```

Readiness can match `stdout` or `stderr`, or wait for a target `file` path. Programs should print a clear ready line after binding their socket; this works without assuming that the target contains `nc`, `curl`, or a host Python installation.

Two processes can coordinate through the tested module or target files:

```bash
klab module load target driver
klab process start target shell -- sh -c \
  'echo $$ >/tmp/shell.pid; while [ ! -f /tmp/input ]; do sleep .05; done; cat /tmp/input; exec /tmp/final-check'
klab process ready target shell file /tmp/shell.pid --timeout 10
klab process start target writer -- sh -c 'echo hello >/tmp/input'
klab process wait target writer
klab process wait target shell
out="$(klab process output target shell stdout)"
printf '%s\n' "$out" | grep -F hello
```

The final `exec` replaces the shell and therefore preserves that process PID. Bash functions, loops, arrays, and target conditionals remain available:

```bash
if [[ "$KLAB_ARCH" == aarch64 ]]; then
  klab exec target -- /tmp/client --unaligned-safe
fi
if klab exec target -- sh -c 'command -v python3' >/dev/null 2>&1; then
  python=python3
else
  python=python2
fi
klab exec target -- "$python" /tmp/check.py
```

The controller receives `KLAB_TARGET`, `KLAB_ARCH`, `KLAB_TEST_DIR`, and `KLAB_REPORT_DIR`. Target command output, controller output, build logs, boot logs, the result, and the matrix-wide `status.tsv` are retained below `KLAB_ROOT/results/tests` unless `--output DIR` is supplied.
