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
# control, guarded where the control is also a drag handle). Plus one thing
# that is not an AC at all: that every SVG this project ships still parses.
#
# Does NOT cover E (touch targets) or F (text inputs): a hit area is a runtime
# rectangle, and the accessors that answer for it -- `omarchy-shell drawer
# searchTarget`, `omarchy-shell wifi passTarget` -- need the phone. See
# docs/style.md §J.
#
#   scripts/style-check.sh            # from anywhere
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
PLUGINS=default/omarchy/plugins

pass=0
fail=0
ok() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [[ -n ${2:-} ]] && printf '%s\n' "$2"; fail=$((fail + 1)); }

# --- A1, A2, A3: nothing is written as a number -----------------------------
# `|| true` on purpose: a grep that matches nothing exits 1, and that would
# otherwise be read as a failure of the check rather than as a clean result.
printf '\nA. tokens\n'
hits=$(grep -rn 'pixelSize: [0-9]\|margins: [0-9]\|Margin: [0-9]\|spacing: [1-9]\|radius: [0-9]' "$PLUGINS" || true)
if [[ -z $hits ]]; then
  ok "no literal sizes, margins, spacings or radii (A1-A3)"
else
  no "literal values where a token belongs (A1-A3)" "$hits"
fi

# --- B, C4, D1: need to know where a block starts and ends ------------------
printf '\nB. type / C. colour / D. shape\n'
report=$(python3 - "$PLUGINS" <<'PY'
import pathlib, re, sys

RADII = ("radiusSheet", "radiusTile", "radiusCard")
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

for path in sorted(pathlib.Path(sys.argv[1]).glob("*/*.qml")):
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
    # Spelled `style.md H7` and not `H7`: a bare (H7) in Shade.qml or
    # Drawer.qml already means gestures.md, and both files have one.
    whole = "\n".join(lines)
    for start, _kind, block in blocks(lines, r"MouseArea"):
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
    # continuation as on the head. The shade's notification card is the case
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
    if path.name in ("Shade.qml", "Drawer.qml"):
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
  ok "every radius is sheet, tile, card, pill or circle (D1)"
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
# Named exceptions rather than a silent pass. moarchy.settings is another
# session's file (docs/refactor.md Open questions) and is migrated in a second
# pass; listing it here means the day it is migrated this check tightens by
# deleting a line, and until then the debt is counted rather than invisible.
printf '\nE. shared code\n'
E7_EXEMPT="moarchy.settings/Settings.qml moarchy.settings/SettingsRow.qml"
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

# F1. The smoothing is the fingerprint: one copy, in the tracker.
smoothing=$(grep -rln 'velocity \* 0\.6' "$PLUGINS" | grep -v 'moarchy.common/DragTracker.qml' || true)
[[ -n $smoothing ]] && f+="  the velocity smoothing is written out again in:"$'\n'"$smoothing"$'\n'

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

# --- gestures.md M4: a shell app's tile wears its own glyph -------------------
# Not a style.md section. A shell app's window carries the shell process's own
# app id, so the drawer's shelf has no desktop entry to take an icon from and
# asks the plugin for a glyph instead -- and an empty one falls through to an
# Image with an empty source, which draws nothing at all. Settings shipped that
# way from a116d9a: the tile carried the right name, the running dot and a
# blank square, and every automated check passed, because M4 is about a
# character and nothing was reading it.
#
# The declaration and not the rendering, which is the half a terminal can see.
printf '\nshell apps (gestures.md M4, not a style.md section)\n'
m4=$(python3 - "$PLUGINS" <<'M4PY'
import pathlib, re, sys

problems, seen = [], 0
for path in sorted(pathlib.Path(sys.argv[1]).glob("*/*.qml")):
    if path.parent.name == "moarchy.common":
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
                            "its tile on the drawer's shelf draws nothing")
if not seen:
    problems.append("!! no AppWindow found -- this check is reading nothing")
print("%d|%s" % (seen, "; ".join(problems)))
M4PY
)
m4_n=${m4%%|*}
m4_bad=${m4#*|}
if [[ -z ${m4_bad// /} ]]; then
  ok "every shell app declares a glyph for its shelf tile ($m4_n windows, M4)"
else
  no "a shell app has no glyph (M4)" "$m4_bad"
fi

# --- the artwork parses ------------------------------------------------------
# Every icon this project ships is a file rather than a theme name, argued at
# length in moarchy.device/icon.svg, and each carries a paragraph of prose
# saying why it is drawn the way it is. XML forbids a double hyphen inside a
# comment, so one em dash rewritten as two hyphens makes the whole file
# unparseable, and nothing says so: rsvg refuses it, Qt refuses it, the drawer
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
     "a double hyphen inside an XML comment; the drawer draws the label and no icon"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
printf 'E (touch targets) and F (text inputs) are not checked here -- they need the phone.\n'
[[ $fail -eq 0 ]]
