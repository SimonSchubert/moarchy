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

# REBUILD=1 rebuilds everything even when the artifact is already there. It has
# to carry -f as well: without it makepkg refuses the overwrite, which is the
# very refusal this flag exists to get past.
FORCE=()
[ "${REBUILD:-0}" = 1 ] && FORCE=(-f)

failed=()
skipped=()

# Everything this build vouches for, name and hash, written to /out at the end.
produced=()

# already_built <dir> -- true when every file makepkg would produce is already
# in PKGDEST.
#
# makepkg refuses to overwrite an existing artifact and exits non-zero saying
# "A package has already been built", and until now that was recorded as a build
# failure, indistinguishable from a compile error. A full rebuild into a
# directory that already held the last one therefore ended with
#
#   ==> FAILED: moarchy-keyboard yay xdg-terminal-exec ... omarchy-config
#       There is no fallback for moarchy-keyboard: without it the phone
#       has no on-screen keyboard and no hardware one either.
#
# about eight packages that were sitting right there. A build's loudest line
# being routinely wrong is worse than no line: it teaches you to skip it, and
# the next one is real.
#
# --packagelist rather than a guess at the filename: it evaluates the PKGBUILD,
# so it accounts for pkgver(), PKGEXT and PKGDEST. If it cannot be read, say so
# and build -- an unreadable recipe is not a reason to skip one.
already_built() {
  [ "${REBUILD:-0}" = 1 ] && return 1
  local dir="$1" list f
  list=$( cd "$dir" && makepkg --packagelist 2>/dev/null ) || return 1
  [ -n "$list" ] || return 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || return 1
  done <<< "$list"
  return 0
}

# try_makepkg <dir> <args...> -- 0 built, 2 already there, 1 genuinely failed.
#
# The second signal, because --packagelist cannot always answer in advance. A
# VCS package derives its version in pkgver(), which needs the sources fetched,
# so `makepkg --packagelist` for moarchy-store-git says 0.1.0-1 while the build
# produces 0.1.0.r22.c08a073-1. already_built therefore looks for a filename
# that never exists, runs makepkg, and gets the refusal anyway.
#
# So the refusal itself is read. That covers the VCS case and anything else
# --packagelist cannot predict, and it is the only place "has already been
# built" is treated as anything other than a failure.
try_makepkg() {
  local dir="$1"; shift
  local log rc
  log=$(mktemp)
  ( cd "$dir" && makepkg "$@" ) 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  if [ "$rc" = 0 ]; then rm -f "$log"; return 0; fi
  if grep -q "has already been built" "$log"; then rm -f "$log"; return 2; fi
  rm -f "$log"
  return 1
}

# record <dir> -- add what makepkg would name for this recipe to the manifest.
record() {
  local dir="$1" list f
  list=$( cd "$dir" && makepkg --packagelist 2>/dev/null ) || return 0
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] && produced+=("$(basename "$f")")
  done <<< "$list"
}

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

# The components with their own repos. Not AUR packages, so they are not in the
# list below; each names its own PKGBUILD directory in the manifest, and naming
# one is what puts it here -- the loop used to spell out `moarchy-keyboard
# moarchy-store`, so a component could be pinned in manifest.toml and simply
# never built, with a package missing from an image as the way you found out.
# Order is the manifest's, and the keyboard is pinned first because it is the
# component whose absence leaves the phone with no way to type at all.
for component in $(manifest_components); do
  c_url=$(manifest_get "$component" url) || { failed+=("$component"); continue; }
  c_ref=$(manifest_get "$component" ref) || { failed+=("$component"); continue; }
  c_dir=$(manifest_get "$component" pkgbuilddir) || { failed+=("$component"); continue; }

  echo "==> $component @ ${c_ref:0:7}"
  if clone_pinned "$c_url" "/home/builder/$component" "$c_ref" \
       --filter=blob:none --no-checkout; then
    if already_built "/home/builder/$component/$c_dir"; then
      echo "    already in $OUT for this pin -- kept"
      skipped+=("$component")
      record "/home/builder/$component/$c_dir"
    else
      try_makepkg "/home/builder/$component/$c_dir" "${FORCE[@]}" -s --noconfirm --needed
      case $? in
        0) cp "/home/builder/$component/$c_dir"/*.pkg.tar.* "$OUT/" 2>/dev/null || true
           record "/home/builder/$component/$c_dir" ;;
        2) echo "    already in $OUT for this pin -- kept"
           skipped+=("$component"); record "/home/builder/$component/$c_dir" ;;
        *) echo "!! build failed: $component" >&2; failed+=("$component") ;;
      esac
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
  if already_built "/home/builder/$pkg"; then
    echo "    already in $OUT for this pin -- kept"
    skipped+=("$pkg")
    record "/home/builder/$pkg"
  else
    try_makepkg "/home/builder/$pkg" "${FORCE[@]}" -s --noconfirm --needed
    case $? in
      0) cp "/home/builder/$pkg"/*.pkg.tar.* "$OUT/" 2>/dev/null || true
         record "/home/builder/$pkg" ;;
      2) echo "    already in $OUT for this pin -- kept"
         skipped+=("$pkg"); record "/home/builder/$pkg" ;;
      *) echo "!! build failed: $pkg" >&2; failed+=("$pkg") ;;
    esac
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
    if already_built "$d"; then
      echo "    already in $OUT for this version -- kept"
      skipped+=("$p")
      record "$d"
    else
      try_makepkg "$d" "${FORCE[@]}" --nodeps --noconfirm --nocheck
      case $? in
        0) record "$d" ;;
        2) echo "    already in $OUT for this version -- kept"
           skipped+=("$p"); record "$d" ;;
        *) echo "!! build failed: $p" >&2; failed+=("$p") ;;
      esac
    fi
  done
fi

# --- the manifest ----------------------------------------------------------
# What this build vouches for, by name and by hash, so a later step can tell a
# file this build produced from one left behind by an earlier one. A name alone
# is not enough and today proved it three times over: moarchy-meta 0.1.0-1
# existed as two different packages, seven cached .pkg.tar.xz files outlived
# their bytes, and so did a published image. The hash is the part that makes a
# filename mean something.
#
# COMMIT and DIRTY arrive from the host if the caller knows them --
# .dockerignore excludes .git, so there is no repository in here to ask.
{
  echo "# moarchy package build"
  echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "commit=${COMMIT:-unknown}"
  echo "dirty=${DIRTY:-unknown}"
  for f in "${produced[@]}"; do
    [ -f "$OUT/$f" ] || continue
    echo "$(sha256sum "$OUT/$f" | cut -d' ' -f1)  $f"
  done
} > "$OUT/.build-manifest"

echo
echo "==> built into $OUT:"
ls -1 "$OUT" | grep -v '^\.build-manifest$' || true

if (( ${#skipped[@]} )); then
  echo
  echo "==> already present, not rebuilt: ${skipped[*]}"
  echo "    Their pin has not moved and the artifact is in $OUT, so makepkg was"
  echo "    not run. This is not a failure; REBUILD=1 forces one."
fi

if (( ${#failed[@]} )); then
  echo
  echo "==> FAILED: ${failed[*]}" >&2
  echo "    There is no fallback for moarchy-keyboard: without it the phone" >&2
  echo "    has no on-screen keyboard and no hardware one either." >&2
  exit 1
fi
