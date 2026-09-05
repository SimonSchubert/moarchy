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

# --- The phone shell, as plugins -------------------------------------------
# 4.x's shell discovers third-party plugins in ~/.config/omarchy/plugins/<id>/
# from their manifest.json, so the gesture layer needs no patching of the
# vendored shell -- the same trick sway.conf.tpl uses for theming.
#
# Everything the phone UI adds to the desktop shell lives here: the bottom-edge
# gestures, the status bar sized for 360px, the app drawer and the shade.
mkdir -p ~/.config/omarchy/plugins

# Remove plugins we used to ship and no longer do. The copy loop below only
# touches plugins that still exist in the repo, so without this a deleted one
# keeps its installed directory, stays in shell.json, and keeps its drawer icon
# -- an app that launches nothing, which is not the sort of thing anyone
# reports as a bug.
#
# Scoped to the mobileomarchy.* namespace on purpose: plugins installed from
# elsewhere are the user's, and a sweep that removed those would be a far worse
# bug than the one it fixes.
# >>> plugin-sweep (scripts/test-plugin-sweep.sh extracts between these markers
# and runs the real code, so do not rename them without updating that script)
repo_plugins=""
for plugin_dir in "$MOBILEOMARCHY_PATH"/default/omarchy/plugins/*/; do
  [[ -d $plugin_dir ]] || continue
  repo_plugins="$repo_plugins $(basename "$plugin_dir")"
done

# An empty list is not "every installed plugin is stale", it is "I could not
# read the repo": MOBILEOMARCHY_PATH unset or wrong, the directory missing, or
# a checkout or rebase in a worktree several sessions share catching it half
# written. Acting on that reading deletes every plugin on the device -- bar,
# drawer, shade, recents, gestures, settings -- and the copy loop below
# iterates the same empty glob, so it restores none of them. The phone comes
# up with no UI at all, recoverable only over ssh.
#
# So refuse. The sweep is a tidying pass; skipping it leaves a stale icon,
# while running it on a half-read repo leaves no phone.
if [[ -z ${repo_plugins// /} ]]; then
  echo "    !! no plugins found in $MOBILEOMARCHY_PATH/default/omarchy/plugins" >&2
  echo "    !! skipping the stale sweep rather than deleting every installed plugin" >&2
else
  for installed in ~/.config/omarchy/plugins/mobileomarchy.*/; do
    [[ -d $installed ]] || continue
    installed_id=$(basename "$installed")
    [[ " $repo_plugins " == *" $installed_id "* ]] && continue
    rm -rf "$installed"
    echo "    removed stale plugin $installed_id"
  done

  # Desktop entries are matched by their ownership marker rather than by
  # filename, so an entry named after something else still gets cleaned up.
  for entry in ~/.local/share/applications/*.desktop; do
    [[ -e $entry ]] || continue
    owner=$(sed -n 's/^X-MobileOmarchy-Plugin=//p' "$entry" | head -1)
    [[ -n $owner ]] || continue
    [[ " $repo_plugins " == *" $owner "* ]] && continue
    rm -f "$entry"
    echo "    removed stale desktop entry $(basename "$entry")"
  done
fi
# <<< plugin-sweep

for plugin_dir in "$MOBILEOMARCHY_PATH"/default/omarchy/plugins/*/; do
  plugin_id=$(basename "$plugin_dir")
  rm -rf ~/.config/omarchy/plugins/"$plugin_id"
  cp -r "$plugin_dir" ~/.config/omarchy/plugins/
  echo "    plugin $plugin_id"

  # A plugin that ships a .desktop wants to be launchable like an app: the
  # drawer lists desktop entries, not plugins, and the entry's Exec asks the
  # shell to summon the overlay. It lives in the plugin directory so a plugin
  # stays one self-contained thing, but it has to be moved into applications/
  # to be found -- and moved rather than copied, so the shell does not also
  # scan it inside plugins/.
  for entry in ~/.config/omarchy/plugins/"$plugin_id"/*.desktop; do
    [[ -e $entry ]] || continue
    mkdir -p ~/.local/share/applications
    mv "$entry" ~/.local/share/applications/
    echo "      desktop entry $(basename "$entry")"
  done
done

# The two kinds are enabled by different keys, and crossing them is a silent
# no-op rather than an error.
#
#   kind "bar"    PluginRegistry.isEnabled() short-circuits on the bar branch
#                 and answers purely from shell.json's `bar.id`. It never looks
#                 at plugins[], so an entry there does nothing at all.
#   everything    falls through to findEntryLocation(), which only finds
#   else          `{"id": ...}` objects in plugins[].
#
# bar.layout is deliberately left alone even though mobileomarchy.bar ignores
# it: it is what `omarchy bar use omarchy.bar` falls back to, and a phone with a
# broken shell plugin should still come up with a bar that works.
python3 - <<'PLUGIN_EOF'
import json, os

p = os.path.expanduser("~/.config/omarchy/shell.json")
try:
    d = json.load(open(p))
except Exception:
    raise SystemExit(0)

dirty = False

bar = d.setdefault("bar", {})
if bar.get("id") != "mobileomarchy.bar":
    bar["id"] = "mobileomarchy.bar"
    dirty = True

plugins = d.setdefault("plugins", [])
for pid in ("mobileomarchy.gestures", "mobileomarchy.drawer", "mobileomarchy.recents",
            "mobileomarchy.shade", "mobileomarchy.themes", "mobileomarchy.settings",
            "mobileomarchy.device"):
    if not os.path.isdir(os.path.expanduser("~/.config/omarchy/plugins/" + pid)):
        continue
    if not any(isinstance(e, dict) and e.get("id") == pid for e in plugins):
        plugins.append({"id": pid})
        dirty = True

# And drop ids whose plugin is gone. The loop above only ever appends, so a
# plugin removed from the repo stayed listed here and the shell went on trying
# to load a directory that the sweep had already deleted. Scoped to our own
# namespace for the same reason the sweep is.
keep = [e for e in plugins
        if not (isinstance(e, dict)
                and str(e.get("id", "")).startswith("mobileomarchy.")
                and not os.path.isdir(os.path.expanduser("~/.config/omarchy/plugins/" + e["id"])))]
if len(keep) != len(plugins):
    plugins[:] = keep
    dirty = True

if dirty:
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
