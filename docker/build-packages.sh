#!/bin/bash
# Build each package that has no aarch64 binary anywhere and drop the resulting
# *.pkg.tar.zst into /out, which install/build-src.sh then installs with
# `pacman -U`.
#
# Every source is fetched at the exact commit named in manifest.toml, never at
# HEAD. Before the pins this cloned everything with `--depth 1` and no ref, so
# two builds a week apart produced different packages and nothing recorded why
# -- see docs/structure.md V2.
set -uo pipefail

OUT=/out
mkdir -p "$OUT"

# Arch Linux ARM's makepkg.conf does not necessarily use PKGEXT=.pkg.tar.zst, so
# never glob for a specific extension -- have makepkg write to $OUT directly.
export PKGDEST="$OUT"

# Dockerfile.builder copies manifest.toml in next to this script's reader.
. /usr/local/share/moarchy/manifest.sh

failed=()

# Clone at a pin and prove it landed there. A checkout that silently resolves
# to something else is the whole class of failure the manifest is for, so this
# compares the result rather than trusting the exit status.
clone_pinned() {   # clone_pinned <url> <dir> <ref> [extra git-clone args...]
  local url="$1" dir="$2" ref="$3"; shift 3
  rm -rf "$dir"
  git clone --quiet "$@" "$url" "$dir" || return 1
  git -C "$dir" checkout --quiet --detach "$ref" || return 1
  local got; got=$(git -C "$dir" rev-parse HEAD)
  if [[ $got != "$ref" ]]; then
    echo "!! $dir: asked for $ref, got $got" >&2
    return 1
  fi
}

# moarchy-keyboard is not an AUR package -- it is its own repo with a PKGBUILD
# in packaging/ -- so it needs its own clause rather than a name in the list
# below. Built first, because it is the one whose absence leaves the phone with
# no way to type at all.
kbd_url=$(manifest_get moarchy-keyboard url) || exit 1
kbd_ref=$(manifest_get moarchy-keyboard ref) || exit 1
kbd_dir=$(manifest_get moarchy-keyboard pkgbuilddir) || exit 1

echo "==> moarchy-keyboard @ ${kbd_ref:0:7}"
if clone_pinned "$kbd_url" /home/builder/moarchy-keyboard "$kbd_ref" \
     --filter=blob:none --no-checkout; then
  if ( cd "/home/builder/moarchy-keyboard/$kbd_dir" && makepkg -s --noconfirm --needed ); then
    cp "/home/builder/moarchy-keyboard/$kbd_dir"/*.pkg.tar.* "$OUT/" 2>/dev/null || true
  else
    echo "!! build failed: moarchy-keyboard -- the phone will have no keyboard" >&2
    failed+=(moarchy-keyboard)
  fi
else
  echo "!! clone failed: moarchy-keyboard" >&2
  failed+=(moarchy-keyboard)
fi

# The package list comes from the manifest's [aur.*] sections, so this script
# has no list of its own to drift out of step with install/build-src.sh.
packages=$(manifest_aur_packages) || exit 1

for pkg in $packages; do
  ref=$(manifest_get "aur.$pkg" ref) || { failed+=("$pkg"); continue; }
  echo "==> $pkg @ ${ref:0:7}"
  # No --filter here: the AUR's git server does not have to support partial
  # clone, and a PKGBUILD repo is a few kilobytes either way.
  if ! clone_pinned "https://aur.archlinux.org/$pkg.git" "/home/builder/$pkg" "$ref"; then
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
