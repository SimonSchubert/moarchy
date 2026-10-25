#!/usr/bin/env bash
# bin/moarchy-owl against a store served from a folder, without the network
# (docs/owl.md OW17).
#
#   ./scripts/test-owl.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OWL="$ROOT/bin/moarchy-owl"
HOMECLI="$ROOT/bin/moarchy-home"
chmod +x "$OWL" "$HOMECLI"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$HOME"
STORE="$WORK/store"
export MOARCHY_OWL_STORE="file://$STORE/"
# What would have been installed, instead of installing it.
printf '#!/bin/sh\necho "$@" >> %s/pacman.log\n' "$WORK" > "$WORK/pacman"; chmod +x "$WORK/pacman"
export MOARCHY_OWL_PACMAN="$WORK/pacman"
W="$XDG_CONFIG_HOME/omarchy/widgets"

fail=0
ok() { printf '  PASS  %s\n' "$1"; }
no() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

# A store of two widgets: one that runs a command and needs jq, one too new.
mkdir -p "$STORE/widgets/test/clock" "$STORE/widgets/test/future"
printf 'widget "clock" {\n  Text { text: "12:00" }\n}\n' > "$STORE/widgets/test/clock/widget.owl"
printf 'widget "future" {\n}\n' > "$STORE/widgets/test/future/widget.owl"
catalog() { # version commands-json sha
  python3 - "$STORE" "$1" "$2" "${3:-}" <<'PY'
import hashlib, json, sys
store, version, commands, sha = sys.argv[1:]
data = open(store + "/widgets/test/clock/widget.owl", "rb").read()
fut = open(store + "/widgets/test/future/widget.owl", "rb").read()
json.dump({"widgets": [
  {"id": "test/clock", "name": "clock", "author": "test", "version": version, "description": "a clock",
   "license": "MIT", "path": "widgets/test/clock/widget.owl", "sha256": sha or hashlib.sha256(data).hexdigest(),
   "size": [2, 2], "requires": {"pacman": ["jq"]}, "commands": json.loads(commands), "owl": 5, "category": "time"},
  {"id": "test/future", "name": "future", "author": "test", "version": "1.0", "description": "too new",
   "license": "MIT", "path": "widgets/test/future/widget.owl", "sha256": hashlib.sha256(fut).hexdigest(),
   "size": [3, 2], "requires": {}, "commands": [], "owl": 99}]}, open(store + "/index.json", "w"))
PY
}
field() { python3 -c 'import json,sys; d=json.load(sys.stdin); w=[x for x in d["widgets"] if x["id"]==sys.argv[1]][0]; print(w[sys.argv[2]])' "$@"; }

# --- a SHA-256 that is not the file's installs nothing (OW11 step 1) -----------
catalog 1.0 '["date +%H:%M"]' 0000000000000000000000000000000000000000000000000000000000000000
rc=0; "$OWL" install test/clock 1 >/dev/null 2>&1 || rc=$?
[[ $rc -eq 5 && ! -e $W/test-clock.owl && ! -e $W/.market.json && ! -e $XDG_CONFIG_HOME/omarchy/home.toml ]] \
  && ok "a download whose SHA-256 is not the catalogue's installs nothing" || no "bad SHA-256: rc=$rc"

# --- install (OW11) ------------------------------------------------------------
catalog 1.0 '["date +%H:%M"]'
"$OWL" catalog --refresh >/dev/null
"$OWL" install test/clock 1 >/dev/null
cmp -s "$W/test-clock.owl" "$STORE/widgets/test/clock/widget.owl" && ok "install writes the reviewed file as <author>-<name>.owl" \
  || no "the installed file is not the store's"
python3 - "$W/.market.json" <<'PY' && ok "install records the version, commands, packages and SHA-256 approved" || no "the record is wrong"
import json, sys
r = json.load(open(sys.argv[1]))["test/clock"]
assert r["version"] == "1.0" and r["commands"] == ["date +%H:%M"] and r["requires"] == {"pacman": ["jq"]}, r
assert len(r["sha256"]) == 64
PY
grep -q -- '-S --needed --noconfirm jq' "$WORK/pacman.log" 2>/dev/null && ok "install installs the packages it needs" \
  || no "pacman was not asked for jq: $(cat "$WORK/pacman.log" 2>/dev/null)"
"$HOMECLI" show | grep -qE '^  test-clock +first free spot +2x2' && ok "install puts a tile of its size on the page" \
  || no "no tile: $("$HOMECLI" show)"
[[ $("$OWL" catalog | field test/clock installed) == 1.0 ]] && ok "the catalogue says what is installed" || no "catalog: not installed"
rc=0; "$OWL" install test/clock >/dev/null 2>&1 || rc=$?
[[ $rc -eq 1 ]] && ok "an installed widget is updated, not installed twice" || no "second install: rc=$rc"

# --- too new (OW10) ------------------------------------------------------------
rc=0; "$OWL" install test/future 1 >/dev/null 2>&1 || rc=$?
[[ $rc -eq 6 && ! -e $W/test-future.owl && $("$OWL" catalog | field test/future supported) == False ]] \
  && ok "a widget above the runtime's owl level is not installed, and says so" || no "future: rc=$rc"

# --- an update that runs other commands asks again (OW12) ------------------------
catalog 1.1 '["date +%H:%M", "curl wttr.in"]'
"$OWL" catalog --refresh >/dev/null
[[ $("$OWL" catalog | field test/clock update) == True && $("$OWL" catalog | field test/clock changed) == True ]] \
  && ok "a newer version whose commands changed is an update, marked changed" || no "update not marked"
rc=0; "$OWL" update test/clock >/dev/null 2>&1 || rc=$?
[[ $rc -eq 3 ]] && grep -q '"1.0"' "$W/.market.json" && ok "it is not applied without --yes" || no "update went ahead: rc=$rc"
"$OWL" update test/clock --yes >/dev/null
grep -q '"1.1"' "$W/.market.json" && grep -q 'curl wttr.in' "$W/.market.json" \
  && ok "with --yes it is, and the new commands are the approved ones" || no "the record was not updated"

# --- an edited file (OW13) -------------------------------------------------------
echo "// mine" >> "$W/test-clock.owl"
[[ $("$OWL" catalog | field test/clock edited) == True ]] && ok "a file changed since it was installed is marked edited" \
  || no "edit not seen"
rc=0; "$OWL" update test/clock >/dev/null 2>&1 || rc=$?
[[ $rc -eq 3 ]] && grep -q '// mine' "$W/test-clock.owl" && ok "and its update does not replace it without --yes" \
  || no "the edit was replaced (rc=$rc)"

# --- offline (OW8) ---------------------------------------------------------------
MOARCHY_OWL_STORE="file://$WORK/nowhere/" "$OWL" catalog --refresh | grep -q '"offline": true' \
  && ok "offline, the cached catalogue is used and said to be" || no "offline catalogue"

# --- remove (OW14) ---------------------------------------------------------------
"$OWL" remove test/clock >/dev/null
[[ ! -e $W/test-clock.owl ]] && ! grep -q test/clock "$W/.market.json" && ! "$HOMECLI" show | grep -q test-clock \
  && ok "remove leaves no file, no record and no tile" || no "remove left something"

echo
if [[ $fail -gt 0 ]]; then echo "$fail failed"; exit 1; fi
echo "all passed"
