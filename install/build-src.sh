#!/bin/bash
# moarchy-keyboard, yay, xdg-terminal-exec, ttf-ia-writer and cbonsai have no
# aarch64 builds in Arch Linux ARM and no aarch64 tree in Omarchy's own repo
# (pkgs.omarchy.org/stable/aarch64/omarchy.db -> 404).
#
# Preferred path: packages/ already holds *.pkg.tar.zst built on the Mac by
# docker/Dockerfile.builder (an aarch64 container, which runs natively on Apple
# Silicon). Fallback: build here on the phone -- slow, and moarchy-keyboard is
# a Qt6 C++ build, so this is measured in tens of minutes on an A53.
#
# Which packages, and at which commit, is manifest.toml's [aur.*] -- the same
# list the container builds from, so the two paths cannot drift apart.

echo "==> source-built packages"

. "$MOARCHY_PATH/scripts/manifest.sh"

PKGDIR="$MOARCHY_PATH/packages"
shopt -s nullglob
prebuilt=("$PKGDIR"/*.pkg.tar.*)

if (( ${#prebuilt[@]} )); then
  echo "    installing ${#prebuilt[@]} prebuilt package(s)"
  sudo pacman -U --needed --noconfirm "${prebuilt[@]}"
else
  echo "    no prebuilt packages found; building on-device (this is slow)"
  sudo pacman -S --needed --noconfirm base-devel git go

  packages=$(manifest_aur_packages) || exit 1

  MOARCHY_BUILD_DIR=$(mktemp -d)

  for pkg in $packages; do
    ref=$(manifest_get "aur.$pkg" ref) || continue
    echo "    building $pkg @ ${ref:0:7}"
    if git clone --quiet "https://aur.archlinux.org/$pkg.git" \
         "$MOARCHY_BUILD_DIR/$pkg" 2>/dev/null &&
       git -C "$MOARCHY_BUILD_DIR/$pkg" checkout --quiet --detach "$ref"; then
      ( cd "$MOARCHY_BUILD_DIR/$pkg" && makepkg -si --noconfirm ) ||
        echo "    !! $pkg failed to build; continuing without it" >&2
    else
      echo "    !! could not clone $pkg at ${ref:0:7}; skipping" >&2
    fi
  done

  rm -rf "$MOARCHY_BUILD_DIR"

  # There is no on-device fallback for moarchy-keyboard: it is not on the AUR,
  # and building Qt6 here is not something to start without being asked. The
  # container path is the supported one, and this says so rather than leaving
  # the phone mute with no explanation.
  if ! command -v moarchy-keyboard >/dev/null 2>&1; then
    echo "    !! moarchy-keyboard is not installed -- the phone has no on-screen" >&2
    echo "       keyboard. Build it on the Mac and copy it in:" >&2
    echo "         ./scripts/provision.sh build" >&2
    echo "         scp packages/*.pkg.tar.* $(id -un)@<phone>:~/" >&2
  fi
fi

# 4.x has no separate launcher: SUPER+SPACE goes through the quickshell shell,
# so walker and elephant are neither built nor installed. See the tail of
# moarchy-base.packages.
