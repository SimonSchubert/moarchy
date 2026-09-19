# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# The palettes come from scripts/fetch-themes.sh, and the two themed shots are
# skipped when they have not been fetched -- a screenshot run should not need
# the network to take the ones that matter.
THEMES="${THEMES:-/tmp/omarchy-themes}"

# The fixture, and the clock it is dated from. Both reach demo.py as well as
# the app, which is what makes "Yesterday" under a file mean the same thing in
# the picture as it does in the directory.
#
# It is outside the harness's own scratch directory on purpose: that one is
# wiped between shots, and building a tree of seventeen files five times over
# is five times the work for five identical trees.
HOME_="MOARCHY_FILES_HOME=/tmp/moarchy-files-demo"
NOW="MOARCHY_FILES_NOW=1789482720"
FIXTURE=("$HOME_" "$NOW")

shot home "${FIXTURE[@]}"
shot downloads "${FIXTURE[@]}" MOARCHY_FILES_PATH=/tmp/moarchy-files-demo/Downloads
shot camera "${FIXTURE[@]}" MOARCHY_FILES_PATH=/tmp/moarchy-files-demo/Pictures/Camera
shot places "${FIXTURE[@]}" MOARCHY_FILES_PAGE=places
shot menu "${FIXTURE[@]}" MOARCHY_FILES_PATH=/tmp/moarchy-files-demo/Downloads \
     MOARCHY_FILES_MENU=firmware.tar.gz
shot view "${FIXTURE[@]}" MOARCHY_FILES_MENU=view
shot paste "${FIXTURE[@]}" MOARCHY_FILES_PATH=/tmp/moarchy-files-demo/Documents \
     MOARCHY_FILES_HOLDING=notes.md

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night "${FIXTURE[@]}" "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte "${FIXTURE[@]}" "THEME=$THEMES/catppuccin-latte/colors.toml"
