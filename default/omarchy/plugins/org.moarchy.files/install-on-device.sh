#!/bin/bash
# Copy Files onto the phone, with shared/qs_ui vendored as ui/.
#
#   plugins/org.moarchy.files/install-on-device.sh
#
# PHONE defaults to the same target scripts/device.sh uses.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$ROOT/../../shared/qs_ui" && pwd)"
# moarchy.local and not an address: the phone's systemd-resolved answers mDNS
# (+mDNS is on by default and avahi is not installed), so this follows it from
# one lease to the next. The literal that used to be here, 192.168.0.18, had
# stopped being the phone at all -- and the router is no help, because its DNS
# returns every lease the name has ever held, four of them dead, one per query.
PHONE="${PHONE:-moarchy@moarchy.local}"
ID="org.moarchy.files"
DEST=".config/omarchy/plugins/$ID"

echo "==> copy $ID to $PHONE:$DEST"
ssh "$PHONE" "mkdir -p $DEST/ui ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps"
scp "$ROOT/manifest.json" "$ROOT/Files.qml" "$ROOT/EntryRow.qml" \
    "$ROOT/Listing.js" "$ROOT/Ops.js" "$ROOT/Path.js" "$ROOT/Places.js" \
    "$ROOT/Store.js" "$ROOT/icon.svg" "$PHONE:$DEST/"
scp "$KIT/"*.qml "$KIT/"*.js "$KIT/qmldir" "$PHONE:$DEST/ui/"
scp "$ROOT/icon.svg" "$PHONE:.local/share/icons/hicolor/scalable/apps/org.moarchy.Files.svg"
scp "$ROOT/org.moarchy.Files.plugin.desktop" \
  "$PHONE:.local/share/applications/org.moarchy.Files.plugin.desktop"

echo "==> validate and enable"
ssh "$PHONE" bash -s <<'ENDSSH'
set -euo pipefail
ID=org.moarchy.files
omarchy plugin validate ~/.config/omarchy/plugins/$ID
omarchy plugin enable $ID 2>/dev/null || omarchy plugin enable $ID --yes 2>/dev/null || true
python3 - <<'PY'
import json
from pathlib import Path
ID = "org.moarchy.files"
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
echo "==> done. tap Files in the drawer, or: omarchy-shell shell toggle $ID"
