# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# The palettes come from scripts/fetch-themes.sh, and the two themed shots are
# skipped when they have not been fetched -- a screenshot run should not need
# the network to take the two that matter.
THEMES="${THEMES:-/tmp/omarchy-themes}"

# Twenty past three on a Tuesday afternoon in Berlin, pinned in both halves:
# demo.py dates the fixture from it and the app reads its clock from it. A
# weather app photographed at whatever time the run happens is a weather app
# whose pictures are sometimes of a dark screen with a moon on it.
NOW="MOARCHY_WEATHER_NOW=1789478400"

shot today "$NOW"
shot places "$NOW" MOARCHY_WEATHER_PAGE=places

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night "$NOW" "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte "$NOW" "THEME=$THEMES/catppuccin-latte/colors.toml"
