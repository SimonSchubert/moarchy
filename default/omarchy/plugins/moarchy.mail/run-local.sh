#!/bin/bash
# Mail on this machine, as a plain Quickshell process.
#
#   plugins/moarchy.mail/run-local.sh
#
# bin/ goes first on PATH, so the app finds this checkout's moarchy-mail rather
# than one a package installed. It needs python3 and nothing else from it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$ROOT/../../shared/qs_ui" && pwd)"

rm -rf "$ROOT/ui"
mkdir -p "$ROOT/ui"
cp "$KIT/"*.qml "$KIT/"*.js "$KIT/qmldir" "$ROOT/ui/"

export PATH="$ROOT/bin:$PATH"
exec quickshell -p "$ROOT/shell.qml" "$@"
