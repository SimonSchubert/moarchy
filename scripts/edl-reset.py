#!/usr/bin/env python3
"""Bring a Fairphone 4 out of EDL without touching it.

The phone sometimes comes up in Qualcomm's emergency download mode instead of
booting (docs/fp4-defects.md D11): powered, enumerating as

    ID 05c6:900e Qualcomm, Inc. QUSB_BULK_SN:...

with no fastboot, no adb and no network. The documented recovery is a physical
power-button hold, which is no use when the handset is not in the room.

It does not need one. EDL speaks Sahara, and Sahara has a reset command that
the device honours before any authentication: it replies RESET_RESPONSE and
reboots normally. Nothing is flashed and no programmer is uploaded -- this
sends two 32-bit words and reads the acknowledgement.

Needs pyusb and permission to talk to the device (a udev rule, or run as root).

Verified on hardware 2026-09-23: recovered a handset that had dropped into EDL
after a reboot, with no physical access.
"""

import struct
import sys
import time

try:
    import usb.core
    import usb.util
except ImportError:
    sys.exit("edl-reset: needs pyusb (pacman -S python-pyusb)")

VENDOR, PRODUCT = 0x05C6, 0x900E
SAHARA_HELLO, SAHARA_HELLO_RESPONSE = 1, 2
SAHARA_RESET, SAHARA_RESET_RESPONSE = 7, 8


def main() -> int:
    dev = usb.core.find(idVendor=VENDOR, idProduct=PRODUCT)
    if dev is None:
        print(f"edl-reset: no device {VENDOR:04x}:{PRODUCT:04x} -- "
              "the phone is not in EDL (which may be good news)")
        return 1

    try:
        if dev.is_kernel_driver_active(0):
            dev.detach_kernel_driver(0)
    except (NotImplementedError, usb.core.USBError):
        pass

    intf = dev.get_active_configuration()[(0, 0)]
    out = usb.util.find_descriptor(intf, custom_match=lambda e: usb.util.
                                   endpoint_direction(e.bEndpointAddress) ==
                                   usb.util.ENDPOINT_OUT)
    inp = usb.util.find_descriptor(intf, custom_match=lambda e: usb.util.
                                   endpoint_direction(e.bEndpointAddress) ==
                                   usb.util.ENDPOINT_IN)
    if out is None or inp is None:
        return print("edl-reset: no bulk endpoints") or 1

    def read(timeout=3000):
        try:
            return bytes(inp.read(4096, timeout))
        except usb.core.USBError:
            return b""

    # The device greets first. A 64-bit target sends command 0x10 rather than
    # HELLO; either way the reset below is accepted, so the greeting is read
    # to drain the endpoint and answered only when it is a HELLO we recognise.
    greeting = read()
    if len(greeting) >= 8:
        cmd, _ = struct.unpack_from("<II", greeting)
        if cmd == SAHARA_HELLO and len(greeting) >= 0x30:
            version, version_min, _maxlen, mode = struct.unpack_from(
                "<IIII", greeting, 8)
            out.write(struct.pack("<IIIIII", SAHARA_HELLO_RESPONSE, 0x30,
                                  version, version_min, 0, mode) + b"\x00" * 24,
                      3000)
            time.sleep(0.2)

    out.write(struct.pack("<II", SAHARA_RESET, 8), 3000)
    reply = read(2000)
    if len(reply) >= 8 and struct.unpack_from("<I", reply)[0] == SAHARA_RESET_RESPONSE:
        print("edl-reset: reset acknowledged, the phone is rebooting")
        return 0

    # No acknowledgement is not necessarily failure: some devices reset without
    # answering, and the endpoint then reads nothing because the link is gone.
    print("edl-reset: reset sent, no acknowledgement -- "
          "watch for the phone to come back before trying anything else")
    return 0


if __name__ == "__main__":
    sys.exit(main())
