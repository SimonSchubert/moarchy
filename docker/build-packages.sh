#!/bin/bash
# Build every package this project ships and drop the results into /out.
#
# Three kinds: the two components with their own repos (keyboard, store), the
# AUR packages with no aarch64 binary anywhere, and the packages defined in
# this repo under pkgbuilds/. `pacman -U /out/*` then installs the phone.
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

# The two components with their own repos. Not AUR packages, so they are not
# in the list below; each names its own PKGBUILD directory in the manifest.
# The keyboard is built first, because it is the one whose absence leaves the
# phone with no way to type at all.
for component in moarchy-keyboard moarchy-store; do
  c_url=$(manifest_get "$component" url) || { failed+=("$component"); continue; }
  c_ref=$(manifest_get "$component" ref) || { failed+=("$component"); continue; }
  c_dir=$(manifest_get "$component" pkgbuilddir) || { failed+=("$component"); continue; }

  echo "==> $component @ ${c_ref:0:7}"
  if clone_pinned "$c_url" "/home/builder/$component" "$c_ref" \
       --filter=blob:none --no-checkout; then
    if ( cd "/home/builder/$component/$c_dir" && makepkg -s --noconfirm --needed ); then
      cp "/home/builder/$component/$c_dir"/*.pkg.tar.* "$OUT/" 2>/dev/null || true
    else
      echo "!! build failed: $component" >&2
      failed+=("$component")
    fi
  else
    echo "!! clone failed: $component" >&2
    failed+=("$component")
  fi
done

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

# The packages this repo defines. Built last: moarchy-meta depends on every
# name above, and makepkg checks depends even though it does not install them.
if [ -d /repo/pkgbuilds ]; then
  # The whole repo, not just pkgbuilds/: each PKGBUILD reads its pins through
  # $startdir/../../scripts/manifest.sh, and moarchy's package() copies bin/,
  # default/ and config/ out of the tree. Copied rather than built in place
  # because /repo is mounted read-only and makepkg writes src/ and pkg/.
  rm -rf /home/builder/repo
  cp -a /repo /home/builder/repo
  chown -R builder /home/builder/repo

  for d in /home/builder/repo/pkgbuilds/*/; do
    p=$(basename "$d")
    echo "==> $p (in-repo)"
    if ! ( cd "$d" && makepkg --nodeps --noconfirm --nocheck ); then
      echo "!! build failed: $p" >&2
      failed+=("$p")
    fi
  done
fi

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
