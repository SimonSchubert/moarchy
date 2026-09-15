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

rm -rf "$DEST"
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
  copied=$((copied + 1))
done

echo "qml-apps: $copied plugins + qs_ui from $SRC"
ls -1d "$DEST"/org.moarchy.*/ | wc -l | awk '{print "  "$1" directories"}'
