#!/usr/bin/env bash
# Read a directory of built packages. Source this; it defines functions.
#
#   . "$REPO_ROOT/scripts/pkgset.sh"
#   pkgset_unique packages || exit 1
#
# docker/build-packages.sh writes into packages/ and never clears it, which is
# right -- a build that fails halfway should not cost the packages that already
# built. The consequence is that the directory accumulates: bump a pkgrel, or
# move a component's pin, and yesterday's file sits beside today's under a
# different version.
#
# Nothing downstream notices. `repo-add ... *.pkg.tar.*` takes whichever the
# shell's glob puts last, `pacstrap` then installs whatever the database ended
# up naming, and both are decided by lexicographic order rather than by anyone.
# It has already happened twice: the published `repo` release carries
# moarchy-store-git r19 *and* r22, and repo/build.sh grew its PKGDIR override
# because a moarchy-0.1.0-2 from another session's work in progress was one
# glob away from being released.
#
# So an ambiguous directory is refused, and the caller is told which files
# disagree. Choosing between them is not something a script should do quietly.
#
# Bash 3.2 (macOS) as well as the build container: no associative arrays.

# pkgset_name <path> -- the pkgname out of an Arch package filename.
#
# The filename is $pkgname-$pkgver-$pkgrel-$arch.pkg.tar.$ext, and pkgname is
# the only one of those four that may itself contain a hyphen, so the other
# three come off the end. `lcl-gui-bin-4.7.1-2-aarch64` -> `lcl-gui-bin`.
pkgset_name() {
  printf '%s\n' "${1##*/}" | sed -e 's/\.pkg\.tar\..*$//' -e 's/-[^-]*-[^-]*-[^-]*$//'
}

# pkgset_unique <dir> -- 0 if every package name appears once, 1 otherwise.
# Prints the offending files on stderr; says nothing when the set is clean.
pkgset_unique() {
  _pkgset_dir="$1"
  _pkgset_dupes=$(
    for _pkgset_f in "$_pkgset_dir"/*.pkg.tar.*; do
      [ -e "$_pkgset_f" ] || continue
      case "$_pkgset_f" in *.sig) continue ;; esac
      pkgset_name "$_pkgset_f"
    done | sort | uniq -d
  )
  [ -z "$_pkgset_dupes" ] && return 0

  echo "!! $_pkgset_dir holds more than one version of the same package:" >&2
  for _pkgset_n in $_pkgset_dupes; do
    printf '   %s\n' "$_pkgset_n" >&2
    for _pkgset_f in "$_pkgset_dir"/*.pkg.tar.*; do
      case "$_pkgset_f" in *.sig) continue ;; esac
      [ "$(pkgset_name "$_pkgset_f")" = "$_pkgset_n" ] &&
        printf '     %s\n' "${_pkgset_f##*/}" >&2
    done
  done
  echo "   Delete the ones this release is not made of, or stage the intended" >&2
  echo "   set elsewhere and point PKGDIR at it." >&2
  return 1
}

# pkgset_list <dir> -- every package, one per line, for a build to print.
# What went in is worth saying out loud; a stale file is far easier to catch in
# a list of eleven names than in a count of eleven.
pkgset_list() {
  for _pkgset_f in "$1"/*.pkg.tar.*; do
    [ -e "$_pkgset_f" ] || continue
    case "$_pkgset_f" in *.sig) continue ;; esac
    printf '%s\n' "${_pkgset_f##*/}"
  done | sort
}
