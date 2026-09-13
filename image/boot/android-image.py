#!/usr/bin/env python3
"""Write an Android boot.img and an AVB vbmeta image.

Two small, well-specified binary formats, written here rather than shelled out
to, because neither tool is in Arch Linux ARM:

  mkbootimg  is in postmarketOS and the AOSP tree, packaged for Alpine, and in
             the AUR only as a source build that drags in the whole platform
             repo. The v0 header is 1600 bytes of fixed-offset fields; parsing
             pmOS's own boot.img with struct is how every offset below was
             confirmed, and writing one back is the same code in reverse.

  avbtool    is a single 200 KB AOSP Python file. Vendoring it to emit a
             4096-byte blob of which 224 bytes are non-zero is the wrong trade.
             make_vbmeta() below is checked byte-for-byte against
             `avbtool make_vbmeta_image --flags 2 --padding_size 4096`; the
             test lives in image/boot/test-android-image.py so the claim stays
             true rather than merely having been true once.

Neither format is guessed. Both were measured against
20260911-0509-postmarketOS-v26.06-sxmo-de-sway-1.18.0-google-sargo-boot.img,
which is an image that demonstrably boots the target device (docs/devices.md
§8.1).
"""

import hashlib
import struct
import sys

# --- Android boot image, header version 0 -----------------------------------
#
# Measured off pmOS's sargo boot.img, and identical to what deviceinfo declares:
#
#   header_version 0        page_size 4096
#   kernel  @ 0x8000        ramdisk @ 0x1000000      tags @ 0x100
#
# The addresses are LOAD addresses relative to base, not file offsets; the
# bootloader adds them to the kernel's physical base. They are device facts and
# wrong values give a black screen with nothing to read, which is why they are
# taken from a working image rather than from a wiki.
BOOT_MAGIC = b"ANDROID!"


def pad_to(data: bytes, page_size: int) -> bytes:
    """Android boot images pad every section up to a page boundary."""
    rem = len(data) % page_size
    return data + (b"\0" * (page_size - rem) if rem else b"")


def make_bootimg(kernel: bytes, ramdisk: bytes, cmdline: str,
                 page_size: int = 4096,
                 kernel_addr: int = 0x00008000,
                 ramdisk_addr: int = 0x01000000,
                 second_addr: int = 0x00000000,
                 tags_addr: int = 0x00000100,
                 os_version: int = 0) -> bytes:
    """Build a header-v0 Android boot image.

    `kernel` is expected to already have its DTB appended -- sargo's deviceinfo
    sets append_dtb=true, and pmOS's image carries FDT magic inside the kernel
    payload rather than in the `second` area. Doing it here would hide a device
    decision inside a generic writer.
    """
    cmd = cmdline.encode()
    if len(cmd) > 512 + 1024:
        raise ValueError(f"cmdline is {len(cmd)} bytes; the v0 header holds 1536")
    # The header splits cmdline across two fields at a fixed boundary.
    cmdline_field, extra_field = cmd[:512], cmd[512:]

    hdr = bytearray(BOOT_MAGIC)
    hdr += struct.pack(
        "<10I",
        len(kernel), kernel_addr,
        len(ramdisk), ramdisk_addr,
        0, second_addr,              # no `second` stage
        tags_addr, page_size,
        0,                           # header_version
        os_version,
    )
    hdr += b"\0" * 16                                  # product name
    hdr += cmdline_field.ljust(512, b"\0")
    # id[] is a SHA1 over each section's data followed by its little-endian
    # length, including the absent `second` section as a bare zero length. An
    # unlocked bootloader does not check it, so this could be zeroes and still
    # boot -- but computing it is eight lines and it is what makes this writer
    # reproduce pmOS's own image byte-for-byte, which is the only evidence that
    # every other field above is right too.
    sha = hashlib.sha1()
    for part in (kernel, ramdisk, b""):
        sha.update(part)
        sha.update(struct.pack("<I", len(part)))
    hdr += sha.digest().ljust(32, b"\0")
    hdr += extra_field.ljust(1024, b"\0")

    return (pad_to(bytes(hdr), page_size)
            + pad_to(kernel, page_size)
            + pad_to(ramdisk, page_size))


# --- AVB vbmeta -------------------------------------------------------------
#
# An Android 12 bootloader will not hand control to an unsigned kernel unless
# the vbmeta it has says verification is off. Flag 2 is
# AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED.
#
# The header is 256 bytes, big-endian, and every size field is zero because
# there are no descriptors, no authentication block and no key: the image says
# only "do not verify".
AVB_MAGIC = b"AVB0"


def make_vbmeta(flags: int = 2, padding_size: int = 4096) -> bytes:
    h = bytearray()
    h += AVB_MAGIC                              # magic
    h += struct.pack(">II", 1, 0)               # required libavb 1.0
    h += struct.pack(">QQ", 0, 0)               # auth block, aux block sizes
    h += struct.pack(">I", 0)                   # algorithm type: NONE
    h += struct.pack(">QQ", 0, 0)               # hash offset, size
    h += struct.pack(">QQ", 0, 0)               # signature offset, size
    h += struct.pack(">QQ", 0, 0)               # public key offset, size
    h += struct.pack(">QQ", 0, 0)               # public key metadata
    h += struct.pack(">QQ", 0, 0)               # descriptors offset, size
    h += struct.pack(">Q", 0)                   # rollback index
    h += struct.pack(">I", flags)               # <-- the whole point
    h += struct.pack(">I", 0)                   # rollback index location
    h += b"avbtool 1.3.0".ljust(48, b"\0")      # release string
    h += b"\0" * (256 - len(h))                 # reserved, to 256 bytes
    assert len(h) == 256, len(h)

    out = bytes(h)
    if padding_size:
        rem = len(out) % padding_size
        if rem:
            out += b"\0" * (padding_size - rem)
    return out


def _main(argv):
    import argparse
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("bootimg")
    b.add_argument("--kernel", required=True)
    b.add_argument("--ramdisk", required=True)
    b.add_argument("--dtb", help="appended to the kernel (sargo: required)")
    b.add_argument("--cmdline", default="")
    b.add_argument("--pagesize", type=int, default=4096)
    b.add_argument("--out", required=True)

    v = sub.add_parser("vbmeta")
    v.add_argument("--flags", type=int, default=2)
    v.add_argument("--padding", type=int, default=4096)
    v.add_argument("--out", required=True)

    a = ap.parse_args(argv)

    if a.cmd == "bootimg":
        kernel = open(a.kernel, "rb").read()
        if a.dtb:
            kernel += open(a.dtb, "rb").read()
        ramdisk = open(a.ramdisk, "rb").read()
        img = make_bootimg(kernel, ramdisk, a.cmdline, page_size=a.pagesize)
        open(a.out, "wb").write(img)
        print(f"boot.img: {len(img)} bytes "
              f"(kernel {len(kernel)}, ramdisk {len(ramdisk)}, page {a.pagesize})")
    else:
        img = make_vbmeta(a.flags, a.padding)
        open(a.out, "wb").write(img)
        print(f"vbmeta.img: {len(img)} bytes, flags={a.flags}")
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
