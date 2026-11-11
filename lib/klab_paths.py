"""Root identity shared by direct Python artifact commands."""
import os
from pathlib import Path


def root_home(explicit=None):
    # --home is an explicit per-command override; environment aliases must
    # otherwise agree, just as they do in lib/klab-root.sh.
    if explicit:
        value = explicit
    else:
        root = os.environ.get("KLAB_ROOT")
        legacy = os.environ.get("KLAB_HOME")
        if root and legacy and os.path.abspath(os.path.expanduser(root)) != os.path.abspath(os.path.expanduser(legacy)):
            raise SystemExit("KLAB_HOME conflicts with KLAB_ROOT; set only KLAB_ROOT")
        value = root or legacy or str(Path.home() / "klab")
    value = os.path.abspath(os.path.expanduser(value))
    if value == "/" or "\n" in value or "\r" in value:
        raise SystemExit("invalid KLab root")
    return value
