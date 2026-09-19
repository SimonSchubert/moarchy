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

if [[ $fail -gt 0 ]]; then
  echo "$fail failed"
  exit 1
fi
echo "all passed"
