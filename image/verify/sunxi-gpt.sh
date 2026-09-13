#!/bin/bash
# Verifying a PinePhone image: the GPT, the SPL, the FAT boot partition.
#
# docs/devices.md D12. image/verify.sh sources one of these and calls the two
# hooks; everything else it checks -- what pacman placed, what must NOT be in
# the image, and the first-boot scripts actually run in a chroot -- is about
# the rootfs and is the same on every device.
#
# Bodies are byte-identical to the ones lifted out of image/verify.sh, for the
# reason image/boot/sunxi-gpt.sh gives at length: the PinePhone image has not
# been re-verified since the device-package work, so a failure has to mean the
# SPLIT broke something rather than an editor did. Hence no reindentation.

# Turn the artifact into $WORK/root.img, and assert everything about the disk
# that only a PinePhone image can be asked about.
verify_artifact() {
# The whole-disk image this backend carves everything out of.
IMG="$WORK/image.img"
sec "decompress"
# A raw .img is accepted too, so the negative control (image/negative-test.sh)
# can tamper with a copy without paying for a compress/decompress round trip.
case "$IMG_XZ" in
  *.xz) xz -dc "$IMG_XZ" > "$IMG"
        printf '  raw %s, compressed %s\n' \
          "$(du -h "$IMG" | cut -f1)" "$(du -h "$IMG_XZ" | cut -f1)" ;;
  *)    cp "$IMG_XZ" "$IMG"
        printf '  raw %s (uncompressed input)\n' "$(du -h "$IMG" | cut -f1)" ;;
esac

# ---------------------------------------------------------------------------
sec "structure"

# The SPL, where the Allwinner BROM looks for it. eGON.BT0 sits at offset 4 of
# the SPL header, so the magic is at 131072 + 4.
magic=$(dd if="$IMG" bs=1 skip=131076 count=8 status=none)
[ "$magic" = "eGON.BT0" ] && ok "eGON.BT0 at byte 131076 (SPL at 128 KiB)" \
                          || no "no eGON.BT0 at byte 131076 -- got '$magic'"

# Partition table. The layout has to match DanctNIX's, because their u-boot is
# what reads it.
sfdisk -d "$IMG" > "$WORK/table.txt" 2>/dev/null
grep -q 'label: gpt' "$WORK/table.txt" && ok "GPT label" || no "not a GPT label"
grep -qE 'start= *16384,.*name="boot"'   "$WORK/table.txt" && ok "boot at LBA 16384"   || no "boot not at LBA 16384"
grep -qE 'start= *266240,.*name="rootfs"' "$WORK/table.txt" && ok "rootfs at LBA 266240" || no "rootfs not at LBA 266240"

BOOT_OFF=$((16384*512)); ROOT_OFF=$((266240*512))
BOOT_SZ=$(( $(grep -oE 'start= *16384, size= *[0-9]+' "$WORK/table.txt" | grep -oE '[0-9]+$') * 512 ))

dd if="$IMG" of="$WORK/boot.img" bs=1M skip=$((BOOT_OFF/1048576)) count=$((BOOT_SZ/1048576)) status=none
dd if="$IMG" of="$WORK/root.img" bs=1M skip=$((ROOT_OFF/1048576)) status=none

# ---------------------------------------------------------------------------
sec "boot partition"
mdir -i "$WORK/boot.img" -b :: > "$WORK/bootls.txt" 2>/dev/null
for f in Image.gz boot.scr initramfs-linux.img dtbs; do
  grep -qi "/$f" "$WORK/bootls.txt" && ok "$f" || no "$f missing from the boot partition"
done
# u-boot loads the DTB by name from boot.txt; the wrong name is a black screen.
mdir -i "$WORK/boot.img" -b ::/dtbs/allwinner 2>/dev/null | grep -q 'sun50i-a64-pinephone-1.2.dtb' \
  && ok "sun50i-a64-pinephone-1.2.dtb present" || no "PinePhone 1.2 DTB missing"
# boot.scr is a u-boot legacy image; the magic is what mkimage stamps.
mcopy -i "$WORK/boot.img" ::/boot.scr "$WORK/boot.scr" 2>/dev/null
if [ -f "$WORK/boot.scr" ]; then
  hdr=$(dd if="$WORK/boot.scr" bs=1 count=4 status=none | od -An -tx1 | tr -d ' \n')
  [ "$hdr" = "27051956" ] && ok "boot.scr carries the u-boot image magic" \
                          || no "boot.scr is not a u-boot image (magic $hdr)"
fi
}

# I7: the rootfs grows to fill the card on first boot. A card is a PinePhone
# concept -- sargo has a fixed-size userdata partition -- so the test is here.
verify_grow() {
sec "behaviour: the rootfs grows onto a bigger card"

# I7 runs exactly once, on a card, on first boot -- so without a test here the
# first execution is on someone's phone.
#
# It cannot be tested the obvious way. moarchy-grow-rootfs takes a partition
# device, and Docker Desktop's kernel has loop.max_part=0, so `losetup -P`
# attaches the disk but /dev/loopNp2 is never created -- no partition nodes
# exist to hand it, whatever the image contains. Reporting that as a failed
# growth test would blame the image for the harness.
#
# So the two operations the script performs are exercised directly, on the real
# image, with the same commands: sfdisk grows the last partition, resize2fs
# follows it. What is left untested is only the script's device discovery
# (findmnt / lsblk), which needs a booted system.
GROW="$WORK/grow.img"
cp --sparse=always "$IMG" "$GROW"
truncate -s "+2G" "$GROW"          # what a bigger card looks like

before_end=$(sfdisk -d "$GROW" | sed -n 's/.*start= *266240, size= *\([0-9]*\).*/\1/p')

# The backup GPT header is stranded mid-disk after the file grows; sfdisk will
# not extend a partition past it until it is moved to the new end.
sgdisk -e "$GROW" >/dev/null 2>&1 || true
# The same command moarchy-grow-rootfs runs, against partition 2.
echo ", +" | sfdisk --no-reread --force -N 2 "$GROW" >/dev/null 2>&1 || true

after_end=$(sfdisk -d "$GROW" | sed -n 's/.*start= *266240, size= *\([0-9]*\).*/\1/p')
if [ "${after_end:-0}" -gt "${before_end:-0}" ]; then
  ok "sfdisk grew the rootfs partition $(( before_end / 2048 ))M -> $(( after_end / 2048 ))M"
else
  no "sfdisk did not grow the partition (${before_end:-?} -> ${after_end:-?} sectors)"
fi

# And resize2fs follows it -- the half that actually gives you the space. The
# rootfs is attached at its offset, with no sizelimit, so the filesystem sees
# the grown partition.
if LOOP=$(losetup -o $((266240*512)) --show -f "$GROW" 2>/dev/null); then
  fs_before=$(dumpe2fs -h "$LOOP" 2>/dev/null | sed -n 's/^Block count: *//p')
  e2fsck -fp "$LOOP" >/dev/null 2>&1 || true
  resize2fs "$LOOP" >/dev/null 2>&1 || true
  fs_after=$(dumpe2fs -h "$LOOP" 2>/dev/null | sed -n 's/^Block count: *//p')
  losetup -d "$LOOP" 2>/dev/null
  if [ "${fs_after:-0}" -gt "${fs_before:-0}" ]; then
    ok "resize2fs grew the filesystem $(( fs_before * 4096 / 1048576 ))M -> $(( fs_after * 4096 / 1048576 ))M"
  else
    no "resize2fs did not grow the filesystem (${fs_before:-?} -> ${fs_after:-?} blocks)"
  fi
else
  no "could not attach the rootfs to a loop device -- I7 filesystem half NOT tested"
fi
}
