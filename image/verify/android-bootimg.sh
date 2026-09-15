#!/bin/bash
# Verifying an Android image: the boot header, the appended DTB, AVB.
#
# docs/devices.md D12. The counterpart to image/verify/sunxi-gpt.sh, asserting
# the things only this artifact shape can be asked about. Everything the two
# have in common is about the rootfs and stays in image/verify.sh.
#
# The artifact is a DIRECTORY, not a file (D10): boot.img, vbmeta.img,
# rootfs.simg and flash.sh. So "decompress" has no counterpart here -- but the
# rootfs is an Android SPARSE image and has to be expanded with simg2img before
# image/verify.sh can mount it, because fastboot cannot flash a raw image over
# 4 GiB and ours is 6.06.

# Assert the boot artifacts, then hand image/verify.sh a $WORK/root.img.
verify_artifact() {
sec "artifact"
# A directory, and saying so plainly beats "cannot open file" three checks later.
[ -d "$IMG_XZ" ] || { no "$IMG_XZ is not a directory -- an Android artifact is a directory of images (D10)"; return 1; }
for f in boot.img vbmeta.img rootfs.simg flash.sh; do
  [ -e "$IMG_XZ/$f" ] && ok "$f present" || no "$f missing from the artifact"
done
[ -x "$IMG_XZ/flash.sh" ] && ok "flash.sh is executable" || no "flash.sh is not executable"

# The retry counter (D26). Without a --set-active the bootloader may refuse the
# image that was just flashed, with nothing on screen to say why -- so the one
# line that clears it is asserted rather than assumed to have survived an edit.
grep -q -- '--set-active' "$IMG_XZ/flash.sh" \
  && ok "flash.sh resets the slot retry counter" \
  || no "flash.sh never runs --set-active; a spent retry counter refuses the new image (D26)"

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

# ramdisk_size, a little-endian u32 at byte 16. This backend ships no initramfs
# (D24) -- the kernel mounts root itself -- and a non-zero value here means one
# crept back in, which on this device is 18 MB of code that cannot print.
rdsz=$(od -An -tu4 -j16 -N4 "$IMG_XZ/boot.img" 2>/dev/null | tr -d ' ')
[ "$rdsz" = 0 ] && ok "no ramdisk (the kernel mounts root itself)" \
                || no "boot.img carries a ${rdsz:-?}-byte ramdisk; this backend ships none (D24)"

# kernel_size, a little-endian u32 at byte 8. Read here because the size check
# below needs it and so does the DTB extraction further down.
ksize=$(od -An -tu4 -j8 -N4 "$IMG_XZ/boot.img" 2>/dev/null | tr -d ' ')

# The whole file should then be the header page plus the padded kernel, with
# nothing after it. Catches a stray page or a truncated kernel, both of which
# boot into silence.
want=$(( 4096 + (ksize + 4095) / 4096 * 4096 ))
have=$(stat -c%s "$IMG_XZ/boot.img")
[ "$have" = "$want" ] && ok "boot.img is header + kernel, $have bytes" \
                      || no "boot.img is $have bytes, not the $want a header plus a padded kernel makes"

sec "boot cmdline"
# Read back out of the artifact rather than trusted from the script that wrote
# it. Every line of this is a thing that, if wrong, gives two penguins and
# silence -- there is no console on this device to say which (D23).
#
# The v0 header splits the cmdline: 512 bytes at offset 64, the rest at 608.
cmdline=$(dd if="$IMG_XZ/boot.img" bs=1 skip=64 count=512 status=none 2>/dev/null | tr -d '\0')
cmdline="$cmdline$(dd if="$IMG_XZ/boot.img" bs=1 skip=608 count=1024 status=none 2>/dev/null | tr -d '\0')"
printf '  cmdline: %s\n' "$cmdline"

case "$cmdline" in
  *root=PARTLABEL=*) ok "root=PARTLABEL= (the kernel resolves this without udev)" ;;
  *root=LABEL=*) no "root=LABEL= needs an initramfs to resolve a filesystem label; this image has none" ;;
  *) no "no root= in the cmdline -- the kernel would use whatever the bootloader passes" ;;
esac

# The one that cost a night. ABL appends init=/init, which is right for an
# Android ramdisk and wrong for an Arch rootfs, and a failed init= is a panic
# with no fallback. Ours must come after it, so it must be here.
case " $cmdline " in
  *" init=/sbin/init "*) ok "init=/sbin/init overrides the bootloader's init=/init (D25)" ;;
  *" init="*) no "init= is set to something other than /sbin/init -- check it exists in the rootfs" ;;
  *) no "no init= -- ABL appends init=/init, an Arch root has no /init, and the kernel panics (D25)" ;;
esac

case " $cmdline " in
  *" ro "*) ok "root starts read-only, so systemd-fsck-root can check it" ;;
  *) no "root is not mounted ro; systemd-fsck-root has ConditionPathIsReadWrite=!/ and will never run" ;;
esac
case " $cmdline " in
  *" rootwait "*) ok "rootwait (the eMMC is not probed when init runs)" ;;
  *) no "no rootwait -- the root device is not necessarily there yet" ;;
esac

# One fact, one spelling: the partition the kernel is told to boot from is the
# partition flash.sh writes the rootfs to.
cmdpart=${cmdline##*root=PARTLABEL=}; cmdpart=${cmdpart%% *}
flashpart=$(sed -n 's/^ROOTPART=//p' "$IMG_XZ/flash.sh" | head -1)
[ -n "$cmdpart" ] && [ "$cmdpart" = "$flashpart" ] \
  && ok "boot cmdline and flash.sh agree on '$cmdpart'" \
  || no "cmdline boots from '${cmdpart:-?}' but flash.sh writes the rootfs to '${flashpart:-?}'"

# The kernel payload must carry an appended DTB: sargo's deviceinfo sets
# append_dtb=true, and a boot image without one is a black screen with nothing
# to read. FDT magic is d00dfeed, big-endian, and it should appear AFTER the
# gzip magic that starts the kernel.
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
# Sparse, and checked for it. A raw image here would flash fine while it is
# small and fail the day the rootfs crosses 4 GiB, with fastboot reporting
# "Failed reading from userdata" -- a message about a partition that is really
# about a size. Catching it here costs one dd.
smagic=$(dd if="$IMG_XZ/rootfs.simg" bs=4 count=1 status=none 2>/dev/null | od -An -tx1 | tr -d " \n")
[ "$smagic" = "3aff26ed" ] && ok "rootfs.simg is an Android sparse image" \
  || no "rootfs.simg has magic $smagic, not 3aff26ed -- fastboot cannot flash a raw image over 4 GiB"

# Expanded rather than mounted in place: the shared checks below mount it
# read-write and run the first-boot scripts inside it.
simg2img "$IMG_XZ/rootfs.simg" "$WORK/root.img" 2>/dev/null || {
  no "simg2img could not expand rootfs.simg"; return 1; }
printf '  rootfs %s sparse -> %s raw\n' \
  "$(du -h "$IMG_XZ/rootfs.simg" | cut -f1)" "$(du -h "$WORK/root.img" | cut -f1)"
}

# What has to be true of THIS device's rootfs (the optional hook in verify.sh).
verify_rootfs() {
sec "the boot slot is marked successful (D26)"
# The check that is invisible in every other section, because an image missing
# this is otherwise perfect. An A/B bootloader counts a slot down on every
# handoff and marks it unbootable at zero unless the OS calls back; a phone
# without qbootctl gets about three reboots and then needs a host with fastboot.
[ -x "$R/usr/bin/qbootctl" ] \
  && ok "qbootctl is installed" \
  || no "no /usr/bin/qbootctl -- nothing will mark the boot slot, and the phone stops booting after a few reboots (D26)"

# Enabled by the PACKAGE's own symlink, not by moarchy-firstboot: a first-boot
# script can fail, and this has to be true from the moment the image exists.
# Same two-tree rule as verify.sh's unit(): /usr/lib is how a package enables
# a unit, /etc is what `systemctl enable` writes.
_u=qbootctl-mark-successful.service
if [ -L "$R/usr/lib/systemd/system/multi-user.target.wants/$_u" ] ||
   [ -L "$R/etc/systemd/system/multi-user.target.wants/$_u" ]; then
  ok "$_u is enabled"
else
  no "$_u is not enabled in either tree -- qbootctl is installed but nothing runs it"
fi

# And that it actually runs qbootctl, rather than being a unit that was renamed
# out from under its ExecStart.
if grep -q '^ExecStart=/usr/bin/qbootctl -m' "$R/usr/lib/systemd/system/$_u" 2>/dev/null; then
  ok "the unit execs qbootctl -m"
else
  no "the unit's ExecStart is not /usr/bin/qbootctl -m"
fi

sec "the Wi-Fi chain (D27)"
# Every link, because on this SoC Wi-Fi is not one component failing loudly but
# a chain going quiet: ath10k_snoc binds, the interface never appears, and
# nothing in dmesg says the word modem. Each of these is separately capable of
# producing that exact picture, so each is asserted separately.
#
# 1. The firmware the modem DSP boots from, and the WLAN image that runs on it.
_fwd=$R/usr/lib/firmware/qcom/sdm670/sargo
for _f in mba.mbn modem.mbn wlanmdsp.mbn; do
  if [ -s "$_fwd/$_f" ]; then ok "firmware $_f present"
  else no "no $_fwd/$_f -- the modem DSP never boots, so the WLAN firmware never runs"; fi
done

# 2. The protection-domain maps, which have to be in THIS directory: pd-mapper
# finds them by dirname()-ing /sys/class/remoteproc/*/firmware, not by search.
_jsn=$(ls "$_fwd"/*.jsn 2>/dev/null | wc -l)
[ "$_jsn" -ge 5 ] \
  && ok "$_jsn protection-domain maps beside the firmware" \
  || no "only $_jsn .jsn files in $_fwd -- pd-mapper has nothing to serve"

# 3. The board file, from linux-firmware-atheros. Named here because it comes
# from a package nothing names explicitly (`linux-firmware` pulls it in), which
# is exactly how the Adreno lost its microcode twice.
[ -s "$R/usr/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin" ] \
  && ok "ath10k WCN3990 board file present" \
  || no "no ath10k/WCN3990/hw1.0/board-2.bin -- install linux-firmware-atheros"

# 4. The daemons. rmtfs is the one that is not optional and does not look
# load-bearing: its -s flag is what writes "start" to the modem remoteproc,
# because the kernel sets rproc->auto_boot = false and starts nothing itself.
for _b in rmtfs pd-mapper tqftpserv; do
  [ -x "$R/usr/bin/$_b" ] && ok "$_b is installed" \
    || no "no /usr/bin/$_b -- moarchy-qcom-modem is missing from the image"
done

# 5. And that something runs them. Same two-tree rule as qbootctl above.
for _u in rmtfs.service pd-mapper.service tqftpserv.service; do
  if [ -L "$R/usr/lib/systemd/system/multi-user.target.wants/$_u" ] ||
     [ -L "$R/etc/systemd/system/multi-user.target.wants/$_u" ]; then
    ok "$_u is enabled"
  else
    no "$_u is not enabled in either tree -- installed and never started"
  fi
done

# 6. The condition rmtfs.service will be judged by at boot. The kernel names
# the node after the device tree's qcom,client-id, and sdm670-google-common.dtsi
# says 1 -- so a unit asking for mem0 would be enabled, correct-looking, and
# skipped at every boot with nothing but a "condition failed" in the journal.
if grep -q '^ConditionPathExists=/dev/qcom_rmtfs_mem1' \
     "$R/usr/lib/systemd/system/rmtfs.service" 2>/dev/null; then
  ok "rmtfs.service waits on /dev/qcom_rmtfs_mem1 (DT client-id 1)"
else
  no "rmtfs.service's ConditionPathExists is not /dev/qcom_rmtfs_mem1 -- it would never start"
fi

# 7. Bluetooth is a different radio and shares none of the above: WCN3990's BT
# is a UART controller on &uart6 driven by hci_qca, wanting only these two.
# Cheap to check and it costs a rebuild to discover on the device.
for _f in crbtfw21.tlv crnv21.bin; do
  [ -s "$R/usr/lib/firmware/qca/$_f" ] && ok "Bluetooth firmware $_f present" \
    || no "no qca/$_f -- hci_qca has no patch/NVM to download"
done
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

# And the half that does happen, exercised ONLINE -- on the mounted filesystem,
# through the loop device backing it.
#
# That is not a workaround for the rootfs being mounted here; it is the more
# faithful test. moarchy-grow-rootfs runs from a systemd unit during boot and
# calls `resize2fs "$root_src"` against the device / is already mounted from,
# so an online grow is exactly what happens on the phone. The first version of
# this check ran resize2fs against $WORK/root.img while verify.sh had it
# mounted, which simply fails.
#
# losetup -c is the part that is easy to miss: truncating the backing file does
# not change the size the loop device reports, so resize2fs would find no new
# room and report success having done nothing.
loop=$(findmnt -no SOURCE "$R" 2>/dev/null)
case "$loop" in
  /dev/loop*)
    before=$(dumpe2fs -h "$loop" 2>/dev/null | awk -F: '/Block count/{gsub(/ /,"",$2); print $2}')
    truncate -s +64M "$WORK/root.img"
    losetup -c "$loop" 2>/dev/null
    if resize2fs "$loop" >/dev/null 2>&1; then
      after=$(dumpe2fs -h "$loop" 2>/dev/null | awk -F: '/Block count/{gsub(/ /,"",$2); print $2}')
      if [ -n "${before:-}" ] && [ -n "${after:-}" ] && [ "$after" -gt "$before" ]; then
        ok "resize2fs grew the mounted rootfs $(( before * 4096 / 1048576 ))M -> $(( after * 4096 / 1048576 ))M"
      else
        no "resize2fs did not grow the filesystem (${before:-?} -> ${after:-?} blocks)"
      fi
    else
      no "resize2fs failed on $loop -- the growth half of I7 is NOT tested"
    fi ;;
  *)
    # Never silently skip: this is the half that reclaims 50 GB of a phone.
    no "rootfs is not on a loop device (got '${loop:-none}') -- growth NOT tested" ;;
esac
}
