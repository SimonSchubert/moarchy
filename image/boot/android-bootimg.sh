#!/bin/bash
# The Android boot backend: mkbootimg-style boot.img, AVB, fastboot.
#
# docs/devices.md D9, and D0's general case rather than the carve-out -- the
# Pixel 3a, the Fairphone 4 and 5 and every other Qualcomm handset with an
# unlockable bootloader are this shape: fastboot, an Android boot image, A/B
# slots, verified boot, non-removable storage. A second device on this backend
# should be a device package and a DTB name, not another file here.
#
# Sourced by image/build.sh, which calls the three hooks below. Produces a
# DIRECTORY rather than a single file, and D10 says that asymmetry with
# sunxi-gpt is kept rather than papered over: there is no container both a `dd`
# workflow and a `fastboot flash` workflow could share that anything can read.
#
# Every offset, address and page size here was measured off a postmarketOS
# boot.img that demonstrably boots the target device (devices.md §8.1), and
# image/boot/test-android-image.py reproduces that image byte-for-byte from its
# own parts. None of it came from a wiki.

# The DTB this device's bootloader needs appended to the kernel. The one
# device-specific string in the whole backend, which is the point -- a second
# Qualcomm phone adds a line here and changes nothing else.
#
# Resolved in a function called BY THE HOOKS, not at source time. It was a bare
# `case` with a ${DTB_NAME:?} default, which meant sourcing this file with an
# unexpected DEVICE killed the shell before a single hook was defined -- so
# build.sh's "does this backend define all three hooks?" check reported a
# backend with no hooks at all, which is a far more alarming thing than the
# wrong device name. Sourcing a backend must never have side effects; it
# defines functions and does nothing else.
_set_dtb_name() {
  case "${DEVICE:-}" in
    sargo) DTB_NAME=sdm670-google-sargo ;;
    *) die "android-bootimg: no DTB known for DEVICE=${DEVICE:-unset}" ;;
  esac
}

# The filesystem label the kernel is told to look for.
#
# LABEL and not a partition path, deliberately. The rootfs is flashed to
# `userdata`, which is /dev/mmcblk0p72 on the handset this was developed
# against -- a number read off one phone, on a device family where the
# partition table is whatever the vendor shipped. The label is set by mkfs
# below, so the cmdline and the thing it names are decided in one place.
ROOT_LABEL=${ROOT_LABEL:-moarchyroot}

# ---------------------------------------------------------------------------
# After pacstrap: the initramfs.
#
# No boot script here, unlike sunxi-gpt -- there is no u-boot to read one. The
# bootloader jumps straight into the kernel with the cmdline baked into the
# boot image, which backend_image assembles.
backend_kernel() {
_set_dtb_name
say "kernel and initramfs"

KREL=$(cat "$ROOTDIR/usr/share/kernel/moarchy-sdm670/kernel.release" 2>/dev/null) ||
  die "no kernel.release in the rootfs -- is linux-moarchy-sdm670 installed?"
info "kernel $KREL"

[ -f "$ROOTDIR/boot/Image.gz" ] || die "no /boot/Image.gz in the rootfs"
[ -f "$ROOTDIR/boot/dtbs/qcom/$DTB_NAME.dtb" ] ||
  die "no $DTB_NAME.dtb in the rootfs -- did the kernel package prune too far?"

# The same resolv.conf trap image/build.sh documents at length: `filesystem`
# ships it as a symlink into systemd-resolved's runtime directory, which does
# not exist in a chroot, so a plain cp writes through a dangling link and fails.
rm -f "$ROOTDIR/etc/resolv.conf"
cp /etc/resolv.conf "$ROOTDIR/etc/resolv.conf" ||
  say "!! no resolv.conf for the chroot -- anything in it that needs DNS fails"

# -p and not -P: the kernel package ships a preset naming ALL_kver, so this
# builds an initramfs for THIS kernel rather than for whatever else is
# installed. `mkinitcpio -P` on a rootfs with two kernels silently builds both
# and the boot image would then carry a coin toss.
arch-chroot "$ROOTDIR" mkinitcpio -p moarchy-sdm670 ||
  die "mkinitcpio failed -- see above"
[ -f "$ROOTDIR/boot/initramfs-moarchy-sdm670.img" ] ||
  die "mkinitcpio produced no initramfs-moarchy-sdm670.img"
info "initramfs $(stat -c%s "$ROOTDIR/boot/initramfs-moarchy-sdm670.img") bytes"
}

# ---------------------------------------------------------------------------
# What /etc/fstab should say.
#
# One line, and the absence of a second is the device fact: sargo has no
# separate boot partition. /boot is a directory inside the rootfs, and the
# bootloader never reads it -- the kernel and initramfs it runs were copied
# into boot.img at build time. An entry for a vfat /boot, as the PinePhone
# has, would mount something that does not exist.
backend_fstab() {
cat <<EOF
LABEL=$ROOT_LABEL  /  ext4  rw,relatime  0 1
EOF
}

# ---------------------------------------------------------------------------
# After the rootfs is trimmed: the three images and a script to flash them.
backend_image() {
_set_dtb_name
local OUTDIR="$OUT/$NAME"
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"

say "boot image"
# The DTB is APPENDED to the compressed kernel, not passed separately. sargo's
# deviceinfo sets append_dtb=true and pmOS's own image carries FDT magic inside
# the kernel payload; a boot.img with the DTB in the `second` area instead is a
# black screen with nothing to read.
#
# The cmdline:
#   root=LABEL=   resolved by the initramfs's udev hook
#   rw            systemd remounts anyway, but fsck wants it first
#   rootwait      eMMC is not necessarily probed by the time init runs
#
# There is deliberately NO console= here, and adding one does nothing.
# ABL STRIPS any console= from the boot image and appends its own console=null
# (devices.md D23). Verified from a shell on the device: with console=tty0 in
# the boot image, `grep -o "console=[^ ]*" /proc/cmdline` returns console=null
# alone, and /proc/consoles lists only ttynull0. Every other parameter here --
# root=, rw, rootwait -- arrives intact; console= is the exception.
#
# The cost is that nothing printed during boot is EVER visible on this device,
# so a failing image and a working one look identical (penguins, then nothing).
# postmarketOS hit the same wall and works around it by writing to /dev/tty0
# directly; see their setup_log(). moarchy's initramfs will have to do the same
# or bring up USB networking, which is the only debug channel that worked.
local CMDLINE=${CMDLINE:-"root=LABEL=$ROOT_LABEL rw rootwait"}
info "cmdline: $CMDLINE"

python3 "$REPO/image/boot/android-image.py" bootimg \
  --kernel  "$ROOTDIR/boot/Image.gz" \
  --dtb     "$ROOTDIR/boot/dtbs/qcom/$DTB_NAME.dtb" \
  --ramdisk "$ROOTDIR/boot/initramfs-moarchy-sdm670.img" \
  --cmdline "$CMDLINE" \
  --pagesize 4096 \
  --out "$OUTDIR/boot.img" || die "boot.img generation failed"

# Prove it rather than trust the writer. The failure this catches -- a header
# field silently wrong -- otherwise presents as a phone that does nothing.
local hdr
hdr=$(dd if="$OUTDIR/boot.img" bs=8 count=1 status=none)
[ "$hdr" = "ANDROID!" ] || die "boot.img does not start with ANDROID!"
info "boot.img $(stat -c%s "$OUTDIR/boot.img") bytes"

say "vbmeta"
# An Android 12 bootloader refuses an unsigned kernel unless the vbmeta it has
# says verification is disabled. This emits exactly what
# `avbtool make_vbmeta_image --flags 2 --padding_size 4096` emits, and
# test-android-image.py checks that byte-for-byte rather than asserting it.
python3 "$REPO/image/boot/android-image.py" vbmeta --out "$OUTDIR/vbmeta.img" ||
  die "vbmeta generation failed"
info "vbmeta.img $(stat -c%s "$OUTDIR/vbmeta.img") bytes"

say "rootfs image"
# The same mkfs.ext4 -d trick sunxi-gpt uses: populate a filesystem image from
# a directory with no loop device and no mount, which is what lets the build
# run in a container.
local ROOT_USED_MIB ROOT_MIB
ROOT_USED_MIB=$(du -sm "$ROOTDIR" | cut -f1)
ROOT_MIB=$(( ROOT_USED_MIB + ROOT_SLACK_MIB ))
truncate -s "${ROOT_MIB}M" "$WORK/rootfs.raw"
mkfs.ext4 -q -L "$ROOT_LABEL" -d "$ROOTDIR" \
  -O ^has_journal,^metadata_csum_seed "$WORK/rootfs.raw"
tune2fs -O has_journal "$WORK/rootfs.raw" >/dev/null
info "rootfs ${ROOT_MIB}M (used ${ROOT_USED_MIB}M + ${ROOT_SLACK_MIB}M slack), label $ROOT_LABEL"

# Ship it SPARSE, not raw, and that is a hard requirement rather than a saving.
#
# fastboot cannot flash a raw image larger than 4 GiB -- FlashPartition takes a
# uint32_t size. A 6.06 GiB rootfs fails instantly with
#
#   fastboot: error: Failed reading from userdata
#
# which names the partition, says nothing about size, and is the same message
# an unreadable file produces. The partition is 49.9 GiB and the file read
# fine; a 200 MB control file to the same partition flashed in five seconds,
# which is what identified it.
#
# An Android sparse image takes a different path: fastboot splits it by
# max-download-size (256 MiB on this device) and streams the chunks. It is also
# smaller, because the holes in a freshly-made filesystem become DONT_CARE.
img2simg "$WORK/rootfs.raw" "$OUTDIR/rootfs.simg" ||
  die "img2simg failed -- is android-tools in the image container?"
info "rootfs.simg $(( $(stat -c%s "$OUTDIR/rootfs.simg") / 1048576 ))M sparse (from ${ROOT_MIB}M raw)"

# Asserted rather than assumed: a raw file here would flash on a small image
# and fail on a large one, which is the worst way to find this out.
smagic=$(dd if="$OUTDIR/rootfs.simg" bs=4 count=1 status=none | od -An -tx1 | tr -d " \n")
[ "$smagic" = "3aff26ed" ] || die "rootfs.simg is not an Android sparse image (magic $smagic)"

say "flash script"
# Written rather than documented, because the ORDER is load-bearing and a
# README gets read afterwards.
cat > "$OUTDIR/flash.sh" <<'FLASH'
#!/bin/bash
# Flash moarchy to a Pixel 3a (sargo) over fastboot.
#
# The phone must be UNLOCKED and in fastboot: power off, then hold Volume Down
# and tap Power. If `fastboot getvar unlocked` says no, `fastboot flashing
# unlock` sets it -- and ERASES THE DEVICE.
#
# This overwrites boot and userdata. The Android install does not survive it.
set -euo pipefail
cd "$(dirname "$0")"

command -v fastboot >/dev/null || { echo "!! fastboot not on PATH" >&2; exit 1; }
fastboot devices | grep -q . || { echo "!! no fastboot device -- is the phone in the bootloader?" >&2; exit 1; }

unlocked=$(fastboot getvar unlocked 2>&1 | sed -n 's/^unlocked: *//p' | head -1)
[ "$unlocked" = yes ] || { echo "!! bootloader is locked (unlocked: ${unlocked:-unknown})" >&2; exit 1; }

# Order is load-bearing. vbmeta disables Android Verified Boot; flash it AFTER
# the kernel and the bootloader rejects the kernel it already has, with an
# error that does not mention verification.
echo "==> vbmeta (disables verified boot)"
fastboot flash vbmeta vbmeta.img

echo "==> boot"
fastboot flash boot boot.img

# Far larger than max-download-size (256 MiB on this device), so fastboot
# splits the sparse image into chunks. Expect several minutes.
echo "==> userdata (the rootfs -- this is the slow one)"
# A SPARSE image. fastboot refuses a raw one over 4 GiB with "Failed reading
# from userdata", which sounds like a read error and is a size limit.
fastboot flash userdata rootfs.simg

echo "==> done; rebooting"
fastboot reboot
FLASH
chmod +x "$OUTDIR/flash.sh"

say "done"
( cd "$OUTDIR" && sha256sum boot.img vbmeta.img rootfs.simg > "$NAME.sha256" )
ls -lh "$OUTDIR" | awk 'NR>1 {print "    " $9 "  " $5}'
info "flash with: $OUTDIR/flash.sh"
}
