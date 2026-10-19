#!/usr/bin/env python3
"""One clean Sahara MEMORY_DEBUG session against a 05c6:900e device.
  sahara-dump.py table                 print the region table
  sahara-dump.py read ADDR LEN OUT     read a range to OUT
  sahara-dump.py scan                  stream every DDR region through a
                                       crash-string scanner (nothing saved)
Read-only. Resets only the Sahara *protocol* state machine, never the phone."""
import struct, sys, re, time, usb.core, usb.util

dev = usb.core.find(idVendor=0x05C6, idProduct=0x900E) or sys.exit("no 900e device")
if '--usbreset' in sys.argv:
    sys.argv.remove('--usbreset')
    try: dev.reset()
    except usb.core.USBError as e: print("usb reset:", e)
    time.sleep(3)
    dev = usb.core.find(idVendor=0x05C6, idProduct=0x900E) or sys.exit("900e device gone after USB reset")
try:
    if dev.is_kernel_driver_active(0): dev.detach_kernel_driver(0)
except Exception: pass
intf = dev.get_active_configuration()[(0, 0)]
OUT = usb.util.find_descriptor(intf, custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_OUT)
IN = usb.util.find_descriptor(intf, custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_IN)

def rd(n=4096, t=3000): return bytes(IN.read(n, timeout=t))
def drain():
    while True:
        try: rd(4096, 300)
        except usb.core.USBTimeoutError: return

def handshake():
    hello = None
    try:
        p = rd(4096, 2000)
        if struct.unpack_from('<I', p)[0] == 1: hello = p
    except usb.core.USBTimeoutError: pass
    if not hello:
        drain(); OUT.write(struct.pack('<II', 0x13, 8))   # RESET_STATE_MACHINE
    for _ in range(0 if hello else 5):
        try:
            p = rd()
            if struct.unpack_from('<I', p)[0] == 1: hello = p; break
        except usb.core.USBTimeoutError: pass
    if not hello: sys.exit("no HELLO after state-machine reset")
    ver, vmin, _, mode = struct.unpack_from('<IIII', hello, 8)
    OUT.write(struct.pack('<IIIIII', 2, 0x30, ver, vmin, 0, 2) + b'\0' * 24)
    p = rd(); cmd = struct.unpack_from('<I', p)[0]
    if cmd == 0x10: return struct.unpack_from('<QQ', p, 8), True
    if cmd == 9:    return struct.unpack_from('<II', p, 8), False
    sys.exit(f"no MEMORY_DEBUG after handshake (cmd={cmd}, raw={p[:16].hex()})")

def reconnect():
    global dev, IN, OUT
    try: dev.reset()
    except Exception: pass
    time.sleep(3)
    dev = usb.core.find(idVendor=0x05C6, idProduct=0x900E)
    if dev is None: raise SystemExit("device gone during reconnect")
    try:
        if dev.is_kernel_driver_active(0): dev.detach_kernel_driver(0)
    except Exception: pass
    i = dev.get_active_configuration()[(0, 0)]
    OUT = usb.util.find_descriptor(i, custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_OUT)
    IN = usb.util.find_descriptor(i, custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_IN)
    handshake()

def mread(addr, n):
    OUT.write(struct.pack('<IIQQ', 0x11, 24, addr, n))
    got = b''
    while len(got) < n:
        d = rd(min(n - len(got), 0x100000), 8000)
        if not got and len(d) == 16 and struct.unpack_from('<I', d)[0] == 4:
            raise IOError(f"END_IMAGE_TX status={struct.unpack_from('<I', d, 12)[0]} at 0x{addr:x}")
        got += d
    return got

(taddr, tlen), is64 = handshake()
tbl = mread(taddr, tlen)
regions = []
esz = 0x40 if is64 else 0x58
for i in range(0, len(tbl) - esz + 1, esz):
    e = tbl[i:i+esz]
    if is64: _, base, ln = struct.unpack_from('<QQQ', e, 0); desc, fn = e[24:44], e[44:64]
    else:    _, base, ln = struct.unpack_from('<III', e, 0); desc, fn = e[12:32], e[32:52]
    regions.append((base, ln, desc.split(b'\0')[0].decode(errors='replace'), fn.split(b'\0')[0].decode(errors='replace')))

mode = sys.argv[1] if len(sys.argv) > 1 else 'table'
if mode == 'table':
    for b, l, d, f in regions: print(f"0x{b:010x} 0x{l:010x} {l>>20:6d} MiB  {d:20s} {f}")
elif mode == 'read':
    a, n, out = int(sys.argv[2], 0), int(sys.argv[3], 0), sys.argv[4]
    data = b''
    while len(data) < n: data += mread(a + len(data), min(0x100000, n - len(data)))
    open(out, 'wb').write(data); print(f"read {len(data)} bytes -> {out}")
elif mode == 'scan':
    pat = re.compile(rb'(Kernel panic[^\n\0]{0,160}|Unable to handle kernel[^\n\0]{0,160}|Internal error:[^\n\0]{0,160}|'
                     rb'SError[^\n\0]{0,120}|Watchdog bark[^\n\0]{0,120}|watchdog[^\n\0]{0,40}bite[^\n\0]{0,80}|'
                     rb'Call trace:|BUG: [^\n\0]{0,160}|Oops[^\n\0]{0,120}|reboot: Restarting system[^\n\0]{0,80}|'
                     rb'systemd-shutdown\[1\]: [^\n\0]{0,160}|Linux version [^\n\0]{0,120}|rcu: INFO[^\n\0]{0,120}|[Hh]ard LOCKUP[^\n\0]{0,80}|soft lockup[^\n\0]{0,120}|Synchronous External Abort[^\n\0]{0,120}|arm-smmu[^\n\0]{0,40}fault[^\n\0]{0,120}|qcom_q6v5[^\n\0]{0,40}(fatal|crash|watchdog)[^\n\0]{0,120}|remoteproc[0-9]: crash detected[^\n\0]{0,120})')
    ddr = [r for r in regions if r[2].strip().startswith('DDR CS')]
    total = sum(r[1] for r in ddr); seen = 0; hits = []; skipped = []; t0 = time.time()
    for base, ln, desc, fn in ddr:
        off, tail = 0, b''
        while off < ln:
            n = min(0x100000, ln - off)
            try:
                chunk = mread(base + off, n)
            except (IOError, usb.core.USBError) as e:
                skipped.append((base + off, n)); reconnect()
                tail = b''; off += n; seen += n; continue
            buf = tail + chunk
            for m in pat.finditer(buf):
                hits.append((base + off - len(tail) + m.start(), m.group(0)[:200]))
            tail = buf[-256:]; off += n; seen += n
            if seen % (0x10000000) < n:
                print(f"  {seen>>20}/{total>>20} MiB, {len(hits)} hits, {seen/(time.time()-t0)/1e6:.1f} MB/s", flush=True)
    print(f"SCAN DONE: {len(hits)} hits, {len(skipped)} unreadable MiB-chunks")
    if skipped: print("first unreadable:", ", ".join(f"0x{a:x}" for a, _ in skipped[:12]))
    for a, h in hits[-120:]: print(f"0x{a:010x}  {h.decode(errors='replace')}")
