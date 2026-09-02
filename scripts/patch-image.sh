#!/usr/bin/env bash
# Patch a DanctNIX PinePhone image so a Mac can actually reach it, before flashing.
#
#   ./scripts/patch-image.sh ~/Downloads/mobileomarchy/archlinux-pinephone-barebone-20251224.img.xz
#
# Why this exists
# ---------------
# DanctNIX's usb-tethering gadget presents RNDIS (USB interface class 02/02/ff).
# macOS ships no RNDIS driver, so the phone enumerates as "Arch Linux Mobile"
# but no network interface ever appears and `ssh alarm@10.15.19.82` cannot work.
# CDC-ECM (02/06/00) is supported natively by macOS, and usb_f_ecm is built into
# the DanctNIX kernel (verified against modules.builtin), so switching costs
# nothing on Linux hosts.
#
# Optionally also preseeds a wifi connection, giving a second, independent way in:
#
#   WIFI_SSID='MyNetwork' WIFI_PSK='secret' ./scripts/patch-image.sh <image>
#
# Pass the PSK via the environment, not a flag, so it stays out of shell history
# and process listings.
#
# Needs e2fsprogs (`brew install e2fsprogs`) -- debugfs edits ext4 directly, so
# no VM, no root, no loop mounts.

set -euo pipefail

SRC="${1:-}"
[[ -n $SRC && -f $SRC ]] || { echo "usage: $0 <image.img|image.img.xz>" >&2; exit 1; }

E2FS_PREFIX="${E2FS_PREFIX:-/opt/homebrew/opt/e2fsprogs}"
DEBUGFS="$E2FS_PREFIX/sbin/debugfs"
E2FSCK="$E2FS_PREFIX/sbin/e2fsck"
for t in "$DEBUGFS" "$E2FSCK"; do
  [[ -x $t ]] || { echo "Missing $t -- run: brew install e2fsprogs" >&2; exit 1; }
done

# --- Decompress if needed --------------------------------------------------
if [[ $SRC == *.xz ]]; then
  IMG="${SRC%.xz}"
  if [[ -f $IMG ]]; then
    echo "==> using already-decompressed $IMG"
  else
    echo "==> decompressing (this takes a minute)"
    xz -dkc "$SRC" >"$IMG"
  fi
else
  IMG="$SRC"
fi
echo "    image: $IMG ($(ls -lh "$IMG" | awk '{print $5}'))"

# --- Locate the rootfs partition in the GPT --------------------------------
OFFSET=$(python3 - "$IMG" <<'PY'
import struct, sys
f = open(sys.argv[1], 'rb')
f.seek(512)
hdr = f.read(92)
assert hdr[:8] == b'EFI PART', 'not a GPT image'
part_lba = struct.unpack('<Q', hdr[72:80])[0]
nparts   = struct.unpack('<I', hdr[80:84])[0]
esize    = struct.unpack('<I', hdr[84:88])[0]
f.seek(part_lba * 512)
for _ in range(nparts):
    e = f.read(esize)
    if e[:16] == b'\x00' * 16:
        continue
    first = struct.unpack('<Q', e[32:40])[0]
    name = e[56:128].decode('utf-16-le').rstrip('\x00')
    if name == 'rootfs':
        print(first * 512)
        break
else:
    sys.exit('no rootfs partition found')
PY
)
echo "    rootfs at byte offset $OFFSET"
FS="$IMG?offset=$OFFSET"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- Sanity: is ECM actually available in this kernel? ----------------------
KVER=$("$DEBUGFS" -R "ls /usr/lib/modules" "$FS" 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' | head -1)
if ! "$DEBUGFS" -R "cat /usr/lib/modules/$KVER/modules.builtin" "$FS" 2>/dev/null | grep -q usb_f_ecm; then
  echo "!! usb_f_ecm is not built into kernel $KVER -- refusing to switch to ECM." >&2
  exit 1
fi
echo "    kernel $KVER has usb_f_ecm built in"

# --- Patch the gadget script ------------------------------------------------
echo "==> switching USB gadget rndis -> ecm"
"$DEBUGFS" -R "cat /usr/lib/danctnix/usb-tethering" "$FS" 2>/dev/null >"$WORK/orig"
grep -q 'rndis.usb0' "$WORK/orig" || { echo "    already patched, or unexpected script layout"; }

sed -e 's|:-rndis\.usb0}"|:-ecm.usb0}"|' \
    -e 's|echo "rndis" > \$CONFIGFS|echo "ecm" > $CONFIGFS|' \
    "$WORK/orig" >"$WORK/new"

python3 - "$WORK/new" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
if 'PATCHED BY mobileomarchy' not in s:
    s = s.replace("#!/bin/sh\n", """#!/bin/sh

# PATCHED BY mobileomarchy: rndis.usb0 -> ecm.usb0
# macOS has no RNDIS driver; CDC-ECM is supported natively.
# Reinstalling danctnix-usb-tethering reverts this.
""", 1)
    open(p, 'w').write(s)
PY

{
  echo "cd /usr/lib/danctnix"
  echo "rm usb-tethering"
  echo "write $WORK/new usb-tethering"
  echo "sif usb-tethering mode 0100755"
  echo "sif usb-tethering uid 0"
  echo "sif usb-tethering gid 0"
} >"$WORK/cmds"

# --- Optional wifi preseed --------------------------------------------------
if [[ -n ${WIFI_SSID:-} && -n ${WIFI_PSK:-} ]]; then
  echo "==> preseeding wifi for SSID '$WIFI_SSID'"
  cat >"$WORK/wifi.nmconnection" <<EOF
[connection]
id=$WIFI_SSID
uuid=$(uuidgen | tr 'A-Z' 'a-z')
type=wifi
autoconnect=true
autoconnect-priority=10

[wifi]
mode=infrastructure
ssid=$WIFI_SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$WIFI_PSK

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto
EOF
  {
    echo "cd /etc/NetworkManager/system-connections"
    echo "write $WORK/wifi.nmconnection $WIFI_SSID.nmconnection"
    # NetworkManager refuses to load a keyfile that is not 0600 root:root.
    echo "sif $WIFI_SSID.nmconnection mode 0100600"
    echo "sif $WIFI_SSID.nmconnection uid 0"
    echo "sif $WIFI_SSID.nmconnection gid 0"
  } >>"$WORK/cmds"
else
  echo "==> no WIFI_SSID/WIFI_PSK set, skipping wifi preseed"
fi

"$DEBUGFS" -w -f "$WORK/cmds" "$FS" >"$WORK/log" 2>&1 || { cat "$WORK/log" >&2; exit 1; }

echo "==> fsck"
"$E2FSCK" -fy "$FS" >"$WORK/fsck" 2>&1 || true
tail -2 "$WORK/fsck" | sed 's/^/    /'

echo
echo "==> verifying"
"$DEBUGFS" -R "cat /usr/lib/danctnix/usb-tethering" "$FS" 2>/dev/null |
  grep -q 'ecm.usb0' && echo "    gadget: ecm.usb0 OK" || { echo "    !! patch did not take" >&2; exit 1; }

cat <<NEXT

Patched image ready:
  $IMG

Flash it with:
  IMAGE_FILE="$IMG" ./scripts/flash-sd.sh /dev/diskN

After boot, the phone should appear on macOS as a network interface, reachable at:
  ssh alarm@10.15.19.82        (password: 123456)
NEXT
