#!/usr/bin/env bash
# Which container engine to use, and the flags that differ between them.
# Source this; it defines functions and one variable.
#
#   . "$REPO_ROOT/scripts/container.sh"
#   ctr_require                 # or it dies with something actionable
#   $CTR build ... $(ctr_build_args) ...
#
# This project was written against Docker Desktop on Apple Silicon, where the
# arm64 containers run natively and the daemon runs as root. Neither holds on
# an x86_64 Linux host, and podman is the better fit there for a reason that is
# not taste: **it needs no root at all**. Docker's daemon runs as root and
# talks over a socket only the `docker` group can open, so using it costs two
# privileged, persistent changes to the machine (`systemctl enable docker`, and
# adding a user to a group that is equivalent to root). Rootless podman costs
# neither, and the build does not need root for anything -- image/build.sh
# deliberately avoids loop devices, and the one privileged thing left is
# arch-chroot's bind mounts, which work inside a user namespace.
#
# So: podman is PREFERRED when both are present, and the choice is overridable.
#
#   MOARCHY_CONTAINER=docker ./scripts/provision.sh build
#
# --- What actually differs between them -------------------------------------
#
# Four things, all of them found by running it rather than by reading about it:
#
# 1. SHORT NAMES. Docker resolves a bare `menci/archlinuxarm` against Docker
#    Hub; podman refuses to guess. Fixed in the Dockerfiles by writing
#    `docker.io/` out, so it is not a flag here.
#
# 2. SETUID DOES NOT WORK, which is the one that actually bites, and it is a
#    kernel rule rather than a podman setting. A mount created by an
#    unprivileged user namespace is forced MS_NOSUID, so the setuid bit on
#    /usr/bin/sudo is ignored and any `sudo` by a non-root container user dies
#    with "effective uid is not 0 ... 'nosuid' option set". --privileged,
#    --cap-add=SETUID and no-new-privileges=false were each measured; none
#    restores it.
#
#    That breaks the builder image's original shape, which ran as `builder`
#    and let makepkg's `-s` sudo for dependencies. The fix is in the image and
#    the build script, not here: the container runs as ROOT and drops to
#    `builder` for every makepkg, so root installs dependencies and makepkg
#    never runs as root. docker/Dockerfile.builder explains it at the bottom.
#
#    A `--userns=keep-id:uid=1000,gid=1000` mapping was tried first, to make
#    `builder` the host user so it could write the bind-mounted packages/. It
#    works for ownership and is the WRONG fix: it leaves the container with no
#    usable root at all, so `pacman -S` cannot run and every component and AUR
#    package fails at "could not resolve all dependencies". Recorded because
#    it is the obvious first answer and it fails two steps later, in a place
#    that does not mention user namespaces.
#
#    Ownership is handled by build-packages.sh instead: it lends $OUT to
#    `builder` for the build and restores $OUT's ORIGINAL owner on exit, which
#    is correct under both engines without either one being named.
#
# 3. /dev/fuse. The verify suite mounts the rootfs image. Rootless podman
#    cannot use a loop device for that (`mount -o loop` is EPERM, and
#    /dev/loop-control belongs to nobody inside the namespace), so verify.sh
#    falls back to fuse2fs -- which needs the device passed in.
#
# 4. `docker info` vs `podman info` both work as liveness checks, but they mean
#    different things: docker's failing usually means a daemon is not running,
#    podman's means something is actually broken, because there is no daemon.
#    ctr_require says the right sentence for whichever one is in use.

# The engine. Set MOARCHY_CONTAINER to force one.
CTR="${MOARCHY_CONTAINER:-}"
if [ -z "$CTR" ]; then
  if command -v podman >/dev/null 2>&1; then
    CTR=podman
  elif command -v docker >/dev/null 2>&1; then
    CTR=docker
  else
    CTR=
  fi
fi
export CTR

# ctr_require -- 0 if the engine is usable, otherwise die with the fix.
#
# `die` is the caller's; scripts/provision.sh, build-image.sh and
# verify-image.sh each define one. Falls back to a plain exit so that sourcing
# this from somewhere that does not is not itself the error.
ctr_require() {
  if ! command -v _ctr_die >/dev/null 2>&1; then
    if command -v die >/dev/null 2>&1; then
      _ctr_die() { die "$@"; }
    else
      _ctr_die() { printf '\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }
    fi
  fi

  [ -n "$CTR" ] || _ctr_die "no container engine found.
   Install one -- podman is recommended, because it needs no root:
     sudo pacman -S podman
   Docker also works, at the cost of a root daemon and a docker group."

  command -v "$CTR" >/dev/null 2>&1 ||
    _ctr_die "MOARCHY_CONTAINER=$CTR, but $CTR is not on PATH"

  if ! "$CTR" info >/dev/null 2>&1; then
    case "$CTR" in
      docker) _ctr_die "docker is installed but not usable.
   sudo systemctl start docker
   sudo usermod -aG docker \"$USER\"   # then log out and back in
   Or use podman, which needs neither:  MOARCHY_CONTAINER=podman" ;;
      *) _ctr_die "$CTR is installed but '$CTR info' failed. Run it by hand to see why.
   If this is rootless podman, the usual cause is no subuid/subgid range:
     grep \"^\$USER:\" /etc/subuid /etc/subgid
   and if empty:  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 \"\$USER\"" ;;
    esac
  fi
}

# ctr_is_rootless -- 0 when this engine runs without root.
ctr_is_rootless() {
  [ "$CTR" = podman ] || return 1
  [ "$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = true ]
}

# ctr_describe -- one line for a build log, so an image or a package set can be
# traced back to what produced it.
ctr_describe() {
  local _v
  _v=$("$CTR" --version 2>/dev/null | head -1)
  if ctr_is_rootless; then
    printf '%s (rootless)\n' "$_v"
  else
    printf '%s\n' "$_v"
  fi
}

# ctr_fuse_args -- pass /dev/fuse in, for the verify container's fuse2fs
# fallback. Harmless on docker, and omitted there because docker can use a
# real loop device and does not need it.
ctr_fuse_args() {
  if ctr_is_rootless; then
    [ -e /dev/fuse ] && printf -- '--device=/dev/fuse\n'
  fi
}
