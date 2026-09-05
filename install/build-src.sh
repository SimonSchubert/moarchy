#!/bin/bash
# moarchy-keyboard, yay, xdg-terminal-exec and ttf-ia-writer have no aarch64
# builds in Arch Linux ARM and no aarch64 tree in Omarchy's own repo
# (pkgs.omarchy.org/stable/aarch64/omarchy.db -> 404).
#
# Preferred path: packages/ already holds *.pkg.tar.zst built on the Mac by
# docker/Dockerfile.builder (an aarch64 container, which runs natively on Apple
# Silicon). Fallback: build here on the phone -- slow, and moarchy-keyboard is
# a Qt6 C++ build, so this is measured in tens of minutes on an A53.

echo "==> source-built packages"

PKGDIR="$MOARCHY_PATH/packages"
shopt -s nullglob
prebuilt=("$PKGDIR"/*.pkg.tar.*)

if (( ${#prebuilt[@]} )); then
  echo "    installing ${#prebuilt[@]} prebuilt package(s)"
  sudo pacman -U --needed --noconfirm "${prebuilt[@]}"
else
  echo "    no prebuilt packages found; building on-device (this is slow)"
  sudo pacman -S --needed --noconfirm base-devel git go

  MOARCHY_BUILD_DIR=$(mktemp -d)

  for pkg in yay xdg-terminal-exec ttf-ia-writer; do
    echo "    building $pkg"
    if git clone --depth 1 "https://aur.archlinux.org/$pkg.git" \
         "$MOARCHY_BUILD_DIR/$pkg" 2>/dev/null; then
      ( cd "$MOARCHY_BUILD_DIR/$pkg" && makepkg -si --noconfirm ) ||
        echo "    !! $pkg failed to build; continuing without it" >&2
    else
      echo "    !! could not clone $pkg; skipping" >&2
    fi
  done

  rm -rf "$MOARCHY_BUILD_DIR"
fi

# 4.x has no separate launcher: SUPER+SPACE goes through the quickshell shell,
# so walker and elephant are neither built nor installed. See the tail of
# moarchy-base.packages.
