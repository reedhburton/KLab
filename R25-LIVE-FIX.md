# R25 live-test fix

Ubuntu 17.04 live validation exposed a second distro-toolchain capture portability issue after R24 fixed generated-shell quoting: the capture script invokes Python 3 inside the historical provider container, but did not ensure Python 3 was installed.

R25:
- explicitly bootstraps `python3` as a capture-time dependency before guest-side provenance/compiler metadata generation;
- changes guest-side `subprocess.check_output(..., text=True)` to `universal_newlines=True`, because Ubuntu 17.04's Python 3 predates the `text=` alias;
- adds `tests/apt-vintage-python-bootstrap.sh` to verify generated-script syntax, ordering, and old-Python API compatibility.

Python remains a capture-time helper only; it is not added to the retained GCC/binutils/make compiler closure.
