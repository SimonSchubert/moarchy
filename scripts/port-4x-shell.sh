#!/usr/bin/env bash
# Port Omarchy 4.x's quickshell shell to run under Sway on the PinePhone.
#
#   PHONE=alarm@192.168.0.18 ./scripts/port-4x-shell.sh
#
# Non-destructive: works on a scratch clone in ~/.cache/omarchy-4x-experiment and
# never touches the live v3.8.4 session. Run it, look at the phone, then stop the
# 4.x bar with:  ssh $PHONE pkill -x quickshell
#
# Status: the bar renders and is populated (workspaces, clock, bluetooth, wifi,
# volume, battery). This is a working proof of concept, not a finished port --
# see docs/omarchy-4x-feasibility.md for what remains.

set -euo pipefail

PHONE="${PHONE:-alarm@10.15.19.82}"
TAG="${OMARCHY_4X_TAG:-v4.0.2}"
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10)

ssh "${SSH_OPTS[@]}" "$PHONE" TAG="$TAG" 'bash -s' <<'REMOTE'
set -uo pipefail
SCRATCH="$HOME/.cache/omarchy-4x-experiment"
say() { printf '\n==> %s\n' "$*"; }

say "dependencies"
sudo pacman -S --needed --noconfirm quickshell inotify-tools >/dev/null 2>&1
echo "    quickshell $(pacman -Q quickshell | awk '{print $2}'), inotify-tools present"

say "hyprctl shim"
# The 4.x shell reads exactly two Hyprland options to size its layout. Answer
# them with Sway's equivalents; everything else returns empty JSON so callers
# get valid output instead of "binary not found".
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/hyprctl" <<'EOF'
#!/bin/bash
for a in "$@"; do
  case "$a" in
    decoration:rounding) echo '{"option":"decoration:rounding","int":0}'; exit 0 ;;
    general:gaps_out)    echo '{"option":"general:gaps_out","custom":"0"}'; exit 0 ;;
  esac
done
echo "{}"
EOF
chmod +x "$HOME/.local/bin/hyprctl"
echo "    written to ~/.local/bin/hyprctl"

say "fetching Omarchy $TAG"
if [[ ! -d $SCRATCH/.git ]]; then
  git clone --quiet --filter=blob:none --no-checkout https://github.com/basecamp/omarchy "$SCRATCH"
fi
cd "$SCRATCH"
git fetch --quiet --depth 1 origin "refs/tags/$TAG:refs/tags/$TAG" 2>/dev/null || true
git checkout --quiet --detach "$TAG"
git checkout --quiet -- shell    # discard any previous run's edits
echo "    at $(git describe --tags 2>/dev/null), $(find shell -name '*.qml' | wc -l | tr -d ' ') qml files"

say "translating Quickshell.Hyprland -> Quickshell.I3"
# I3 mirrors the Hyprland singleton for everything this shell uses:
#   workspaces, focusedWorkspace, focusedMonitor, dispatch, rawEvent
for f in $(grep -rl "Hyprland" shell --include=*.qml 2>/dev/null); do
  sed -i -e "s/import Quickshell.Hyprland/import Quickshell.I3/g" \
         -e "s/\bHyprlandEvent\b/I3Event/g" \
         -e "s/target: Hyprland/target: I3/g" \
         -e "s/\bHyprland\.\([a-zA-Z]\)/I3.\1/g" "$f"
done

# HyprlandFocusGrab is the one genuine gap: it lives only under
# Quickshell/Hyprland/_FocusGrab and has no I3 counterpart. Neutralise it --
# popups lose click-outside-to-dismiss but everything else renders.
python3 - <<'PY'
p = "shell/Ui/PopupCard.qml"
try:
    s = open(p).read()
except FileNotFoundError:
    raise SystemExit(0)
import re
s = re.sub(
    r'HyprlandFocusGrab \{[^}]*\}',
    '// FocusGrab has no Quickshell.I3 counterpart; click-outside-dismiss disabled\n  Item {}',
    s, flags=re.S)
open(p, "w").write(s)
PY
echo "    remaining Hyprland identifiers: $(grep -rho 'Hyprland[A-Za-z.]*' shell --include=*.qml 2>/dev/null | sort -u | tr '\n' ' ')"

say "launching"
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=wayland-1
export PATH="$HOME/.local/bin:$PATH"
export OMARCHY_PATH="$SCRATCH"
# Quickshell.I3 talks to sway over SWAYSOCK; without it the module never connects.
export SWAYSOCK=$(ls /run/user/$(id -u)/sway-ipc.* 2>/dev/null | head -1)

pkill -x quickshell 2>/dev/null; sleep 1
LOG=/tmp/omarchy-4x.log
( setsid quickshell -p "$SCRATCH/shell/shell.qml" >"$LOG" 2>&1 & )
sleep 15

if pgrep -x quickshell >/dev/null; then
  echo "    RUNNING -- RSS $(ps -o rss= -C quickshell | awk '{s+=$1} END {printf "%.0f", s/1024}') MB"
else
  echo "    !! exited; see $LOG"
fi

say "remaining diagnostics"
sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -iE 'error|cannot|not a type|not defined' | sort -u | head -8 | sed 's/^/    /'

say "done -- stop it with: pkill -x quickshell"
REMOTE
