# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# The palettes come from scripts/fetch-themes.sh, and the two themed shots are
# skipped when they have not been fetched -- a screenshot run should not need
# the network to take the ones that matter.
THEMES="${THEMES:-/tmp/omarchy-themes}"

# Nine minutes past ten on Tuesday 15 September 2026, pinned in both halves:
# demo.py dates its fixture from it and the app reads its clock from it. A
# clock photographed at whatever time the run happens is a clock whose pictures
# all disagree, and 10:09 is the time every watch in every advertisement has
# ever shown -- the hands make a V and none of the three covers another.
NOW="MOARCHY_CLOCK_NOW=1789466976"

shot alarm "$NOW"
shot stopwatch "$NOW" MOARCHY_CLOCK_PAGE=stopwatch
shot timer "$NOW" MOARCHY_CLOCK_PAGE=timer
shot keypad "$NOW" MOARCHY_CLOCK_PAGE=keypad MOARCHY_CLOCK_TYPED=1500
shot editor "$NOW" MOARCHY_CLOCK_PAGE=editor
shot ringing "$NOW" MOARCHY_CLOCK_PAGE=ring

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night "$NOW" "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte "$NOW" "THEME=$THEMES/catppuccin-latte/colors.toml"
# The light theme's hardest screen is not the one with the palette on it, it is
# the one with two solid fills: a Stop key mixed from the theme's red and a
# Start key that is the accent itself. Both have to keep a legible word on them
# when the window behind them is nearly white, and that is the calculation in
# `accentInk` -- so it is photographed rather than argued about.
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte-stopwatch "$NOW" MOARCHY_CLOCK_PAGE=stopwatch \
    "THEME=$THEMES/catppuccin-latte/colors.toml"
