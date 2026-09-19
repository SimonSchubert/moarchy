#!/bin/bash
# Files on this machine, as a plain Quickshell process.
#
#   plugins/org.moarchy.files/run-local.sh
#
# The plugin imports its chrome as `ui`, which the installers vendor from
# shared/qs_ui. Nothing vendors it in a checkout, so this does that first and
# then hands shell.qml to quickshell. No omarchy-shell involved: this is the
# same path a package on another distribution would take.
#
# It opens on your real home directory and it can really delete things -- into
# the same freedesktop trash your desktop uses, which is the point, but point
# it somewhere else if that is not what you wanted:
#
#   MOARCHY_FILES_HOME=/tmp/tree MOARCHY_FILES_PATH=/tmp/tree run-local.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$ROOT/../../shared/qs_ui" && pwd)"

rm -rf "$ROOT/ui"
mkdir -p "$ROOT/ui"
cp "$KIT/"*.qml "$KIT/"*.js "$KIT/qmldir" "$ROOT/ui/"

exec quickshell -p "$ROOT/shell.qml" "$@"
