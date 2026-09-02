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


# --- Workspaces widget -----------------------------------------------------
# Three Hyprland assumptions that a bare import swap does not catch:
#
#   occupied:       reads workspace.toplevels, which only Hyprland's workspace
#                   object has. On I3Workspace it throws, killing the binding.
#                   Sway's IPC workspace carries `representation` instead -- a
#                   layout string that is empty exactly when the workspace holds
#                   no windows.
#   focusWorkspace: dispatches through hyprctl, which our shim deliberately does
#                   not implement -- so tapping a workspace silently did nothing.
#   workspaceIds:   pins five persistent workspaces. Five numbers plus the
#                   indicators leave no room on a 360px bar.
python3 - "$SHELL_DIR" <<'PY_EOF'
import pathlib, sys

p = pathlib.Path(sys.argv[1]) / "plugins" / "bar" / "widgets" / "Workspaces.qml"
if not p.exists():
    raise SystemExit(0)
s = p.read_text()

s = s.replace(
    "readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0",
    """readonly property bool occupied: {
          if (!workspace) return false
          // Hyprland exposes a toplevel model; I3Workspace does not.
          if (workspace.toplevels && workspace.toplevels.values)
            return workspace.toplevels.values.length > 0
          // sway: `representation` is empty only when the workspace is empty.
          var ipc = workspace.lastIpcObject
          if (ipc && typeof ipc.representation === "string")
            return ipc.representation.length > 0
          return false
        }""")

# Matched by regex: the literal contains backslash-escaped quotes that are
# painful to reproduce exactly in a nested heredoc.
import re
s, n = re.subn(r'root\.bar\.run\("hyprctl dispatch ".*?\)\)',
               'root.bar.run("swaymsg workspace number " + id)', s)
if n == 0:
    print("    !! focusWorkspace pattern did not match", file=sys.stderr)

# A phone bar fits three; sway creates more on demand and they still appear.
s = s.replace("var ids = [1, 2, 3, 4, 5]", "var ids = [1, 2, 3]")

# Hyprland's workspace .id IS the visible number. Sway's .id is an internal
# handle and the visible number lives in .number -- so comparing .id against
# 1/2/3 never matches the real workspace, and the internal id leaks in as a
# phantom extra entry (the stray glyph after the last number).
s = s.replace("if (values[i].id === id) return values[i]",
              "if (root.wsNumber(values[i]) === id) return values[i]")
s = s.replace("var id = values[i].id\n", "var id = root.wsNumber(values[i])\n")
s = s.replace("readonly property bool focused: I3.focusedWorkspace !== null && I3.focusedWorkspace.id === modelData",
              "readonly property bool focused: I3.focusedWorkspace !== null && root.wsNumber(I3.focusedWorkspace) === modelData")
s, n = re.subn(r'^(\s*)function workspaceById\(id\) \{',
    lambda m: (f"{m.group(1)}// sway exposes the visible number as .number (.num on some "
               f"versions);\n{m.group(1)}// .id is an internal handle. Hyprland conflated the two.\n"
               f"{m.group(1)}function wsNumber(ws) {{\n"
               f"{m.group(1)}  if (!ws) return -1\n"
               f"{m.group(1)}  if (ws.number !== undefined && ws.number !== null) return ws.number\n"
               f"{m.group(1)}  if (ws.num !== undefined && ws.num !== null) return ws.num\n"
               f"{m.group(1)}  return ws.id\n"
               f"{m.group(1)}}}\n\n" + m.group(0)),
    s, count=1, flags=re.M)
if n == 0:
    print("    !! wsNumber helper not inserted", file=sys.stderr)

p.write_text(s)
PY_EOF
echo "    Workspaces.qml: occupied guarded, focus via swaymsg, 3 persistent workspaces"

remaining=$(grep -rl "import Quickshell.Hyprland" "$SHELL_DIR" --include=*.qml 2>/dev/null | wc -l | tr -d ' ')
echo "    translated; files still importing Quickshell.Hyprland: $remaining"
