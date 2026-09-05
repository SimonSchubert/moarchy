#!/bin/bash
# Wire the vendored Omarchy config layer up to Sway.

echo "==> config"

# --- Retire the mobileomarchy name ----------------------------------------
# ONE RELEASE ONLY. The project was called mobileomarchy until 2026-09-05, and
# a phone provisioned before then has the old name in five places that nothing
# else here would ever revisit. Delete this block, the two legacy globs in the
# plugin sweep below, the legacy prefix in the shell.json filter, and the
# legacy case in scripts/test-plugin-sweep.sh, once every device you care about
# has run this installer at least once.
#
# Plugins and desktop entries are *not* handled here -- the sweep below already
# removes anything that is not in the repo, and teaching it the old namespace
# is both smaller and the thing that is already tested.
if [[ -d ~/.local/state/mobileomarchy && ! -d ~/.local/state/moarchy ]]; then
  # Carries screen-locked, shell-off and gaps-on across. Moved rather than
  # dropped: these are toggles the user set, and silently resetting them looks
  # like the update broke something.
  mv ~/.local/state/mobileomarchy ~/.local/state/moarchy
  echo "    migrated ~/.local/state/mobileomarchy -> moarchy"
fi

# The old PATH export. This is the one that actually breaks a phone: the guard
# further down greps for MOARCHY_PATH, which is *not* a substring of
# MOBILEOMARCHY_PATH, so without this it appends a second block and leaves
# ~/.local/share/mobileomarchy/bin -- a directory this same run deletes --
# ahead of the real one on PATH. Every moarchy-* command then resolves to
# nothing on the next login.
if [[ -f ~/.profile ]] && grep -q MOBILEOMARCHY_PATH ~/.profile; then
  python3 - <<'LEGACY_PROFILE_EOF'
import os, re
p = os.path.expanduser("~/.profile")
s = open(p).read()
# The block as install/config.sh wrote it: a "# mobileomarchy" comment through
# the export PATH line that mentions it. Anchored at both ends so a profile the
# user has since edited by hand loses only what we put there.
out = re.sub(r"\n*# mobileomarchy\n(?:.*\n)*?export PATH=\"\$MOBILEOMARCHY_PATH/bin.*\n", "\n", s)
if out != s:
    open(p, "w").write(out)
LEGACY_PROFILE_EOF
  if grep -q MOBILEOMARCHY_PATH ~/.profile; then
    echo "    !! ~/.profile still mentions MOBILEOMARCHY_PATH -- remove it by hand," >&2
    echo "    !! or its stale bin/ shadows this install on the next login" >&2
  else
    echo "    removed the legacy MOBILEOMARCHY_PATH block from ~/.profile"
  fi
fi

# The old checkout. Guarded on the new one existing and being a different
# directory, so a half-set MOARCHY_PATH cannot make this delete the tree it is
# currently running from.
if [[ -d ~/.local/share/mobileomarchy && -d $MOARCHY_PATH ]] &&
   ! [[ ~/.local/share/mobileomarchy -ef $MOARCHY_PATH ]]; then
  rm -rf ~/.local/share/mobileomarchy
  echo "    removed the old ~/.local/share/mobileomarchy checkout"
fi

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

# --- Mobile tweak: a heavier default UI weight -------------------------------
# Lift Regular to SemiBold for the UI font, system-wide, via fontconfig. The
# file itself carries the reasoning and the measurements; the short version is
# that the shell has 336 Text sites across upstream and our plugins, none of
# which inherit a weight, so there is no one place in QML to set this -- and
# doing it in fontconfig brings every GTK and Qt app along, which is the point.
mkdir -p ~/.config/fontconfig/conf.d
cp "$MOARCHY_PATH/default/fontconfig/50-moarchy-weight.conf" \
   ~/.config/fontconfig/conf.d/
fc-cache -f >/dev/null 2>&1

# And the terminal keeps its Regular, which pages of semibold `ls` output are
# not an improvement on.
#
# Belt and braces, and worth being honest about which: foot's config names a
# family and a size and no weight, so its pattern never matches the rule above
# in the first place -- rendering the same foot window with and without this
# line produced identical ink. This makes that accident deliberate, against the
# day foot starts putting a weight in its pattern.
#
# `style=Regular` rather than `weight=regular`, and the difference matters: the
# rule tests `weight eq regular`, so asking for weight=regular is asking to be
# rewritten, while style=Regular sidesteps it. fc-match agrees --
# `:style=Regular` answers Regular, `:weight=regular` answers SemiBold.
#
# Applied here rather than shipped as a config, because the loop above copies
# upstream's foot config verbatim over ~/.config/foot on every run. Alacritty
# already names `style = "Regular"` upstream and needs nothing.
if [[ -f ~/.config/foot/foot.ini ]] && ! grep -q "style=Regular" ~/.config/foot/foot.ini; then
  sed -i "s/^font=JetBrainsMono Nerd Font:/font=JetBrainsMono Nerd Font:style=Regular:/" \
    ~/.config/foot/foot.ini
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
# split; moarchy-launch-tui is what actually makes it fit, by dropping the
# font size.
if [[ -f ~/.config/btop/btop.conf ]]; then
  sed -i 's/^shown_boxes = .*/shown_boxes = "cpu mem"/' ~/.config/btop/btop.conf
fi

# --- Our Sway config -------------------------------------------------------
cp "$MOARCHY_PATH/config/sway/config" ~/.config/sway/config

# --- The one new theme template -------------------------------------------
# omarchy-theme-set-templates already processes $HOME/.config/omarchy/themed
# before its own built-ins, so adding sway.conf.tpl there themes Sway from every
# theme's colors.toml without patching upstream at all.
cp "$MOARCHY_PATH/default/themed/sway.conf.tpl" ~/.config/omarchy/themed/

# --- The 4.x shell ---------------------------------------------------------
# shell.json is the shell's config; upstream ships a default we copy verbatim so
# the shell has something to read (it warns and degrades without one).
mkdir -p ~/.config/omarchy
[[ -f $OMARCHY_PATH/config/omarchy/shell.json ]] &&
  cp -n "$OMARCHY_PATH/config/omarchy/shell.json" ~/.config/omarchy/shell.json 2>/dev/null

# --- On-screen keyboard ------------------------------------------------------
# Nothing to do. squeekboard needed two GSettings keys
# (org.gnome.desktop.a11y.applications screen-keyboard-enabled and
# org.gnome.desktop.input-sources sources) and silently did nothing without
# them, which cost a keyboard on a freshly installed phone and a long hunt --
# the block that wrote them, through dbus-run-session because the installer has
# no session bus, and then read them back rather than trusting the exit status,
# lived here.
#
# moarchy-keyboard reads neither. It takes its palette from colors.toml and its
# layouts from its own package, so there is no gate to open and nothing here to
# fail silently.

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
# Scoped to the moarchy.* namespace on purpose: plugins installed from
# elsewhere are the user's, and a sweep that removed those would be a far worse
# bug than the one it fixes.
# >>> plugin-sweep (scripts/test-plugin-sweep.sh extracts between these markers
# and runs the real code, so do not rename them without updating that script)
repo_plugins=""
for plugin_dir in "$MOARCHY_PATH"/default/omarchy/plugins/*/; do
  [[ -d $plugin_dir ]] || continue
  repo_plugins="$repo_plugins $(basename "$plugin_dir")"
done

# An empty list is not "every installed plugin is stale", it is "I could not
# read the repo": MOARCHY_PATH unset or wrong, the directory missing, or
# a checkout or rebase in a worktree several sessions share catching it half
# written. Acting on that reading deletes every plugin on the device -- bar,
# drawer, shade, recents, gestures, settings -- and the copy loop below
# iterates the same empty glob, so it restores none of them. The phone comes
# up with no UI at all, recoverable only over ssh.
#
# So refuse. The sweep is a tidying pass; skipping it leaves a stale icon,
# while running it on a half-read repo leaves no phone.
if [[ -z ${repo_plugins// /} ]]; then
  echo "    !! no plugins found in $MOARCHY_PATH/default/omarchy/plugins" >&2
  echo "    !! skipping the stale sweep rather than deleting every installed plugin" >&2
else
  # The mobileomarchy.* half is the rename migration (see the top of this
  # file) and comes out with it: repo_plugins never contains an old-namespace
  # id, so every one of them is stale by definition and the loop below removes
  # it. Nothing else here needs to know the project changed name.
  for installed in ~/.config/omarchy/plugins/moarchy.*/ \
                   ~/.config/omarchy/plugins/mobileomarchy.*/; do
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
    # Both spellings of the marker: an entry written before the rename says
    # X-MobileOmarchy-Plugin, and an entry we no longer recognise is an entry
    # we can never clean up -- it keeps a drawer icon that launches nothing.
    owner=$(sed -n -e 's/^X-Moarchy-Plugin=//p' \
                   -e 's/^X-MobileOmarchy-Plugin=//p' "$entry" | head -1)
    [[ -n $owner ]] || continue
    [[ " $repo_plugins " == *" $owner "* ]] && continue
    rm -f "$entry"
    echo "    removed stale desktop entry $(basename "$entry")"
  done
fi
# <<< plugin-sweep

for plugin_dir in "$MOARCHY_PATH"/default/omarchy/plugins/*/; do
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
# bar.layout is deliberately left alone even though moarchy.bar ignores
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
if bar.get("id") != "moarchy.bar":
    bar["id"] = "moarchy.bar"
    dirty = True

plugins = d.setdefault("plugins", [])
for pid in ("moarchy.gestures", "moarchy.drawer", "moarchy.recents",
            "moarchy.shade", "moarchy.themes", "moarchy.settings",
            "moarchy.device", "moarchy.splash"):
    if not os.path.isdir(os.path.expanduser("~/.config/omarchy/plugins/" + pid)):
        continue
    if not any(isinstance(e, dict) and e.get("id") == pid for e in plugins):
        plugins.append({"id": pid})
        dirty = True

# And drop ids whose plugin is gone. The loop above only ever appends, so a
# plugin removed from the repo stayed listed here and the shell went on trying
# to load a directory that the sweep had already deleted. Scoped to our own
# namespace for the same reason the sweep is.
#
# The mobileomarchy. prefix is the rename migration and comes out with it. It
# has to be listed explicitly: "mobileomarchy.shade" does not start with
# "moarchy.", so without it every pre-rename id stays in shell.json pointing at
# a directory the sweep above has just deleted. (bar.id needs no such care --
# it is assigned unconditionally a few lines up.)
keep = [e for e in plugins
        if not (isinstance(e, dict)
                and str(e.get("id", "")).startswith(("moarchy.", "mobileomarchy."))
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
if ! grep -q "MOARCHY_PATH" "$PROFILE"; then
  cat >>"$PROFILE" <<'PROFILE_EOF'

# moarchy
export OMARCHY_PATH="$HOME/.local/share/omarchy"
export MOARCHY_PATH="$HOME/.local/share/moarchy"
# moarchy's bin comes first so its Sway shims shadow Omarchy's Hyprland scripts
export PATH="$MOARCHY_PATH/bin:$OMARCHY_PATH/bin:$PATH"
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
cp "$MOARCHY_PATH/default/systemd/sway-session.target" ~/.config/systemd/user/
systemctl --user daemon-reload 2>/dev/null || true

# --- Pick a starting theme (also generates ~/.local/state/omarchy/current/theme/sway.conf)
omarchy-theme-set tokyo-night || echo "    !! theme apply failed; run 'omarchy-theme-set tokyo-night' by hand" >&2

echo "    config in place"
