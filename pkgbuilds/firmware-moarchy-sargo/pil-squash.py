#!/usr/bin/env python3
"""Reassemble a Qualcomm split-ELF firmware blob (.mdt + .bNN) into one .mbn.

Qualcomm ships signed firmware as an ELF whose segments live in separate files:
`foo.mdt` carries the ELF header and program headers, and `foo.b00`, `foo.b01`
... carry each segment's bytes. The kernel's `firmware-name` in the device tree
names a single `.mbn`, so the pieces have to be put back together.

postmarketOS uses `pil-squasher` for this, a small C program packaged for
Alpine and absent from Arch. Rather than add a package and a build to get one
binary, this does the same job in 40 lines -- the same trade
image/boot/android-image.py makes against mkbootimg, and for the same reason.

It is not trusted on its say-so. The vendor tree ships `a615_zap.elf` beside
the split pieces, which is the unsplit original, and
pkgbuilds/firmware-moarchy-sargo/test-pil-squash.py checks that squashing the
pieces reproduces that file byte-for-byte.
"""

import struct
import sys


def squash(mdt_path):
    """Return the reassembled blob for <base>.mdt and its <base>.bNN files."""
    with open(mdt_path, "rb") as f:
        mdt = f.read()
    if mdt[:4] != b"\x7fELF":
        raise ValueError(f"{mdt_path} is not an ELF ({mdt[:4]!r})")

    is64 = mdt[4] == 2
    if is64:
        (e_phoff,) = struct.unpack_from("<Q", mdt, 0x20)
        e_phentsize, e_phnum = struct.unpack_from("<HH", mdt, 0x36)
    else:
        (e_phoff,) = struct.unpack_from("<I", mdt, 0x1C)
        e_phentsize, e_phnum = struct.unpack_from("<HH", mdt, 0x2A)

    base = mdt_path[:-4] if mdt_path.endswith(".mdt") else mdt_path
    segments = []
    for i in range(e_phnum):
        o = e_phoff + i * e_phentsize
        if is64:
            p_offset, _, _, p_filesz = struct.unpack_from("<QQQQ", mdt, o + 8)
        else:
            _, p_offset, _, _, p_filesz = struct.unpack_from("<IIIII", mdt, o)
        if p_filesz:
            segments.append((i, p_offset, p_filesz))

    if not segments:
        # Never silently emit an empty blob: a zero-length .mbn installs fine
        # and fails at boot as a firmware load error naming the file, not the
        # build that produced it.
        raise ValueError(f"{mdt_path} declares no segments with content")

    total = max(off + size for _, off, size in segments)
    out = bytearray(total)
    for i, off, size in segments:
        part = f"{base}.b{i:02d}"
        with open(part, "rb") as f:
            data = f.read()
        if len(data) != size:
            raise ValueError(
                f"{part} is {len(data)} bytes, header says {size}")
        out[off:off + size] = data
    return bytes(out)


def main(argv):
    if len(argv) != 2:
        print("usage: pil-squash.py <in.mdt> <out.mbn>", file=sys.stderr)
        return 2
    blob = squash(argv[0])
    with open(argv[1], "wb") as f:
        f.write(blob)
    print(f"{argv[1]}: {len(blob)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
