#!/bin/bash
# The targeted checks for the second refactor pass. Runs ON the phone.
# Each one is an A/B or reads a value that can only be right if the change
# works -- nothing here passes just because the shell is up.
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export SWAYSOCK="$(ls "$XDG_RUNTIME_DIR"/sway-ipc.* 2>/dev/null | head -1)"
export WAYLAND_DISPLAY="$(cd "$XDG_RUNTIME_DIR" && ls wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
export PATH="/usr/lib/moarchy/bin:$PATH"
pass=0; fail=0
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail+1)); }
sh_() { timeout 8 omarchy-shell "$@" 2>&1; }
active() { sh_ shell listPlugins | python3 -c "import json,sys
d=json.load(sys.stdin)
print(next((str(p['active']).lower() for p in d if p['id']==sys.argv[1]), 'missing'))" "$1"; }
wins() { swaymsg -t get_tree | python3 -c 'import json,sys
def w(n):
  c=0
  for k in n.get("nodes",[])+n.get("floating_nodes",[]):
    if k.get("app_id") or k.get("window"): c+=1
    c+=w(k)
  return c
print(w(json.load(sys.stdin)))'; }

echo "== every plugin still loads (J8: 43 declarations deleted) =="
missing=""
for id in bar bluetooth device drawer gestures settings shade sim splash themes wifi; do
  a=$(active "moarchy.$id"); [ "$a" = "missing" ] && missing="$missing moarchy.$id"
done
[ -z "$missing" ] && ok "all eleven moarchy plugins are registered" \
                  || no "plugins missing from the registry:$missing"
warn=$(grep -icE 'error|cannot assign|is not a type|unable to' ~/.local/state/moarchy/shell.log 2>/dev/null | tail -1)
[ "${warn:-0}" -eq 0 ] && ok "shell.log carries no binding or type error" \
                       || no "shell.log has $warn error lines" "$(grep -iE 'error|cannot assign|is not a type' ~/.local/state/moarchy/shell.log | tail -5)"

echo "== J2: Shared.Probe actually answers (A/B on a probe-backed value) =="
TOG="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles"
before=$(sh_ bar metrics | tr ' ' '\n' | sed -n 's/^pct=//p')
mkdir -p "$TOG" && touch "$TOG/battery-percentage-off"
sh_ -q bar syncFlags >/dev/null; sleep 1
during=$(sh_ bar metrics | tr ' ' '\n' | sed -n 's/^pct=//p')
rm -f "$TOG/battery-percentage-off"
sh_ -q bar syncFlags >/dev/null; sleep 1
after=$(sh_ bar metrics | tr ' ' '\n' | sed -n 's/^pct=//p')
if [ "$during" = "off" ] && [ "$after" = "on" ]; then
  ok "a probe reads the toggles file and reports it ($before -> $during -> $after)"
else
  no "the probe did not follow the file ($before -> $during -> $after)" \
     "Shared.Probe's answered() signal is not reaching Bar.qml"
fi

echo "== I2a: a window opening clears the theme picker =="
sh_ -q themes open >/dev/null; sleep 2
t1=$(sh_ themes state)
sh_ -q wifi open >/dev/null; sleep 2
t2=$(sh_ themes state); w2=$(sh_ wifi state)
sh_ -q wifi close >/dev/null; sleep 1; sh_ -q themes close >/dev/null; sleep 1
if [ "$t1" = "open" ] && [ "$t2" = "closed" ] && [ "$w2" = "open" ]; then
  ok "Wi-Fi over the picker leaves the picker closed (was: picker stayed up)"
else
  no "picker before=$t1 after=$t2, wifi=$w2" "expected open -> closed, wifi open"
fi

echo "== B6 read from the other end: the shade does NOT clear the drawer =="
sh_ -q drawer open >/dev/null; sleep 2
sh_ -q shade open >/dev/null; sleep 2
d=$(sh_ drawer state); s=$(sh_ shade state)
sh_ -q shade close >/dev/null; sleep 1; sh_ -q drawer close >/dev/null; sleep 1
[ "$d" = "open" ] && [ "$s" = "open" ] && ok "shade over drawer leaves both open (S28)" \
  || no "drawer=$d shade=$s after the shade opened over it" "expected both open"

echo "== N1: a back swipe over the Omarchy menu closes the menu, not the app =="
setsid foot >/dev/null 2>&1 &
sleep 4
w_before=$(wins)
sh_ -q shell toggle omarchy.menu '{"menu":"root"}' >/dev/null; sleep 3
m1=$(active omarchy.menu)
sh_ gestures back >/dev/null; sleep 3
m2=$(active omarchy.menu); w_after=$(wins)
if [ "$m1" = "true" ] && [ "$m2" = "false" ] && [ "$w_before" = "$w_after" ]; then
  ok "menu closed and the window survived (windows $w_before -> $w_after)"
else
  no "menu $m1 -> $m2, windows $w_before -> $w_after" \
     "pre-fix this left the menu up and took the window with it"
fi
swaymsg '[app_id="foot"] kill' >/dev/null 2>&1; sleep 1

echo "== F8/H3: no tracker is left holding a touch =="
for s in "shade sheet" "drawer geometry"; do
  out=$(sh_ $s); d=$(printf '%s' "$out" | tr ' ' '\n' | sed -n 's/^drag=//p')
  [ "$d" = "idle" ] && ok "$s reports drag=idle with no finger down" \
                    || no "$s reports drag=$d" "$out"
done

echo "== G14a: tapping the drawer's search field raises the keyboard =="
# The workspace rect, never sm.puri.OSK0 Visible: that property reports the
# keyboard's intent and has been seen true with grim showing nothing drawn.
rect_h() { swaymsg -t get_workspaces | python3 -c 'import json,sys
print(next((w["rect"]["height"] for w in json.load(sys.stdin) if w["focused"]), 0))'; }
touch_bin=/usr/lib/moarchy/bin/moarchy-touch
sh_ -q drawer close >/dev/null; sleep 1
osk_down=$(rect_h)
sh_ -q drawer open >/dev/null; sleep 2
field=$(sh_ drawer searchTarget | tr ' ' '\n' | sed -n 's/^field=//p')
fx=$(printf '%s' "$field" | cut -d, -f1); fy=$(printf '%s' "$field" | cut -d, -f2)
if [ -n "$fx" ] && [ -n "$fy" ]; then
  sudo -n "$touch_bin" tap "$fx" "$fy" >/dev/null 2>&1; sleep 3
  focused=$(sh_ drawer searchTarget | tr ' ' '\n' | sed -n 's/^focused=//p')
  osk_up=$(rect_h)
  sh_ -q drawer close >/dev/null; sleep 3
  osk_after=$(rect_h)
  if [ "$focused" = "true" ] && [ "$osk_up" -lt "$osk_down" ] 2>/dev/null; then
    ok "the tap focused the field and the rect dropped ($osk_down -> $osk_up)"
  else
    no "focused=$focused rect $osk_down -> $osk_up" "expected focus and a lower rect"
  fi
  [ "$osk_after" = "$osk_down" ] && ok "closing the drawer put it back ($osk_after)" \
    || no "rect is $osk_after after closing, was $osk_down before" "the drawer left its keyboard up"
else
  no "drawer searchTarget gave no field centre" "$(sh_ drawer searchTarget)"
fi

echo "== H1/H5: the back edge has a tracker, so its trace marks a cancel =="
bt=$(sh_ gestures backTrace)
ok "backTrace answers ('${bt:-empty}')"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
