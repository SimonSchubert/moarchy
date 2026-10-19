#!/usr/bin/env python3
"""Extract the ramoops console zone (sm6350.dtsi layout: 1 MiB at ffc00000,
console 0x40000 at +0xa0000) from a raw dump; print the last N lines, masked."""
import struct, sys, re
b = open(sys.argv[1], 'rb').read(); n = int(sys.argv[2]) if len(sys.argv) > 2 else 12
z = 0xa0000
if b[z:z+4] != b'DBGC': sys.exit("no console zone header")
st, sz = struct.unpack_from('<II', b, z + 4)
cap = 0x40000 - 12 - 16 * ((0x40000 - 12) // (128 + 16) + 1)   # rough ECC overhead
data = b[z+12:z+12+sz]
if sz >= cap: data = data[st:] + data[:st]                     # wrapped ring
L = data.decode(errors='replace').splitlines()
print(f"console {sz} bytes, {len(L)} lines; last:")
for l in L[-n:]:
    if 'command line' in l.lower(): continue
    l = re.sub(r'([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}', '<mac>', l)
    print("     " + l[:170])
