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
# C4 (no stray hex), D1 (four named radii).
#
# Does NOT cover E (touch targets) or F (text inputs): a hit area is a runtime
# rectangle, and the accessors that answer for it -- `omarchy-shell drawer
# searchTarget`, `omarchy-shell wifi passTarget` -- need the phone. See
# docs/style.md §I.
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

print("\n".join(problems))
PY
)
if [[ -z $report ]]; then
  ok "every Text names its family and weight; glyphs in slots use OpticalGlyph (B1, B3, B5)"
  ok "hex only as a pre-theme fallback (C4)"
  ok "every radius is sheet, tile, card, pill or circle (D1)"
else
  no "style violations" "$report"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
printf 'E (touch targets) and F (text inputs) are not checked here -- they need the phone.\n'
[[ $fail -eq 0 ]]
