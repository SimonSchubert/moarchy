#!/usr/bin/env bash
# The power button's two meanings (docs/gestures.md Q11), without a phone.
#
#   ./scripts/test-power-press.sh
#
# moarchy-power-press is pure arithmetic over one timestamp file, so what it
# needs stubbing is only the two things it calls. That is the whole reason the
# double-press window lives in a script rather than in the sway binding: a
# 400ms rule nobody can run is a 400ms rule that becomes 4000ms in a refactor
# and is noticed by hand, once, months later.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
export XDG_STATE_HOME="$HOME/.local/state"
mkdir -p "$XDG_STATE_HOME/moarchy" "$WORK/bin"

# Stubs that record rather than act.
cat > "$WORK/bin/moarchy-screen" <<'E'
#!/bin/bash
printf 'screen:%s\n' "$1" >>"$XDG_STATE_HOME/moarchy/calls"
E
cat > "$WORK/bin/moarchy-trigger" <<'E'
#!/bin/bash
printf 'trigger:%s:%s\n' "$1" "$2" >>"$XDG_STATE_HOME/moarchy/calls"
E
chmod +x "$WORK/bin"/*
export PATH="$WORK/bin:$PATH"

PRESS="$ROOT/bin/moarchy-power-press"
CALLS="$XDG_STATE_HOME/moarchy/calls"

fail=0
ok() { printf '  PASS  %s\n' "$1"; }
no() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
reset() { : >"$CALLS"; rm -f "$XDG_STATE_HOME/moarchy/power-press"; }
calls() { tr '\n' ' ' <"$CALLS"; }

# --- one press on its own -------------------------------------------------
reset
bash "$PRESS" >/dev/null 2>&1
[[ $(calls) == "screen:toggle " ]] \
  && ok "one press toggles the screen and fires nothing" \
  || no "one press did: $(calls)"

# --- two presses inside the window ----------------------------------------
reset
bash "$PRESS" >/dev/null 2>&1
bash "$PRESS" >/dev/null 2>&1
[[ $(calls) == "screen:toggle screen:unlock trigger:fire:power " ]] \
  && ok "two fast presses unlock and fire the trigger (Q11)" \
  || no "two fast presses did: $(calls)"

# Q11a. `unlock`, never a second `toggle`: the first press may have been the
# unlock, and toggling there would blank the screen the trigger is opening on.
reset
bash "$PRESS" >/dev/null 2>&1
bash "$PRESS" >/dev/null 2>&1
[[ $(grep -c 'screen:toggle' "$CALLS") -eq 1 ]] \
  && ok "the second press unlocks rather than toggling again (Q11a)" \
  || no "toggle was called $(grep -c 'screen:toggle' "$CALLS") times"

# --- two presses outside the window ---------------------------------------
reset
bash "$PRESS" >/dev/null 2>&1
sleep 0.6
bash "$PRESS" >/dev/null 2>&1
[[ $(calls) == "screen:toggle screen:toggle " ]] \
  && ok "two slow presses are two single presses" \
  || no "two slow presses did: $(calls)"

# --- three fast presses ---------------------------------------------------
# Q11b. A double and then a single, not two overlapping doubles.
reset
bash "$PRESS" >/dev/null 2>&1
bash "$PRESS" >/dev/null 2>&1
bash "$PRESS" >/dev/null 2>&1
[[ $(grep -c 'trigger:fire:power' "$CALLS") -eq 1 ]] \
  && ok "three fast presses fire the trigger once (Q11b)" \
  || no "three fast presses fired it $(grep -c 'trigger:fire:power' "$CALLS") times"

# --- a stamp that is not a number -----------------------------------------
# The file is in $HOME and a person may have looked at it; garbage in it must
# read as "no previous press" rather than as an arithmetic error.
reset
echo "not a number" >"$XDG_STATE_HOME/moarchy/power-press"
bash "$PRESS" >/dev/null 2>&1
[[ $(calls) == "screen:toggle " ]] \
  && ok "a corrupt stamp reads as no previous press" \
  || no "a corrupt stamp did: $(calls)"

# --- the very first press of a session ------------------------------------
reset
bash "$PRESS" >/dev/null 2>&1
[[ -s "$XDG_STATE_HOME/moarchy/power-press" ]] \
  && ok "the press is stamped for the next one to measure against" \
  || no "no stamp was written"

if [[ $fail -gt 0 ]]; then
  echo "$fail failed"
  exit 1
fi
echo "all passed"
