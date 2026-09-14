#!/bin/bash
# Build a moarchy image for $DEVICE.
#
# Runs inside image/Dockerfile with no phone attached (docs/structure.md I1).
#
# This file builds a ROOTFS, which is the same for every device moarchy
# supports, and then hands it to a boot backend that turns it into something
# that device can boot (docs/devices.md D8). What comes out the far end differs
# in shape, not just in content, and D10 says that is kept rather than hidden:
#
#   pinephone  -> sunxi-gpt        one moarchy-pinephone-<ver>-<date>.img.xz
#                                  to dd onto a card
#   sargo      -> android-bootimg  boot.img + rootfs.img + vbmeta.img + a
#                                  flash.sh, to fastboot onto a phone
#
# No loop devices: mkfs.ext4 -d and mcopy populate a filesystem image from a
# directory without mounting it. The chroot is what wants --privileged --
# configure.sh runs useradd, locale-gen and a package-database refresh inside
# the rootfs, and the PinePhone backend builds an initramfs there.
set -euo pipefail

OUT=${OUT:-/out}
WORK=${WORK:-/work}
REPO=${REPO:-/repo}
PKGS=${PKGS:-/pkgs}

# Which phone this image is for (docs/devices.md D11). It selects the device
# package pacstrap installs, the boot backend that assembles the artifact, and
# the artifact's name.
DEVICE=${DEVICE:-pinephone}
[ -d "$REPO/pkgbuilds/moarchy-device-$DEVICE" ] ||
  { printf '\033[31m!! no pkgbuilds/moarchy-device-%s\033[0m\n' "$DEVICE" >&2; exit 1; }

# Device to boot backend. A case rather than a key in the device package's
# device.conf, because this is a BUILD-time fact and that file is a RUNTIME
# one -- it is installed into the rootfs and read by moarchy-firstboot on the
# phone, where "which script assembled my image" is not a question anything
# can ask. Two concerns, two homes.
#
# The list is short and adding to it is the point: a third Qualcomm handset is
# a line here and a device package, not a new backend (D0 -- the Android case
# is the general one).
case "$DEVICE" in
  pinephone) BACKEND=sunxi-gpt ;;
  sargo)     BACKEND=android-bootimg ;;
  *) printf '\033[31m!! DEVICE=%s has no boot backend; add one to the case in %s\033[0m\n' \
       "$DEVICE" "$0" >&2; exit 1 ;;
esac
[ -f "$REPO/image/boot/$BACKEND.sh" ] ||
  { printf '\033[31m!! no image/boot/%s.sh\033[0m\n' "$BACKEND" >&2; exit 1; }
# Exported because the rootfs build and the backends both read them, and
# because a build log that does not say which phone it was for is a log that
# has to be guessed at later.
export DEVICE BACKEND

# How much room above the rootfs contents. Shared: both backends size a
# filesystem to its contents and both want it to boot and run growpart once.
# The partition geometry that is NOT shared moved into the backends with the
# code that reads it.
ROOT_SLACK_MIB=${ROOT_SLACK_MIB:-350}

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die() { printf '\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }

# The boot backend (docs/devices.md D8, D9). Sourced AFTER say/info/die, which
# its hook bodies call, and after the variables above, which they read -- it
# defines three functions and runs nothing at source time.
. "$REPO/image/boot/$BACKEND.sh"
for _hook in backend_kernel backend_fstab backend_image; do
  declare -F "$_hook" >/dev/null ||
    die "$BACKEND.sh defines no $_hook -- a backend owes all three (D8)"
done
info "device $DEVICE, boot backend $BACKEND"

# The release version, from manifest.toml -- the file that already answers
# "what version of anything" (V1). Four images carrying only a date landed in
# one afternoon, and telling them apart afterwards meant reading the .packages
# manifest beside each.
_version=$(. "$REPO/scripts/manifest.sh" && manifest_get moarchy version) || _version=0.0.0
STAMP=$(date +%Y%m%d)
NAME="moarchy-$DEVICE-$_version-$STAMP"
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
#
# scripts/build-image.sh answers both questions on the HOST and passes them in,
# and that is not tidiness. /repo arrives as a read-only bind mount, which does
# not carry the inode and mtime metadata the host's .git/index recorded, so a
# stat-based `git diff-index --quiet HEAD` here calls all 159 tracked files
# modified with no content difference in any of them -- and the refresh that
# would settle it writes to .git/index, which this mount deliberately forbids.
#
# Only reached when this script is run directly. `git diff`, not `git
# diff-index`: it refreshes the index in memory before comparing, so it answers
# about content rather than about stat. Both directions were run against a
# read-only mount, clean and with one file edited.
COMMIT="${COMMIT:-$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)}"
if [ -z "${DIRTY:-}" ]; then
  if git -C "$REPO" diff --quiet HEAD -- 2>/dev/null; then
    DIRTY=0
  else
    DIRTY=1
    printf '\033[31m!! the working tree has uncommitted changes\033[0m\n' >&2
    git -C "$REPO" diff --name-only HEAD -- 2>/dev/null | sed 's/^/       /' >&2
  fi
fi
if [ "$DIRTY" = 1 ] && [ "${ALLOW_DIRTY:-0}" != 1 ]; then
  printf '   This image would correspond to no commit, and a file being edited\n' >&2
  printf '   while it builds is copied half-written. Commit, or re-run with\n' >&2
  printf '   ALLOW_DIRTY=1 if you mean it.\n' >&2
  exit 1
fi
if [ "$DIRTY" = 1 ]; then
  # An `if`, not `[ ... ] && printf`: this file runs under `set -e`, where a
  # bare AND-list that is false is a live grenade at the end of any block.
  printf '   ALLOW_DIRTY=1 -- continuing; this image is not reproducible\n' >&2
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
# A leftover from an earlier build is not a duplicate and looks like nothing at
# all, which is how a release nearly shipped a store from a pin that had moved.
pkgset_vouched "$PKGS" || die "$PKGS holds files no build vouches for; no image built"
# Our own packages are evicted from the shared pacman cache before pacstrap
# runs, and this is not housekeeping.
#
# /var/cache/pacman/pkg is a bind mount from .cache/, kept because pacstrap
# pulls 1.26 GiB and re-downloading it turns a five-minute change into a
# thirty-minute one. It is keyed by FILENAME. Rebuild a pinned package and the
# name does not move but the bytes do -- so the cached copy is stale for exactly
# the packages this project builds, and for no others.
#
# What that looked like: the first 0.1.1 attempt died with seven packages
# "corrupted (invalid or corrupted package (checksum))" -- lcl-gui-bin, yay,
# xdg-terminal-exec, ttf-ia-writer, cbonsai, moarchy-keyring, omarchy-config,
# which is precisely the set that had just been rebuilt. pacman was right, and
# the retry loop above absorbed it. But that loop is there for a slow mirror,
# and a local cache going stale on every clean rebuild is not that: it cost a
# whole pacstrap and read like a network fault.
#
# Only ours, and only by name. Everything else in the cache is an upstream
# package whose filename does identify its contents, and re-downloading 1.26 GiB
# to avoid thinking about that would be the wrong trade.
for _p in "$PKGS"/*.pkg.tar.*; do
  [ -e "$_p" ] || continue
  rm -f "/var/cache/pacman/pkg/${_p##*/}" "/var/cache/pacman/pkg/${_p##*/}.sig"
done

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
# The hardware is named ONCE, in moarchy-device-$DEVICE, and this line installs
# that package rather than its contents (docs/devices.md D2). DanctNIX's
# device-pine64-pinephone -- linux-megi, uboot-pinephone, linux-firmware-realtek
# and the rest -- moved into its depends, along with the note about why picking
# that list by hand loses the wifi.
#
# moarchy-meta depends on the VIRTUAL name `moarchy-device` (D5), so naming the
# concrete package here is what decides which phone this image is for. It is
# also deliberately explicit: pacman could resolve the virtual name on its own
# while exactly one provider exists in the repo, and would silently start
# guessing on the day a second one lands.
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
  "moarchy-device-$DEVICE" \
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
# Whatever this device needs doing to the kernel before the image is built.
# PinePhone: mkinitcpio -P then mkscr. sargo: nothing but checks -- that kernel
# mounts root itself and ships no initramfs (D24). Nothing in common but the
# word "boot" (docs/devices.md D8).
backend_kernel

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

# The disk layout, from the backend that is about to create it (D8). Written
# here rather than inside configure.sh so that script stays device-independent
# and needs no backend of its own.
#
# By label rather than UUID on both devices: the backend sets the label at mkfs
# time, so this and the thing it describes are decided in one place.
backend_fstab > "$ROOTDIR/etc/fstab"
info "fstab: $(wc -l < "$ROOTDIR/etc/fstab") entries from $BACKEND"

# ---------------------------------------------------------------------------
say "trim the rootfs"
# pacstrap leaves every downloaded package in /var/cache/pacman/pkg -- 1.26 GiB
# of it, which would be sized into the partition and then compressed into the
# download for no reason. The first `pacman -Syu` refills it as needed.
rm -rf "${ROOTDIR:?}/var/cache/pacman/pkg/"*
rm -f  "$ROOTDIR/etc/resolv.conf"          # the builder's, not the phone's
# Put back the symlink `filesystem` ships, rather than handing over an image
# with a packaged file missing. Nothing resolves through it -- nsswitch sends
# lookups to resolved directly, which is why this went unnoticed -- but
# `pacman -Qk filesystem` reports it, and a phone that reinstalls that package
# silently gets it back anyway.
ln -sf ../run/systemd/resolve/stub-resolv.conf "$ROOTDIR/etc/resolv.conf"
info "after trim: $(du -sh "$ROOTDIR" | cut -f1)"

# ---------------------------------------------------------------------------
# The artifact itself: filesystems, partition table, bootloader, compression.
# All of it differs completely between a PinePhone and an Android handset, so
# all of it is the backend's (docs/devices.md D9, D10).
backend_image
