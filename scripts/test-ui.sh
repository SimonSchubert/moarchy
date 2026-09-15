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
[[ $out == *'corners=large'* && $out == *'shade=roomy'* ]] \
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

"$UI" shade compact >/dev/null
[[ $("$UI" get shade) == compact ]] && ok "shade compact sticks" \
  || no "after compact: $("$UI" get shade)"
[[ $("$UI" get corners) == square ]] && ok "shade write keeps corners" \
  || no "corners lost after shade write: $("$UI" get corners)"

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

if [[ $fail -gt 0 ]]; then
  echo "$fail failed"
  exit 1
fi
echo "all passed"
