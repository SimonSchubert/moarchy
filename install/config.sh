#!/bin/bash
# Wire the vendored Omarchy config layer up to Sway.

echo "==> config"

# 4.x keeps the *current* theme under ~/.local/state; ~/.config/omarchy holds
# only user-supplied overrides (themes, templates, shell.json).
mkdir -p ~/.config/omarchy/themed ~/.local/state/omarchy/current ~/.config/sway/config.d

# --- Omarchy's own app configs, used unmodified --------------------------
# These are compositor-agnostic: they describe apps, not a window manager.
# 4.x has no waybar/walker/elephant/swayosd config -- one quickshell shell
# replaces all of them, and it lives in $OMARCHY_PATH/shell, not ~/.config.
for d in alacritty foot btop wiremix lazygit tmux imv omarchy; do
  if [[ -d $OMARCHY_PATH/config/$d ]]; then
    rm -rf ~/".config/$d"
    cp -r "$OMARCHY_PATH/config/$d" ~/".config/$d"
  fi
done
[[ -f $OMARCHY_PATH/config/starship.toml ]] && cp "$OMARCHY_PATH/config/starship.toml" ~/.config/

# --- Omarchy's icon font (the bar's logo glyph, \ue900, comes from it) -------
# 4.x moved this from config/omarchy.ttf to default/fonts/omarchy/omarchy.ttf.
# Without it the logo renders as tofu.
mkdir -p ~/.local/share/fonts
if [[ -f $OMARCHY_PATH/default/fonts/omarchy/omarchy.ttf ]]; then
  cp "$OMARCHY_PATH/default/fonts/omarchy/omarchy.ttf" ~/.local/share/fonts/
  fc-cache -f >/dev/null 2>&1
fi

# --- Mobile tweak: bar clock -----------------------------------------------
# The bar is centre-anchored on the clock, so its width sets where every other
# module sits. Upstream's "dddd HH:mm" changes width with the day name
# ("Wednesday" vs "Monday"), which visibly shifts the whole bar once a day and
# leaves no slack on a 360px-wide screen. HH:mm is fixed width.
# Patched in place so a user's own shell.json edits survive.
if [[ -f ~/.config/omarchy/shell.json ]]; then
  python3 - <<'CLOCK_EOF'
import json, os
p = os.path.expanduser("~/.config/omarchy/shell.json")
try:
    d = json.load(open(p))
except Exception:
    raise SystemExit(0)
for m in d.get("bar", {}).get("layout", {}).get("center", []):
    if m.get("id") == "omarchy.clock":
        m["format"] = "HH:mm"
        m["formatAlt"] = "ddd d MMM"
json.dump(d, open(p, "w"), indent=2)
CLOCK_EOF
fi

# --- Mobile tweak: btop -----------------------------------------------------
# A fullscreen terminal here is 47x41 characters, and btop refuses to draw below
# 60 columns whatever shown_boxes says. Trimming the boxes still helps in a
# split; mobileomarchy-launch-tui is what actually makes it fit, by dropping the
# font size.
if [[ -f ~/.config/btop/btop.conf ]]; then
  sed -i 's/^shown_boxes = .*/shown_boxes = "cpu mem"/' ~/.config/btop/btop.conf
fi

# --- Our Sway config -------------------------------------------------------
cp "$MOBILEOMARCHY_PATH/config/sway/config" ~/.config/sway/config

# --- The one new theme template -------------------------------------------
# omarchy-theme-set-templates already processes $HOME/.config/omarchy/themed
# before its own built-ins, so adding sway.conf.tpl there themes Sway from every
# theme's colors.toml without patching upstream at all.
cp "$MOBILEOMARCHY_PATH/default/themed/sway.conf.tpl" ~/.config/omarchy/themed/

# --- The 4.x shell ---------------------------------------------------------
# shell.json is the shell's config; upstream ships a default we copy verbatim so
# the shell has something to read (it warns and degrades without one).
mkdir -p ~/.config/omarchy
[[ -f $OMARCHY_PATH/config/omarchy/shell.json ]] &&
  cp -n "$OMARCHY_PATH/config/omarchy/shell.json" ~/.config/omarchy/shell.json 2>/dev/null

# --- On-screen keyboard gating ---------------------------------------------
# squeekboard reads both of these through GSettings and refuses to do anything
# useful without them. They are normally set by GNOME/Phosh, which nothing here
# runs, so a bare Sway session leaves them at their defaults and the keyboard
# silently never appears:
#
#   screen-keyboard-enabled  false by default -> squeekboard binds the input
#                            method but never shows a surface
#   input-sources            empty by default -> "No system layout present",
#                            so it has no layout to draw
# These MUST go through a D-Bus session bus. gsettings' dconf backend writes by
# calling the dconf service on the session bus, so with no bus the write fails
# -- and the old `2>/dev/null || true` swallowed that, reporting success while
# storing nothing. The installer runs as a detached systemd unit with no bus, so
# that is the normal case, not the edge case, and the result was a keyboard that
# never appeared on a freshly installed phone.
#
# dbus-run-session spins up a throwaway bus just long enough for dconf to write.
# The write itself lands in ~/.config/dconf/user, so it persists after the bus
# goes away -- verified by reading the value back on a *different* bus below.
gset() {
  if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then gsettings "$@"
  else dbus-run-session -- gsettings "$@" 2>/dev/null
  fi
}

gset set org.gnome.desktop.a11y.applications screen-keyboard-enabled true
if [[ $(gset get org.gnome.desktop.input-sources sources) == "@a(ss) []" ]]; then
  gset set org.gnome.desktop.input-sources sources "[('xkb','us')]"
fi

# Read back rather than trust the exit status: a silent no-op here costs a
# keyboard, and the symptom (squeekboard runs, logs nothing useful, draws
# nothing) is a long way from the cause.
if [[ $(gset get org.gnome.desktop.a11y.applications screen-keyboard-enabled) != "true" ]]; then
  echo "    !! screen-keyboard-enabled did not stick -- squeekboard will not show" >&2
else
  echo "    on-screen keyboard gated on"
fi

# --- Touch gestures, as a shell plugin -------------------------------------
# 4.x's shell discovers third-party plugins in ~/.config/omarchy/plugins/<id>/
# from their manifest.json, so the gesture layer needs no patching of the
# vendored shell -- the same trick sway.conf.tpl uses for theming.
#
# Unlike first-party plugins, third-party ones are opt-in: PluginRegistry's
# isEnabled() falls through to findEntryLocation(), which only looks for
# `{"id": ...}` objects in shell.json's plugins[]. Without the entry the plugin
# loads nothing and says nothing, so register it here.
mkdir -p ~/.config/omarchy/plugins
rm -rf ~/.config/omarchy/plugins/mobileomarchy.gestures
cp -r "$MOBILEOMARCHY_PATH/default/omarchy/plugins/mobileomarchy.gestures" ~/.config/omarchy/plugins/

python3 - <<'PLUGIN_EOF'
import json, os
p = os.path.expanduser("~/.config/omarchy/shell.json")
try:
    d = json.load(open(p))
except Exception:
    raise SystemExit(0)
plugins = d.setdefault("plugins", [])
if not any(isinstance(e, dict) and e.get("id") == "mobileomarchy.gestures" for e in plugins):
    plugins.append({"id": "mobileomarchy.gestures"})
    json.dump(d, open(p, "w"), indent=2)
PLUGIN_EOF

# --- Make omarchy-* scripts work outside the installer ---------------------
PROFILE=~/.profile
touch "$PROFILE"
if ! grep -q "MOBILEOMARCHY_PATH" "$PROFILE"; then
  cat >>"$PROFILE" <<'PROFILE_EOF'

# mobileomarchy
export OMARCHY_PATH="$HOME/.local/share/omarchy"
export MOBILEOMARCHY_PATH="$HOME/.local/share/mobileomarchy"
# mobileomarchy's bin comes first so its Sway shims shadow Omarchy's Hyprland scripts
export PATH="$MOBILEOMARCHY_PATH/bin:$OMARCHY_PATH/bin:$PATH"
PROFILE_EOF
fi

# --- systemd user units ----------------------------------------------------
# Omarchy's units are all WantedBy=graphical-session.target, and nothing here
# activates that target: sway is started from ~/.bash_profile, not uwsm or a
# display manager. sway-session.target is BindsTo it and is started from
# autostart.conf, so 4.x's user units (bt-agent, omarchy-sleep-lock, ...) come
# up at all.
#
# The swayosd-server unit this originally existed for is gone in 4.x -- the
# quickshell shell owns the OSD -- but the target is still what makes every
# other graphical-session unit start.
mkdir -p ~/.config/systemd/user
cp "$MOBILEOMARCHY_PATH/default/systemd/sway-session.target" ~/.config/systemd/user/
systemctl --user daemon-reload 2>/dev/null || true

# --- Pick a starting theme (also generates ~/.local/state/omarchy/current/theme/sway.conf)
omarchy-theme-set tokyo-night || echo "    !! theme apply failed; run 'omarchy-theme-set tokyo-night' by hand" >&2

echo "    config in place"
