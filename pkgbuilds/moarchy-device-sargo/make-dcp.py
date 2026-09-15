#!/usr/bin/env python3
"""Emit the DNG camera profiles megapixels needs for the Pixel 3a.

WHY THIS IS A GENERATOR AND NOT TWO COMMITTED .dcp FILES
--------------------------------------------------------
A .dcp is a small TIFF whose payload is nine numbers twice over. Committing it
as a binary would make the one thing worth reviewing -- the matrices -- the one
thing nobody can read in a diff. Everything here is derived from the constants
at the top, so a correction is a number rather than a rebuilt blob.

WHERE THE NUMBERS COME FROM
---------------------------
Google's own calibration for this sensor, read out of a Pixel 3a DNG published
on raw.pixls.us under CC0 (sample 3496, IMG_20190918_164153.dng). Every DNG the
stock camera ever wrote carries ColorMatrix1/2 in its tags; this is that data,
not a guess and not a measurement of ours.

    ColorMatrix1   illuminant 20 (D55)
    ColorMatrix2   illuminant 17 (Standard A)

What that DNG does NOT carry is ForwardMatrix1/2, and megapixels reads them:
src/process_pipeline.c falls back to IDENTITY colour matrices and an sRGB
forward matrix when no profile is found, which is exactly the green preview
this fixes. So the forward matrices are derived here, per the DNG 1.4 spec:

    n  = CM . W                     the camera's response to the illuminant
    FM = CA(W->D50) . CM^-1 . diag(n)

which satisfies the spec's requirement that FM . [1,1,1] be the XYZ of D50 --
white balanced camera values map to D50 white. CA is Bradford.

NOT A SUBSTITUTE FOR A MEASURED PROFILE. This has no HueSatMap and no look
table, which is where a chart-shot profile earns its keep; it fixes white
balance and primaries, which is the difference between "green" and "right".
"""

import struct
import sys

# --- Google's matrices, XYZ -> camera RGB, row-major ------------------------
COLOR_MATRIX_1 = [1.0598, -0.5058, -0.1606,
                  -0.9956, 1.9269, 0.0401,
                  0.0642, -0.2328, 1.2123]
COLOR_MATRIX_2 = [1.6298, -0.7708, -0.2489,
                  -0.9956, 1.9269, 0.0401,
                  0.0482, -0.1686, 0.8591]
ILLUMINANT_1 = 20   # D55
ILLUMINANT_2 = 17   # Standard illuminant A

# XYZ of each illuminant, normalised to Y=1, from their CIE chromaticities.
WHITE = {
    17: (1.09850, 1.0, 0.35585),   # A    x 0.44757 y 0.40745
    20: (0.95682, 1.0, 0.92149),   # D55  x 0.33242 y 0.34743
    21: (0.95047, 1.0, 1.08883),   # D65
}
D50 = (0.96422, 1.0, 0.82521)

BRADFORD = [0.8951, 0.2664, -0.1614,
            -0.7502, 1.7135, 0.0367,
            0.0389, -0.0685, 1.0296]


def mul(a, b):
    return [sum(a[r * 3 + k] * b[k * 3 + c] for k in range(3))
            for r in range(3) for c in range(3)]


def apply(m, v):
    return tuple(sum(m[r * 3 + c] * v[c] for c in range(3)) for r in range(3))


def inverse(m):
    a, b, c, d, e, f, g, h, i = m
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    if abs(det) < 1e-12:
        raise SystemExit("colour matrix is singular; check the constants")
    return [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
            (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
            (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]


def adaptation(src, dst):
    """Bradford chromatic adaptation, src white -> dst white."""
    s = apply(BRADFORD, src)
    t = apply(BRADFORD, dst)
    scale = [t[0] / s[0], 0, 0, 0, t[1] / s[1], 0, 0, 0, t[2] / s[2]]
    return mul(inverse(BRADFORD), mul(scale, BRADFORD))


def forward_matrix(cm, illuminant):
    w = WHITE[illuminant]
    n = apply(cm, w)
    diag = [n[0], 0, 0, 0, n[1], 0, 0, 0, n[2]]
    return mul(adaptation(w, D50), mul(inverse(cm), diag))


# --- the TIFF/DCP container -------------------------------------------------
# A .dcp is a little-endian TIFF whose magic is 0x4352 rather than 42, with one
# IFD of DNG profile tags. Structure copied from the PinePhone profile
# megapixels already reads, minus the HueSatMap and look tables it has and we
# have no measurements for.
SRATIONAL, SHORT, LONG, ASCII, FLOAT = 10, 3, 4, 2, 11


def srational(values, denom=1000000):
    return b''.join(struct.pack('<ii', int(round(v * denom)), denom)
                    for v in values)


def build(name, cm1, cm2, fm1, fm2, model):
    entries = []          # (tag, type, count, payload)
    entries.append((50708, ASCII, len(model) + 1, model.encode() + b'\0'))
    entries.append((50721, SRATIONAL, 9, srational(cm1)))
    entries.append((50722, SRATIONAL, 9, srational(cm2)))
    entries.append((50778, SHORT, 1, struct.pack('<H', ILLUMINANT_1)))
    entries.append((50779, SHORT, 1, struct.pack('<H', ILLUMINANT_2)))
    entries.append((50936, ASCII, len(name) + 1, name.encode() + b'\0'))
    # 1 = "allow copying", the same policy the PinePhone profile ships.
    entries.append((50941, LONG, 1, struct.pack('<I', 1)))
    entries.append((50964, SRATIONAL, 9, srational(fm1)))
    entries.append((50965, SRATIONAL, 9, srational(fm2)))
    entries.sort(key=lambda e: e[0])

    header = struct.pack('<HHI', 0x4949, 0x4352, 8)
    ifd_size = 2 + 12 * len(entries) + 4
    data_off = len(header) + ifd_size
    ifd, blob = struct.pack('<H', len(entries)), b''
    for tag, typ, count, payload in entries:
        if len(payload) <= 4:
            value = payload.ljust(4, b'\0')
        else:
            value = struct.pack('<I', data_off + len(blob))
            blob += payload
            if len(blob) % 2:          # TIFF wants even offsets
                blob += b'\0'
        ifd += struct.pack('<HHI', tag, typ, count) + value
    ifd += struct.pack('<I', 0)
    return header + ifd + blob


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: make-dcp.py <rear.dcp> <front.dcp>")

    fm1 = forward_matrix(COLOR_MATRIX_1, ILLUMINANT_1)
    fm2 = forward_matrix(COLOR_MATRIX_2, ILLUMINANT_2)

    # The spec's own check, asserted rather than assumed: a forward matrix must
    # take white-balanced camera values to D50 white. Getting this wrong tints
    # every photograph, and nothing downstream would say so.
    for label, fm in (("1", fm1), ("2", fm2)):
        got = apply(fm, (1.0, 1.0, 1.0))
        if max(abs(got[i] - D50[i]) for i in range(3)) > 1e-4:
            raise SystemExit("ForwardMatrix%s maps white to %s, not D50 %s"
                             % (label, got, D50))

    # Both cameras get the same profile. The IMX355 front sensor has no
    # published calibration of its own, and Google's rear matrices are a far
    # better starting point than the identity matrix megapixels falls back to
    # -- which is the whole bug. Said out loud because it IS an approximation
    # for the front camera, unlike the rear where it is the vendor's data.
    for path, which in ((sys.argv[1], "rear"), (sys.argv[2], "front")):
        with open(path, 'wb') as f:
            f.write(build("Pixel 3a %s" % which,
                          COLOR_MATRIX_1, COLOR_MATRIX_2, fm1, fm2,
                          "Google Pixel 3a"))
        print("wrote %s" % path)


if __name__ == '__main__':
    main()
