# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# Four tabs, and every one of them reads the container's own /proc -- which is
# the point: the numbers in these pictures are real, they are just not this
# machine's. Nothing is pinned, so two runs disagree in the last digit.
THEMES="${THEMES:-/tmp/omarchy-themes}"

shot processor
shot memory MOARCHY_VITALS_PAGE=memory
shot tasks MOARCHY_VITALS_PAGE=tasks
shot network MOARCHY_VITALS_PAGE=network

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte "THEME=$THEMES/catppuccin-latte/colors.toml"
