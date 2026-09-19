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
# the difference is kept rather than papered over: there is no container both a `dd`
# workflow and a `fastboot flash` workflow could share that anything can read.
#
# Every offset, address and page size here was measured off a postmarketOS
# boot.img that demonstrably boots the target device (devices.md §8.1), and
# image/boot/test-android-image.py reproduces that image byte-for-byte from its
# own parts. None of it came from a wiki.

# The two device-specific strings in the whole backend, which is the point -- a
# second Qualcomm phone adds a line here and changes nothing else.
#
#   DTB_NAME        the device tree appended to the kernel
#   ROOT_PARTLABEL  the GPT partition the rootfs is flashed to, and the name the
#                   kernel is given to find it again at boot (D24). A vendor
#                   fact: we do not choose it, we read it -- `blkid` on the
#                   handset reports PARTLABEL="userdata" for /dev/mmcblk0p72.
#
# Resolved in a function called BY THE HOOKS, not at source time. It was a bare
# `case` with a ${DTB_NAME:?} default, which meant sourcing this file with an
# unexpected DEVICE killed the shell before a single hook was defined -- so
# build.sh's "does this backend define all three hooks?" check reported a
# backend with no hooks at all, which is a far more alarming thing than the
# wrong device name. Sourcing a backend must never have side effects; it
# defines functions and does nothing else.
_set_device_facts() {
  case "${DEVICE:-}" in
    sargo) DTB_NAME=sdm670-google-sargo; ROOT_PARTLABEL=userdata ;;
    *) die "android-bootimg: no DTB known for DEVICE=${DEVICE:-unset}" ;;
  esac
}

# The ext4 label, set by mkfs in backend_image and read by /etc/fstab.
#
# It is NOT what the kernel is told to look for. `root=LABEL=` needs a udev
# that reads filesystem superblocks, which is an initramfs, and this backend
# has none (D24); the kernel resolves `root=PARTLABEL=` out of the GPT on its
# own. So the boot image names the partition and fstab names the filesystem
# inside it -- two identifiers for one device, each in the only form its reader
# can resolve.
ROOT_LABEL=${ROOT_LABEL:-moarchyroot}

# ---------------------------------------------------------------------------
# After pacstrap: check the kernel is there, and that it can mount root alone.
#
# This backend builds NO initramfs (D24) and writes no boot script -- there is
# no u-boot to read one. The bootloader jumps straight into the kernel with the
# cmdline baked into the boot image, which backend_image assembles.
#
# The hook stays because build.sh requires all three of them (D8), and because
# the checks below turn a missing package into one sentence rather than into a
# phone that shows two penguins and stops.
backend_kernel() {
_set_device_facts
say "kernel"

KREL=$(cat "$ROOTDIR/usr/share/kernel/moarchy-sdm670/kernel.release" 2>/dev/null) ||
  die "no kernel.release in the rootfs -- is linux-moarchy-sdm670 installed?"
info "kernel $KREL"

[ -f "$ROOTDIR/boot/Image.gz" ] || die "no /boot/Image.gz in the rootfs"
[ -f "$ROOTDIR/boot/dtbs/qcom/$DTB_NAME.dtb" ] ||
  die "no $DTB_NAME.dtb in the rootfs -- did the kernel package prune too far?"

# The same resolv.conf trap image/build.sh documents at length: `filesystem`
# ships it as a symlink into systemd-resolved's runtime directory, which does
# not exist in a chroot, so a plain cp writes through a dangling link and fails.
#
# Nothing in THIS hook needs DNS any more -- but image/configure.sh runs after
# it and refreshes the package database in the same chroot, and it has no
# resolv.conf handling of its own. Removing this costs:
# an image whose moarchy.db has no signature, where nothing installs until
# somebody runs `pacman -Sy` by hand.
rm -f "$ROOTDIR/etc/resolv.conf"
cp /etc/resolv.conf "$ROOTDIR/etc/resolv.conf" ||
  say "!! no resolv.conf for the chroot -- anything in it that needs DNS fails"

# The whole of D24 rests on three symbols being built INTO this kernel rather
# than shipped as modules, and they are decided in another package's config
# file. Asserted here because the failure mode is otherwise a mute phone: with
# no initramfs there is nothing to load a module from and nothing to print, so
# `CONFIG_EXT4_FS=m` would present exactly as a bad flash.
#
# modules.builtin is a list of the .ko files this kernel does NOT ship, which
# is precisely the question being asked.
local _builtin="$ROOTDIR/usr/lib/modules/$KREL/modules.builtin"
[ -f "$_builtin" ] || die "no modules.builtin for $KREL -- cannot check what is built in"
for _ko in fs/ext4/ext4.ko drivers/mmc/core/mmc_block.ko drivers/mmc/host/sdhci-msm.ko; do
  grep -qF "$_ko" "$_builtin" ||
    die "$_ko is a module, not built in -- this kernel cannot mount root without an initramfs (D24)"
done
info "ext4, mmc_block and sdhci-msm are built in; no initramfs needed"
}

# ---------------------------------------------------------------------------
# What /etc/fstab should say.
#
# One line, and the absence of a second is the device fact: sargo has no
# separate boot partition. /boot is a directory inside the rootfs, and the
# bootloader never reads it -- the kernel it runs was copied into boot.img at
# build time. An entry for a vfat /boot, as the PinePhone has, would mount
# something that does not exist.
#
# `rw` here is load-bearing and not decoration. The kernel mounts root READ-ONLY
# (backend_image's cmdline says so, and the bootloader says so too) precisely so
# that systemd-fsck-root can run -- its ConditionPathIsReadWrite=!/ means a root
# already mounted rw is a root that is never checked. systemd-remount-fs then
# remounts / with the options on THIS line. If it said `ro`, the phone would
# stay read-only for the rest of its life.
#
# passno 1 for the same reason: systemd-fstab-generator only pulls in
# systemd-fsck-root.service when the root entry has a non-zero pass.
backend_fstab() {
cat <<EOF
LABEL=$ROOT_LABEL  /  ext4  rw,relatime  0 1
EOF
}

# ---------------------------------------------------------------------------
# After the rootfs is trimmed: the three images and a script to flash them.
backend_image() {
_set_device_facts
local OUTDIR="$OUT/$NAME"
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"

say "boot image"
# The DTB is APPENDED to the compressed kernel, not passed separately. sargo's
# deviceinfo sets append_dtb=true and pmOS's own image carries FDT magic inside
# the kernel payload; a boot.img with the DTB in the `second` area instead is a
# black screen with nothing to read.
#
# The cmdline. ABL does not pass this through; it BUILDS one, putting ~40
# androidboot.* parameters of its own first, this string next, and console=null
# last (devices.md D23, D25). What that means for every line below is that ABL
# has already set some of them, earlier, to values meant for Android -- and the
# kernel's __setup handlers keep the LAST occurrence, so these win.
#
#   root=PARTLABEL=  the GPT name, resolved by the kernel itself out of the
#                    partition table. Not LABEL=, which needs a udev that reads
#                    superblocks, which needs an initramfs (D24). ABL passes its
#                    own root=PARTUUID= for the Android system partition; this
#                    overrides it.
#   ro               so systemd-fsck-root can check the root before anything
#                    writes to it; /etc/fstab then remounts it rw. ABL sets ro
#                    too, but relying on that would be relying on a bootloader.
#   rootwait         eMMC is not necessarily probed by the time init runs.
#                    rootwait retries the WHOLE lookup, PARTLABEL included --
#                    devt_from_partlabel returns -ENODEV, not -EINVAL, so the
#                    wait is not disabled.
#   rootfstype=ext4  f2fs is built into this kernel too and registers first, so
#                    without this the kernel tries and fails f2fs before ext4.
#                    Harmless, and unreadable on a device with no console.
#   init=/sbin/init  THE one that is not optional. ABL appends init=/init, which
#                    is right for an Android ramdisk and wrong for every rootfs
#                    we will ever ship. An Arch root has no /init, and a failed
#                    init= is a kernel panic() with no fallback to /sbin/init --
#                    so the phone mounted root correctly and died one exec
#                    later, showing two penguins and nothing else, for a whole
#                    night. Do not remove this line.
#
# There is deliberately NO console= here, and adding one does nothing: ABL
# strips it and appends console=null. Verified from a shell on the device --
# `grep -o "console=[^ ]*" /proc/cmdline` returns console=null alone and
# /proc/consoles lists only ttynull0. Nothing printed during boot is ever
# visible here, which is why the assertions in this file exist at all.
local CMDLINE=${CMDLINE:-"root=PARTLABEL=$ROOT_PARTLABEL ro rootwait rootfstype=ext4 init=/sbin/init"}
info "cmdline: $CMDLINE"

# No --ramdisk: this kernel mounts root itself (D24).
python3 "$REPO/image/boot/android-image.py" bootimg \
  --kernel  "$ROOTDIR/boot/Image.gz" \
  --dtb     "$ROOTDIR/boot/dtbs/qcom/$DTB_NAME.dtb" \
  --cmdline "$CMDLINE" \
  --pagesize 4096 \
  --out "$OUTDIR/boot.img" || die "boot.img generation failed"

# Prove it rather than trust the writer. The failure this catches -- a header
# field silently wrong -- otherwise presents as a phone that does nothing.
local hdr
hdr=$(dd if="$OUTDIR/boot.img" bs=8 count=1 status=none)
[ "$hdr" = "ANDROID!" ] || die "boot.img does not start with ANDROID!"
# ramdisk_size, a little-endian u32 at byte 16. Zero is the point of D24, and a
# non-zero value here means an initramfs crept back in.
rdsz=$(od -An -tu4 -j16 -N4 "$OUTDIR/boot.img" | tr -d " ")
[ "$rdsz" = 0 ] || die "boot.img carries a $rdsz-byte ramdisk; this backend ships none (D24)"
info "boot.img $(stat -c%s "$OUTDIR/boot.img") bytes, no ramdisk"

say "vbmeta"
# An Android 12 bootloader refuses an unsigned kernel unless the vbmeta it has
# says verification is disabled. This emits exactly what
# `avbtool make_vbmeta_image --flags 2 --padding_size 4096` emits, and
# test-android-image.py checks that byte-for-byte rather than asserting it.
python3 "$REPO/image/boot/android-image.py" vbmeta --out "$OUTDIR/vbmeta.img" ||
  die "vbmeta generation failed"
info "vbmeta.img $(stat -c%s "$OUTDIR/vbmeta.img") bytes"

say "rootfs image"
# The mkfs.ext4 -d trick: populate a filesystem image from
# a directory with no loop device and no mount, which is what lets the build
# run in a container.
local ROOT_USED_MIB ROOT_MIB
ROOT_USED_MIB=$(du -sm "$ROOTDIR" | cut -f1)
ROOT_MIB=$(( ROOT_USED_MIB + ROOT_SLACK_MIB ))
# Checked here because here is the earliest it can be checked without
# guessing: the rootfs exists, so its size is a fact rather than an estimate.
need_space "$ROOT_MIB" "the rootfs image"
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
cat > "$OUTDIR/flash.sh" <<FLASH
#!/bin/bash
# The one fact this script shares with the boot image: the partition the rootfs
# is flashed to is the partition root=PARTLABEL= names. Interpolated here, on
# its own line, so the rest of the script can stay a QUOTED heredoc -- an
# unquoted one would expand \$(dirname "\$0") and \$unlocked below at build
# time and write a script that flashes from whatever directory built it.
ROOTPART=$ROOT_PARTLABEL
FLASH
cat >> "$OUTDIR/flash.sh" <<'FLASH'
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
echo "==> $ROOTPART (the rootfs -- this is the slow one)"
# A SPARSE image. fastboot refuses a raw one over 4 GiB with "Failed reading
# from userdata", which sounds like a read error and is a size limit.
fastboot flash "$ROOTPART" rootfs.simg

# Reset the slot's retry counter and clear any "unbootable" flag.
#
# Not optional, and not tidiness. An A/B bootloader counts down a retry counter
# on every handoff and marks the slot unbootable at zero unless the OS calls
# back to say the boot worked. A phone that has been flashed a few times, or
# that failed to boot a few times, arrives here with the counter already spent
# -- and then refuses to boot the image you have just written, exactly as if
# the flash had failed. Measured on sargo 2026-09-14 (devices.md D26):
#
#   (bootloader) slot-retry-count:a:0
#   (bootloader) slot-unbootable:a:yes
#
# --set-active is the only thing that clears that flag. It erases nothing.
#
# Staying on the CURRENT slot is the point (D17): the other one keeps whatever
# was there, so a bad flash is recoverable by switching back in the bootloader.
echo "==> marking the current slot bootable"
slot=$(fastboot getvar current-slot 2>&1 | sed -n 's/^current-slot: *//p' | head -1)
if [ -n "$slot" ]; then
  fastboot --set-active="$slot"
else
  echo "!! could not read current-slot; if the phone does not boot, run:" >&2
  echo "   fastboot --set-active=a" >&2
fi

echo "==> done; rebooting"
fastboot reboot
FLASH
chmod +x "$OUTDIR/flash.sh"

say "done"
( cd "$OUTDIR" && sha256sum boot.img vbmeta.img rootfs.simg > "$NAME.sha256" )
ls -lh "$OUTDIR" | awk 'NR>1 {print "    " $9 "  " $5}'
info "flash with: $OUTDIR/flash.sh"
}
