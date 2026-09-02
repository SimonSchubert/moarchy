#!/usr/bin/env bash
# Experiment: can Omarchy 4.x's quickshell-based shell run on the PinePhone?
#
#   PHONE=alarm@192.168.0.18 ./scripts/experiment-4x.sh
#
# Runs ON the phone via SSH. Non-destructive: it clones 4.x to a scratch
# directory and never touches the working v3.8.4 setup, the running session, or
# ~/.config. Kill it any time; nothing persists but the scratch clone.
#
# See docs/omarchy-4x-feasibility.md for why this is worth trying and what the
# expected failure mode is (memory, not rendering).

set -euo pipefail

PHONE="${PHONE:-alarm@10.15.19.82}"
TAG="${OMARCHY_4X_TAG:-v4.0.2}"
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10)

ssh "${SSH_OPTS[@]}" "$PHONE" TAG="$TAG" 'bash -s' <<'REMOTE'
set -uo pipefail
SCRATCH="$HOME/.cache/omarchy-4x-experiment"
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=wayland-1

say() { printf '\n==> %s\n' "$*"; }

say "quickshell availability"
if ! command -v quickshell >/dev/null; then
  echo "    installing quickshell"
  sudo pacman -S --needed --noconfirm quickshell >/dev/null 2>&1 || {
    echo "    !! quickshell install failed"; exit 1; }
fi
echo "    $(pacman -Q quickshell)"
echo "    modules: $(pacman -Ql quickshell | awk '{print $2}' | grep -oE 'Quickshell/[A-Za-z0-9]+' | sort -u | xargs)"

say "fetching Omarchy $TAG shell"
if [[ -d $SCRATCH/.git ]]; then
  git -C "$SCRATCH" fetch --quiet --depth 1 origin "refs/tags/$TAG:refs/tags/$TAG" 2>/dev/null || true
else
  git clone --quiet --filter=blob:none --no-checkout \
    https://github.com/basecamp/omarchy "$SCRATCH"
fi
git -C "$SCRATCH" checkout --quiet --detach "$TAG" 2>/dev/null || {
  echo "    !! could not check out $TAG"; exit 1; }
echo "    at $(git -C "$SCRATCH" describe --tags 2>/dev/null)"
echo "    QML files: $(find "$SCRATCH/shell" -name '*.qml' 2>/dev/null | wc -l | tr -d ' ')"

say "Hyprland coupling (what would need repointing at Quickshell.I3)"
grep -rl 'import Quickshell.Hyprland' "$SCRATCH/shell" 2>/dev/null | sed "s|$SCRATCH/|    |"
echo "    total files importing Quickshell.Hyprland: $(grep -rl 'import Quickshell.Hyprland' "$SCRATCH/shell" 2>/dev/null | wc -l | tr -d ' ')"

say "attempting to launch the 4.x shell (10s, then killed)"
ENTRY=$(find "$SCRATCH/shell" -maxdepth 1 -name 'shell.qml' -o -maxdepth 1 -name '*.qml' | head -1)
if [[ -z $ENTRY ]]; then
  echo "    !! no entry .qml found under shell/"; exit 1
fi
echo "    entry: ${ENTRY#$SCRATCH/}"

LOG=$(mktemp)
( setsid quickshell -p "$ENTRY" >"$LOG" 2>&1 & )
sleep 10

if pgrep -x quickshell >/dev/null; then
  RSS=$(ps -o rss= -C quickshell | awk '{s+=$1} END {printf "%.0f", s/1024}')
  echo "    RUNNING -- RSS ${RSS} MB"
  echo "    (waybar for comparison: $(ps -o rss= -C waybar 2>/dev/null | awk '{s+=$1} END {printf "%.0f", s/1024}') MB)"
  echo "    available RAM: $(free -m | awk '/Mem:/{print $7}') MB"
else
  echo "    EXITED -- shell did not stay up"
fi

say "log (errors first)"
sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -iE 'error|warn|fail|cannot|unable' | head -20 | sed 's/^/    /'
echo "    --- tail ---"
sed 's/\x1b\[[0-9;]*m//g' "$LOG" | tail -8 | sed 's/^/    /'

pkill -x quickshell 2>/dev/null
rm -f "$LOG"
say "done -- quickshell stopped, v3.8.4 session untouched"
REMOTE
