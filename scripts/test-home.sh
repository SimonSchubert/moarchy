#!/usr/bin/env bash
# bin/moarchy-home's arranging, sharing and importing (docs/home.md HM47,
# HM48), against a throwaway HOME, without a phone.
#
#   ./scripts/test-home.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOMECLI="$ROOT/bin/moarchy-home"
[[ -x $HOMECLI ]] || chmod +x "$HOMECLI"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME"
FILE="$XDG_CONFIG_HOME/omarchy/home.toml"
WIDGETS="$XDG_CONFIG_HOME/omarchy/widgets"

fail=0
ok() { printf '  PASS  %s\n' "$1"; }
no() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

# --- set (HM48) --------------------------------------------------------------
layout='{"page":[{"face":"start"},{"tiles":[{"widget":"today","x":0,"y":0,"w":3,"h":4},{"widget":"fetch","x":3,"y":0,"w":3,"h":4}]},{"tiles":[{"widget":"media","x":0,"y":0,"w":6,"h":2}]}]}'
"$HOMECLI" set "$layout" >/dev/null
python3 - "$FILE" <<'EOF' && ok "set writes the pages it was given, in order, at their cells" || no "set did not write what it was given"
import sys, tomllib
p = tomllib.load(open(sys.argv[1], "rb"))["page"]
assert p[0] == {"face": "start"}, p[0]
assert p[1]["tiles"] == [{"widget": "today", "x": 0, "y": 0, "w": 3, "h": 4},
                         {"widget": "fetch", "x": 3, "y": 0, "w": 3, "h": 4}], p[1]
assert p[2]["tiles"] == [{"widget": "media", "x": 0, "y": 0, "w": 6, "h": 2}], p[2]
EOF

printf '# my notes about home\n\n' | cat - "$FILE" > "$WORK/f" && mv "$WORK/f" "$FILE"
"$HOMECLI" set "$layout" >/dev/null
head -1 "$FILE" | grep -qx '# my notes about home' && ok "set keeps the comments above the first page" \
  || no "set dropped the header comments"

before=$(cat "$FILE")
for bad in '{"page":[{"tiles":[{"widget":"a","x":-1}]}]}' \
           '{"page":[{"tiles":[{"widget":"a","w":0}]}]}' \
           '{"page":[{"tiles":[{"widget":"../x"}]}]}' \
           '{"page":[{"face":"start"}]}' \
           '{"page":[{"face":"a","tiles":[]}]}' \
           'not json'; do
  rc=0; "$HOMECLI" set "$bad" >/dev/null 2>&1 || rc=$?
  if [[ $rc -eq 2 && $(cat "$FILE") == "$before" ]]; then ok "set refuses, and writes nothing: $bad"
  else no "set took $bad (rc=$rc)"; fi
done

printf '[[page]\nbroken' > "$FILE"
rc=0; "$HOMECLI" set "$layout" >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 && $(cat "$FILE") == $'[[page]\nbroken' ]] \
  && ok "set never writes over a file that does not parse (HM16)" || no "set wrote over a broken file"
rm "$FILE"

# --- json (HM57) --------------------------------------------------------------
rm -f "$FILE"
shipped=$("$HOMECLI" json)
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["page"][0]=={"face":"start"} and d["page"][1]["tiles"][0]["widget"]=="fetch"' "$shipped" \
  && ok "json with no file is the shipped layout" || no "json printed: $shipped"
"$HOMECLI" set "$shipped" >/dev/null
[[ $("$HOMECLI" json) == "$shipped" ]] && ok "json and set round-trip: set takes back what json prints" \
  || no "json after set differs"
rm -f "$FILE"

# --- remove drops a page it empties (HM52) -----------------------------------
"$HOMECLI" set '{"page":[{"tiles":[{"widget":"a","x":0,"y":0,"w":1,"h":1}]},{"tiles":[{"widget":"b","x":0,"y":0,"w":1,"h":1}]}]}' >/dev/null
"$HOMECLI" remove b >/dev/null
[[ $("$HOMECLI" show | grep -c '^page') -eq 1 ]] && ok "remove takes away the page it emptied" || no "an empty page stayed: $("$HOMECLI" show)"
"$HOMECLI" remove a >/dev/null
"$HOMECLI" show | grep -q '^page 1: tiles' && ok "but the last page of tiles stays, empty" || no "page 1 went: $("$HOMECLI" show)"
rm -f "$FILE"

# --- share and import (HM47) -------------------------------------------------
mkdir -p "$WIDGETS"
cp "$ROOT/default/omarchy/plugins/moarchy.common/widgets/Fetch.qml" "$WIDGETS/clock.qml"
link=$("$HOMECLI" share clock 2>/dev/null)
[[ $link == https://simonschubert.github.io/omarchy-widgets/w#qml1.clock.* ]] \
  && ok "share prints the link, with the id after the prefix" || no "share printed: ${link:0:80}"
[[ ${link#*#} != *[^A-Za-z0-9._-]* ]] && ok "the fragment is base64url, no padding" \
  || no "the fragment has other characters"

"$HOMECLI" import "$link" --as clock2 >/dev/null
cmp -s "$WIDGETS/clock.qml" "$WIDGETS/clock2.qml" && ok "import of a shared link is byte-identical" \
  || no "import changed the file"

rc=0; "$HOMECLI" import "$link" >/dev/null 2>&1 || rc=$?
[[ $rc -eq 1 ]] && cmp -s "$WIDGETS/clock.qml" "$ROOT/default/omarchy/plugins/moarchy.common/widgets/Fetch.qml" \
  && ok "import never writes over a widget that exists" || no "import overwrote clock.qml (rc=$rc)"

printf 'import QtQuick\nItem {}\n' > "$WIDGETS/tiny.qml"
frag=$("$HOMECLI" share tiny); "$HOMECLI" import "${frag#*#}" --as tiny2 >/dev/null
cmp -s "$WIDGETS/tiny.qml" "$WIDGETS/tiny2.qml" && ok "a bare qml1. fragment imports too" \
  || no "the fragment alone did not import"

rc=0; "$HOMECLI" import "${link%?????}" --as broken >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 && ! -e $WIDGETS/broken.qml ]] && ok "a damaged link is refused, and writes nothing" \
  || no "a damaged link was taken (rc=$rc)"

rc=0; "$HOMECLI" share fetch >/dev/null 2>&1 || rc=$?
[[ $rc -eq 1 ]] && ok "a shipped widget is not shared" || no "share fetch: rc=$rc"

printf 'import QtQuick\n// %s\nItem {}\n' "$(head -c 6000 /dev/urandom | base64 | tr -d '\n')" > "$WIDGETS/huge.qml"
err=$("$HOMECLI" share huge 2>&1 >/dev/null)
[[ $err == *'more than a QR code holds'* ]] && ok "a link too long for a QR code still prints, and says so" \
  || no "share huge: $err"

echo
if [[ $fail -gt 0 ]]; then echo "$fail failed"; exit 1; fi
echo "all passed"
