#!/usr/bin/env python3
"""Print the printk text records of a raw __log_buf dump that follow MARK
(default: the last line the ramoops console got), i.e. what was logged but
maybe never reached a console. Masks MACs and skips the cmdline."""
import re, sys
b = open(sys.argv[1], 'rb').read(); mark = sys.argv[2] if len(sys.argv) > 2 else 'gmu: Adding to iommu group'
txt = [m.group(0).decode(errors='replace') for m in re.finditer(rb'[\x20-\x7e\t]{8,}', b)]
idx = [i for i, t in enumerate(txt) if mark in t]
print(f"{len(txt)} strings; mark '{mark}' at {idx[-3:] if idx else 'NOT FOUND'}")
start = idx[-1] if idx else max(0, len(txt) - 15)
for t in txt[start:start + 25]:
    if 'command line' in t.lower(): continue
    print("     " + re.sub(r'([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}', '<mac>', t)[:170])
