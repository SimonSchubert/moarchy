#!/bin/bash
# Build each AUR package and drop the resulting *.pkg.tar.zst into /out,
# which install/build-src.sh then installs with `pacman -U`.
set -uo pipefail

OUT=/out
mkdir -p "$OUT"

# Arch Linux ARM's makepkg.conf does not necessarily use PKGEXT=.pkg.tar.zst, so
# never glob for a specific extension -- have makepkg write to $OUT directly.
export PKGDEST="$OUT"

PACKAGES=(yay elephant walker xdg-terminal-exec ttf-ia-writer)
failed=()

for pkg in "${PACKAGES[@]}"; do
  echo "==> $pkg"
  rm -rf "/home/builder/$pkg"
  if ! git clone --depth 1 "https://aur.archlinux.org/$pkg.git" "/home/builder/$pkg"; then
    echo "!! clone failed: $pkg" >&2
    failed+=("$pkg")
    continue
  fi
  if ( cd "/home/builder/$pkg" && makepkg -s --noconfirm --needed ); then
    cp "/home/builder/$pkg"/*.pkg.tar.* "$OUT/" 2>/dev/null || true
  else
    echo "!! build failed: $pkg" >&2
    failed+=("$pkg")
  fi
done

echo
echo "==> built into $OUT:"
ls -1 "$OUT" || true

if (( ${#failed[@]} )); then
  echo
  echo "==> FAILED: ${failed[*]}" >&2
  echo "    install/build-src.sh falls back to fuzzel if walker is missing." >&2
  exit 1
fi
