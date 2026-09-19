#!/bin/bash
# Copy Mail onto the phone, with qs_ui vendored as ui/.
#
#   plugins/moarchy.mail/install-on-device.sh
#
# PHONE defaults to the same target scripts/device.sh uses. moarchy-mail goes
# to ~/.local/bin, which the shell's PATH has before /usr/bin, so a phone with
# the package installed runs this checkout's copy until the file is removed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$ROOT/../../qs_ui" && pwd)"
PHONE="${PHONE:-moarchy@moarchy.local}"
ID="moarchy.mail"
DEST=".config/omarchy/plugins/$ID"

echo "==> copy $ID to $PHONE:$DEST"
ssh "$PHONE" "mkdir -p $DEST/ui ~/.local/bin ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps"
scp "$ROOT/manifest.json" "$ROOT/Mail.qml" \
    "$ROOT/Address.js" "$ROOT/Compose.js" "$ROOT/Helper.js" "$ROOT/Mailbox.js" "$ROOT/Store.js" \
    "$ROOT/icon.svg" "$PHONE:$DEST/"
scp "$KIT/"*.qml "$KIT/"*.js "$KIT/qmldir" "$PHONE:$DEST/ui/"
scp "$ROOT/bin/moarchy-mail" "$PHONE:.local/bin/moarchy-mail"
scp "$ROOT/icon.svg" "$PHONE:.local/share/icons/hicolor/scalable/apps/org.moarchy.Mail.svg"
scp "$ROOT/org.moarchy.Mail.plugin.desktop" "$ROOT/org.moarchy.Mail.compose.desktop" \
  "$PHONE:.local/share/applications/"

echo "==> validate and enable"
ssh "$PHONE" bash -s <<'ENDSSH'
set -euo pipefail
ID=moarchy.mail
chmod +x ~/.local/bin/moarchy-mail
omarchy plugin validate ~/.config/omarchy/plugins/$ID
omarchy plugin enable $ID 2>/dev/null || omarchy plugin enable $ID --yes 2>/dev/null || true
python3 - <<'PY'
import json
from pathlib import Path
ID = "moarchy.mail"
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
# mailto: links, for this user, rather than whatever Geary registered.
xdg-mime default org.moarchy.Mail.compose.desktop x-scheme-handler/mailto 2>/dev/null || true
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t "$XDG_RUNTIME_DIR"/hypr 2>/dev/null | head -1)}"
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
# Restarted through the compositor, for the reason Messages' installer gives: a shell
# started from this ssh session lives in it, and dies with it.
pkill -x quickshell 2>/dev/null || true
for _ in $(seq 20); do pgrep -x quickshell >/dev/null || break; sleep 0.2; done
mkdir -p ~/.local/state/moarchy
if [ -x /usr/lib/moarchy/bin/moarchy-restart-shell ] && [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
  hyprctl dispatch 'hl.dsp.exec_cmd("/usr/lib/moarchy/bin/moarchy-restart-shell")' >/dev/null
else
  QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 \
    setsid quickshell -n -p "$OMARCHY_PATH/shell" >~/.local/state/moarchy/shell.log 2>&1 &
fi
sleep 4
pgrep -x quickshell >/dev/null && echo "    restarted omarchy-shell" || echo "    shell failed to start, see ~/.local/state/moarchy/shell.log"
ENDSSH
echo "==> done. tap Mail in the appDrawer, or: omarchy-shell shell toggle $ID"
