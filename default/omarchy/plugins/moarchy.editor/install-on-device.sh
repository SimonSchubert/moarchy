#!/bin/bash
# Copy Text Editor onto the phone, with qs_ui vendored as ui/.
#
#   plugins/moarchy.editor/install-on-device.sh
#
# PHONE defaults to the same target scripts/device.sh uses.
#
# Two desktop entries and a command, where other plugins have one entry: the
# app drawer's, the hidden one xdg-open runs for a text file, and moarchy-editor in
# ~/.local/bin, which is what $EDITOR needs because it has to wait. None of
# this makes the editor the phone's default; `omarchy-default-editor
# moarchy-editor` does that on an image whose moarchy package knows the name.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$ROOT/../../qs_ui" && pwd)"
# moarchy.local and not an address: the phone's systemd-resolved answers mDNS
# (+mDNS is on by default and avahi is not installed), so this follows it from
# one lease to the next.
PHONE="${PHONE:-moarchy@moarchy.local}"
ID="moarchy.editor"
DEST=".config/omarchy/plugins/$ID"

echo "==> copy $ID to $PHONE:$DEST"
ssh "$PHONE" "mkdir -p $DEST/ui ~/.local/bin ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps"
scp "$ROOT/manifest.json" "$ROOT/Editor.qml" "$ROOT/Doc.js" "$ROOT/Store.js" \
    "$ROOT/icon.svg" "$PHONE:$DEST/"
scp "$KIT/"*.qml "$KIT/"*.js "$KIT/qmldir" "$PHONE:$DEST/ui/"
scp "$ROOT/icon.svg" "$PHONE:.local/share/icons/hicolor/scalable/apps/org.moarchy.Editor.svg"
scp "$ROOT/org.moarchy.Editor.plugin.desktop" "$ROOT/org.moarchy.Editor.open.desktop" \
  "$PHONE:.local/share/applications/"
scp "$ROOT/bin/moarchy-editor" "$PHONE:.local/bin/moarchy-editor"

echo "==> validate and enable"
ssh "$PHONE" bash -s <<'ENDSSH'
set -euo pipefail
ID=moarchy.editor
chmod +x ~/.local/bin/moarchy-editor
omarchy plugin validate ~/.config/omarchy/plugins/$ID
omarchy plugin enable $ID 2>/dev/null || omarchy plugin enable $ID --yes 2>/dev/null || true
python3 - <<'PY'
import json
from pathlib import Path
ID = "moarchy.editor"
defaults = json.loads(Path("/usr/share/omarchy/config/omarchy/shell.json").read_text())
p = Path.home() / ".config/omarchy/shell.json"
data = dict(defaults)
if p.exists():
    try:
        user = json.loads(p.read_text())
        if isinstance(user, dict):
            data.update(user)
    except ValueError:
        pass
data["version"] = data.get("version") or defaults.get("version") or 1
plugins = data.get("plugins")
if not isinstance(plugins, list) or not plugins:
    plugins = list(defaults.get("plugins") or [])
def pid(entry):
    return entry.get("id") if isinstance(entry, dict) else entry
ids = [pid(e) for e in plugins]
if ID not in ids:
    plugins.append({"id": ID})
    print("    added", ID, "to shell.json")
else:
    print("   ", ID, "already in shell.json")
data["plugins"] = plugins
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(data, indent=2) + "\n")
PY
update-desktop-database ~/.local/share/applications >/dev/null 2>&1 || true
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export SWAYSOCK="${SWAYSOCK:-$(ls "$XDG_RUNTIME_DIR"/sway-ipc.* 2>/dev/null | head -1)}"
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
pkill -x quickshell 2>/dev/null || true
for _ in $(seq 20); do pgrep -x quickshell >/dev/null || break; sleep 0.2; done
mkdir -p ~/.local/state/moarchy
QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 \
  setsid quickshell -n -p "$OMARCHY_PATH/shell" >~/.local/state/moarchy/shell.log 2>&1 &
sleep 2
pgrep -x quickshell >/dev/null && echo "    restarted omarchy-shell" || echo "    shell failed to start, see ~/.local/state/moarchy/shell.log"
ENDSSH
echo "==> done. tap Text Editor in the appDrawer, or: ~/.local/bin/moarchy-editor FILE"
