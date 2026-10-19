#!/usr/bin/env python3
"""FP4 GPS XTRA (predicted-orbits) assistance injector - DIAGNOSTIC (D8).

The FP4 modem's raw GNSS receiver works but never fixes indoors because it has
no predicted-orbits (xtra) assistance. ModemManager cannot load it (its
data-source indication omits the allowed_sizes TLV, so MM sets
SupportedAssistanceData=NONE) and qmicli exposes no xtra inject. This drives
QMI-LOC directly over libqmi to do it from userspace.

Status (2026-09-28): every part transfers with indication_status=SUCCESS
(bytes verified correct in a QMI_DEBUG trace), but the modem rejects the
ASSEMBLED xtra at finalization -- terminal indication GENERAL_FAILURE with a
fixed detail code 2, validity stays "missing". Ruled out exhaustively: xtra
v1/v2/v3; part sizes 1024 (the hard max; 1025 -> ArgumentTooLong) and
even-division; time injected; engine on/off; register_events beforehand.
inject_predicted_orbits_data (0x0025) is NotSupported. Conclusion: QMI-LOC xtra
finalization is a non-functional stub on this MPSS build -- xtra A-GPS is not
reachable from mainline userspace here. This tool stays as the diagnostic that
reaches the wall. The one working lever is coarse --loc-inject-time /
--loc-inject-position. See docs/fp4-defects.md D8.

Coexists with ModemManager via qmi-proxy; worst-case recovery is
`systemctl restart ModemManager`, never a reboot. Run as root.

Usage:
    fp4-gps-xtra-inject.py                 # get source URL, download, inject
    fp4-gps-xtra-inject.py --file xtra.bin # inject a local file
    fp4-gps-xtra-inject.py --source-only   # just print the modem's xtra URLs
    fp4-gps-xtra-inject.py --part-size 997
"""
import sys, math, argparse, urllib.request, gi
gi.require_version("Qmi", "1.0")
from gi.repository import Qmi, Gio, GLib

QRTR = "qrtr://0"

def run(fn):
    """Drive one async libqmi flow on a private main loop; return fn's result."""
    loop = GLib.MainLoop()
    box = {"rc": 1, "val": None}
    GLib.idle_add(lambda: (fn(loop, box), False)[1])
    GLib.timeout_add_seconds(120, lambda: (loop.quit(), False)[1])
    loop.run()
    return box

def open_loc(on_client, loop, box):
    def new_ready(_, res):
        try: dev = Qmi.Device.new_finish(res)
        except GLib.Error as e: print("FAIL new:", e.message); return loop.quit()
        dev.open(Qmi.DeviceOpenFlags.PROXY, 15, None, open_ready)
    def open_ready(dev, res):
        try: dev.open_finish(res)
        except GLib.Error as e: print("FAIL open:", e.message); return loop.quit()
        dev.allocate_client(Qmi.Service.LOC, Qmi.CID_NONE, 10, None, client_ready)
    def client_ready(dev, res):
        try: cli = dev.allocate_client_finish(res)
        except GLib.Error as e: print("FAIL allocate:", e.message); return loop.quit()
        on_client(cli, loop, box)
    Qmi.Device.new(Gio.File.new_for_commandline_arg(QRTR), None, new_ready)

def get_source():
    def flow(loop, box):
        def on_client(cli, loop, box):
            def on_ind(c, out):
                # get_server_list may return a bare list or (ok, list, ...)
                r = out.get_server_list()
                servers = r[1] if isinstance(r, tuple) and len(r) >= 2 else r
                box["val"] = servers; box["rc"] = 0
                loop.quit()
            cli.connect("get-predicted-orbits-data-source", on_ind)
            def resp(c, res):
                try: c.get_predicted_orbits_data_source_finish(res).get_result()
                except GLib.Error as e: print("FAIL source:", e.message); loop.quit()
            cli.get_predicted_orbits_data_source(None, 15, None, resp)
        open_loc(on_client, loop, box)
    return run(flow)

def inject(data, part_size):
    total_size = len(data)
    total_parts = max(1, math.ceil(total_size / part_size))
    parts = [data[i*part_size:(i+1)*part_size] for i in range(total_parts)]
    print("xtra: %d bytes, %d parts of <=%d" % (total_size, total_parts, part_size))
    def flow(loop, box):
        def on_client(cli, loop, box):
            box["n"] = 0
            def send(idx):
                inp = Qmi.MessageLocInjectXtraDataInput()
                inp.set_total_size(total_size)
                inp.set_total_parts(total_parts)
                inp.set_part_number(idx + 1)          # 1-based (0-based -> MalformedMessage)
                inp.set_part_data(parts[idx])
                cli.inject_xtra_data(inp, 20, None, on_resp)
            def on_resp(c, res):
                try: c.inject_xtra_data_finish(res).get_result()
                except GLib.Error as e: print("FAIL part %d req: %s" % (box["n"]+1, e.message)); loop.quit()
            def on_ind(c, out):
                st = int(out.get_indication_status())
                if st != 0:
                    print("FAIL: part %d finalization status=%d (GENERAL_FAILURE=1)" % (box["n"]+1, st))
                    return loop.quit()
                box["n"] += 1
                if box["n"] % 16 == 0 or box["n"] == total_parts:
                    print("confirmed %d/%d" % (box["n"], total_parts))
                if box["n"] < total_parts:
                    send(box["n"])
                else:
                    box["rc"] = 0; print("XTRA injected OK"); loop.quit()
            cli.connect("inject-xtra-data", on_ind)
            send(0)
        open_loc(on_client, loop, box)
    return run(flow)

def main():
    ap = argparse.ArgumentParser(description="FP4 GPS XTRA injector (diagnostic, D8)")
    ap.add_argument("--file", help="inject a local xtra file instead of downloading")
    ap.add_argument("--source-only", action="store_true", help="print modem xtra URLs and exit")
    ap.add_argument("--part-size", type=int, default=1024)
    args = ap.parse_args()

    box = get_source()
    servers = box.get("val") or []
    print("modem xtra servers:", servers)
    if args.source_only:
        return 0 if servers else 1

    if args.file:
        data = open(args.file, "rb").read()
    else:
        if not servers:
            print("no server URL from modem; pass --file"); return 1
        url = servers[0]
        print("downloading", url)
        data = urllib.request.urlopen(url, timeout=30).read()

    rc = inject(data, args.part_size)["rc"]
    print("(check validity: qmicli -d %s --loc-get-predicted-orbits-data-validity)" % QRTR)
    return rc

if __name__ == "__main__":
    sys.exit(main())
