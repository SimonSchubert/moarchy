#!/usr/bin/env bash
# Verify a built image, in the same aarch64 container that built it.
#
#   ./scripts/verify-image.sh                 # newest image in images/
#   ./scripts/verify-image.sh path/to.img.xz
#
# Structure, contents and the two first-boot scripts. It cannot prove the phone
# boots -- that needs the phone -- but everything short of the hardware is here.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Newest artifact of EITHER shape (docs/devices.md D10): a PinePhone image is
# one .img.xz, an Android image is a directory of boot.img, rootfs.img,
# vbmeta.img and flash.sh. This globbed only moarchy-pinephone-*.img.xz until
# the second device existed, and would have said "No image found" with a sargo
# build sitting in images/.
IMAGE="${1:-$(ls -td images/moarchy-*-*.img.xz images/moarchy-*-*/ 2>/dev/null | head -1)}"
IMAGE="${IMAGE%/}"
[ -n "$IMAGE" ] || { echo "No image found. Run ./scripts/build-image.sh first." >&2; exit 1; }
# -e and not -f: an Android artifact is a directory.
[ -e "$IMAGE" ] || { echo "No such image: $IMAGE" >&2; exit 1; }
echo "==> verifying $(basename "$IMAGE")"

docker build --platform linux/arm64 -f image/Dockerfile -t moarchy-image . >/dev/null
# --privileged for the loop mount of the rootfs and for the chroot the
# behavioural checks run in.
docker run --rm --privileged --platform linux/arm64 \
  -v "$REPO_ROOT/$(dirname "$IMAGE")":/img:ro \
  --entrypoint bash moarchy-image \
  /repo/image/verify.sh "/img/$(basename "$IMAGE")"
