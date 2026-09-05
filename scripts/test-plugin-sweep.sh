#!/usr/bin/env bash
# Verify that install/config.sh's stale-plugin sweep deletes what it should and
# nothing else -- above all, that it deletes nothing when it cannot read the
# repo.
#
# This is the only rm -rf in the repo aimed at a directory the user owns, and
# three of its four branches are reachable only by breaking the environment on
# purpose, so nobody will exercise them by hand. An earlier version wiped every
# plugin on the device when MOARCHY_PATH was unset.
#
# Runs anywhere bash does -- including macOS, with no device attached. The sweep
# is extracted from install/config.sh between its plugin-sweep markers rather
# than copied here, so this tests the shipping code and fails loudly if it moves.
#
#   ./scripts/test-plugin-sweep.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

SWEEP="$WORK/sweep.sh"
{
  # install.sh sources config.sh under these flags; -u is deliberately absent,
  # which is what lets an unset MOARCHY_PATH expand to nothing.
  echo '#!/usr/bin/env bash'
  echo 'set -eEo pipefail'
  awk '/^# >>> plugin-sweep/{f=1} f{print} /^# <<< plugin-sweep/{exit}' \
    "$REPO_ROOT/install/config.sh"
} > "$SWEEP"

if ! grep -q '^# <<< plugin-sweep' "$SWEEP"; then
  echo "!! could not extract the sweep from install/config.sh -- markers gone?" >&2
  exit 1
fi

REPO_IDS=$(ls "$REPO_ROOT/default/omarchy/plugins")
[[ -n $REPO_IDS ]] || { echo "!! no plugins in the repo to test against" >&2; exit 1; }

# A device as it would actually be: every plugin the repo ships, one we used to
# ship, and one the user installed from somewhere else.
setup() {
  rm -rf "$WORK/home"
  mkdir -p "$WORK/home/.config/omarchy/plugins" "$WORK/home/.local/share/applications"
  # mobileomarchy.shade is the rename migration: a phone provisioned before
  # 2026-09-05 has the whole set under the old namespace, and they are stale by
  # definition because the repo now ships moarchy.*. Retire this fixture when
  # the legacy globs come out of install/config.sh.
  for id in $REPO_IDS "moarchy.gone" "mobileomarchy.shade" "someoneelse.widget"; do
    mkdir -p "$WORK/home/.config/omarchy/plugins/$id"
  done
  printf '[Desktop Entry]\nName=Device\nX-Moarchy-Plugin=moarchy.device\n' \
    > "$WORK/home/.local/share/applications/device.desktop"
  # Deliberately misnamed: the sweep must match on the marker, not the filename.
  printf '[Desktop Entry]\nName=Gone\nX-Moarchy-Plugin=moarchy.gone\n' \
    > "$WORK/home/.local/share/applications/not-obviously-ours.desktop"
  # Written by an install from before the rename, so it carries the old marker
  # key. An entry whose marker we no longer read is an entry nothing can ever
  # clean up -- a drawer icon that launches nothing, permanently.
  printf '[Desktop Entry]\nName=Shade\nX-MobileOmarchy-Plugin=mobileomarchy.shade\n' \
    > "$WORK/home/.local/share/applications/legacy.desktop"
  printf '[Desktop Entry]\nName=Firefox\n' \
    > "$WORK/home/.local/share/applications/firefox.desktop"
}

installed() { ls "$WORK/home/.config/omarchy/plugins" 2>/dev/null | tr '\n' ' '; }
entries()   { ls "$WORK/home/.local/share/applications" 2>/dev/null | tr '\n' ' '; }

pass=0 fail=0
check() {  # check <label> <expected> <actual>
  if [[ $2 == "$3" ]]; then
    printf "  ok   %s\n" "$1"; pass=$((pass + 1))
  else
    printf "  FAIL %s\n       expected: %s\n       actual:   %s\n" "$1" "$2" "$3"
    fail=$((fail + 1))
  fi
}

untouched_plugins="$(printf '%s\n' $REPO_IDS moarchy.gone mobileomarchy.shade someoneelse.widget | sort | tr '\n' ' ')"
untouched_entries="device.desktop firefox.desktop legacy.desktop not-obviously-ours.desktop "
swept_plugins="$(printf '%s\n' $REPO_IDS someoneelse.widget | sort | tr '\n' ' ')"
swept_entries="device.desktop firefox.desktop "

# --- the three branches that must delete nothing ----------------------------
# Each is a real way this has gone wrong: the env regressions in provision.sh's
# systemd-run invocation cost a run apiece to find (docs/build-log.md), and a
# provision racing another session's git checkout in the shared worktree can see
# default/omarchy/plugins/ half written.

echo "==> MOARCHY_PATH unset"
setup; HOME="$WORK/home" bash "$SWEEP" >/dev/null 2>&1
check "nothing deleted" "$untouched_plugins" "$(installed)"
check "no entry deleted" "$untouched_entries" "$(entries)"

echo "==> MOARCHY_PATH points somewhere that does not exist"
setup; HOME="$WORK/home" MOARCHY_PATH="$WORK/nope" bash "$SWEEP" >/dev/null 2>&1
check "nothing deleted" "$untouched_plugins" "$(installed)"

echo "==> plugins directory present but empty (a checkout caught mid-flight)"
mkdir -p "$WORK/empty/default/omarchy/plugins"
setup; HOME="$WORK/home" MOARCHY_PATH="$WORK/empty" bash "$SWEEP" >/dev/null 2>&1
check "nothing deleted" "$untouched_plugins" "$(installed)"

# --- and the branch that must delete, precisely ------------------------------

echo "==> healthy repo"
setup; HOME="$WORK/home" MOARCHY_PATH="$REPO_ROOT" bash "$SWEEP" >/dev/null 2>&1
check "stale plugin gone, ours and third-party kept" "$swept_plugins" "$(installed)"
check "stale entry gone by marker, not by name"      "$swept_entries" "$(entries)"

echo
echo "==> $pass passed, $fail failed"
(( fail == 0 ))
