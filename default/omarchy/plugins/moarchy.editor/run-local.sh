#!/bin/bash
# Text Editor on this machine, as a plain Quickshell process.
#
#   plugins/moarchy.editor/run-local.sh
#   MOARCHY_EDITOR_OPEN=$PWD/README.md plugins/moarchy.editor/run-local.sh
#
# The plugin imports its chrome as `ui`, which the installers vendor from
# shared/qs_ui. Nothing vendors it in a checkout, so this does that first and
# then hands shell.qml to quickshell. No omarchy-shell involved: this is the
# same path a package on another distribution would take.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$ROOT/../../shared/qs_ui" && pwd)"

rm -rf "$ROOT/ui"
mkdir -p "$ROOT/ui"
cp "$KIT/"*.qml "$KIT/"*.js "$KIT/qmldir" "$ROOT/ui/"

exec quickshell -p "$ROOT/shell.qml" "$@"
