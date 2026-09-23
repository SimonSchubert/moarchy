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

# --- root, and why this script now has to know whether it is ----------------
#
# This container starts as ROOT and drops to `builder` for every makepkg. It
# used to start as `builder` and reach for `sudo`, and that cannot work in a
# rootless container: the kernel forces MS_NOSUID on a mount created by an
# unprivileged user namespace, so the setuid bit on /usr/bin/sudo is ignored
# and every `sudo` fails with
#
#   sudo: effective uid is not 0, is /usr/sbin/sudo on a file system with
#         the 'nosuid' option set ...
#
# No flag fixes it -- --privileged, --cap-add=SETUID and no-new-privileges=false
# were all measured and none of them restores setuid, because the restriction
# is the kernel's and not the runtime's. The only way to have root in a
# rootless container is to already BE root in its user namespace.
#
# makepkg still refuses to run as root, and rightly, so the split is: root does
# the privileged half (refresh the databases, install dependencies) and
# `builder` does the build. mp() below is the only place makepkg is invoked.
#
# Running as root is equally correct under Docker, where it is what the daemon
# gives you anyway, so there is one code path rather than two.
AS_ROOT=0; [ "$(id -u)" = 0 ] && AS_ROOT=1

# run_root <cmd...> -- the privileged half, whichever way we got here.
run_root() { if [ "$AS_ROOT" = 1 ]; then "$@"; else sudo "$@"; fi; }

# --- $OUT ownership ---------------------------------------------------------
#
# PKGDEST is $OUT, so `builder` writes packages straight into the bind mount --
# which means the mount has to be writable by `builder` while the build runs,
# and owned by whoever owns it on the host once it stops.
#
# Both halves are needed and the second is easy to forget. Under rootless
# podman the host user maps to container root, so a file `builder` creates
# belongs to a SUBUID on the host -- one the user cannot read or delete without
# `podman unshare`. Under Docker the same chown would hand the directory to
# whatever uid 1000 is there.
#
# So: remember what $OUT looked like, lend it to `builder`, and give it back on
# the way out however we leave. Restoring the ORIGINAL owner rather than a
# hardcoded uid is what makes this correct on both engines -- it is 0 under
# rootless podman and the invoking user under Docker, and neither is written
# down anywhere.
# If this container is SIGKILLed the trap does not run and $OUT is left owned
# by a subuid, which on the host looks like a packages/ directory the user
# cannot touch. It is not lost -- recover it from outside with:
#
#   podman unshare chown -R 0:0 packages
#
# (inside `podman unshare` the host user IS uid 0, which is the whole trick).
if [ "$AS_ROOT" = 1 ]; then
  _out_uid=$(stat -c %u "$OUT"); _out_gid=$(stat -c %g "$OUT")
  _give_out_back() { chown -R "$_out_uid:$_out_gid" "$OUT" 2>/dev/null || true; }
  trap _give_out_back EXIT INT TERM
  chown -R builder:builder "$OUT" 2>/dev/null || true
fi

# mp <makepkg args...> -- run makepkg, never as root.
#
# `runuser -u builder --` rather than `su builder -c`, because the latter goes
# through a shell and would re-quote every argument.
#
# --preserve-environment, because PKGDEST and the rest of this script's
# environment have to reach makepkg -- but then HOME is explicitly put back,
# and that is not tidiness. Preserving the environment preserves root's
# HOME=/root, so everything makepkg shells out to goes looking there:
#
#   warning: unable to access '/root/.config/git/ignore': Permission denied
#
# Git only warns. gpg does not -- it wants a writable GNUPGHOME to verify a
# source signature -- and makepkg keeps its own caches under $HOME. Leaving it
# pointing at a directory `builder` cannot read is a failure waiting for the
# first PKGBUILD with a validpgpkeys line.
mp() {
  if [ "$AS_ROOT" = 1 ]; then
    runuser -u builder --preserve-environment -- \
      env HOME=/home/builder makepkg "$@"
  else
    makepkg "$@"
  fi
}

# as_builder_dir <dir> -- hand a freshly-cloned tree to the user who builds it.
# Only meaningful when root did the cloning.
as_builder_dir() {
  [ "$AS_ROOT" = 1 ] && chown -R builder:builder "$1" 2>/dev/null
  return 0
}

# sync_deps <dir> -- install a recipe's declared dependencies, as root.
#
# This replaces makepkg's own `-s`, which shells out to sudo and therefore
# cannot work here. The dependency list comes from makepkg itself
# (--printsrcinfo, run as `builder` like every other makepkg) rather than from
# parsing the PKGBUILD, so version constraints and split packages are handled
# by the thing that understands them.
#
# The `sed` strips version constraints -- `glib2>=2.80` is not a package name.
# It matches depends, makedepends and checkdepends, including their
# architecture-suffixed forms (`depends_aarch64`), and NOT optdepends, whose
# values are "name: description" and would be installed as garbage. Checked
# against a hand-written .SRCINFO covering all of those.
#
# checkdepends is in the list because these recipes are built WITHOUT
# --nocheck, so makepkg may run check() and would otherwise reach for a tool
# that was never installed.
#
# Installed in one transaction, then one at a time if that fails. The retry is
# not belt and braces: `pacman -S a b c` is all-or-nothing, so a single name
# pacman cannot resolve -- a virtual provide, or a dependency that has been
# renamed upstream -- throws away every other dependency with it, and the build
# then fails on something unrelated to the name that was actually wrong.
# One at a time, the bad name is the only casualty and it is named.
#
# Never fatal either way: a dependency that is genuinely missing should fail at
# makepkg, with makepkg's message naming it, rather than here with pacman's.
sync_deps() {
  [ "$AS_ROOT" = 1 ] || return 0
  local dir="$1" deps d
  deps=$( cd "$dir" && mp --printsrcinfo 2>/dev/null |
          sed -n 's/^[[:space:]]*\(make\|check\)\?depends[^=]*= *//p' |
          sed 's/[<>=].*$//' | sort -u | tr '\n' ' ' )
  [ -n "${deps// /}" ] || return 0
  echo "    deps: $deps"
  if pacman -S --needed --noconfirm --asdeps $deps >/dev/null 2>&1; then
    return 0
  fi
  echo "    (batch install failed; retrying one at a time)"
  for d in $deps; do
    pacman -S --needed --noconfirm --asdeps "$d" >/dev/null 2>&1 ||
      echo "    !! could not install $d"
  done
  return 0
}

# Dockerfile.builder copies manifest.toml in next to this script's reader.
. /usr/local/share/moarchy/manifest.sh

# Refresh the databases before anything asks them for a dependency.
#
# `pacman -Syu` runs in the Dockerfile, but that is a LAYER, and the layer is
# cached: nothing in the Dockerfile changes between releases, so the database
# baked into it is as old as the last time the image was rebuilt from scratch.
# Arch mirrors carry one version of a package and delete the rest, so a
# fortnight-old database names files that are no longer there.
#
# That is not a soft failure. `makepkg -s` installs its dependencies from
# whatever database is present, and one 404 fails the WHOLE transaction, so
# every dependency goes unmet and the build ends at "Could not resolve all
# dependencies" -- naming qt6-base and five others that are all perfectly
# available. The line that says why is a `libwacom-2.19.1-1 ... 404` thirteen
# mirrors up, and it reads as a mirror problem rather than a stale index.
#
# -Syu and not -Sy: a refresh without the upgrade is the partial-upgrade state
# Arch refuses to support, and it produces the same 404 one library deeper.
# Failure is not fatal here -- an offline rebuild of packages that are all
# already in $OUT should still skip its way to a clean exit -- so the run that
# actually needs a package it cannot get fails at makepkg, with makepkg's
# reason, rather than here with a network one.
echo "==> refreshing pacman databases"
run_root pacman -Syu --noconfirm >/dev/null 2>&1 ||
  echo "!! could not refresh the databases -- continuing on the cached ones"

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
  list=$( cd "$dir" && mp --packagelist 2>/dev/null ) || return 1
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
  # makepkg's -s installs dependencies with sudo, which a rootless container
  # cannot do (see the AS_ROOT note at the top). When root is orchestrating,
  # install them here instead and hand makepkg --nodeps -- the dependencies
  # are present either way, so the build sees no difference.
  local args=() want_deps=0
  for a in "$@"; do
    case "$a" in
      -s|--syncdeps) want_deps=1 ;;
      *) args+=("$a") ;;
    esac
  done
  if [ "$want_deps" = 1 ]; then
    if [ "$AS_ROOT" = 1 ]; then
      sync_deps "$dir"
      args+=(--nodeps)
    else
      args+=(-s)
    fi
  fi
  set -- "${args[@]}"
  log=$(mktemp)
  ( cd "$dir" && mp "$@" ) 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  if [ "$rc" = 0 ]; then rm -f "$log"; return 0; fi
  if grep -q "has already been built" "$log"; then rm -f "$log"; return 2; fi
  rm -f "$log"
  return 1
}

# record <dir> -- add what makepkg would name for this recipe to the manifest.
record() {
  local dir="$1" list f
  list=$( cd "$dir" && mp --packagelist 2>/dev/null ) || return 0
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
       --filter=blob:none --no-checkout &&
     as_builder_dir "/home/builder/$component"; then
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
  if ! { clone_pinned "https://aur.archlinux.org/$pkg.git" "/home/builder/$pkg" "$ref" &&
         as_builder_dir "/home/builder/$pkg"; }; then
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

  # --- which devices this build is for --------------------------------------
  #
  # DEVICES is a space-separated list of codenames ("fp4", "sargo fp4"). Unset
  # -- the default -- builds everything, which is what every build did before
  # this existed and what a release still does.
  #
  # It exists because an in-repo package can be exclusive to one handset, and
  # the most expensive package in the tree is exactly that: a KERNEL. With two
  # phones supported there are two of them, and on an emulated host building
  # the one you are not flashing is hours spent on nothing. Naming the target
  # skips it.
  #
  # The skip list is built from the OTHER devices' exclusive-packages, minus
  # anything the target also claims -- so a package two devices share is kept
  # even if both list it. Shared packages (qbootctl, bootmac,
  # moarchy-qcom-modem, the shell itself) are in nobody's list and are always
  # built.
  _skip=""
  if [ -n "${DEVICES:-}" ]; then
    _keep=""
    for _dev in $DEVICES; do
      _keep="$_keep $(manifest_get "device.$_dev" exclusive-packages 2>/dev/null)"
    done
    for _dev in $(manifest_devices); do
      case " $DEVICES " in *" $_dev "*) continue ;; esac
      for _p in $(manifest_get "device.$_dev" exclusive-packages 2>/dev/null); do
        case " $_keep " in *" $_p "*) continue ;; esac
        _skip="$_skip $_p"
      done
    done
    echo "==> building for: $DEVICES"
    [ -n "$_skip" ] && echo "    skipping other devices' packages:$_skip"
  fi

  # --- the ones other in-repo packages build AGAINST ------------------------
  #
  # This loop walks pkgbuilds/ alphabetically, and alphabetical order is not
  # dependency order: pil-squasher sorts 16th while firmware-moarchy-fp4,
  # whose build() calls it, sorts 3rd. So anything named in the manifest's
  # [build] install-first is built and INSTALLED before the walk starts.
  #
  # Installed, not merely built -- the point is to have the binary on PATH for
  # a later package's build(), which a .pkg.tar in $OUT does not provide.
  # `pacman -U` rather than adding it to the image, because it is this repo's
  # package pinned by this repo's manifest; baking it into the builder would
  # be a second copy that drifts.
  for _first in $(manifest_get build install-first 2>/dev/null); do
    _fd="/home/builder/repo/pkgbuilds/$_first"
    [ -d "$_fd" ] || { echo "!! install-first names $_first, which is not in pkgbuilds/" >&2; continue; }
    case " $_skip " in *" $_first "*) continue ;; esac
    echo "==> $_first (in-repo, needed by a later build)"
    if ! already_built "$_fd"; then
      try_makepkg "$_fd" "${FORCE[@]}" --nodeps --noconfirm --nocheck
      case $? in
        0|2) record "$_fd" ;;
        *) echo "!! build failed: $_first" >&2; failed+=("$_first") ;;
      esac
    else
      echo "    already in $OUT for this version -- kept"
      record "$_fd"
    fi
    # Install whatever it produced, so the later build() can call it.
    _fp=$(ls -1t "$OUT"/"$_first"-*.pkg.tar.* 2>/dev/null | head -1)
    if [ -n "$_fp" ]; then
      run_root pacman -U --noconfirm --needed "$_fp" >/dev/null 2>&1 &&
        echo "    installed $(basename "$_fp")" ||
        echo "    !! could not install $(basename "$_fp") -- a later build may not find it"
    fi
    _done="${_done:-} $_first"   # do not build it a second time in the walk below
  done

  for d in /home/builder/repo/pkgbuilds/*/; do
    p=$(basename "$d")
    # Two reasons to pass over a package here, and they are different things
    # to be told: it belongs to a phone this build is not for, or it was
    # already built above because something else needs it installed.
    case " ${_done:-} " in
      *" $p "*) continue ;;
    esac
    case " $_skip " in
      *" $p "*) echo "==> $p (in-repo) -- not for $DEVICES, skipped"; continue ;;
    esac
    echo "==> $p (in-repo)"
    if already_built "$d"; then
      echo "    already in $OUT for this version -- kept"
      skipped+=("$p")
      record "$d"
    else
      # Install this recipe's declared dependencies first, exactly as the
      # component and AUR builds do.
      #
      # These are still built with --nodeps, and the builder image still
      # carries the common tools -- what changed is that the image is now an
      # optimisation rather than the only source of truth. It had been the
      # only one, and that failed twice in one evening: megapixels stopped on
      # libfeedback, and when the image gained feedbackd it stopped again on
      # zbar, with eight more behind it. Each round cost an image rebuild and
      # a full pass to discover exactly one name.
      #
      # A PKGBUILD already declares what it needs. Reading that is strictly
      # better than maintaining a second copy of the same list in a Dockerfile
      # where nothing checks the two against each other.
      sync_deps "$d"
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
