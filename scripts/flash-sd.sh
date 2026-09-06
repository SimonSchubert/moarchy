#!/usr/bin/env bash
# Flash the DanctNIX PinePhone barebone image to an SD card, from macOS.
#
#   ./scripts/flash-sd.sh /dev/disk28
#
# Guards before writing: refuses internal system disks, refuses anything that
# is not removable-or-explicitly-confirmed, verifies the MD5 against the
# release manifest, and prints the partition table for you to eyeball.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$REPO_ROOT/scripts/manifest.sh"

# The release is a pin, not a constant in this script: it is one of the inputs
# this project does not version itself, so it lives in manifest.toml with the
# rest (docs/structure.md V1). RELEASE= still overrides it, for flashing an
# older card without editing the manifest.
RELEASE="${RELEASE:-$(manifest_get danctnix release)}"
[[ -n $RELEASE ]] || exit 1
BASE_URL="$(manifest_get danctnix url)/${RELEASE}" || exit 1
IMAGE="archlinux-pinephone-barebone-${RELEASE}.img.xz"
CACHE="${CACHE:-$HOME/Downloads/moarchy}"

DISK="${1:-}"
if [[ -z $DISK ]]; then
  echo "usage: $0 /dev/diskN" >&2
  echo >&2
  # A Mac's BUILT-IN SD reader reports as `internal`, so `diskutil list
  # external physical` prints nothing at all for the most common way of
  # flashing a card -- which reads as "no card inserted" when the card is in.
  # Ask the card reader directly first; it names the BSD device.
  card=$(system_profiler SPCardReaderDataType 2>/dev/null |
           sed -n 's/^ *BSD Name: *\(disk[0-9]*\)$/\1/p' | head -1)
  if [[ -n $card ]]; then
    echo "Card reader holds /dev/$card:" >&2
    diskutil list "/dev/$card" >&2
    echo >&2
    echo "  $0 /dev/$card" >&2
    echo >&2
  fi
  echo "Other removable disks:" >&2
  diskutil list external physical >&2 2>/dev/null || true
  exit 1
fi

[[ $DISK =~ ^/dev/disk[0-9]+$ ]] || { echo "Expected /dev/diskN, got '$DISK'" >&2; exit 1; }
[[ $DISK == "/dev/disk0" ]] && { echo "Refusing to write to /dev/disk0." >&2; exit 1; }

diskutil info "$DISK" >/dev/null 2>&1 || { echo "No such disk: $DISK" >&2; exit 1; }

# A locked SD adapter makes the device node read-only (mode r--r-----) and even
# root gets EACCES. Catch it here rather than after the sudo password prompt and
# a long wait, where it surfaces as a bare "dd: Permission denied".
if diskutil info "$DISK" 2>/dev/null | grep -q "Media Read-Only: *Yes"; then
  cat >&2 <<'LOCKED'
This card is write-protected (diskutil reports "Media Read-Only: Yes").

That is the physical lock switch on the SD adapter, not a permissions problem --
no amount of sudo will get past it.

  1. Eject the card
  2. Slide the LOCK tab on the adapter's left edge AWAY from "LOCK"
  3. Reinsert and re-run this script

LOCKED
  exit 1
fi

# Resolve IMAGE_FILE BEFORE the cd below. Everything downloaded lives in
# $CACHE, so this script works from there -- which silently breaks a relative
# IMAGE_FILE, the natural way to name an image this repo just built:
#   IMAGE_FILE=images/moarchy-pinephone-<date>.img.xz ./scripts/flash-sd.sh ...
#   No such image: images/moarchy-pinephone-<date>.img.xz
# It is there; the script had simply moved.
if [[ -n ${IMAGE_FILE:-} && $IMAGE_FILE != /* ]]; then
  IMAGE_FILE="$PWD/$IMAGE_FILE"
fi

mkdir -p "$CACHE"
cd "$CACHE"

# IMAGE_FILE flashes a local image rather than downloading DanctNIX's -- which
# is how you flash the one ./scripts/build-image.sh produces. Checksum
# verification is skipped for it by definition: it is not upstream's image and
# has no entry in upstream's manifest. build-image.sh writes its own .sha256
# next to the file.
if [[ -n ${IMAGE_FILE:-} ]]; then
  [[ -f $IMAGE_FILE ]] || { echo "No such image: $IMAGE_FILE" >&2; exit 1; }
  IMAGE="$IMAGE_FILE"
  echo "==> using local image: $IMAGE"
  echo "    $(ls -lh "$IMAGE" | awk '{print $5}'), checksum check skipped (locally modified)"
else
  echo "==> fetching image (cached in $CACHE)"
  [[ -f $IMAGE ]]                  || curl -fL# -O "$BASE_URL/$IMAGE"
  [[ -f release-${RELEASE}.md5 ]]  || curl -fsSL -O "$BASE_URL/release-${RELEASE}.md5"

  echo "==> verifying checksum"
  EXPECTED=$(awk -v f="$IMAGE" '$2 == f { print $1 }' "release-${RELEASE}.md5")
  ACTUAL=$(md5 -q "$IMAGE")
  if [[ -z $EXPECTED || $EXPECTED != "$ACTUAL" ]]; then
    echo "Checksum mismatch. expected='$EXPECTED' actual='$ACTUAL'" >&2
    exit 1
  fi
  echo "    ok ($ACTUAL)"
fi

echo
echo "==> TARGET: $DISK -- everything on it will be destroyed"
diskutil list "$DISK"
echo
DISK_ID="$(basename "$DISK")"

# Confirmation has to work from an interactive terminal AND from a
# non-interactive stdin (Claude Code's `!` mode, CI, `sh -c`). Without the
# /dev/tty fallback, `read` hits EOF, returns non-zero, and `set -e` kills the
# script silently -- looking exactly like a flash that did nothing.
CONFIRM=""
if [[ -n ${FLASH_CONFIRM:-} ]]; then
  CONFIRM="$FLASH_CONFIRM"
  echo "Confirmed via FLASH_CONFIRM=$CONFIRM"
elif [[ -t 0 ]]; then
  echo "This is NOT your password prompt -- sudo will ask for that separately, after this."
  read -r -p "Type '$DISK_ID' to erase and flash that disk: " CONFIRM || true
elif { : </dev/tty; } 2>/dev/null; then   # -r /dev/tty is not enough: the file
                                          # exists even with no controlling tty
  echo "This is NOT your password prompt -- sudo asks for that separately." >/dev/tty
  printf "Type '%s' to erase and flash that disk: " "$DISK_ID" >/dev/tty
  read -r CONFIRM </dev/tty || true
else
  cat >&2 <<UNATTENDED
No terminal available to confirm on, and FLASH_CONFIRM is unset.

Re-run with the disk identifier passed explicitly:

    FLASH_CONFIRM=$DISK_ID $0 $DISK

UNATTENDED
  exit 1
fi

if [[ $CONFIRM != "$DISK_ID" ]]; then
  echo "Aborted (got '$CONFIRM', expected '$DISK_ID'). Nothing was written."
  exit 1
fi

RDISK="/dev/r$(basename "$DISK")"   # raw device: dramatically faster

echo "==> unmounting"
diskutil unmountDisk "$DISK"

echo "==> writing (press Ctrl-T for progress; macOS dd has no status=progress)"
# Raw .img streams straight through; .xz is decompressed on the fly.
if [[ $IMAGE == *.xz ]]; then
  xz -dc "$IMAGE" | sudo dd of="$RDISK" bs=4m
else
  sudo dd if="$IMAGE" of="$RDISK" bs=4m
fi

sync
echo "==> ejecting"
diskutil eject "$DISK" || true

# The closing instructions depend on which image was written. A moarchy image
# creates its own user with a locked password and comes up in the session on
# its own; DanctNIX's barebone image needs the whole provisioning path.
if [[ $IMAGE == *moarchy-pinephone-* ]]; then
  cat <<'NEXT'

Done. Put the card in the PinePhone and power it on.

That is the whole procedure. The image has no default password to change --
the account's password is locked and tty1 autologin brings the session up
without one. The rootfs grows to fill the card on first boot.

To get a shell, open the terminal on the phone. To set a password so you can
log in over SSH, run `passwd` there.
NEXT
else
  cat <<'NEXT'

Done. Next:
  1. Put the card in the PinePhone and power it on.
  2. Get it on wifi -- attach a USB keyboard once and run `sudo nmtui`.
  3. ssh alarm@<its address>      (password: 123456; root password: root)
     Find the address from your router, or with `arp -a`.
  4. Change both passwords, then, from the Mac:

       ./scripts/provision.sh build
       ./scripts/provision.sh deploy
       ./scripts/provision.sh install
NEXT
fi
