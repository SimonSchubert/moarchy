#!/bin/bash
# Install everything that exists as a prebuilt aarch64 package.

echo "==> packages"

sudo pacman-key --init 2>/dev/null || true
sudo pacman-key --populate archlinuxarm 2>/dev/null || true

mapfile -t packages < <(grep -v '^#' "$MOARCHY_PATH/moarchy-base.packages" | grep -v '^$')
echo "    installing ${#packages[@]} packages"

sudo pacman -Syu --needed --noconfirm "${packages[@]}"
