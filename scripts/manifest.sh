#!/usr/bin/env bash
# Read manifest.toml -- the version pins. Source this; it defines functions.
#
#   . "$REPO_ROOT/scripts/manifest.sh"
#   ref=$(manifest_get omarchy ref) || exit 1
#
# The `|| exit 1` is not decoration. manifest_get runs inside $(...), so it
# cannot kill its caller by exiting; a caller that drops the check gets an
# empty string and clones at HEAD, which is precisely the failure the pins
# exist to prevent. So the failure is loud on stderr AND non-zero, and every
# call site checks it.
#
# This runs in three places with three different bash versions -- macOS's 3.2
# (flash-sd.sh, provision.sh), the aarch64 build container, and the phone --
# so: no associative arrays, no `mapfile`, nothing but POSIX awk.
#
# It parses the shape manifest.toml is written in, not TOML in general:
# `[section]` headers and `key = "value"` lines, `#` comments, values always
# double-quoted. Anything else it does not see, which is a feature at 100 lines
# of dependency-free parser and a reason to keep the manifest boring.

# Callers may set MANIFEST_FILE. Otherwise look next to this script (the
# container layout, where both are copied into one directory) and then one
# level up (the repo layout, where the manifest is at the root).
if [ -z "${MANIFEST_FILE:-}" ]; then
  _manifest_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  if [ -f "$_manifest_dir/manifest.toml" ]; then
    MANIFEST_FILE="$_manifest_dir/manifest.toml"
  else
    MANIFEST_FILE="$_manifest_dir/../manifest.toml"
  fi
  unset _manifest_dir
fi

# manifest_get <section> <key> -- print the value, or fail loudly.
manifest_get() {
  if [ ! -f "$MANIFEST_FILE" ]; then
    echo "manifest: no such file: $MANIFEST_FILE" >&2
    return 1
  fi

  _manifest_value=$(awk -v want_sec="$1" -v want_key="$2" '
    /^[ \t]*#/ { next }
    /^[ \t]*\[/ {
      sec = $0
      sub(/^[ \t]*\[/, "", sec)
      sub(/\][ \t]*$/, "", sec)
      next
    }
    sec == want_sec && /=/ {
      key = $0
      sub(/=.*/, "", key)
      gsub(/[ \t]/, "", key)
      if (key != want_key) next

      val = $0
      sub(/^[^=]*=[ \t]*/, "", val)
      if (val ~ /^"/) { sub(/^"/, "", val); sub(/".*$/, "", val) }
      else { sub(/[ \t]*#.*$/, "", val); gsub(/^[ \t]+|[ \t]+$/, "", val) }

      print val
      found = 1
      exit
    }
    END { exit(found ? 0 : 1) }
  ' "$MANIFEST_FILE") || {
    echo "manifest: [$1] has no key '$2' in $MANIFEST_FILE" >&2
    return 1
  }

  if [ -z "$_manifest_value" ]; then
    echo "manifest: [$1] $2 is empty in $MANIFEST_FILE" >&2
    return 1
  fi

  printf '%s\n' "$_manifest_value"
}

# manifest_aur_packages -- the names under [aur.*], one per line, in file order.
#
# The AUR half of the package list. docker/build-packages.sh reads it here and
# pkgbuilds/moarchy-meta names the same packages in depends, so pacman resolves
# what used to be resolved by three lists with two of them right (P5).
# manifest_components -- the sections that name a `pkgbuilddir`, in file order.
#
# Our own repos, built from a PKGBUILD they carry themselves. Derived rather
# than listed: docker/build-packages.sh looped over a hardcoded
# `moarchy-keyboard moarchy-store`, which is the second list this file exists to
# abolish -- a component could be pinned here and simply never built, and the
# way you would find out is a package missing from an image.
#
# `pkgbuilddir` is the marker because it is already the thing that makes a
# section buildable: it says where in the clone the PKGBUILD lives. [aur.*]
# pins, [repo], [danctnix] and [builder] do not have one and are not this.
#
# File order is load-bearing and cheap to keep: the keyboard is pinned first
# and is built first, because it is the component whose absence leaves the
# phone with no way to type at all.
manifest_components() {
  if [ ! -f "$MANIFEST_FILE" ]; then
    echo "manifest: no such file: $MANIFEST_FILE" >&2
    return 1
  fi

  _manifest_comps=$(awk '
    /^[ \t]*#/ { next }
    /^[ \t]*\[/ {
      sec = $0
      sub(/^[ \t]*\[/, "", sec)
      sub(/\][ \t]*$/, "", sec)
      next
    }
    /^[ \t]*pkgbuilddir[ \t]*=/ { if (sec != "") print sec }
  ' "$MANIFEST_FILE")

  # Same reasoning as below: empty means the file was unreadable or its shape
  # moved, never that this project has no components of its own.
  if [ -z "$_manifest_comps" ]; then
    echo "manifest: no sections with a pkgbuilddir in $MANIFEST_FILE" >&2
    return 1
  fi

  printf '%s\n' "$_manifest_comps"
}

manifest_aur_packages() {
  if [ ! -f "$MANIFEST_FILE" ]; then
    echo "manifest: no such file: $MANIFEST_FILE" >&2
    return 1
  fi

  _manifest_pkgs=$(awk '
    /^[ \t]*#/ { next }
    /^[ \t]*\[aur\./ {
      sec = $0
      sub(/^[ \t]*\[aur\./, "", sec)
      sub(/\][ \t]*$/, "", sec)
      print sec
    }
  ' "$MANIFEST_FILE")

  # An empty list here means the manifest was unreadable or its shape changed,
  # never that the project builds no packages -- so say so rather than letting
  # a caller loop zero times and report success.
  if [ -z "$_manifest_pkgs" ]; then
    echo "manifest: no [aur.*] sections found in $MANIFEST_FILE" >&2
    return 1
  fi

  printf '%s\n' "$_manifest_pkgs"
}
