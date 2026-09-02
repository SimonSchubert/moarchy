#!/bin/bash
# walker, elephant, yay, xdg-terminal-exec and ttf-ia-writer have no aarch64
# builds in Arch Linux ARM and no aarch64 tree in Omarchy's own repo
# (pkgs.omarchy.org/stable/aarch64/omarchy.db -> 404).
#
# Preferred path: packages/ already holds *.pkg.tar.zst built on the Mac by
# docker/Dockerfile.builder (an aarch64 container, which runs natively on Apple
# Silicon). Fallback: build here on the phone -- slow, but these are small Go
# programs.

echo "==> source-built packages"

PKGDIR="$MOBILEOMARCHY_PATH/packages"
shopt -s nullglob
prebuilt=("$PKGDIR"/*.pkg.tar.*)

if (( ${#prebuilt[@]} )); then
  echo "    installing ${#prebuilt[@]} prebuilt package(s)"
  sudo pacman -U --needed --noconfirm "${prebuilt[@]}"
else
  echo "    no prebuilt packages found; building on-device (this is slow)"
  sudo pacman -S --needed --noconfirm base-devel git go

  MOBILEOMARCHY_BUILD_DIR=$(mktemp -d)

  for pkg in yay elephant walker xdg-terminal-exec ttf-ia-writer; do
    echo "    building $pkg"
    if git clone --depth 1 "https://aur.archlinux.org/$pkg.git" \
         "$MOBILEOMARCHY_BUILD_DIR/$pkg" 2>/dev/null; then
      ( cd "$MOBILEOMARCHY_BUILD_DIR/$pkg" && makepkg -si --noconfirm ) ||
        echo "    !! $pkg failed to build; continuing without it" >&2
    else
      echo "    !! could not clone $pkg; skipping" >&2
    fi
  done

  rm -rf "$MOBILEOMARCHY_BUILD_DIR"
fi

# A launcher is load-bearing for Omarchy's SUPER+SPACE. If walker did not make
# it, fall back to something that always exists so the binding is never dead.
if ! command -v walker >/dev/null; then
  echo "    walker unavailable -- installing fuzzel as the fallback launcher"
  sudo pacman -S --needed --noconfirm fuzzel || true
fi
