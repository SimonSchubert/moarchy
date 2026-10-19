#!/usr/bin/env bash
# Verify a built image, in the same aarch64 container that built it.
#
#   ./scripts/verify-image.sh                 # newest artifact in images/
#   ./scripts/verify-image.sh path/to/moarchy-sargo-<ver>-<date>
#
# Structure, contents and the two first-boot scripts. It cannot prove the phone
# boots -- that needs the phone -- but everything short of the hardware is here.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# The newest artifact, which is a DIRECTORY (docs/devices.md D10): boot.img,
# rootfs.simg, vbmeta.img and flash.sh. The trailing slash in the glob is what
# keeps the .tar.xz sitting beside it from being picked instead.
IMAGE="${1:-$(ls -td images/moarchy-*-*/ 2>/dev/null | head -1)}"
IMAGE="${IMAGE%/}"
[ -n "$IMAGE" ] || { echo "No image found. Run ./scripts/build-image.sh first." >&2; exit 1; }
# -e and not -f: an Android artifact is a directory.
[ -e "$IMAGE" ] || { echo "No such image: $IMAGE" >&2; exit 1; }
echo "==> verifying $(basename "$IMAGE")"

# Resolved to an absolute path HERE, and the bind mount built from that rather
# than from "$REPO_ROOT/$IMAGE".
#
# The prefix used to be unconditional, so an absolute path -- which is exactly
# what build-image.sh's own "verify it:" line prints for an Android artifact --
# became $REPO_ROOT/Users/simon/Projects/moarchy/images/..., a path that does
# not exist. Docker does not refuse a missing bind source: it CREATES it, as an
# empty directory. So the run mounted nothing, verified nothing, and failed
# with
#
#   FAIL /img/moarchy-sargo-... is not a directory -- an Android artifact is a
#        directory of images (D10)
#   FAIL could not mount the rootfs
#
# which is a report about a broken image, from a perfectly good one, because of
# a path. The relative form worked, so this hid behind whichever form you
# happened to type.
IMAGE_ABS=$(cd "$(dirname "$IMAGE")" && pwd)/$(basename "$IMAGE")

# Which container engine, and the flags that differ between docker and podman.
. "$REPO_ROOT/scripts/container.sh"
ctr_require

"$CTR" build --platform linux/arm64 -f image/Dockerfile -t moarchy-image . >/dev/null
# --privileged for the mount of the rootfs and for the chroot the behavioural
# checks run in.
#
# --device=/dev/fuse is added on rootless podman, and only there. A rootless
# container cannot use a loop device -- `mount -o loop` is EPERM and
# /dev/loop-control belongs to nobody inside the user namespace -- so
# image/verify.sh falls back to fuse2fs, which needs the device passed in. On
# docker the loop mount works and the flag would buy nothing.
"$CTR" run --rm --privileged --platform linux/arm64 $(ctr_fuse_args) \
  -v "$(dirname "$IMAGE_ABS")":/img:ro \
  --entrypoint bash moarchy-image \
  /repo/image/verify.sh "/img/$(basename "$IMAGE_ABS")"
