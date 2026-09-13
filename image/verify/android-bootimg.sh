#!/bin/bash
# Verifying an Android image: the boot header, the appended DTB, AVB.
#
# docs/devices.md D12. The counterpart to image/verify/sunxi-gpt.sh, asserting
# the things only this artifact shape can be asked about. Everything the two
# have in common is about the rootfs and stays in image/verify.sh.
#
# The artifact is a DIRECTORY, not a file (D10): boot.img, vbmeta.img,
# rootfs.img and flash.sh. So "decompress" has no counterpart here -- there is
# nothing to decompress, and rootfs.img is already an ext4 filesystem image
# that image/verify.sh can mount directly.

# Assert the boot artifacts, then hand image/verify.sh a $WORK/root.img.
verify_artifact() {
sec "artifact"
# A directory, and saying so plainly beats "cannot open file" three checks later.
[ -d "$IMG_XZ" ] || { no "$IMG_XZ is not a directory -- an Android artifact is a directory of images (D10)"; return 1; }
for f in boot.img vbmeta.img rootfs.img flash.sh; do
  [ -e "$IMG_XZ/$f" ] && ok "$f present" || no "$f missing from the artifact"
done
[ -x "$IMG_XZ/flash.sh" ] && ok "flash.sh is executable" || no "flash.sh is not executable"

sec "boot image"
# The v0 header, at the offsets image/boot/android-image.py writes and that
# were measured off an image which demonstrably boots this device.
hdr=$(dd if="$IMG_XZ/boot.img" bs=8 count=1 status=none 2>/dev/null)
[ "$hdr" = "ANDROID!" ] && ok "ANDROID! magic" || no "boot.img does not start with ANDROID! (got '$hdr')"

# page_size is at byte 36, header_version at 40, both little-endian u32.
psize=$(od -An -tu4 -j36 -N4 "$IMG_XZ/boot.img" 2>/dev/null | tr -d ' ')
hver=$(od -An -tu4 -j40 -N4 "$IMG_XZ/boot.img" 2>/dev/null | tr -d ' ')
[ "$psize" = 4096 ] && ok "page size 4096" || no "page size is $psize, not 4096"
[ "$hver" = 0 ] && ok "header version 0" || no "header version is $hver, not 0"

# The kernel payload must carry an appended DTB: sargo's deviceinfo sets
# append_dtb=true, and a boot image without one is a black screen with nothing
# to read. FDT magic is d00dfeed, big-endian, and it should appear AFTER the
# gzip magic that starts the kernel.
ksize=$(od -An -tu4 -j8 -N4 "$IMG_XZ/boot.img" 2>/dev/null | tr -d ' ')
dd if="$IMG_XZ/boot.img" of="$WORK/kernel.bin" bs=1 skip=4096 count="${ksize:-0}" status=none 2>/dev/null
kmagic=$(dd if="$WORK/kernel.bin" bs=2 count=1 status=none 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$kmagic" = "1f8b" ] && ok "kernel payload is gzip (Image.gz)" || no "kernel payload is not gzip (magic $kmagic)"
if od -An -tx1 -v "$WORK/kernel.bin" 2>/dev/null | tr -d ' \n' | grep -q 'd00dfeed'; then
  ok "a device tree is appended to the kernel"
else
  no "no FDT magic in the kernel payload -- the DTB was not appended"
fi

sec "verified boot"
# Flag 2 is AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED. Without it an
# Android 12 bootloader refuses an unsigned kernel, and the error it gives does
# not mention verification -- which is why this is asserted rather than assumed.
vmagic=$(dd if="$IMG_XZ/vbmeta.img" bs=4 count=1 status=none 2>/dev/null)
[ "$vmagic" = "AVB0" ] && ok "vbmeta magic AVB0" || no "vbmeta.img is not an AVB image (got '$vmagic')"
# Flags are a big-endian u32 at byte 120 of the header.
vflags=$(od -An -tu4 --endian=big -j120 -N4 "$IMG_XZ/vbmeta.img" 2>/dev/null | tr -d ' ')
[ "$vflags" = 2 ] && ok "vbmeta flags = 2 (verification disabled)" \
                  || no "vbmeta flags = ${vflags:-?}, not 2 -- the bootloader will refuse this kernel"

sec "rootfs"
# Already a filesystem image; no partition table to carve it out of. Copied
# rather than used in place because image/verify.sh mounts it read-write and
# runs the first-boot scripts inside it.
cp "$IMG_XZ/rootfs.img" "$WORK/root.img" || { no "could not copy rootfs.img"; return 1; }
printf '  rootfs %s\n' "$(du -h "$WORK/root.img" | cut -f1)"
}

# The rootfs growing to fill its partition.
verify_grow() {
sec "behaviour: the rootfs grows to fill userdata"

# Half of I7 on this device, and the other half must NOT happen. The PinePhone
# grows in two steps -- sfdisk extends the last partition, resize2fs follows.
# Here the partition is `userdata`, sized by the vendor and sitting in a GPT
# beside xbl, abl, tz and the A/B slots, so only the filesystem grows.
# docs/devices.md D22.
#
# The first check is the one that matters: sfdisk running on this device would
# rewrite a vendor partition table on a phone with no removable storage and no
# recovery image.
grow=$(grep -h '^DEVICE_GROW=' "$R/usr/share/moarchy/device/device.conf" 2>/dev/null | cut -d= -f2)
[ "$grow" = filesystem ] \
  && ok "device.conf says DEVICE_GROW=filesystem (the vendor GPT is never rewritten)" \
  || no "DEVICE_GROW is '${grow:-unset}', not filesystem -- this device would run sfdisk on a vendor partition table"

# And the half that does happen, exercised directly on the real image with the
# real command -- the same way the PinePhone backend does it, and for the same
# reason: Docker Desktop's kernel has loop.max_part=0, so the script's own
# device discovery cannot be driven here.
before=$(dumpe2fs -h "$WORK/root.img" 2>/dev/null | awk -F: '/Block count/{gsub(/ /,"",$2); print $2}')
truncate -s +64M "$WORK/root.img"
if resize2fs "$WORK/root.img" >/dev/null 2>&1; then
  after=$(dumpe2fs -h "$WORK/root.img" 2>/dev/null | awk -F: '/Block count/{gsub(/ /,"",$2); print $2}')
  if [ -n "${before:-}" ] && [ -n "${after:-}" ] && [ "$after" -gt "$before" ]; then
    ok "resize2fs grew the filesystem $(( before * 4096 / 1048576 ))M -> $(( after * 4096 / 1048576 ))M"
  else
    no "resize2fs did not grow the filesystem (${before:-?} -> ${after:-?} blocks)"
  fi
else
  no "resize2fs failed on the rootfs image -- the growth half of I7 is NOT tested"
fi
}
