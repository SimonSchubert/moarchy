#!/bin/bash
# Build each AUR package and drop the resulting *.pkg.tar.zst into /out,
# which install/build-src.sh then installs with `pacman -U`.
set -uo pipefail

OUT=/out
mkdir -p "$OUT"

# Arch Linux ARM's makepkg.conf does not necessarily use PKGEXT=.pkg.tar.zst, so
# never glob for a specific extension -- have makepkg write to $OUT directly.
export PKGDEST="$OUT"

PACKAGES=(yay xdg-terminal-exec ttf-ia-writer)
failed=()

# moarchy-keyboard is not an AUR package -- it is its own repo with a PKGBUILD
# in packaging/ -- so it needs its own clause rather than a name in the list
# above. Built first, because it is the one whose absence leaves the phone with
# no way to type at all.
echo "==> moarchy-keyboard"
rm -rf /home/builder/moarchy-keyboard
if git clone --depth 1 https://github.com/SimonSchubert/moarchy-keyboard \
     /home/builder/moarchy-keyboard; then
  if ( cd /home/builder/moarchy-keyboard/packaging && makepkg -s --noconfirm --needed ); then
    cp /home/builder/moarchy-keyboard/packaging/*.pkg.tar.* "$OUT/" 2>/dev/null || true
  else
    echo "!! build failed: moarchy-keyboard -- the phone will have no keyboard" >&2
    failed+=(moarchy-keyboard)
  fi
else
  echo "!! clone failed: moarchy-keyboard" >&2
  failed+=(moarchy-keyboard)
fi

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
  echo "    There is no fallback for moarchy-keyboard: without it the phone" >&2
  echo "    has no on-screen keyboard and no hardware one either." >&2
  exit 1
fi
