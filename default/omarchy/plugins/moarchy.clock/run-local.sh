#!/bin/bash
# The clock on this machine, as a plain Quickshell process.
#
#   plugins/moarchy.clock/run-local.sh
#
# The plugin imports its chrome as `ui`, which the installers vendor from
# shared/qs_ui. Nothing vendors it in a checkout, so this does that first and
# then hands shell.qml to quickshell. No omarchy-shell involved: this is the
# same path a package on another distribution would take.
#
# Standalone, the alarm only watches the clock while the window is open --
# there is nothing here to keep the plugin loaded. On the phone the shell does,
# which is the whole argument for this app being a plugin.
#
#   MOARCHY_CLOCK_PAGE=stopwatch   opens on that tab
#   MOARCHY_CLOCK_NOW=1789475376   pins the clock, as the shot harness does
#   MOARCHY_CLOCK_OFFLINE=1        rings without making a sound
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$ROOT/../../shared/qs_ui" && pwd)"

rm -rf "$ROOT/ui"
mkdir -p "$ROOT/ui"
cp "$KIT/"*.qml "$KIT/"*.js "$KIT/qmldir" "$ROOT/ui/"

exec quickshell -p "$ROOT/shell.qml" "$@"
