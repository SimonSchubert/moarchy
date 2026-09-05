#!/bin/bash
# Vendor upstream Omarchy's configuration and theme layer -- and nothing else.
#
# It is cloned to the exact path upstream expects ($HOME/.local/share/omarchy),
# because every omarchy-* script and every `source =` line in the config layer
# hardcodes it. We never run install.sh from it.
#
# ---------------------------------------------------------------------------
# Why 4.x
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
# The v3.8.4 (waybar-based) port was replaced, not kept on a branch; it exists
# only in git history.
#
# Which commit of 4.x is not decided here. It is [omarchy] in manifest.toml,
# alongside every other pin, because a version written in a script is a version
# that gets written in a second script later (docs/structure.md V1, V3).
# ---------------------------------------------------------------------------

echo "==> vendoring Omarchy config layer"

. "$MOARCHY_PATH/scripts/manifest.sh"

# OMARCHY_PIN= still overrides, for bisecting against upstream without touching
# the manifest. Everything else reads the pin.
OMARCHY_PIN="${OMARCHY_PIN:-$(manifest_get omarchy ref)}"
[[ -n $OMARCHY_PIN ]] || exit 1
OMARCHY_URL="$(manifest_get omarchy url)" || exit 1
OMARCHY_VERSION="$(manifest_get omarchy version)" || exit 1

if [[ -d $OMARCHY_PATH/.git ]]; then
  echo "    updating existing clone"
  git -C "$OMARCHY_PATH" fetch --depth 1 origin "$OMARCHY_PIN"
else
  mkdir -p "$(dirname "$OMARCHY_PATH")"
  git clone --quiet --filter=blob:none --no-checkout \
    "$OMARCHY_URL" "$OMARCHY_PATH"
fi

git -C "$OMARCHY_PATH" checkout --quiet --detach "$OMARCHY_PIN"

# Prove the checkout landed on the pin rather than trusting an exit status: a
# clone that was already here at a different commit and a fetch that quietly
# did nothing both leave a working tree that looks fine.
got=$(git -C "$OMARCHY_PATH" rev-parse HEAD)
if [[ $got != "$OMARCHY_PIN" ]]; then
  echo "    !! asked for $OMARCHY_PIN, got $got" >&2
  exit 1
fi

echo "    pinned at ${OMARCHY_PIN:0:7} ($OMARCHY_VERSION)"
echo "    themes: $(find "$OMARCHY_PATH/themes" -maxdepth 2 -name colors.toml | wc -l | tr -d ' ') with colors.toml"

for required in shell config/omarchy themes; do
  if [[ ! -e $OMARCHY_PATH/$required ]]; then
    echo "    !! $required missing -- is [omarchy] ref pointing at a pre-4.x commit?" >&2
    exit 1
  fi
done
