#!/bin/bash
# Vendor upstream Omarchy's configuration and theme layer -- and nothing else.
#
# It is cloned to the exact path upstream expects ($HOME/.local/share/omarchy),
# because every omarchy-* script and every `source =` line in the config layer
# hardcodes it. We never run install.sh from it.
#
# ---------------------------------------------------------------------------
# Why v4.0.2
# ---------------------------------------------------------------------------
# 4.x replaced the whole shell layer: no waybar, walker, elephant, mako or
# swayosd. The bar, launcher, notifications and OSD are all one quickshell/QML
# shell that ships as `shell/` inside this repo, and omarchy-menu talks to it
# via omarchy-shell.
#
# That is portable here -- quickshell is packaged for aarch64 and renders on the
# Mali-400 -- but it needs a translation pass from Quickshell.Hyprland to
# Quickshell.I3, applied by install/port-4x.sh. See docs/omarchy-4x-feasibility.md.
#
# The v3.8.4 (waybar-based) port lives on the `main` branch.
# ---------------------------------------------------------------------------

echo "==> vendoring Omarchy config layer"

OMARCHY_PIN="${OMARCHY_PIN:-346e69e1cec6c4e8924531874af6ba010a1bc99e}"   # v4.0.2

if [[ -d $OMARCHY_PATH/.git ]]; then
  echo "    updating existing clone"
  git -C "$OMARCHY_PATH" fetch --depth 1 origin "$OMARCHY_PIN"
else
  mkdir -p "$(dirname "$OMARCHY_PATH")"
  git clone --quiet --filter=blob:none --no-checkout \
    https://github.com/basecamp/omarchy "$OMARCHY_PATH"
fi

git -C "$OMARCHY_PATH" checkout --quiet --detach "$OMARCHY_PIN"

echo "    pinned at $(git -C "$OMARCHY_PATH" rev-parse --short HEAD) (v4.0.2)"
echo "    themes: $(find "$OMARCHY_PATH/themes" -maxdepth 2 -name colors.toml | wc -l | tr -d ' ') with colors.toml"

for required in shell config/omarchy themes; do
  if [[ ! -e $OMARCHY_PATH/$required ]]; then
    echo "    !! $required missing -- is OMARCHY_PIN pointing at a pre-4.x commit?" >&2
    exit 1
  fi
done
