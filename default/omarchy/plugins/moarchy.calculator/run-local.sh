#!/bin/bash
# The calculator on this machine, as a plain Quickshell process.
#
#   plugins/moarchy.calculator/run-local.sh
#
# The plugin imports its chrome as `ui`, which the installers vendor from
# qs_ui. Nothing vendors it in a checkout, so this does that first and
# then hands shell.qml to quickshell. No omarchy-shell involved: this is the
# same path a package on another distribution would take.
#
# MOARCHY_CALCULATOR_TYPED=1234.5+20% opens with that already keyed in.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$ROOT/../../qs_ui" && pwd)"

rm -rf "$ROOT/ui"
mkdir -p "$ROOT/ui"
cp "$KIT/"*.qml "$KIT/"*.js "$KIT/qmldir" "$ROOT/ui/"

exec quickshell -p "$ROOT/shell.qml" "$@"
