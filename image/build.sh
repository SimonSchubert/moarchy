#!/bin/bash
# Build moarchy-pinephone-<date>.img.xz -- a GPT disk image to write with dd.
#
# Runs inside image/Dockerfile with no phone attached (docs/structure.md I1).
#
# Layout, measured off DanctNIX's own image and kept identical so their u-boot
# finds what it expects (§1.1, I3):
#
#   byte 131072   u-boot SPL          (bs=128k seek=1, the GPT path)
#   LBA 16384     boot   FAT32 122M   Image.gz, dtbs, boot.scr, initramfs
#   LBA 266240    rootfs ext4         sized to contents + slack, grows on first boot
#
# No loop devices: mkfs.ext4 -d and mcopy populate a filesystem image from a
# directory without mounting it. Only mkinitcpio needs a chroot, which is why
# the container wants --privileged.
set -euo pipefail

OUT=${OUT:-/out}
WORK=${WORK:-/work}
REPO=${REPO:-/repo}
PKGS=${PKGS:-/pkgs}

BOOT_LBA=16384
BOOT_MIB=122
ROOT_LBA=266240
SECTOR=512
SPL_VARIANT=${SPL_VARIANT:-528}      # update-u-boot's own default_freq
ROOT_SLACK_MIB=${ROOT_SLACK_MIB:-350}

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die() { printf '\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }

# The release version, from manifest.toml -- the file that already answers
# "what version of anything" (V1). Four images carrying only a date landed in
# one afternoon, and telling them apart afterwards meant reading the .packages
# manifest beside each.
_version=$(. "$REPO/scripts/manifest.sh" && manifest_get moarchy version) || _version=0.0.0
STAMP=$(date +%Y%m%d)
NAME="moarchy-pinephone-$_version-$STAMP"
IMG="$WORK/$NAME.img"
ROOTDIR="$WORK/rootfs"

rm -rf "$WORK"; mkdir -p "$WORK" "$OUT"

# --- provenance ------------------------------------------------------------
# What commit is this image? A published artifact that answers "none" cannot be
# rebuilt, bisected, or trusted to contain what its release notes claim.
#
# This is not hypothetical. An image built during a parallel session's edits
# picked up their uncommitted working tree, and one file in it matched neither
# HEAD nor the finished file -- it was copied mid-write. Nothing in the build
# noticed, and the only reason it was not published is that someone thought to
# compare hashes afterwards.
#
# So the commit goes in the image and beside it, and a dirty tree is refused
# unless the caller says otherwise.
COMMIT=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)
if ! git -C "$REPO" diff-index --quiet HEAD -- 2>/dev/null; then
  DIRTY=1
  printf '\033[31m!! the working tree has uncommitted changes\033[0m\n' >&2
  git -C "$REPO" diff-index --name-only HEAD -- 2>/dev/null | sed 's/^/       /' >&2
  if [ "${ALLOW_DIRTY:-0}" != 1 ]; then
    printf '   This image would correspond to no commit, and a file being edited\n' >&2
    printf '   while it builds is copied half-written. Commit, or re-run with\n' >&2
    printf '   ALLOW_DIRTY=1 if you mean it.\n' >&2
    exit 1
  fi
  printf '   ALLOW_DIRTY=1 -- continuing; this image is not reproducible\n' >&2
else
  DIRTY=0
fi
info "commit ${COMMIT:0:12}$([ "$DIRTY" = 1 ] && echo ' (DIRTY)')"

# ---------------------------------------------------------------------------
say "local package repository"
# M3 publishes this over HTTP. Until then the image build consumes the same
# packages from a file:// repo, which is the only part of §7 that actually
# needed §6 -- pacstrap does not care whether the repo is local or remote
# (docs/structure.md I2).
compgen -G "$PKGS/*.pkg.tar.*" >/dev/null || die "no packages in $PKGS -- run ./scripts/provision.sh build first"
# docker/build-packages.sh never clears its output directory, so a pkgrel bump
# or a moved pin leaves yesterday's file beside today's. repo-add below takes
# whichever the glob puts last and pacstrap installs whatever the database then
# names -- a version chosen by lexicographic order rather than by anyone. The
# image is the worst place for that to be decided quietly, because the answer
# ships on a card. See scripts/pkgset.sh.
. "$REPO/scripts/pkgset.sh"
pkgset_unique "$PKGS" || die "$PKGS is ambiguous; no image built"
mkdir -p "$WORK/repo"
cp "$PKGS"/*.pkg.tar.* "$WORK/repo/"
repo-add --quiet "$WORK/repo/moarchy.db.tar.gz" "$WORK/repo"/*.pkg.tar.* >/dev/null
# Named rather than counted, so a stale one is visible here rather than in
# `pacman -Q` on a phone three days later.
pkgset_list "$PKGS" | sed 's/^/    /'

cat >"$WORK/pacman.conf" <<EOF
[options]
Architecture = aarch64
SigLevel = Never
DisableSandbox
# pacman's default gives up on a stalled mirror with "Operation too slow. Less
# than 1 bytes/sec", which failed a build 40 minutes in on webkitgtk. The retry
# loop below covers a mirror that drops the connection outright; this covers one
# that merely crawls.
DisableDownloadTimeout
HoldPkg = pacman glibc
[moarchy]
Server = file://$WORK/repo
[core]
Server = http://mirror.archlinuxarm.org/\$arch/\$repo
[extra]
Server = http://mirror.archlinuxarm.org/\$arch/\$repo
[alarm]
Server = http://mirror.archlinuxarm.org/\$arch/\$repo
[aur]
Server = http://mirror.archlinuxarm.org/\$arch/\$repo
[danctnix]
Server = https://archmobile.mirror.danctnix.org/\$repo/\$arch/
EOF

# ---------------------------------------------------------------------------
say "pacstrap the rootfs"
# The base DanctNIX phone, then moarchy-meta, which pulls the entire phone UI
# through its depends. This is the same one transaction M2 made possible; the
# image build is just running it in a chroot instead of on a device.
# The package set is DanctNIX's own explicitly-installed list, read out of
# /var/lib/pacman/local in their release image, plus moarchy-meta. Hand-picking
# it was a mistake caught before it shipped: `linux-megi uboot-pinephone
# danctnix-tweaks` looked like the device stack and left out
# linux-firmware-realtek, which is the wifi.
#
# pipewire-jack is named explicitly, and that is not cosmetic: pipewire-audio
# leaves the jack provider ambiguous, pacstrap prompts "1) jack2 2)
# pipewire-jack", and with no tty it takes the default -- so an unattended
# build silently shipped jack2 alongside pipewire. Naming it removes the prompt
# and matches DanctNIX's list.
#
# device-pine64-pinephone is their device meta package and pulls the lot --
# danctnix-tweaks, linux-megi, uboot-pinephone, linux-firmware-realtek,
# anx7688-firmware, ov5640-firmware, eg25-manager -- plus the brightness and
# proximity udev rules and the suspend hook. Depending on it rather than on its
# contents means a device fix from DanctNIX arrives without an edit here.
mkdir -p "$ROOTDIR"
# -c uses the HOST's package cache (a bind mount from the repo's .cache/) rather
# than downloading into the target root. Without it every build re-fetched
# 1.26 GiB, and the downloads landed inside the rootfs where they then had to be
# trimmed back out before sizing the partition.
# Retried, because a single slow mirror should not cost a 40-minute build.
# Each attempt resumes from the package cache, so a retry fetches only what
# is still missing rather than starting the 1.26 GiB over.
attempt=1
until pacstrap -c -C "$WORK/pacman.conf" -M "$ROOTDIR" \
  base \
  archlinuxarm-keyring danctnix-keyring \
  device-pine64-pinephone danctnix-usb-tethering \
  linux-firmware \
  networkmanager wpa_supplicant iw dhcpcd \
  pipewire-audio pipewire-alsa pipewire-pulse pipewire-jack \
  dosfstools f2fs-tools v4l-utils zramswap sudo which \
  moarchy-meta
do
  if [ $attempt -ge 3 ]; then
    die "pacstrap failed $attempt times -- see the mirror errors above"
  fi
  attempt=$(( attempt + 1 ))
  info "pacstrap failed; retrying ($attempt/3)"
  sleep 5
done
info "rootfs: $(du -sh "$ROOTDIR" | cut -f1)"

# ---------------------------------------------------------------------------
say "kernel, initramfs and boot script"
cp /etc/resolv.conf "$ROOTDIR/etc/resolv.conf" 2>/dev/null || true

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

# ---------------------------------------------------------------------------
say "recording provenance"
# Inside the image, so a phone can say what it is running, and beside the
# download, so the release can be tied to a commit without unpacking it.
install -d "$ROOTDIR/usr/share/moarchy"
{ echo "commit=$COMMIT"
  echo "dirty=$DIRTY"
  echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "version=$_version"
} > "$ROOTDIR/usr/share/moarchy/build-info"
cp "$ROOTDIR/usr/share/moarchy/build-info" "$OUT/$NAME.build-info"
info "commit ${COMMIT:0:12}, dirty=$DIRTY"

say "first-boot configuration"
"$REPO/image/configure.sh" "$ROOTDIR"

# ---------------------------------------------------------------------------
say "trim the rootfs"
# pacstrap leaves every downloaded package in /var/cache/pacman/pkg -- 1.26 GiB
# of it, which would be sized into the partition and then compressed into the
# download for no reason. The first `pacman -Syu` refills it as needed.
rm -rf "${ROOTDIR:?}/var/cache/pacman/pkg/"*
rm -f  "$ROOTDIR/etc/resolv.conf"          # the builder's, not the phone's
info "after trim: $(du -sh "$ROOTDIR" | cut -f1)"

# ---------------------------------------------------------------------------
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
