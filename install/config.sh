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
