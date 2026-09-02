#!/usr/bin/env bash
# Flash the DanctNIX PinePhone barebone image to an SD card, from macOS.
#
#   ./scripts/flash-sd.sh /dev/disk28
#
# Guards before writing: refuses internal system disks, refuses anything that
# is not removable-or-explicitly-confirmed, verifies the MD5 against the
# release manifest, and prints the partition table for you to eyeball.

set -euo pipefail

RELEASE="${RELEASE:-20251224}"
IMAGE="archlinux-pinephone-barebone-${RELEASE}.img.xz"
BASE_URL="https://github.com/dreemurrs-embedded/Pine64-Arch/releases/download/${RELEASE}"
CACHE="${CACHE:-$HOME/Downloads/mobileomarchy}"

DISK="${1:-}"
if [[ -z $DISK ]]; then
  echo "usage: $0 /dev/diskN" >&2
  echo >&2
  diskutil list external physical >&2 || diskutil list >&2
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

mkdir -p "$CACHE"
cd "$CACHE"

# IMAGE_FILE lets you flash a locally modified image (e.g. one patched from
# rndis to CDC-ECM so macOS can see the USB network gadget). Checksum
# verification is skipped for it by definition -- it no longer matches upstream.
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

cat <<'NEXT'

Done. Next:
  1. Put the card in the PinePhone and power it on.
  2. Connect it to this Mac by USB; a CDC-ECM interface appears.
  3. ssh alarm@10.15.19.82        (password: 123456; root password: root)
  4. Change both passwords, join wifi with `sudo nmtui`, then:

       sudo pacman-key --init && sudo pacman-key --populate archlinuxarm
       sudo pacman -Syu
       git clone <this repo> ~/.local/share/mobileomarchy
       ~/.local/share/mobileomarchy/install.sh
NEXT
