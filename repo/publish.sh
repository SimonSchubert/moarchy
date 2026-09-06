#!/usr/bin/env bash
# Upload the signed repository so phones can `pacman -Syu` from it.
#
#   ./repo/publish.sh
#
# One fixed release tag, re-uploaded rather than re-created, so the Server URL
# in every phone's pacman.conf never changes. Version tags (v0.1.0) stay for
# images, which are a different thing: an image is a moment, a repo is a
# moving target.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
. scripts/manifest.sh

TAG=$(manifest_get repo tag)       || exit 1
SERVER=$(manifest_get repo server) || exit 1
DIST="${DIST:-$REPO_ROOT/repo/dist}"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }

[ -d "$DIST" ] || die "no $DIST -- run ./repo/build.sh first"
command -v gh >/dev/null || die "gh is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not logged in"

# The release is a container for files, not an announcement: prerelease so it
# does not displace the newest image as "Latest" on the repository page, and a
# body that says what it is, because a bare tag called "repo" invites someone
# to delete it.
if ! gh release view "$TAG" >/dev/null 2>&1; then
  say "creating the $TAG release"
  gh release create "$TAG" --prerelease --title "Package repository" --notes \
"Not a release. This holds the pacman repository so phones can update without
reflashing; the assets are replaced in place, so the URL never changes.

    [moarchy]
    Server = $SERVER

Images are the versioned releases. Deleting this tag breaks \`pacman -Syu\` on
every phone in the field."
fi

say "uploading $(ls -1 "$DIST" | wc -l | tr -d ' ') files"
# --clobber, because this is the same tag every time and the whole point is
# that the URLs are stable while the contents move.
gh release upload "$TAG" "$DIST"/* --clobber

say "verifying the database is actually reachable"
NAME=$(manifest_get repo name) || exit 1
code=$(curl -sL -o /dev/null -w '%{http_code}' "$SERVER/$NAME.db")
[ "$code" = 200 ] || die "$SERVER/$NAME.db returned HTTP $code"
info "$SERVER/$NAME.db -> 200"

say "done"
info "on a phone:  sudo pacman -Sy && sudo pacman -Su"
