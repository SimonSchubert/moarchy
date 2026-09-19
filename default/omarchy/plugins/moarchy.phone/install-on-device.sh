#!/bin/bash
# Copy Phone onto the phone, with shared/qs_ui vendored as ui/.
#
#   plugins/moarchy.phone/install-on-device.sh
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
ID="moarchy.phone"
DEST=".config/omarchy/plugins/$ID"

echo "==> copy $ID to $PHONE:$DEST"
ssh "$PHONE" "mkdir -p $DEST/ui ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps"
scp "$ROOT/manifest.json" "$ROOT/Phone.qml" "$ROOT/DialKey.qml" "$ROOT/CallButton.qml" \
    "$ROOT/Calls.js" "$ROOT/Modem.js" "$ROOT/Numbers.js" "$ROOT/Store.js" "$ROOT/icon.svg" "$PHONE:$DEST/"
scp "$KIT/"*.qml "$KIT/"*.js "$KIT/qmldir" "$PHONE:$DEST/ui/"
scp "$ROOT/icon.svg" "$PHONE:.local/share/icons/hicolor/scalable/apps/org.moarchy.Phone.svg"
scp "$ROOT/org.moarchy.Phone.plugin.desktop" \
  "$PHONE:.local/share/applications/org.moarchy.Phone.plugin.desktop"

echo "==> validate and enable"
ssh "$PHONE" bash -s <<'ENDSSH'
set -euo pipefail
ID=moarchy.phone
omarchy plugin validate ~/.config/omarchy/plugins/$ID
omarchy plugin enable $ID 2>/dev/null || omarchy plugin enable $ID --yes 2>/dev/null || true
python3 - <<'PY'
import json
from pathlib import Path
ID = "moarchy.phone"
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
# gnome-calls' own daemon would ring as well, and answer from its own window.
# Masked rather than disabled, because the moarchy package links it into
# default.target.wants where `disable` cannot reach it.
if systemctl --user cat calls-daemon.service >/dev/null 2>&1; then
  systemctl --user stop calls-daemon.service 2>/dev/null || true
  systemctl --user mask calls-daemon.service >/dev/null 2>&1 \
    && echo "    masked calls-daemon (undo: systemctl --user unmask calls-daemon.service)"
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export SWAYSOCK="${SWAYSOCK:-$(ls "$XDG_RUNTIME_DIR"/sway-ipc.* 2>/dev/null | head -1)}"
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
# Restarted through sway, not from here. A shell started by this ssh session
# lives in this ssh session, and polkit gives a remote session nothing:
# ModemManager then refuses every call and every text with "not authorized",
# while the app looks fine. `swaymsg exec` makes it sway's child, in the seat.
pkill -x quickshell 2>/dev/null || true
for _ in $(seq 20); do pgrep -x quickshell >/dev/null || break; sleep 0.2; done
mkdir -p ~/.local/state/moarchy
if [ -x /usr/lib/moarchy/bin/moarchy-restart-shell ] && [ -n "$SWAYSOCK" ]; then
  swaymsg exec /usr/lib/moarchy/bin/moarchy-restart-shell >/dev/null
else
  QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 \
    setsid quickshell -n -p "$OMARCHY_PATH/shell" >~/.local/state/moarchy/shell.log 2>&1 &
fi
sleep 4
pgrep -x quickshell >/dev/null && echo "    restarted omarchy-shell" || echo "    shell failed to start, see ~/.local/state/moarchy/shell.log"
ENDSSH
echo "==> done. tap Phone in the appDrawer, or: omarchy-shell shell toggle $ID"
