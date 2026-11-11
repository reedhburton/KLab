#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq 'image_exec_inside "$root" "$p"' "$ROOT/klab-buildenv.sh" || { echo 'FAIL: distro-native compiler preflight is not image-symlink-aware' >&2; exit 1; }
f="$ROOT/lib/buildenv-capture.sh"
grep -Fq 'resolved=$(readlink -f "$p"' "$f"
grep -Fq 'dpkg-query -S "$resolved"' "$f"
grep -Fq 'rpm -qf --qf "%{NAME}\n" "$resolved"' "$f"
grep -Fq 'printf "%s\t%s\t%s\n" "$t" "$resolved" "$owner"' "$f"
# Execute the production ownership block with an isolated PATH and package
# database stubs. Only the baseline list and output directory are redirected.
python3 - "$f" <<'PYTEST'
import os, pathlib, shutil, subprocess, sys, tempfile
source = pathlib.Path(sys.argv[1]).read_text()
start = source.index('set -eu\nmkdir -p /var/lib/klab')
end = source.index("\n'", start)
block = source[start:end]
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    bindir = root / 'bin'
    bindir.mkdir()
    for tool in ('mkdir', 'readlink', 'head', 'cut', 'sort'):
        (bindir / tool).symlink_to(shutil.which(tool))
    target = root / 'mawk'
    target.write_text('#!/bin/sh\nexit 0\n')
    target.chmod(0o755)
    alternative = root / 'alternative'
    alternative.symlink_to(target)
    public = root / 'awk'
    public.symlink_to(alternative)
    output = root / 'state'
    script = block.replace('/var/lib/klab', str(output))
    lines = script.splitlines()
    loop = next(i for i, line in enumerate(lines) if line.startswith('for t in '))
    lines[loop] = f'for t in {public}; do'
    script = '\n'.join(lines)
    env = dict(os.environ, PATH=str(bindir))
    for manager in ('dpkg-query', 'rpm'):
        stub = bindir / manager
        if manager == 'dpkg-query':
            body = '[ "$1" = -S ] && [ "$2" = "$EXPECTED" ] || exit 9\nprintf "mawk: %s\\n" "$2"\n'
        else:
            body = '[ "$1" = -qf ] && [ "$2" = --qf ] && [ "$3" = "%{NAME}\\n" ] && [ "$4" = "$EXPECTED" ] || exit 9\nprintf "mawk\\n"\n'
        stub.write_text('#!/bin/sh\n' + body)
        stub.chmod(0o755)
        env['EXPECTED'] = str(target)
        run = subprocess.run(['/bin/sh', '-c', script], env=env, capture_output=True, text=True)
        assert run.returncode == 0, (manager, run.stderr)
        assert (output / 'host-tool-owners.tsv').read_text() == f'{public}\t{target}\tmawk\n'
        stub.write_text('#!/bin/sh\nexit 1\n')
        run = subprocess.run(['/bin/sh', '-c', script], env=env, capture_output=True, text=True)
        assert run.returncode == 67, (manager, run.returncode, run.stderr)
        assert 'no owning package' in run.stderr
        stub.unlink()
    target.unlink()
    run = subprocess.run(['/bin/sh', '-c', script], env=env, capture_output=True, text=True)
    assert run.returncode == 66, (run.returncode, run.stderr)
PYTEST
echo 'PASS: production ownership follows alternatives for Debian/RPM and rejects unowned or missing executables'
