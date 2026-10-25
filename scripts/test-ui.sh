#!/usr/bin/env bash
# ~/.config/omarchy/ui.toml is the chrome file. This checks the writer
# against the documented defaults, without a phone.
#
#   ./scripts/test-ui.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI="$ROOT/bin/moarchy-ui"
[[ -x $UI ]] || chmod +x "$UI"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME"

fail=0
ok() { printf '  PASS  %s\n' "$1"; }
no() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

out=$("$UI")
[[ $out == *'corners=large'* && $out == *'control_center=roomy'* ]] \
  && ok "missing file is large/roomy" \
  || no "missing file should be large/roomy, got: $out"

[[ $("$UI" get corners) == large ]] && ok "get corners defaults to large" \
  || no "get corners: $("$UI" get corners)"
[[ $("$UI" get corners-label) == Large ]] && ok "corners-label Large" \
  || no "corners-label: $("$UI" get corners-label)"

"$UI" corners modest >/dev/null
[[ $("$UI" get corners) == modest ]] && ok "corners modest sticks" \
  || no "after modest: $("$UI" get corners)"
[[ -f $HOME/.config/omarchy/ui.toml ]] && ok "writes ~/.config/omarchy/ui.toml" \
  || no "user file was not created"

"$UI" corners none >/dev/null
[[ $("$UI" get corners) == square ]] && ok "none aliases to square" \
  || no "none should be square, got $("$UI" get corners)"
[[ $("$UI" get corners-label) == Square ]] && ok "corners-label Square" \
  || no "label: $("$UI" get corners-label)"

"$UI" control-center compact >/dev/null
[[ $("$UI" get control-center) == compact ]] && ok "control-center compact sticks" \
  || no "after compact: $("$UI" get control-center)"
[[ $("$UI" get corners) == square ]] && ok "control-center write keeps corners" \
  || no "corners lost after control-center write: $("$UI" get corners)"

"$UI" set sheet 16 >/dev/null
[[ $("$UI" get sheet) == 16 ]] && ok "numeric sheet override" \
  || no "sheet: $("$UI" get sheet)"
grep -q 'sheet = 16' "$HOME/.config/omarchy/ui.toml" \
  && ok "override is in the file" \
  || no "sheet = 16 missing from toml"

"$UI" corners large >/dev/null
sheet=$("$UI" get sheet)
[[ -z $sheet ]] && ok "preset retake drops radius overrides" \
  || no "sheet still $sheet after corners large"

# gestures.md Q1. Which sheet each swipeable edge raises. Words, and the
# defaults are today's wiring -- a home with no ui.toml is the phone as it
# shipped, which is the half of this that nobody would notice was broken.
rm -f "$HOME/.config/omarchy/ui.toml"
[[ $("$UI" get gesture-bottom) == app-drawer ]] && ok "gesture-bottom defaults to app-drawer" \
  || no "gesture-bottom: $("$UI" get gesture-bottom)"
[[ $("$UI" get gesture-right) == workspace-overview ]] && ok "gesture-right defaults to workspace-overview" \
  || no "gesture-right: $("$UI" get gesture-right)"
[[ $("$UI" get gesture-bottom-label) == "App drawer" ]] && ok "gesture-bottom-label reads App drawer" \
  || no "label: $("$UI" get gesture-bottom-label)"
[[ $("$UI" get gesture-summary) == "App drawer · Workspace overview" ]] && ok "gesture-summary is the pair" \
  || no "summary: $("$UI" get gesture-summary)"

"$UI" gesture-right control-center >/dev/null
[[ $("$UI" get gesture-right) == control-center ]] && ok "gesture-right control-center sticks" \
  || no "after control-center: $("$UI" get gesture-right)"
[[ $("$UI" get gesture-bottom) == app-drawer ]] && ok "one edge's write leaves the other alone" \
  || no "bottom moved to: $("$UI" get gesture-bottom)"

# A typo must not switch an edge off. Ui.js normTarget() is the same rule, and
# both sides falling back to the caller's current value is what makes a
# hand-edited file safe.
"$UI" gesture-right nonsense >/dev/null
[[ $("$UI" get gesture-right) == control-center ]] && ok "an unknown word keeps the current value" \
  || no "nonsense left: $("$UI" get gesture-right)"

"$UI" gesture-bottom none >/dev/null
[[ $("$UI" get gesture-bottom) == none ]] && ok "none is a value, not a fallback" \
  || no "after none: $("$UI" get gesture-bottom)"
[[ $("$UI" get gesture-bottom-label) == Nothing ]] && ok "none reads as Nothing" \
  || no "label: $("$UI" get gesture-bottom-label)"

# A file written before these keys existed has neither of them, and must come
# back as the shipped pairing rather than as two dead edges.
printf 'corners = "modest"\n' >"$HOME/.config/omarchy/ui.toml"
[[ $("$UI" get gesture-bottom) == app-drawer && $("$UI" get gesture-right) == workspace-overview ]] \
  && ok "a file with no gesture keys is the shipped pairing" \
  || no "old file gave: $("$UI" get gesture-bottom)/$("$UI" get gesture-right)"

# The corners verb drops the radii it owns; it must not drop these.
"$UI" gesture-right control-center >/dev/null
"$UI" corners square >/dev/null
[[ $("$UI" get gesture-right) == control-center ]] && ok "a corners retake keeps the edges" \
  || no "corners write lost gesture-right: $("$UI" get gesture-right)"

# gestures.md Q10. The two triggers that tap rather than drag take a wider
# vocabulary: a word, or any desktop entry id. An id cannot be whitelisted, so
# the rule is the opposite of the edges' -- pass an unknown value through
# rather than fall back to a default.
rm -f "$HOME/.config/omarchy/ui.toml"
[[ $("$UI" get gesture-hold) == agent ]] && ok "gesture-hold ships as the coding agent (C1)" \
  || no "gesture-hold: $("$UI" get gesture-hold)"
[[ $("$UI" get gesture-power) == none ]] && ok "gesture-power ships off (Q11c)" \
  || no "gesture-power: $("$UI" get gesture-power)"
[[ $("$UI" get gesture-hold-label) == "Coding agent" ]] && ok "agent reads as Coding agent" \
  || no "hold label: $("$UI" get gesture-hold-label)"

"$UI" gesture-hold org.gnome.Calls >/dev/null
[[ $("$UI" get gesture-hold) == org.gnome.Calls ]] \
  && ok "an app id is stored verbatim, case and all" \
  || no "after an app id: $("$UI" get gesture-hold)"

# The edges fall back on an unknown word; these must not, or every app would
# be normalised away to the default the moment it was chosen.
"$UI" gesture-power some.unknown.App >/dev/null
[[ $("$UI" get gesture-power) == some.unknown.App ]] \
  && ok "an unknown value passes through rather than falling back" \
  || no "unknown value became: $("$UI" get gesture-power)"

"$UI" gesture-power control-center >/dev/null
[[ $("$UI" get gesture-power-label) == "Control Center" ]] \
  && ok "a sheet word still reads as its name" \
  || no "power label: $("$UI" get gesture-power-label)"

"$UI" gesture-hold off >/dev/null
[[ $("$UI" get gesture-hold) == none ]] && ok "off is an alias for none here too" \
  || no "after off: $("$UI" get gesture-hold)"

# All four keys survive a write to any one of them.
"$UI" gesture-bottom control-center >/dev/null
[[ $("$UI" get gesture-power) == control-center && $("$UI" get gesture-hold) == none ]] \
  && ok "an edge write leaves both tap triggers alone" \
  || no "after an edge write: hold=$("$UI" get gesture-hold) power=$("$UI" get gesture-power)"
"$UI" corners large >/dev/null
[[ $("$UI" get gesture-hold) == none && $("$UI" get gesture-power) == control-center ]] \
  && ok "a corners retake leaves all four gesture keys alone" \
  || no "corners write lost a gesture key"

# docs/home.md HM29. A file from before the sections reads as it did, and the
# first write moves each flat key into its section without losing a comment
# the user wrote.
cat >"$HOME/.config/omarchy/ui.toml" <<'TOML'
# my phone, my corners
corners = "square"
gesture_bottom = "control-center"
sheet = 9
TOML
[[ $("$UI" get corners) == square && $("$UI" get gesture-bottom) == control-center && $("$UI" get sheet) == 9 ]] \
  && ok "a flat file reads as it always did" \
  || no "flat file read as: $("$UI" get corners)/$("$UI" get gesture-bottom)/$("$UI" get sheet)"
"$UI" gesture-right none >/dev/null
F="$HOME/.config/omarchy/ui.toml"
grep -q '^# my phone, my corners$' "$F" && ok "the user's comment survives the migration" \
  || no "the comment is gone: $(cat "$F")"
# Above the first section only: `corners` and `sheet` keep their names inside
# [shape], which is what moarchy-keyboard's section-blind reader relies on.
top=$(awk '/^\[/{exit} {print}' "$F")
grep -qE '^(corners|gesture_bottom|sheet) *=' <<<"$top" && no "a flat key is still at the top: $top" \
  || ok "no flat key is left above the sections"
python3 -c 'import sys,tomllib; d=tomllib.load(open(sys.argv[1],"rb")); assert d["shape"]["corners"]=="square" and d["shape"]["sheet"]==9 and d["gestures"]["bottom"]=="control-center" and d["gestures"]["right"]=="none", d' "$F" \
  && ok "the migrated file is TOML with every value in its section" \
  || no "migrated file: $(cat "$F")"

# HM29. Not TOML -- no quotes -- and read for a year by the old reader.
printf 'corners = modest\n' >"$F"
[[ $("$UI" get corners) == modest ]] && ok "an unquoted value still reads" \
  || no "unquoted corners read as $("$UI" get corners)"

# HM31. A write changes the line it was asked about and nothing else.
rm -f "$F"
"$UI" set home.opacity 0.7 >/dev/null
cat >>"$F" <<'TOML'
# a note I keep here
TOML
before=$(grep -v '^opacity' "$F")
"$UI" set home.opacity 0.5 >/dev/null
after=$(grep -v '^opacity' "$F")
[[ $before == "$after" && $("$UI" get home.opacity) == 0.5 ]] && ok "set home.opacity changes one line" \
  || no "set changed more than the line: $(diff <(echo "$before") <(echo "$after"))"
grep -q '^\[home\]$' "$F" && ok "the key lands under [home]" || no "no [home] in: $(cat "$F")"

rc=0; out=$("$UI" set home.opacty 0.7 2>&1) || rc=$?
[[ $rc -eq 2 && $out == *opacity* ]] && ok "a misspelt key exits 2 and names the real one" \
  || no "misspelt key: rc=$rc out=$out"
rc=0; "$UI" set home.columns 40 >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 && $("$UI" get home.columns) == 6 ]] && ok "an out-of-range value is refused, not clamped" \
  || no "columns 40: rc=$rc now $("$UI" get home.columns)"
"$UI" set home.prompt-bar no >/dev/null
[[ $("$UI" get home.prompt-bar) == false ]] && ok "a boolean takes yes/no and stores false" \
  || no "prompt-bar: $("$UI" get home.prompt-bar)"
rc=0; "$UI" set gestures.bottom nonsense >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 && $("$UI" get gesture-bottom) == app-drawer ]] && ok "a dotted gesture set refuses an unknown sheet" \
  || no "gestures.bottom nonsense: rc=$rc now $("$UI" get gesture-bottom)"
"$UI" set shape.corners modest >/dev/null
"$UI" set sheet 5 >/dev/null
"$UI" set shape.corners large >/dev/null
[[ -z $("$UI" get sheet) ]] && ok "set shape.corners drops the radius overrides, as the corners verb does" \
  || no "sheet still $("$UI" get sheet)"

n=$("$UI" keys | grep -c ' = ')
[[ $n -ge 20 ]] && ok "keys lists every documented key ($n)" || no "keys listed $n"
"$UI" keys | grep -q '^shape.frame = 16' && ok "an override documented as a comment is a key too" \
  || no "shape.frame missing from: $("$UI" keys)"

if [[ $fail -gt 0 ]]; then
  echo "$fail failed"
  exit 1
fi
echo "all passed"
