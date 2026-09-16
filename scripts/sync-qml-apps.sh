#!/usr/bin/env bash
# Snapshot the Quickshell apps from moarchy-apps into qml-apps/.
#
# The plugins live in a sibling repo and several of them are not on a
# published commit yet, so a GitHub tarball cannot be the input. This copies
# the working tree in front of you: the QML the phone will run, not tests,
# screenshots, or the install-on-device helper.
#
#   ./scripts/sync-qml-apps.sh
#   ./scripts/sync-qml-apps.sh /path/to/moarchy-apps
#
# ui.catalog is a kit review window, not an app, and is left out on purpose.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-$REPO/../moarchy-apps}"
DEST="$REPO/qml-apps"

[[ -d $SRC/plugins ]] || {
  echo "sync-qml-apps: no plugins/ under $SRC" >&2
  exit 1
}
[[ -d $SRC/shared/qs_ui ]] || {
  echo "sync-qml-apps: no shared/qs_ui under $SRC" >&2
  exit 1
}

# Everything but the README, which is this repo's and says what the snapshot
# is. A plain rm -rf of the directory deleted it on every sync.
mkdir -p "$DEST"
find "$DEST" -mindepth 1 -maxdepth 1 ! -name README.md -exec rm -rf {} +
mkdir -p "$DEST/qs_ui"

# The kit every plugin imports as ui/. Tests stay in the source repo.
find "$SRC/shared/qs_ui" -maxdepth 1 \( -name '*.qml' -o -name '*.js' -o -name 'qmldir' \) \
  -exec cp -a {} "$DEST/qs_ui/" \;

copied=0
for dir in "$SRC"/plugins/org.moarchy.*/; do
  id=$(basename "$dir")
  [[ $id == org.moarchy.ui.catalog ]] && continue
  mkdir -p "$DEST/$id"
  # Runtime files only. shell.qml is the standalone Quickshell process, which
  # this package does not launch -- the overlay entry in manifest.json is what
  # omarchy-shell loads.
  find "$dir" -maxdepth 1 \( \
      -name '*.qml' -o -name '*.js' -o -name '*.svg' \
      -o -name 'manifest.json' -o -name '*.desktop' \
    \) ! -name 'shell.qml' -exec cp -a {} "$DEST/$id/" \;
  # bin/ is a command the plugin ships outside the shell -- the editor's
  # moarchy-editor, which $EDITOR runs -- and the package installs it to
  # /usr/bin. Without it the snapshot has an editor that cannot be $EDITOR.
  if [[ -d $dir/bin ]]; then
    mkdir -p "$DEST/$id/bin"
    cp -a "$dir"/bin/. "$DEST/$id/bin/"
  fi
  copied=$((copied + 1))
done

echo "qml-apps: $copied plugins + qs_ui from $SRC"
ls -1d "$DEST"/org.moarchy.*/ | wc -l | awk '{print "  "$1" directories"}'
