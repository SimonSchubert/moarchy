#!/bin/bash
# Wire the vendored Omarchy config layer up to Sway.

echo "==> config"

mkdir -p ~/.config/omarchy/{current,themed} ~/.config/sway/config.d

# --- Omarchy's own app configs, used unmodified --------------------------
# These are compositor-agnostic: they describe apps, not a window manager.
for d in alacritty foot btop fastfetch waybar walker elephant swayosd wiremix \
         lazygit tmux imv fontconfig; do
  if [[ -d $OMARCHY_PATH/config/$d ]]; then
    rm -rf ~/".config/$d"
    cp -r "$OMARCHY_PATH/config/$d" ~/".config/$d"
  fi
done
[[ -f $OMARCHY_PATH/config/starship.toml ]] && cp "$OMARCHY_PATH/config/starship.toml" ~/.config/

# --- Omarchy's icon font (waybar's custom/omarchy module renders from it) ---
mkdir -p ~/.local/share/fonts
cp "$OMARCHY_PATH/config/omarchy.ttf" ~/.local/share/fonts/ 2>/dev/null && fc-cache -f >/dev/null 2>&1

# --- Mobile tweak: btop -----------------------------------------------------
# A fullscreen terminal on the PinePhone is exactly 24x80 -- btop's stated
# minimum -- so upstream's four-box layout renders only when nothing is tiled
# beside it, and shows "Terminal size too small" the moment you split.
# Dropping to cpu+mem makes it usable at any size this screen can produce.
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

# --- Waybar: our mobile module set overrides Omarchy's desktop one ----------
cp "$MOBILEOMARCHY_PATH/config/waybar/config.jsonc" ~/.config/waybar/config.jsonc

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

# --- Pick a starting theme (also generates ~/.config/omarchy/current/theme/sway.conf)
omarchy-theme-set tokyo-night || echo "    !! theme apply failed; run 'omarchy-theme-set tokyo-night' by hand" >&2

echo "    config in place"
