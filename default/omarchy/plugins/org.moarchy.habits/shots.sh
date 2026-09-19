# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# The day is pinned in both halves: demo.py dates its history from it and the
# app reads its today from it. A habit tracker photographed on whatever day the
# run happens is one whose streaks disagree with its grid.
THEMES="${THEMES:-/tmp/omarchy-themes}"
TODAY="MOARCHY_HABITS_TODAY=2026-09-15"

shot today "$TODAY"
shot detail "$TODAY" MOARCHY_HABITS_OPEN=Read
shot achievements "$TODAY" MOARCHY_HABITS_PAGE=achievements

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night "$TODAY" "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte "$TODAY" "THEME=$THEMES/catppuccin-latte/colors.toml"
