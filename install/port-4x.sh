#!/bin/bash
# Make Omarchy 4.x's quickshell shell run under Sway.
#
# The shell is written against Hyprland, but Quickshell ships an `I3` module that
# mirrors the Hyprland singleton for everything this shell uses, so the port is a
# mechanical translation over the vendored QML plus two small shims.
#
# Idempotent: re-running restores the vendored shell from git before translating,
# so it is safe after any `install/vendor-omarchy.sh` update.

echo "==> porting 4.x shell to Sway"

SHELL_DIR="$OMARCHY_PATH/shell"
[[ -d $SHELL_DIR ]] || { echo "    !! $SHELL_DIR missing -- is the pin on a 4.x commit?" >&2; return 1 2>/dev/null || exit 1; }

# --- hyprctl shim ----------------------------------------------------------
# The shell shells out to hyprctl for two layout metrics. Without this every
# call logs "binary could not be found" and layout falls back to defaults.
mkdir -p ~/.local/bin
cat >~/.local/bin/hyprctl <<'EOF'
#!/bin/bash
# Shim for Omarchy 4.x's shell under Sway. It reads exactly two options; answer
# those with Sway's equivalents and return valid empty JSON for anything else.
for a in "$@"; do
  case "$a" in
    decoration:rounding) echo '{"option":"decoration:rounding","int":0}'; exit 0 ;;
    general:gaps_out)    echo '{"option":"general:gaps_out","custom":"0"}'; exit 0 ;;
  esac
done
echo "{}"
EOF
chmod +x ~/.local/bin/hyprctl

# --- QML translation -------------------------------------------------------
# Start from pristine vendored QML so this is repeatable.
git -C "$OMARCHY_PATH" checkout --quiet -- shell 2>/dev/null

# Quickshell.I3 mirrors the Hyprland singleton: workspaces, focusedWorkspace,
# focusedMonitor and rawEvent all keep their names.
#
# NOTE `target: Hyprland` is a *bare* singleton reference -- a dot-anchored
# regex silently misses it and the bar then draws but never populates.
for f in $(grep -rl "Hyprland" "$SHELL_DIR" --include=*.qml 2>/dev/null); do
  sed -i -e "s/import Quickshell.Hyprland/import Quickshell.I3/g" \
         -e "s/\bHyprlandEvent\b/I3Event/g" \
         -e "s/target: Hyprland/target: I3/g" \
         -e "s/\bHyprland\.\([a-zA-Z]\)/I3.\1/g" "$f"
done

# HyprlandFocusGrab is the one genuine gap -- it exists only under
# Quickshell/Hyprland/_FocusGrab. Neutralise it; popups lose
# click-outside-to-dismiss but everything else renders.
python3 - "$SHELL_DIR" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1]) / "Ui" / "PopupCard.qml"
if p.exists():
    s = p.read_text()
    s = re.sub(r'HyprlandFocusGrab \{[^}]*\}',
               '// FocusGrab has no Quickshell.I3 counterpart; click-outside-dismiss disabled\n  Item {}',
               s, flags=re.S)
    p.write_text(s)
PY

remaining=$(grep -rl "import Quickshell.Hyprland" "$SHELL_DIR" --include=*.qml 2>/dev/null | wc -l | tr -d ' ')
echo "    translated; files still importing Quickshell.Hyprland: $remaining"
