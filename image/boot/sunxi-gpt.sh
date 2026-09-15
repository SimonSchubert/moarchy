#!/bin/bash
# The PinePhone boot backend: GPT, u-boot SPL at a raw offset, one .img.xz.
#
# docs/devices.md D9. This is the carve-out, not the general case (D0) -- of
# the devices moarchy targets the PinePhone is the only one that boots from raw
# sectors rather than from a bootloader that understands partitions, and the
# only one whose deliverable is a whole-disk image you dd to removable media.
#
# Sourced by image/build.sh, which calls the three hooks below at the points
# the device-specific work actually happens. D8 records why it is three hooks
# and not one tail: the device-specific sections INTERLEAVE with the
# device-independent ones, so a two-way cut would have moved the initramfs
# generation past configure.sh and changed behaviour under cover of a refactor.
#
# --- On the indentation -----------------------------------------------------
#
# The hook bodies are NOT indented, and that is deliberate rather than sloppy.
# D8 says the split is a move and not a rewrite: these lines are byte-identical
# to the ones they were lifted from in image/build.sh, so that when the
# PinePhone image is finally re-verified, a failure means the SPLIT broke
# something rather than an editor did. Re-indenting would have made every one
# of these 99 lines differ from its original and thrown that away for a
# cosmetic gain.
#
# Whoever verifies the PinePhone (see the outstanding note at the top of
# devices.md) may reindent freely once it has booted.

# The disk layout, measured off DanctNIX's own image and kept identical so
# their u-boot finds what it expects (structure.md §1.1, I3):
#
#   byte 131072   u-boot SPL          (bs=128k seek=1, the GPT path)
#   LBA 16384     boot   FAT32 122M   Image.gz, dtbs, boot.scr, initramfs
#   LBA 266240    rootfs ext4         sized to contents + slack, grows on first boot
#
# These lived at the top of image/build.sh until the D8 split. They are read by
# backend_image below and by nothing else, which is what makes them the
# backend's rather than the build's.
BOOT_LBA=16384
BOOT_MIB=122
ROOT_LBA=266240
SECTOR=512
SPL_VARIANT=${SPL_VARIANT:-528}      # update-u-boot's own default_freq

# After pacstrap: the initramfs and u-boot's boot script.
backend_kernel() {
say "kernel, initramfs and boot script"
# The rootfs ships /etc/resolv.conf as a symlink to systemd-resolved's stub --
# `filesystem` owns it -- and in a chroot nothing is running to create
# /run/systemd/resolve. So `cp` followed the symlink, tried to write through it
# into a directory that is not there, and failed; the `2>/dev/null || true`
# that used to be on this line then hid it.
#
# What that cost: the chroot had no DNS at all, which is invisible until
# something inside it wants the network. The one thing that does is the
# database refresh in configure.sh, whose entire job is to leave a *signed*
# moarchy.db in the image -- so it failed on every build, and the image it
# produced was the one where nothing installs until somebody runs `pacman -Sy`
# by hand. That is the exact failure 4ad66d1 was written to end.
#
# Replace the symlink rather than write through it, and say so if even that
# does not work.
rm -f "$ROOTDIR/etc/resolv.conf"
cp /etc/resolv.conf "$ROOTDIR/etc/resolv.conf" ||
  say "!! no resolv.conf for the chroot -- anything in it that needs DNS fails"

# mkinitcpio prints "ERROR: failed to detect root filesystem" here, twice, and
# it is benign -- but it looks exactly like a build that just produced an
# unbootable image, so: the `fsck` hook is asking what filesystem / is, and in a
# chroot there is no answer. The consequences are that boot-time fsck of root is
# skipped, and that `autodetect` cannot narrow the module set, so it includes
# more rather than less -- our initramfs is 23.1 MB against DanctNIX's 18.0 MB.
#
# Root still mounts: ext4 is built into megi's kernel rather than shipped as a
# module (there is no ext4*.ko under /usr/lib/modules), and boot.txt passes
# root=/dev/mmcblk${linux_mmcdev}p${rootpart} with rootwait on the cmdline.
arch-chroot "$ROOTDIR" mkinitcpio -P
( cd "$ROOTDIR/boot" && ./mkscr >/dev/null ) || die "mkscr failed -- is uboot-tools in the rootfs?"
[ -f "$ROOTDIR/boot/boot.scr" ] || die "boot.scr not generated"
info "boot.scr $(stat -c%s "$ROOTDIR/boot/boot.scr") bytes, Image.gz $(stat -c%s "$ROOTDIR/boot/Image.gz") bytes"
}

# What /etc/fstab should say. Called by image/configure.sh.
#
# Moved out of configure.sh, where it was the third interleaved device-specific
# thing D8 found. It describes the disk layout, and the disk layout is exactly
# what a boot backend owns: this one has a separate vfat /boot to mount, and
# the Android backend has no boot partition at all.
backend_fstab() {
cat <<'EOF'
LABEL=rootfs  /       ext4  rw,relatime  0 1
LABEL=BOOT    /boot   vfat  rw,relatime  0 2
EOF
}

# After the rootfs is trimmed: build the filesystems, lay out the GPT, drop the
# SPL where the BROM reads it, and compress.
backend_image() {
IMG="$WORK/$NAME.img"
say "filesystem images"
# boot: everything under /boot. u-boot reads Image.gz, the dtbs and boot.scr
# from here; the SPL itself lives before the partition table, not in it.
BOOTIMG="$WORK/boot.img"
truncate -s "${BOOT_MIB}M" "$BOOTIMG"
mkfs.vfat -F 32 -n BOOT "$BOOTIMG" >/dev/null
( cd "$ROOTDIR/boot" && mcopy -i "$BOOTIMG" -s -Q ./* :: )

# rootfs: sized to contents plus slack. It grows to fill the card on first boot
# (I7), so this only has to be big enough to boot and run growpart once.
ROOT_USED_MIB=$(du -sm "$ROOTDIR" | cut -f1)
ROOT_MIB=$(( ROOT_USED_MIB + ROOT_SLACK_MIB ))
# Checked here because here is the earliest it can be checked without
# guessing: the rootfs exists, so its size is a fact rather than an estimate.
need_space "$ROOT_MIB" "the rootfs image"
ROOTIMG="$WORK/root.img"
truncate -s "${ROOT_MIB}M" "$ROOTIMG"
# -d populates from a directory with no mount and no loop device.
mkfs.ext4 -q -L rootfs -d "$ROOTDIR" -O ^has_journal,^metadata_csum_seed "$ROOTIMG"
tune2fs -O has_journal "$ROOTIMG" >/dev/null
info "boot ${BOOT_MIB}M, rootfs ${ROOT_MIB}M (used ${ROOT_USED_MIB}M + ${ROOT_SLACK_MIB}M slack)"

# ---------------------------------------------------------------------------
say "assemble the disk image"
TOTAL_MIB=$(( ROOT_LBA * SECTOR / 1024 / 1024 + ROOT_MIB + 1 ))
truncate -s "${TOTAL_MIB}M" "$IMG"

# All fields named. Mixing positional (start,size,type) with name= is what
# sfdisk rejects as "line 1: unsupported command", and it says so without
# naming the field, so the shape of the line is the thing to check.
sfdisk --quiet "$IMG" <<EOF
label: gpt
unit: sectors
start=${BOOT_LBA}, size=$(( BOOT_MIB * 1024 * 1024 / SECTOR )), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="boot"
start=${ROOT_LBA}, size=$(( ROOT_MIB * 1024 * 1024 / SECTOR )), type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="rootfs"
EOF

dd if="$BOOTIMG" of="$IMG" bs=$SECTOR seek=$BOOT_LBA conv=notrunc status=none
dd if="$ROOTIMG" of="$IMG" bs=$SECTOR seek=$ROOT_LBA conv=notrunc status=none

# The SPL, before the partition table. bs=128k seek=1 is what update-u-boot
# uses for a GPT label -- the 8k offset in its other branch is the DOS path.
SPL="$ROOTDIR/boot/u-boot-sunxi-with-spl-pinephone-$SPL_VARIANT.bin"
[ -f "$SPL" ] || die "missing $SPL"
dd if="$SPL" of="$IMG" bs=128k seek=1 conv=notrunc status=none
info "SPL: $(basename "$SPL") at byte 131072"

# Prove it landed where the BROM will look, rather than trusting dd's status.
magic=$(dd if="$IMG" bs=1 skip=131076 count=8 status=none)
[ "$magic" = "eGON.BT0" ] || die "no eGON.BT0 at byte 131076 -- the SPL is not where the BROM reads"
info "verified eGON.BT0 at byte 131076"

# ---------------------------------------------------------------------------
say "compress"
# -9 for a release, but it is the slowest step in the build by a wide margin on
# a 6 GB image. XZ_LEVEL=1 turns a ~30 minute wait into a couple of minutes
# while iterating on everything upstream of it.
xz -T0 "-${XZ_LEVEL:-9}" --force --keep "$IMG"
mv "$IMG.xz" "$OUT/$NAME.img.xz"
( cd "$OUT" && sha256sum "$NAME.img.xz" > "$NAME.img.xz.sha256" )

# What is actually in it (I2, V4).
arch-chroot "$ROOTDIR" pacman -Q > "$OUT/$NAME.packages" 2>/dev/null ||
  cp "$ROOTDIR/var/lib/pacman/local"/*/desc /dev/null 2>/dev/null || true

say "done"
ls -lh "$OUT/$NAME.img.xz" | awk '{print "    " $9 "  " $5}'
info "$(wc -l < "$OUT/$NAME.packages" 2>/dev/null || echo '?') packages recorded in $NAME.packages"
}
