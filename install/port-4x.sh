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

# `|| true` is load-bearing. grep exits 1 when it matches nothing, install.sh
# runs under `set -eo pipefail`, and pipefail propagates that 1 out of the
# whole pipeline -- so the assignment fails and the installer aborts here
# *precisely when the translation above worked perfectly*. It cost a full
# 21-minute install run to find, because the abort looks like a clean stop.
remaining=$( { grep -rl "import Quickshell.Hyprland" "$SHELL_DIR" --include=*.qml 2>/dev/null || true; } | wc -l | tr -d ' ')
echo "    translated; files still importing Quickshell.Hyprland: $remaining"

# --- Launcher back button --------------------------------------------------
# The 4.x launcher retreats on Escape (clear filter / close) and on
# Backspace-or-Left at an empty filter (up one level). Both are keyboard-only,
# and this device has no keyboard: wvkbd can send them, but it is a layer-shell
# panel covering the bottom half of the screen, so reaching "up one level"
# means summoning a keyboard over the very list you are navigating.
#
# So give the header a back button whenever the hardware says the keys are not
# there -- a touchscreen is present, or no real keyboard is.
#
# "No real keyboard" cannot come from `swaymsg -t get_inputs`: it types the
# power button, the volume rocker, the headset jack *and* wvkbd itself as
# "keyboard", so that check is true on every PinePhone and the button would
# never appear. /proc/bus/input/devices carries the evdev capability bitmaps
# instead, which say what a device can actually emit.
python3 - "$SHELL_DIR" <<'BACKBTN_EOF'
import pathlib, sys

p = pathlib.Path(sys.argv[1]) / "plugins" / "menu" / "Menu.qml"
if not p.exists():
    raise SystemExit(0)
s = p.read_text(encoding="utf-8")

# --- probe -----------------------------------------------------------------
probe = r'''  property var navStack: []

  // Does this machine have the keys the launcher's navigation assumes?
  //
  // Defaults say "no keyboard" so the button is present on the first frame:
  // blockLoading resolves the probe during construction, but if /proc ever
  // fails to read, a spare back button on a desktop is the harmless way to be
  // wrong -- a phone with no way back is not.
  property bool hasTouchscreen: false
  property bool hasHardwareKeyboard: false
  readonly property bool showBackButton: root.hasTouchscreen || !root.hasHardwareKeyboard

  // The icon has to predict what the button will do. goBackOrClose() retreats
  // through filter -> menu -> close, so the only state that actually closes is
  // the root menu with an empty filter -- and that is the one that shows an x.
  // (dmenu prompts sit at "root" too, where closing is also the right answer.)
  readonly property bool backClosesMenu: root.activeMenu === "root" && !root.filterText

  // /proc/bus/input/devices prints capability bitmaps as space-separated hex
  // words, most significant first, so the LAST word holds bits 0-63. Indexing
  // by hex digit keeps this clear of JS's 32-bit bitwise operators (and of
  // BigInt, which the QML engine does not guarantee).
  function evdevBit(mask, bit) {
    if (!mask) return false
    var words = String(mask).split(/\s+/).filter(function(w) { return w.length > 0 })
    var w = words.length - 1 - Math.floor(bit / 64)
    if (w < 0 || w >= words.length) return false
    var within = bit % 64
    var digit = words[w].length - 1 - Math.floor(within / 4)   // 4 bits per hex digit
    if (digit < 0) return false
    var nibble = parseInt(words[w].charAt(digit), 16)
    if (isNaN(nibble)) return false
    return ((nibble >> (within % 4)) & 1) === 1
  }

  // Classify by capability, the way libinput itself does:
  //
  //   keyboard    KEY_ESC + KEY_1 + KEY_Q + KEY_SPACE. A key-emitting device
  //               that cannot type a letter is a button, not a keyboard --
  //               which is exactly what the PinePhone's four pseudo-keyboards
  //               are (power, volume, wakeup, headset jack).
  //   touchscreen BTN_TOUCH + INPUT_PROP_DIRECT. The PROP is what separates a
  //               touchscreen from a touchpad; both report BTN_TOUCH.
  function classifyInputDevices(text) {
    var KEY_ESC = 1, KEY_1 = 2, KEY_Q = 16, KEY_SPACE = 57
    var BTN_TOUCH = 0x14a, INPUT_PROP_DIRECT = 1
    var touch = false, keyboard = false
    var blocks = String(text || "").split(/\n\s*\n/)
    for (var i = 0; i < blocks.length; i++) {
      var lines = blocks[i].split("\n")
      var name = "", key = "", prop = "", m
      for (var j = 0; j < lines.length; j++) {
        if ((m = lines[j].match(/^N: Name="(.*)"/))) name = m[1]
        else if ((m = lines[j].match(/^B: KEY=(.*)$/))) key = m[1]
        else if ((m = lines[j].match(/^B: PROP=(.*)$/))) prop = m[1]
      }
      if (!name) continue
      if (root.evdevBit(key, BTN_TOUCH) && root.evdevBit(prop, INPUT_PROP_DIRECT)) touch = true
      if (root.evdevBit(key, KEY_ESC) && root.evdevBit(key, KEY_1)
          && root.evdevBit(key, KEY_Q) && root.evdevBit(key, KEY_SPACE)) keyboard = true
    }
    root.hasTouchscreen = touch
    root.hasHardwareKeyboard = keyboard
  }

  // Read once during construction (blockLoading, so the first frame is already
  // right), then re-read on each open -- /proc/bus/input/devices delivers no
  // inotify events, and an open is the only moment the answer is needed. It is
  // 1.5 KB.
  FileView {
    id: inputDevicesFile
    path: "/proc/bus/input/devices"
    blockLoading: true
    onLoaded: root.classifyInputDevices(inputDevicesFile.text())
    onLoadFailed: { root.hasTouchscreen = false; root.hasHardwareKeyboard = false }
  }

  // One affordance for all three retreats, so the button never dead-ends:
  // narrow the search, then climb the menu, then close. Same order as Escape
  // and Backspace, so touch and keyboard stay in step.
  function goBackOrClose() {
    if (root.filterText) root.setFilter("")
    else if (!root.goBack()) root.cancel()
  }
'''

anchor = "  property var navStack: []\n"
if anchor not in s:
    print("    !! navStack anchor not found -- back button probe not inserted", file=sys.stderr)
    raise SystemExit(0)
s = s.replace(anchor, probe, 1)

# --- refresh the probe as the launcher opens -------------------------------
# Deferred, and that is load-bearing. open() runs inside the IPC handler for
# `omarchy-shell shell summon`, and a blockLoading FileView reload spins a
# nested event loop; doing that here leaves the rest of open() unfinished, so
# the launcher never becomes visible -- silently, with nothing in the log.
# Qt.callLater puts the read after the open has returned.
old_open = """  function open(payloadJson) {
    var payload = ({})"""
new_open = """  function open(payloadJson) {
    Qt.callLater(function() { inputDevicesFile.reload() })
    var payload = ({})"""
if old_open in s:
    s = s.replace(old_open, new_open, 1)
else:
    print("    !! open() anchor not found -- probe will not refresh per open", file=sys.stderr)

# --- header: back button, then the filter/prompt text ----------------------
# Matched down to the Text's anchors only, so the prompt's own bindings (which
# contain non-ASCII ellipses) stay untouched.
old_header = """        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
"""

new_header = """        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          // Square on the header's own height, so the tap target is as tall as
          // the row it sits in rather than as tall as the glyph.
          Rectangle {
            id: backButton
            visible: root.showBackButton
            width: visible ? root.headerHeight : 0
            height: root.headerHeight
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            radius: root.cornerRadius
            color: backTap.pressed ? root.selectedBackground : "transparent"

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: root.backClosesMenu ? "\\uf00d" : "\\uf053"   // nf-fa-times / nf-fa-chevron_left
              color: backTap.pressed ? root.selectedText : root.foreground
              opacity: backTap.pressed ? 1 : 0.58   // matches the idle prompt
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
            }

            MouseArea {
              id: backTap
              anchors.fill: parent
              onClicked: root.goBackOrClose()
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.left: backButton.visible ? backButton.right : parent.left
            anchors.leftMargin: backButton.visible ? Style.space(4) : 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
"""

if old_header in s:
    s = s.replace(old_header, new_header, 1)
else:
    print("    !! menu header anchor not found -- back button not rendered", file=sys.stderr)

p.write_text(s, encoding="utf-8")
BACKBTN_EOF
echo "    Menu.qml: back button when a touchscreen is present or no real keyboard is"

# --- Launch splash ---------------------------------------------------------
# Upstream shows a launch OSD two seconds after a tap: a rounded panel reading
# "Launching Files..." with a rocket glyph, taken down when a toplevel appears.
# On this phone two seconds is most of an app launch, so that feedback arrived
# after the moment it was for -- you tapped, nothing happened, you tapped again.
#
# mobileomarchy.splash draws the app's own icon on the wallpaper instead, from
# the tap onwards. This rewires AppLibrary to feed it rather than duplicating
# the bookkeeping: which app, whether a toplevel arrived and the 15s giving-up
# timer all stay exactly where upstream put them. Three edits:
#
#   launchIcon    a new property, resolved from the desktop id at launch, which
#                 is the one thing upstream never needed to know.
#   interval 0    the delay is the bug; a splash is feedback for the tap.
#   no osd calls  `launchOsdOpen` stops driving `omarchy-shell osd` and becomes
#                 the plain flag the splash plugin binds to. Kept under its
#                 upstream name so this patch stays small enough to survive the
#                 next vendored bump.
#
# See docs/windows.md L1-L8.
python3 - "$SHELL_DIR" <<'SPLASH_EOF'
import pathlib, sys

p = pathlib.Path(sys.argv[1]) / "services" / "AppLibrary.qml"
if not p.exists():
    print("    !! AppLibrary.qml missing -- launch splash not wired", file=sys.stderr)
    raise SystemExit(0)
s = p.read_text(encoding="utf-8")
ok = True

# --- launchIcon ------------------------------------------------------------
anchor = '  property string launchOsdMessage: ""\n'
addition = anchor + '''
  // The icon mobileomarchy.splash draws. Resolved here rather than in the
  // plugin because this is the only place that sees the desktop id.
  property string launchIcon: ""

  // One pass over the entry list, once per launch. Short enough on this device
  // to be beneath measuring, and it leans on nothing but `id` and `icon` --
  // the two fields every caller of launch() already relies on.
  function launchIconFor(desktopId) {
    var id = String(desktopId || "")
    var entries = []
    try { entries = DesktopEntries.applications.values || [] } catch (e) { entries = [] }
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && String(entries[i].id) === id) return root.iconSource(entries[i].icon)
    }
    return root.iconSource("")
  }
'''
if anchor in s:
    s = s.replace(anchor, addition, 1)
else:
    print("    !! launchOsdMessage anchor not found -- no launchIcon property", file=sys.stderr)
    ok = False

# Set it before the feedback starts, so the plugin never sees `launching` true
# with last launch's icon still on it.
old_launch = "    root.beginLaunchFeedback(name)\n"
new_launch = "    root.launchIcon = root.launchIconFor(id)\n    root.beginLaunchFeedback(name)\n"
if old_launch in s:
    s = s.replace(old_launch, new_launch, 1)
else:
    print("    !! beginLaunchFeedback call not found -- launchIcon never set", file=sys.stderr)
    ok = False

# --- the delay -------------------------------------------------------------
# Anchored on the id so this cannot land on one of the file's other Timers.
old_delay = "    id: launchDelay\n    interval: 2000\n"
new_delay = ("    id: launchDelay\n"
             "    // 0, not 2000: the splash is feedback for the tap, and a tap\n"
             "    // acknowledged two seconds later is a tap that got no answer.\n"
             "    // Still a Timer rather than a direct assignment, so the guard\n"
             "    // below keeps its chance to see a window that was already up.\n"
             "    interval: 0\n")
if old_delay in s:
    s = s.replace(old_delay, new_delay, 1)
else:
    print("    !! launchDelay interval not found -- splash still waits 2s", file=sys.stderr)
    ok = False

# --- the OSD calls ---------------------------------------------------------
# Dropped by line rather than matched as literals: the show call embeds a Nerd
# Font glyph, and reproducing that exactly through two levels of heredoc is a
# way to fail silently on an encoding rather than on the code.
lines = s.split("\n")
kept = [l for l in lines if 'execDetached(["omarchy-shell", "osd",' not in l]
dropped = len(lines) - len(kept)
if dropped == 2:
    s = "\n".join(kept)
else:
    print("    !! expected 2 osd calls in AppLibrary.qml, found %d -- left alone" % dropped,
          file=sys.stderr)
    ok = False

p.write_text(s, encoding="utf-8")
if ok:
    print("    AppLibrary.qml: launch feedback rewired to mobileomarchy.splash")
SPLASH_EOF
