#!/usr/bin/env bash
# Build the flashable image, on the Mac, with no phone attached.
#
#   ./scripts/provision.sh build      # the packages, first
#   ./scripts/build-image.sh          # -> images/moarchy-pinephone-<date>.img.xz
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

command -v docker >/dev/null || { echo "docker is not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker is not running" >&2; exit 1; }
compgen -G "packages/*.pkg.tar.*" >/dev/null || {
  echo "No packages built yet. Run: ./scripts/provision.sh build" >&2; exit 1; }

mkdir -p "$OUTDIR"

echo "==> building the image container"
docker build --platform linux/arm64 -f image/Dockerfile -t moarchy-image . >/dev/null

# --privileged: arch-chroot bind-mounts /proc, /sys and /dev so mkinitcpio can
# run inside the rootfs. Everything else in build.sh deliberately avoids loop
# devices, which Docker Desktop's VM does not give us.
#
# WIFI_PSK is passed through the environment, never as an argument, so it stays
# out of `docker inspect` and the shell history.
# A persistent package cache. pacstrap pulls 1.26 GiB; without this every
# rebuild re-downloads all of it, which turns a five-minute change into a
# thirty-minute one.
CACHE="${PACMAN_CACHE:-$REPO_ROOT/.cache/pacman}"
mkdir -p "$CACHE"

docker run --rm --privileged --platform linux/arm64 \
  -v "$REPO_ROOT:/repo:ro" \
  -v "$CACHE:/var/cache/pacman/pkg" \
  -v "$REPO_ROOT/packages:/pkgs:ro" \
  -v "$OUTDIR:/out" \
  -e "WIFI_SSID=${WIFI_SSID:-}" -e "WIFI_PSK=${WIFI_PSK:-}" \
  -e "MOARCHY_USER=${MOARCHY_USER:-moarchy}" \
  -e "XZ_LEVEL=${XZ_LEVEL:-9}" \
  -e "MOARCHY_SSH_KEY=${MOARCHY_SSH_KEY:+/key.pub}" \
  ${MOARCHY_SSH_KEY:+-v "$MOARCHY_SSH_KEY:/key.pub:ro"} \
  moarchy-image

# Resolve the real filename rather than printing a placeholder: this line is
# meant to be pasted.
BUILT=$(ls -t "$OUTDIR"/moarchy-pinephone-*.img.xz 2>/dev/null | head -1)
echo
if [ -n "$BUILT" ]; then
  echo "==> verify it:"
  echo "     ./scripts/verify-image.sh"
  echo
  echo "==> flash it (find N with: diskutil list external physical):"
  echo "     IMAGE_FILE=\"$BUILT\" ./scripts/flash-sd.sh /dev/diskN"
else
  echo "!! no image produced" >&2
  exit 1
fi
