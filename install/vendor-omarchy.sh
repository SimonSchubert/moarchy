#!/bin/bash
# Vendor upstream Omarchy's configuration and theme layer -- and nothing else.
#
# It is cloned to the exact path upstream expects ($HOME/.local/share/omarchy),
# because every omarchy-* script and every `source =` line in the config layer
# hardcodes it. We never run install.sh from it.
#
# ---------------------------------------------------------------------------
# Why v3.8.4 and not master
# ---------------------------------------------------------------------------
# Omarchy 4.x replaced the entire shell layer. At v4.0.0 upstream dropped
# config/waybar, config/walker, config/elephant, config/swayosd and
# config/fastfetch, along with the waybar.css / mako.ini / walker.css /
# swayosd.css / hyprland.conf templates, and moved to `herdr` (a bespoke shell
# shipped as an x86_64-only binary in pkgs.omarchy.org) plus a Lua-based
# Hyprland config (default/themed/hyprland.lua.tpl).
#
# None of that is portable here: herdr has no aarch64 build, and the Lua config
# is Hyprland-specific on a device that cannot run Hyprland at all.
#
# v3.8.4 is the last release built on waybar + walker + mako + swayosd -- all of
# which either ship for aarch64 or are Go programs we can build. It also still
# uses ~/.config/omarchy/current/theme (4.x moved this to ~/.local/state).
#
# Upgrading past this pin is a real porting project, not a version bump.
# ---------------------------------------------------------------------------

echo "==> vendoring Omarchy config layer"

OMARCHY_PIN="${OMARCHY_PIN:-8fcc9d6048af4cb0e3af8512c78049857a3b53dd}"   # v3.8.4

if [[ -d $OMARCHY_PATH/.git ]]; then
  echo "    updating existing clone"
  git -C "$OMARCHY_PATH" fetch --depth 1 origin "$OMARCHY_PIN"
else
  mkdir -p "$(dirname "$OMARCHY_PATH")"
  git clone --quiet --filter=blob:none --no-checkout \
    https://github.com/basecamp/omarchy "$OMARCHY_PATH"
fi

git -C "$OMARCHY_PATH" checkout --quiet --detach "$OMARCHY_PIN"

echo "    pinned at $(git -C "$OMARCHY_PATH" rev-parse --short HEAD) (v3.8.4)"
echo "    themes: $(find "$OMARCHY_PATH/themes" -maxdepth 2 -name colors.toml | wc -l | tr -d ' ') with colors.toml"

for required in config/waybar config/walker themes; do
  if [[ ! -e $OMARCHY_PATH/$required ]]; then
    echo "    !! $required missing -- is OMARCHY_PIN pointing at a 4.x commit?" >&2
    exit 1
  fi
done
