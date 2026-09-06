#!/usr/bin/env bash
# Assemble the signed pacman repository from the built packages.
#
#   ./scripts/provision.sh build   # produces packages/
#   ./repo/build.sh                # -> repo/dist/ (moarchy.db + signed packages)
#   ./repo/publish.sh              # uploads it
#
# Everything a phone needs to run `pacman -Syu` lives in repo/dist afterwards:
# every package, a detached signature per package, and the database with its
# own signature. That is what lets the stanza say SigLevel = Required rather
# than trusting HTTPS alone with code that installs as root.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
. scripts/manifest.sh

NAME=$(manifest_get repo name)   || exit 1
KEYID=$(manifest_get repo keyid) || exit 1
DIST="${DIST:-$REPO_ROOT/repo/dist}"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }

compgen -G "packages/*.pkg.tar.*" >/dev/null ||
  die "no packages -- run ./scripts/provision.sh build first"
gpg --list-secret-keys "$KEYID" >/dev/null 2>&1 ||
  die "no secret key $KEYID -- run ./repo/genkey.sh, or import your backup"

# Rebuilt from scratch every time. repo-add updates a database in place, and an
# incremental one accumulates entries for packages that are no longer shipped:
# a phone would then be offered a version whose file has been deleted, and the
# upgrade fails at download with a 404 rather than anywhere useful.
say "assembling $DIST"
rm -rf "$DIST"; mkdir -p "$DIST"
cp packages/*.pkg.tar.* "$DIST/"
info "$(ls -1 "$DIST" | wc -l | tr -d ' ') packages"

# The armored public key, published beside the packages.
#
# Bootstrapping needs it: moarchy-keyring is itself signed, so pacman refuses
# to install it without already holding the key --
#   error: key "..." could not be looked up remotely
#   error: required key missing from keyring
# A phone adding this repo by hand imports this file first, and everything
# after that validates normally. The image side does not hit it, because
# pacstrap installs the keyring at build time from a local repo.
cp "$REPO_ROOT/repo/keyring/moarchy.asc" "$DIST/moarchy.asc"

say "signing packages"
# Detached, one per package, which is what SigLevel = Required checks. --yes so
# a rebuild overwrites the previous signature rather than prompting.
for p in "$DIST"/*.pkg.tar.*; do
  case "$p" in *.sig) continue ;; esac
  gpg --detach-sign --use-agent --no-armor --local-user "$KEYID" --yes "$p"
done
info "$(ls -1 "$DIST"/*.sig | wc -l | tr -d ' ') signatures"

say "building the database"
# repo-add runs in a container -- it is pacman tooling and does not exist on
# macOS -- but WITHOUT --sign. gpg 2.4 keeps public keys in keyboxd's
# pubring.db, which does not travel by bind-mounting ~/.gnupg: repo-add inside
# the container reports "The key ... does not exist in your keyring" while the
# same key signs fine on the host. Signing the database here afterwards is also
# the better arrangement -- the private key never enters a container.
docker run --rm --platform linux/arm64 -v "$DIST:/dist" \
  --entrypoint bash moarchy-image -c "
    set -e
    cd /dist
    # *.pkg.tar.* also matches the .sig files signed a step earlier, and
    # repo-add rejects each one as 'not a package file' and then produces no
    # database at all. Build the list explicitly.
    pkgs=()
    for f in *.pkg.tar.*; do
      case \"\$f\" in *.sig) continue ;; esac
      pkgs+=(\"\$f\")
    done
    repo-add --quiet '$NAME.db.tar.gz' \"\${pkgs[@]}\" 2>&1 | tail -3
  " || die "repo-add failed"
[ -f "$DIST/$NAME.db.tar.gz" ] || die "repo-add produced no database"

say "flattening symlinks"
# repo-add leaves .db and .files as symlinks to the .tar.gz. Symlinks do not
# survive an upload as release assets -- they would arrive as text files
# containing a filename -- so resolve them into real files.
for l in "$DIST/$NAME.db" "$DIST/$NAME.files"; do
  [ -L "$l" ] || continue
  t=$(readlink "$l"); rm "$l"; cp "$DIST/$t" "$l"
  info "$(basename "$l") <- $t"
done

say "signing the database"
# Both names, and this is not redundant: pacman fetches `$repo.db` and then
# `$repo.db.sig`, while repo-add's own tooling refers to the .tar.gz. Signing
# only one leaves the other unverifiable.
for f in "$NAME.db" "$NAME.db.tar.gz" "$NAME.files" "$NAME.files.tar.gz"; do
  [ -f "$DIST/$f" ] || continue
  gpg --detach-sign --no-armor --local-user "$KEYID" --yes "$DIST/$f"
  info "$f.sig"
done

say "done"
info "$(du -sh "$DIST" | cut -f1) in $DIST"
ls -1 "$DIST" | grep -E "\.db|\.files" | sed 's/^/    /'
