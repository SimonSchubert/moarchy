#!/bin/bash
# Enforce docs/style.md against the shell plugins.
#
# The ACs that can be checked from the source are checked here, and the ones
# that cannot say so out loud rather than passing quietly. A style rule nobody
# can run is a style rule the fourth screen breaks and nobody notices -- which
# is how moarchy.device came to be written in raw pixels with no font family at
# all while every comment in it claimed to mirror the others.
#
# Covers: A1/A2/A3 (no literals), B1 (family), B3 (weight), B5 (glyph slots),
# C4 (no stray hex), D1 (four named radii), H1/H6 (a pressed state on every
# control, guarded where the control is also a drag handle). Plus three things
# that are not ACs at all: that every SVG this project ships still parses, the
# sheet-stacking rule, the edge table (gestures.md Q2), and the workspace-layout
# rule the workspace overview drags onto (gestures.md P7) -- all of which decide behaviour
# and none of which needs the phone to run.
#
# Does NOT cover E (touch targets) or F (text inputs): a hit area is a runtime
# rectangle, and the accessors that answer for it -- `omarchy-shell app drawer
# searchTarget`, `omarchy-shell wifi passTarget` -- need the phone. See
# docs/style.md §J.
#
#   scripts/style-check.sh            # from anywhere
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
PLUGINS=default/omarchy/plugins

# The apps absorbed from moarchy-apps (docs/structure.md B6) live in the same
# directory as the shell's own plugins and are built on the other kit: they
# import it as ui/, and it carries its own Theme.js, its own token names and
# its own radii. style.md does not describe them yet, so the rules that are
# about the shell's token API skip them -- A1-A3, B/C/D, and the shell-app
# glyph, which keys on an `AppWindow` the kit also defines.
#
# They join the contract by themselves. refactor.md E10 reconciles the two kits
# into one, and at that point nothing imports "ui", this list is empty by
# construction, and every plugin is checked -- without anyone remembering to
# come back here and delete an exemption.
KIT_APPS=$(grep -rl 'import "ui' "$PLUGINS"/*/*.qml 2>/dev/null \
             | xargs -n1 dirname 2>/dev/null | xargs -n1 basename 2>/dev/null \
             | sort -u)
export KIT_APPS
shell_dirs() {
  local d n
  for d in "$PLUGINS"/*/; do
    n=$(basename "$d")
    printf '%s\n' "$KIT_APPS" | grep -qx "$n" || printf '%s ' "$d"
  done
}

pass=0
fail=0
ok() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [[ -n ${2:-} ]] && printf '%s\n' "$2"; fail=$((fail + 1)); }
# Counted as neither. A check that cannot run here says so on the way past,
# rather than passing and reading as coverage it is not.
skipped=0
skip() { printf '  \033[33mSKIP\033[0m  %s\n' "$1"; skipped=$((skipped + 1)); }

# --- A1, A2, A3: nothing is written as a number -----------------------------
# `|| true` on purpose: a grep that matches nothing exits 1, and that would
# otherwise be read as a failure of the check rather than as a clean result.
printf '\nA. tokens\n'
hits=$(grep -rn 'pixelSize: [0-9]\|margins: [0-9]\|Margin: [0-9]\|spacing: [1-9]\|radius: [0-9]' $(shell_dirs) || true)
if [[ -z $hits ]]; then
  ok "no literal sizes, margins, spacings or radii (A1-A3)"
else
  no "literal values where a token belongs (A1-A3)" "$hits"
fi

# --- B, C4, D1: need to know where a block starts and ends ------------------
printf '\nB. type / C. colour / D. shape\n'
report=$(python3 - "$PLUGINS" <<'PY'
import os, pathlib, re, sys

RADII = ("radiusSheet", "radiusTile", "radiusCard", "radiusOn")
HEX = re.compile(r'"#[0-9a-fA-F]{3,8}"')
problems = []

def blocks(lines, opener):
    """Yield (start_line_number, text) for each `<opener> {` block, matched by
    brace depth with comments stripped -- a `{` inside a sentence would
    otherwise never close."""
    i = 0
    while i < len(lines):
        m = re.match(r"^\s*(%s)\s*\{" % opener, lines[i])
        if not m:
            i += 1
            continue
        depth, j, body = 0, i, []
        while j < len(lines):
            code = re.sub(r"//.*$", "", lines[j])
            depth += code.count("{") - code.count("}")
            body.append(lines[j])
            j += 1
            if depth <= 0:
                break
        yield i + 1, m.group(1), "\n".join(body)
        i = j

SKIP = set(os.environ.get("KIT_APPS", "").split())
for path in sorted(pathlib.Path(sys.argv[1]).glob("*/*.qml")):
    if path.parent.name in SKIP:
        continue
    lines = path.read_text().splitlines()

    for start, kind, block in blocks(lines, r"Text|Ui\.OpticalGlyph"):
        # A glyph is a block that paints an icon rather than words: either a
        # private-use codepoint written into it, or a helper that returns one.
        # Weight on an icon font means nothing, so B3 does not apply.
        is_glyph = any(ch >= "" for ch in block) or re.search(
            r"text:.*[Gg]lyph", block)
        centred = "anchors.centerIn" in block or "anchors.fill" in block

        if kind != "Text":
            continue
        if "font.family" not in block:
            problems.append(f"{path}:{start}  Text without font.family (B1)")
        if not is_glyph and "font.weight" not in block:
            problems.append(f"{path}:{start}  Text without font.weight (B3)")
        if is_glyph and centred:
            problems.append(f"{path}:{start}  glyph centred in a slot as a plain "
                            "Text; use Ui.OpticalGlyph (B5)")

    for n, line in enumerate(lines, 1):
        # D1: a radius is one of the four names, a pill/circle, or inherited.
        if re.search(r"^\s*radius:", line):
            if not any(r in line for r in RADII) and not re.search(
                    r"(height|width|iconSize)\s*/|parent\.radius", line):
                problems.append(f"{path}:{n}  radius is not one of the four (D1)")

        # C4: hex is allowed only as the fallback in a typeof-Color guard, and
        # that guard routinely wraps onto the line above.
        if HEX.search(re.sub(r"//.*$", "", line)):
            window = "\n".join(lines[max(0, n - 4):n])
            if "typeof Color" not in window:
                problems.append(f"{path}:{n}  literal hex colour (C4)")

    # ------------------------------------------------------------- H1, H6
    # A control is a MouseArea that answers a tap. It has to name itself, and
    # that name has to reach a press state -- or say in a comment which of the
    # four non-controls it is. The exemption is a comment and not an absence,
    # because an absence is what a forgotten control looks like (H7).
    #
    # Spelled `style.md H7` and not `H7`: a bare (H7) in ControlCenter.qml or
    # AppDrawer.qml already means gestures.md, and both files have one.
    #
    # `SheetArea` counts, and leaving it out was a silent hole for exactly as
    # long as it took to test for: a sheet's controls are MouseAreas by
    # inheritance (refactor.md H3), and ten of them became invisible here the
    # moment they were declared by their new name. The failing branch was run --
    # one `.pressed` read taken away from a converted tile, which this passed --
    # so the type list is part of the check and not a detail of it.
    # J2. Declaring `stdout` on a Shared.Probe replaces the collector that
    # raises `answered`, so the probe runs and tells nobody. Same trap as
    # SheetArea's four handlers, one component along.
    for start, _kind, block in blocks(lines, r"Shared\.Probe"):
        if re.search(r"^\s*stdout\s*:", block, re.M):
            problems.append(f"{path}:{start}  Shared.Probe declares stdout, which "
                            "replaces the collector that raises answered (J2)")

    whole = "\n".join(lines)
    for start, _kind, block in blocks(lines, r"MouseArea|SheetArea"):
        # H3. Declaring one of the four on an instance replaces the shared
        # handler rather than adding to it, so the control silently stops driving
        # the sheet. The hooks are onGrabbed, onDragged and onUngrabbed.
        if _kind == "SheetArea":
            for h in ("onPressed", "onPositionChanged", "onReleased", "onCanceled"):
                if re.search(r"^\s*%s\s*:" % h, block, re.M):
                    problems.append(
                        f"{path}:{start}  SheetArea declares {h}, which replaces "
                        "the shared one: use onGrabbed/onDragged/onUngrabbed (H3)")
        if "onClicked" not in block:
            continue
        if re.search(r"//\s*no press state \(style\.md H7\)", block):
            continue
        m = re.search(r"^\s*id:\s*(\w+)\s*$", block, re.M)
        if not m:
            problems.append(f"{path}:{start}  MouseArea answers onClicked with "
                            "no id, so nothing can bind to its press (H1)")
            continue
        if not re.search(r"\b%s\.pressed\b" % re.escape(m.group(1)), whole):
            problems.append(f"{path}:{start}  {m.group(1)}.pressed is read "
                            "nowhere: this control has no press state (H1)")

    # H6. On the two surfaces whose controls are also the sheet's drag handle,
    # `pressed` stays true for the whole drag -- so an unguarded read lights
    # every tile a scrolling thumb crosses.
    #
    # Read over the following three lines and not the one, because an `on:`
    # expression with three terms wraps, and the guard is as likely to be on the
    # continuation as on the head. The control center's notification card is the case
    # that forced it: it drags sideways rather than opening the sheet, so its
    # guard is the card's own displacement and it sits on line two of the
    # binding. Line-by-line, that read as an unguarded press on a control that
    # has been guarded since it was written.
    #
    # `drag guard (style.md H6)` is the third spelling, for a control whose
    # guard is neither of the two named ones -- declared in a comment, the same
    # way H7 declares a non-control above, because the alternative is teaching
    # this regex one bespoke property name per surface until it matches
    # anything with an `&&` in it.
    if path.name in ("ControlCenter.qml", "AppDrawer.qml"):
        for n, line in enumerate(lines, 1):
            if not re.search(r"\w+\.pressed\b", line):
                continue
            window = "\n".join(lines[n - 1:n + 3])
            if not re.search(r"sheetDragging|handedOver"
                             r"|//\s*drag guard \(style\.md H6\)", window):
                problems.append(f"{path}:{n}  press state on a sheet-drag "
                                "MouseArea with no drag guard (H6)")

print("\n".join(problems))
PY
)
if [[ -z $report ]]; then
  ok "every Text names its family and weight; glyphs in slots use OpticalGlyph (B1, B3, B5)"
  ok "hex only as a pre-theme fallback (C4)"
  ok "every radius is sheet, tile, card, pill or radiusOn (D1)"
  ok "every control that answers a tap shows a pressed state (H1, H6)"
else
  no "style violations" "$report"
fi

# --- E7: nothing that lives in moarchy.common is written out again ----------
# docs/refactor.md E2, E3, E7. PressVeil stood in nine files at 27 identical
# lines apiece and the colour maths in six at twenty, each under a comment
# explaining that an import across plugin directories could not be relied on.
# It can (E1), so the copies are gone -- and this is what stops them coming
# back one screen at a time, which is exactly how they arrived.
#
# Named exceptions rather than a silent pass, and the list is empty now: the two
# moarchy.settings files were migrated 2026-09-15 and the check tightened by
# deleting their names, which is what it was built to do. The mechanism stays --
# the next un-migrated file is counted here rather than being invisible, and an
# entry that stops describing anything fails below.
printf '\nE. shared code\n'
E7_EXEMPT=""
e7=$(python3 - "$PLUGINS" "$E7_EXEMPT" <<'PY'
import pathlib, re, sys

owned = {
    "component PressVeil": r"^\s*component PressVeil\s*:\s*Rectangle",
    "function luminance": r"^\s*function luminance\s*\(",
    "function contrastRatio": r"^\s*function contrastRatio\s*\(",
    "function mix": r"^\s*function mix\s*\(",
    "function readableOn": r"^\s*function readableOn\s*\(",
}
exempt = set(sys.argv[2].split())
problems, stale = [], []

for path in sorted(pathlib.Path(sys.argv[1]).glob("*/*.qml")):
    rel = f"{path.parent.name}/{path.name}"
    if path.parent.name == "moarchy.common":
        continue
    text = path.read_text()
    hits = [name for name, rx in owned.items()
            if re.search(rx, text, re.M)]
    if not hits:
        if rel in exempt:
            stale.append(rel)
        continue
    if rel in exempt:
        continue
    problems.append(f"{rel}  defines {', '.join(hits)}; "
                    "import it from moarchy.common instead")

# An exemption that no longer describes anything is worse than none: it reads
# as remaining debt and silences a real regression in that file.
for rel in stale:
    problems.append(f"{rel}  is listed as an E7 exception but defines none of "
                    "the shared types; drop it from E7_EXEMPT")

print("\n".join(problems))
PY
)
if [[ -z $e7 ]]; then
  ok "PressVeil and the colour maths exist once, in moarchy.common (E2, E3, E7)"
  [[ -n $E7_EXEMPT ]] && printf '        still to migrate: %s\n' "$E7_EXEMPT"
else
  no "shared code written out again (E7)" "$e7"
fi

# --- B1, I2: one list of sheets --------------------------------------------
# docs/refactor.md B1, B6, I1, I2. Five screens kept their own answer to "which
# sheets do I cover" and gave three different ones, which gestures.md A8 records
# as already having cost Settings and Themes their place in the back gesture.
# The list is moarchy.common/Sheet.js now; this is what stops a sixth screen
# writing its own again.
printf '\nB. one list of sheets\n'
sheets=$(grep -rn 'isPluginOpen("moarchy\.\|hide("moarchy\.' "$PLUGINS" \
         | grep -v 'moarchy.common/Sheet.js' | grep -vE ':\s*//' || true)
if [[ -z $sheets ]]; then
  ok "no plugin names another sheet's id: the list is Sheet.js (B1, I2)"
else
  no "a sheet id is written outside Sheet.js (B1)" "$sheets"
fi

# I1a. Sheet.js is plain JavaScript with the host handed in, so the rule that
# decides what leaves the screen can be run without the phone.
#
# Skipped out loud rather than passed quietly when node is absent -- it is a
# development dependency and is not on the device, and a check that stops
# running where nobody looks is the thing this file exists to prevent.
if command -v node >/dev/null 2>&1; then
  if sheet_out=$(node scripts/sheet-test.js 2>&1); then
    ok "Sheet.js covers what B6 says it covers ($(grep -c 'ok' <<<"$sheet_out") cases, I1a)"
  else
    no "the sheet rule is broken (I1a)" "$sheet_out"
  fi
else
  skip "the Sheet.js cases need node, which is not installed here (I1a)"
fi

# gestures.md Q11. The power button's double-press window, with moarchy-screen
# and moarchy-trigger stubbed. Pure arithmetic over one timestamp file, so the
# 400ms rule can be run here rather than checked by hand on glass once.
printf '\npower button (gestures.md Q11, not a style.md section)\n'
if pp_out=$(bash scripts/test-power-press.sh 2>&1); then
  ok "one press toggles, two fire the trigger ($(grep -c PASS <<<"$pp_out") cases, Q11)"
else
  no "the power button's double press is broken (Q11)" "$pp_out"
fi

# gestures.md Q2, Q2a. The edge table: which axis a sheet arrives on, which way
# it opens, and where it sits part-way in. Pure arithmetic with no Qt in it, and
# the first group of cases is each sheet's own pre-Q formula -- so a wrong row
# is caught here rather than as a sheet arriving sideways on the phone.
if command -v node >/dev/null 2>&1; then
  if edge_out=$(node scripts/edge-test.js 2>&1); then
    ok "Edge.js puts each sheet where it shipped ($(grep -c 'ok' <<<"$edge_out") cases, Q2)"
  else
    no "the edge table is broken (Q2)" "$edge_out"
  fi
else
  skip "the Edge.js cases need node, which is not installed here (Q2)"
fi

# gestures.md P7. What a workspace holding two windows is arranged as, which is
# the rule the workspace overview's drag exists on top of. The daemon's own functions with
# `swaymsg` stubbed, so the command strings are asserted rather than the phone --
# including the fallback that focuses a window to set the layout, and therefore
# has to put focus back.
printf '\nworkspace layout (gestures.md P7, not a style.md section)\n'
if ws_out=$(python3 scripts/test-workspace-layout.py 2>&1); then
  ok "one window splits, two are tabs, and the fallback restores focus ($(grep -c 'ok' <<<"$ws_out") cases, P7)"
else
  no "the workspace layout rule is broken (P7)" "$ws_out"
fi

# Chrome file. Corners, control center sizes and which sheet each swipeable edge raises
# (gestures.md Q1) live in ~/.config/omarchy/ui.toml, and moarchy-ui is the
# writer the theme switcher, Settings and an agent all use.
# A parser that disagrees with the writer is a theme switcher that does not
# stick, so both halves are checked here rather than only on the phone.
printf '\nchrome (ui.toml)\n'
if ui_out=$(bash scripts/test-ui.sh 2>&1); then
  ok "moarchy-ui reads and writes the chrome file ($(grep -c PASS <<<"$ui_out") cases)"
else
  no "the chrome file writer is broken" "$ui_out"
fi

# The apps cannot import moarchy.common, so Ui.js exists twice. The tables have
# to be the same tables or a corners pick in the shell would not match the apps.
ui_a=$(grep -A3 'var CORNERS' "$PLUGINS/moarchy.common/Ui.js")
ui_b=$(grep -A3 'var CORNERS' default/omarchy/qs_ui/Ui.js)
if [[ $ui_a == "$ui_b" ]]; then
  ok "plugin and app Ui.js share the same corner table"
else
  no "plugin and app Ui.js corner tables have drifted" "$ui_a"$'\n'"$ui_b"
fi

rad_a=$(grep -A8 'function radiusOn' "$PLUGINS/moarchy.common/Ui.js")
rad_b=$(grep -A8 'function radiusOn' default/omarchy/qs_ui/Ui.js)
if [[ $rad_a == "$rad_b" ]]; then
  ok "plugin and app Ui.js share radiusOn"
else
  no "plugin and app Ui.js radiusOn have drifted" "$rad_a"$'\n'"$rad_b"
fi

# --- F1-F4, F6: one drag tracker, and it stays one -------------------------
# docs/refactor.md §F. Four surfaces each re-derived the same machinery and two
# of the four remembered a watchdog. The component is one file now; these are
# what stop it becoming five again, and what stop it growing the things it
# deliberately does not own.
#
# Greps rather than behaviour, and that is the genre: §F is a contract about
# the shape of the code. What the gestures still *do* is bin/moarchy-selftest
# --gestures, which §G makes the acceptance condition for the whole section.
printf '\nF. one drag tracker\n'
TRACKER="$PLUGINS/moarchy.common/DragTracker.qml"
f=""
[[ -f $TRACKER ]] || f+="  $TRACKER is missing; every surface below has nothing to call"$'\n'

# F1. The speed reading is the fingerprint: one copy, in the tracker. Keyed to
# `speedFloorMs` since the frame-to-frame smoothing it used to name went away --
# a grep for a string that exists nowhere passes whatever the tree looks like.
smoothing=$(grep -rln 'speedFloorMs\|speedAt(' "$PLUGINS" | grep -v 'moarchy.common/DragTracker.qml' || true)
[[ -n $smoothing ]] && f+="  the velocity measurement is written out again in:"$'\n'"$smoothing"$'\n'
grep -q 'speedFloorMs' "$TRACKER" || f+="  the tracker has no speed measurement left to share (F1)"$'\n'

# F3. Thresholds belong to the surface that decided them.
thresholds=$(grep -nE 'Commit|Fraction|fling|homeExtra' "$TRACKER" | grep -v '^\s*[0-9]*:\s*//' | grep -vE ':\s*//' || true)
[[ -n $thresholds ]] && f+="  the tracker names a threshold (F3):"$'\n'"$thresholds"$'\n'

# F4. Travel is an input, never a choice.
travel=$(grep -nE 'closeTravel|sheetHeight|pullTravel|screen\.height' "$TRACKER" | grep -vE ':\s*//' || true)
[[ -n $travel ]] && f+="  the tracker picks its own travel (F4):"$'\n'"$travel"$'\n'

# F6. Nothing forks or marshals at touch-event rate.
host=$(grep -nE 'panelLoaders|shell\.|execDetached|Quickshell\.' "$TRACKER" | grep -vE ':\s*//' || true)
[[ -n $host ]] && f+="  the tracker reaches for the host (F6):"$'\n'"$host"$'\n'

if [[ -z $f ]]; then
  ok "the drag machinery exists once, owns no threshold and no travel (F1, F3, F4, F6)"
else
  no "the drag tracker has drifted (F)" "$f"
fi

# --- gestures.md K5: a shell app's tile wears its own glyph -------------------
# Not a style.md section. A shell app's window carries the shell process's own
# app id, so the workspace overview's tile has no desktop entry to take an icon from and
# asks the plugin for a glyph instead -- and an empty one falls through to an
# Image with an empty source, which draws nothing at all. Settings shipped that
# way from a116d9a: the tile carried the right name and a blank square, and
# every automated check passed, because the criterion is about a character and
# nothing was reading it.
#
# The declaration and not the rendering, which is the half a terminal can see.
printf '\nshell apps (gestures.md K5, not a style.md section)\n'
glyphs=$(python3 - "$PLUGINS" <<'GLYPHPY'
import os, pathlib, re, sys

problems, seen = [], 0
SKIP = set(os.environ.get("KIT_APPS", "").split())
for path in sorted(pathlib.Path(sys.argv[1]).glob("*/*.qml")):
    if path.parent.name == "moarchy.common" or path.parent.name in SKIP:
        continue
    lines = path.read_text().splitlines()
    for i, line in enumerate(lines):
        if not re.match(r"^\s*(?:\w+\.)?AppWindow\s*{", line):
            continue
        seen += 1
        # Everything indented past the opening line, which is enough here:
        # these are hand-written declarations, and a brace counter would trip
        # over a brace inside a string.
        indent = len(line) - len(line.lstrip())
        body = []
        for rest in lines[i + 1:]:
            if rest.strip() and (len(rest) - len(rest.lstrip())) <= indent:
                break
            body.append(rest)
        # The window's own properties, at one level in -- not any `glyph:`
        # anywhere inside it. Settings has a second one on a row delegate
        # eleven levels down (`glyph: modelData.glyph || ""`), and a search
        # over the whole block found that instead and passed while the
        # window's own was missing. A check that reads the wrong line is worse
        # than no check: it reports the thing it is not looking at.
        own = [b for b in body
               if len(b) - len(b.lstrip()) == indent + 2]
        glyph = re.search(r"^\s*glyph\s*:\s*(.+?)\s*$", "\n".join(own), re.M)
        rel = f"{path.parent.name}/{path.name}"
        if not glyph:
            problems.append(f"{rel}:{i + 1}  AppWindow declares no glyph")
        elif glyph.group(1) in ('""', "''"):
            problems.append(f"{rel}:{i + 1}  AppWindow declares an empty glyph; "
                            "its tile in the workspaceOverview draws nothing")
if not seen:
    problems.append("!! no AppWindow found -- this check is reading nothing")
print("%d|%s" % (seen, "; ".join(problems)))
GLYPHPY
)
glyph_n=${glyphs%%|*}
glyph_bad=${glyphs#*|}
if [[ -z ${glyph_bad// /} ]]; then
  ok "every shell app declares a glyph for its tile ($glyph_n windows, K5)"
else
  no "a shell app has no glyph (K5)" "$glyph_bad"
fi

# --- the artwork parses ------------------------------------------------------
# Every icon this project ships is a file rather than a theme name, argued at
# length in moarchy.device/icon.svg, and each carries a paragraph of prose
# saying why it is drawn the way it is. XML forbids a double hyphen inside a
# comment, so one em dash rewritten as two hyphens makes the whole file
# unparseable, and nothing says so: rsvg refuses it, Qt refuses it, the app drawer
# draws the label with an empty square above it, and no log anywhere mentions
# it. It has now happened twice, in the same hour, in two files whose own
# comments warn about it -- which is the definition of a rule that needs a
# check rather than a paragraph.
#
# ElementTree and not xmllint: python3 is already what every check above runs
# on, and a check that silently stops running on a machine without libxml2 is
# the shape of thing this file exists to prevent.
printf '\nartwork (not a style.md section)\n'
svg_report=$(python3 - "$PLUGINS" default/agents <<'PY'
import pathlib, sys
import xml.etree.ElementTree as ET

files = []
for root in sys.argv[1:]:
    files.extend(sorted(pathlib.Path(root).rglob("*.svg")))
if not files:
    print("!! no SVG found under " + " ".join(sys.argv[1:]))
    raise SystemExit
problems = []
for path in files:
    try:
        ET.parse(path)
    except ET.ParseError as exc:
        problems.append(f"{path}  {exc}")
print("%d|%s" % (len(files), "; ".join(problems)))
PY
)
svg_n=${svg_report%%|*}
svg_bad=${svg_report#*|}
if [[ $svg_report == !!* || -z $svg_n || $svg_n == 0 ]]; then
  no "${svg_report:-no SVG found}" "with nothing to read, this check reports every icon fine"
elif [[ -z ${svg_bad// /} ]]; then
  ok "every shipped SVG parses ($svg_n files)"
else
  no "unparseable SVG: $svg_bad" \
     "a double hyphen inside an XML comment; the appDrawer draws the label and no icon"
fi

printf '\n%d passed, %d failed' "$pass" "$fail"
[[ $skipped -gt 0 ]] && printf ', %d skipped' "$skipped"
printf '\n'
printf 'E (touch targets) and F (text inputs) are not checked here -- they need the phone.\n'
[[ $fail -eq 0 ]]
