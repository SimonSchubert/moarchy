#!/usr/bin/env bash
# Build the flashable image, on the Mac, with no phone attached.
#
#   ./scripts/provision.sh build      # the packages, first
#   ./scripts/build-image.sh          # -> images/moarchy-sargo-<version>-<date>/
#
# For a debug image that joins your wifi on first boot and enables sshd:
#
#   WIFI_SSID='MyNetwork' WIFI_PSK='secret' ./scripts/build-image.sh
#
# Never publish one of those: it carries your PSK (docs/structure.md I6a).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OUTDIR="${OUTDIR:-$REPO_ROOT/images}"

# Which container engine, and the flags that differ between docker and podman.
. "$REPO_ROOT/scripts/container.sh"
ctr_require
compgen -G "packages/*.pkg.tar.*" >/dev/null || {
  echo "No packages built yet. Run: ./scripts/provision.sh build" >&2; exit 1; }

# --- provenance, decided here and not in the container -----------------------
# The container sees /repo through a read-only bind mount, and a bind mount does
# not carry the inode and mtime metadata git's index recorded on the host. So
# `git diff-index`, which is a stat comparison, calls every tracked file
# modified -- 159 of them, with no content difference between any of them and
# HEAD. It cannot be fixed on that side either: the refresh that would settle it
# writes to .git/index, and the mount is read-only on purpose.
#
# The host is where the working tree is a native idea, so the question is asked
# here and the answer passed in. `git status --porcelain` rather than a diff,
# because an untracked file counts: pkgbuilds/moarchy copies default/ wholesale,
# so a file that is merely present lands in the package.
COMMIT=$(git rev-parse HEAD 2>/dev/null || echo unknown)
DIRTY=0
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  DIRTY=1
  printf '\033[31m!! the working tree has uncommitted changes\033[0m\n' >&2
  git status --porcelain | sed 's/^/       /' >&2
  if [ "${ALLOW_DIRTY:-0}" != 1 ]; then
    printf '   This image would correspond to no commit, and a file being edited\n' >&2
    printf '   while it builds is copied half-written. Commit, or re-run with\n' >&2
    printf '   ALLOW_DIRTY=1 if you mean it.\n' >&2
    exit 1
  fi
  printf '   ALLOW_DIRTY=1 -- continuing; this image is not reproducible\n' >&2
  # And it has to reach the container, which asks the same question again off
  # the DIRTY passed below. Without it this waiver got exactly as far as the
  # `docker build`, and image/build.sh then refused with the very message that
  # tells you to set the flag you had already set.
fi

mkdir -p "$OUTDIR"

echo "==> building the image container ($(ctr_describe))"
"$CTR" build --platform linux/arm64 -f image/Dockerfile -t moarchy-image . >/dev/null

# --privileged: arch-chroot bind-mounts /proc, /sys and /dev so configure.sh
# can run useradd, locale-gen and a pacman refresh inside the rootfs.
# Everything else in build.sh deliberately avoids loop devices, which Docker
# Desktop's VM does not give us.
#
# WIFI_PSK is passed through the environment, never as an argument, so it stays
# out of `docker inspect` and the shell history.
# A persistent package cache. pacstrap pulls 1.26 GiB; without this every
# rebuild re-downloads all of it, which turns a five-minute change into a
# thirty-minute one.
CACHE="${PACMAN_CACHE:-$REPO_ROOT/.cache/pacman}"
mkdir -p "$CACHE"

# No --userns here, unlike the package builder: this container runs as root,
# and rootless podman already maps container root to the host user -- so what
# lands in $OUTDIR is owned by whoever ran the build. Adding keep-id would
# break that rather than fix it.
"$CTR" run --rm --privileged --platform linux/arm64 \
  -v "$REPO_ROOT:/repo:ro" \
  -v "$CACHE:/var/cache/pacman/pkg" \
  -v "$REPO_ROOT/packages:/pkgs:ro" \
  -v "$OUTDIR:/out" \
  -e "WIFI_SSID=${WIFI_SSID:-}" -e "WIFI_PSK=${WIFI_PSK:-}" \
  -e "MOARCHY_USER=${MOARCHY_USER:-moarchy}" \
  -e "XZ_LEVEL=${XZ_LEVEL:-9}" \
  -e "MOARCHY_SSH_KEY=${MOARCHY_SSH_KEY:+/key.pub}" \
  -e "COMMIT=$COMMIT" -e "DIRTY=$DIRTY" \
  -e "ALLOW_DIRTY=${ALLOW_DIRTY:-0}" \
  -e "DEVICE=${DEVICE:-sargo}" \
  ${MOARCHY_SSH_KEY:+-v "$MOARCHY_SSH_KEY:/key.pub:ro"} \
  moarchy-image

# Resolve the real artifact rather than printing a placeholder: these lines are
# meant to be pasted (and [[no-placeholder-commands]] is why).
#
# The artifact is a DIRECTORY (docs/devices.md D10): boot.img, rootfs.simg,
# vbmeta.img and a flash.sh you run with the phone in fastboot. Matched with a
# trailing slash so a stray .tar.xz beside it is never picked up as the thing
# to verify.
_dev=${DEVICE:-sargo}
echo
BUILT=$(ls -td "$OUTDIR"/moarchy-"$_dev"-*/ 2>/dev/null | head -1)
if [ -z "$BUILT" ]; then
  echo "!! no image produced for $_dev" >&2
  exit 1
fi
echo "==> verify it:"
echo "     ./scripts/verify-image.sh \"${BUILT%/}\""
echo
echo "==> flash it (phone in fastboot, bootloader unlocked):"
echo "     ${BUILT}flash.sh"
