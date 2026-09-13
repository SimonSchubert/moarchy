#!/usr/bin/env python3
"""Prove android-image.py against artifacts that are known to work.

Run: python3 image/boot/test-android-image.py

Two claims are made in android-image.py's docstring, and a claim that was true
once is not a test. This file is what keeps them true:

  1. make_vbmeta() emits exactly what
     `avbtool make_vbmeta_image --flags 2 --padding_size 4096` emits.
  2. make_bootimg() reproduces a real, device-booting Android boot image
     byte-for-byte when given that image's own kernel and ramdisk back.

(2) is the load-bearing one. Every field in the v0 header -- the load
addresses, the page size, the cmdline split across two fields, the SHA1 id, the
per-section padding -- has to be right simultaneously or the bytes differ. A
writer that reproduces an image we watched boot a Pixel 3a (docs/devices.md
§8.1) is a writer whose every offset is confirmed, not reviewed.

The fixture for (2) is a 24 MB postmarketOS boot image, which is too big to
vendor. Point MOARCHY_SARGO_BOOTIMG at a copy, or fetch one with:

  curl -LO https://images.postmarketos.org/bpo/v26.06/google-sargo/\\
  sxmo-de-sway/20260911-0509/20260911-0509-postmarketOS-v26.06-\\
  sxmo-de-sway-1.18.0-google-sargo-boot.img.xz && xz -d *.img.xz

Without it, (2) SKIPS loudly rather than passing quietly -- a test that reports
success while measuring nothing is worse than one that does not run.
"""

import hashlib
import importlib.util
import os
import pathlib
import struct
import sys

_HERE = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("android_image",
                                               _HERE / "android-image.py")
ai = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ai)

# sha256 of `avbtool make_vbmeta_image --flags 2 --padding_size 4096`,
# avbtool 1.3.0 from AOSP. Recorded rather than the whole 4 KB file, because
# 4064 of those bytes are zero.
AVBTOOL_VBMETA_SHA256 = \
    "fe1f4b55088fbc97040bc898d8b076f93c93e203c8ba7a15c8348080351f4ca2"

_failures = []
_skips = []


def check(name, ok, detail=""):
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        _failures.append(name)


def skip(name, why):
    print(f"  skip {name}: {why}")
    _skips.append(name)


def test_vbmeta():
    # NO ARGUMENTS. The backend calls make_vbmeta() bare and relies on the
    # defaults, so the defaults are what has to be tested.
    #
    # This line said `ai.make_vbmeta(flags=2, padding_size=4096)` when it was
    # written, and changing the default to flags=0 -- verification back ON, the
    # one mistake that makes the bootloader silently refuse our kernel -- did
    # not fail a single check. Passing the value in tested the caller's
    # argument, not the code under test.
    img = ai.make_vbmeta()
    check("vbmeta is 4096 bytes", len(img) == 4096, f"got {len(img)}")
    check("vbmeta magic is AVB0", img[:4] == b"AVB0", repr(img[:4]))
    # Flags live at a fixed offset; if this moves, verification comes back on
    # and the bootloader silently refuses an unsigned kernel.
    flags = struct.unpack(">I", img[120:124])[0]
    check("vbmeta flags == 2 (verification disabled)", flags == 2, f"got {flags}")
    digest = hashlib.sha256(img).hexdigest()
    check("vbmeta matches avbtool byte-for-byte",
          digest == AVBTOOL_VBMETA_SHA256, f"sha256 {digest}")


def test_bootimg_roundtrip():
    # Searched relative to the REPO, not the cwd. `Path(".")` here walked
    # whatever directory the test happened to be run from -- and because /tmp
    # and /private/tmp are the same filesystem on macOS, running it from /tmp
    # silently reached into a scratch directory and found a fixture nobody
    # meant to offer it. A test whose inputs depend on where it was invoked
    # from reports on the machine rather than on the code.
    env = os.environ.get("MOARCHY_SARGO_BOOTIMG")
    candidates = [pathlib.Path(env)] if env else []
    candidates += sorted((_HERE.parent.parent).glob("**/*google-sargo-boot.img"))
    path = next((p for p in candidates if p.is_file()), None)
    if path is None:
        skip("boot.img round-trip",
             "no sargo boot.img fixture (set MOARCHY_SARGO_BOOTIMG)")
        return

    orig = path.read_bytes()
    if orig[:8] != b"ANDROID!":
        skip("boot.img round-trip", f"{path} is not an Android boot image")
        return

    ks, ka, rs, ra, ss, sa, ta, ps, hv, osv = struct.unpack("<10I", orig[8:48])
    if hv != 0:
        skip("boot.img round-trip", f"fixture is header v{hv}; writer emits v0")
        return

    cmdline = (orig[64:576].rstrip(b"\0") + orig[608:1632].rstrip(b"\0")).decode()

    def pad(n, p):
        return (n + p - 1) // p * p

    ko = ps
    ro = ko + pad(ks, ps)
    kernel = orig[ko:ko + ks]
    ramdisk = orig[ro:ro + rs]

    rebuilt = ai.make_bootimg(kernel, ramdisk, cmdline, page_size=ps,
                              kernel_addr=ka, ramdisk_addr=ra,
                              second_addr=sa, tags_addr=ta, os_version=osv)

    check("boot.img round-trip is byte-identical", rebuilt == orig,
          f"{sum(1 for a, b in zip(rebuilt, orig) if a != b)} differing bytes, "
          f"len {len(rebuilt)} vs {len(orig)}")
    # Named separately so a mismatch says which half moved.
    check("boot.img id[] SHA1 matches mkbootimg",
          rebuilt[576:596] == orig[576:596],
          f"mine {rebuilt[576:596].hex()} orig {orig[576:596].hex()}")


def main():
    print("android-image.py")
    test_vbmeta()
    test_bootimg_roundtrip()
    print()
    if _failures:
        print(f"FAILED: {len(_failures)} check(s): {', '.join(_failures)}")
        return 1
    if _skips:
        print(f"passed, but {len(_skips)} check(s) SKIPPED: {', '.join(_skips)}")
        print("The round-trip is the check that proves the header; a run "
              "without it has not tested the boot image writer.")
        return 0
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
