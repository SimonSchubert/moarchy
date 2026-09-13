#!/usr/bin/env python3
"""Prove pil-squash.py against the vendor's own unsplit blob.

Run: python3 pkgbuilds/firmware-moarchy-sargo/test-pil-squash.py

pil-squash.py replaces postmarketOS's `pil-squasher`, which is packaged for
Alpine and not for Arch. Replacing a tool is only defensible if the replacement
is checked against something authoritative, and here there is something better
than a checksum: the vendor tree ships `a615_zap.elf` -- the unsplit original --
right beside the `.mdt` and `.bNN` pieces it was split into. Reassembling the
pieces must reproduce it byte-for-byte.

That is a stronger claim than "the output looks like an ELF". Every program
header offset, every segment length and the total size all have to be right at
once, or the bytes differ.

The fixtures are proprietary firmware and are not vendored. Point
MOARCHY_SARGO_FW at a directory holding a615_zap.{mdt,b00,b01,b02,elf}, or
fetch them:

  C=c631f0f2aa24ea60cfb505d327cd4ae56ca27f16
  B=https://raw.githubusercontent.com/TheMuppets/\\
proprietary_vendor_google_sargo/$C/proprietary/vendor/firmware
  for f in a615_zap.mdt a615_zap.b00 a615_zap.b01 a615_zap.b02 a615_zap.elf; do
    curl -sSLO "$B/$f"
  done

Without them the round-trip SKIPS loudly. A test that reports success while
measuring nothing is worse than one that does not run.
"""

import importlib.util
import os
import pathlib
import sys

_HERE = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("pil_squash", _HERE / "pil-squash.py")
ps = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ps)

_failures = []
_skips = []


def check(name, ok, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'} {name}" + (f": {detail}" if not ok and detail else ""))
    if not ok:
        _failures.append(name)


def find_fixtures():
    env = os.environ.get("MOARCHY_SARGO_FW")
    roots = [pathlib.Path(env)] if env else []
    # Searched relative to this file, never the cwd: a cwd-relative glob once
    # wandered into a scratch directory and silently found a fixture nobody
    # meant to offer it (see image/boot/test-android-image.py).
    roots += [_HERE, _HERE.parent.parent]
    for r in roots:
        if (r / "a615_zap.mdt").is_file() and (r / "a615_zap.elf").is_file():
            return r
        for p in r.glob("**/a615_zap.mdt"):
            if (p.parent / "a615_zap.elf").is_file():
                return p.parent
    return None


def main():
    print("pil-squash.py")
    root = find_fixtures()
    if root is None:
        print("  skip a615_zap round-trip: no fixtures (set MOARCHY_SARGO_FW)")
        _skips.append("a615_zap round-trip")
    else:
        print(f"  (fixtures: {root})")
        blob = ps.squash(str(root / "a615_zap.mdt"))
        want = (root / "a615_zap.elf").read_bytes()
        check("squashed a615_zap matches the vendor's unsplit .elf",
              blob == want,
              f"{len(blob)} bytes vs {len(want)}")
        check("output is an ELF", blob[:4] == b"\x7fELF", repr(blob[:4]))

        # A truncated segment must be refused, not silently padded -- a short
        # blob installs fine and fails at boot naming the firmware.
        import tempfile, shutil
        with tempfile.TemporaryDirectory() as td:
            for f in root.glob("a615_zap.*"):
                shutil.copy(f, td)
            victim = pathlib.Path(td) / "a615_zap.b01"
            victim.write_bytes(victim.read_bytes()[:-10])
            try:
                ps.squash(str(pathlib.Path(td) / "a615_zap.mdt"))
                check("a truncated segment is refused", False, "squash() returned normally")
            except ValueError:
                check("a truncated segment is refused", True)

    print()
    if _failures:
        print(f"FAILED: {len(_failures)} check(s): {', '.join(_failures)}")
        return 1
    if _skips:
        print(f"passed, but {len(_skips)} SKIPPED: {', '.join(_skips)}")
        print("The round-trip is the only thing that proves the reassembly; "
              "a run without it has not tested pil-squash.py.")
        return 0
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
