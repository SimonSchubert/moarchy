#!/usr/bin/env bash
# Preseed a wifi connection into a PinePhone image before flashing, so the phone
# joins the network on first boot and is reachable over SSH without a keyboard.
#
#   WIFI_SSID='MyNetwork' WIFI_PSK='secret' ./scripts/patch-image.sh <image.img|.img.xz>
#
# Optional. It exists to save a round trip on a debug build -- flash, boot, and
# the phone is already on the network. Without it you need a USB keyboard (or a
# serial console) to run `nmtui` once.
#
# Pass the PSK via the environment, not a flag, so it stays out of shell history
# and process listings.
#
# ---------------------------------------------------------------------------
# What this used to do, and why it does not any more
# ---------------------------------------------------------------------------
# This script's original job was switching DanctNIX's USB gadget from RNDIS to
# CDC-ECM, because macOS has no RNDIS driver. That worked at the file level --
# the gadget script really was patched, and usb_f_ecm really is built into the
# kernel -- but the link never came up in practice: macOS binds the interface
# and the gadget side never gains carrier. Wifi is the only way in that has been
# made to work from this host, so the USB path is gone rather than left in as a
# route that reads like it should work.
#
# Once the image builder in image/ exists, this goes too: preseeding is a build
# input there, not surgery on someone else's ext4. See docs/structure.md I6.
#
# Needs e2fsprogs (`brew install e2fsprogs`) -- debugfs edits ext4 directly, so
# no VM, no root, no loop mounts.

set -euo pipefail

SRC="${1:-}"
[[ -n $SRC && -f $SRC ]] || { echo "usage: WIFI_SSID=... WIFI_PSK=... $0 <image.img|image.img.xz>" >&2; exit 1; }

if [[ -z ${WIFI_SSID:-} || -z ${WIFI_PSK:-} ]]; then
  echo "!! WIFI_SSID and WIFI_PSK are both required -- preseeding wifi is all this does." >&2
  echo "   Skip this step entirely if you plan to run nmtui on the phone instead." >&2
  exit 1
fi

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

# --- Write the NetworkManager keyfile --------------------------------------
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
  echo "rm $WIFI_SSID.nmconnection"
  echo "write $WORK/wifi.nmconnection $WIFI_SSID.nmconnection"
  # NetworkManager refuses to load a keyfile that is not 0600 root:root.
  echo "sif $WIFI_SSID.nmconnection mode 0100600"
  echo "sif $WIFI_SSID.nmconnection uid 0"
  echo "sif $WIFI_SSID.nmconnection gid 0"
} >"$WORK/cmds"

"$DEBUGFS" -w -f "$WORK/cmds" "$FS" >"$WORK/log" 2>&1 || { cat "$WORK/log" >&2; exit 1; }

echo "==> fsck"
"$E2FSCK" -fy "$FS" >"$WORK/fsck" 2>&1 || true
tail -2 "$WORK/fsck" | sed 's/^/    /'

echo
echo "==> verifying"
# Read it back rather than trusting debugfs's exit status: it reports success
# for a write into a directory that does not exist.
if "$DEBUGFS" -R "cat /etc/NetworkManager/system-connections/$WIFI_SSID.nmconnection" \
     "$FS" 2>/dev/null | grep -q "ssid=$WIFI_SSID"; then
  echo "    wifi keyfile: $WIFI_SSID OK"
else
  echo "    !! the keyfile did not take" >&2
  exit 1
fi

cat <<NEXT

Patched image ready:
  $IMG

Flash it with:
  IMAGE_FILE="$IMG" ./scripts/flash-sd.sh /dev/diskN

After boot the phone joins '$WIFI_SSID'. Find it with \`arp -a\` or your router,
then:
  ssh alarm@<its address>        (password: 123456)
NEXT
