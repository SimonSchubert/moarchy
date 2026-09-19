# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# A calculator has one screen, and the only thing that varies on it is what has
# been typed -- so the second shot types the expression the README describes
# rather than photographing a keypad under a zero twice.
THEMES="${THEMES:-/tmp/omarchy-themes}"

shot keypad MOARCHY_CALCULATOR_TYPED=1234.5+20%

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night MOARCHY_CALCULATOR_TYPED=1234.5+20% \
    "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte MOARCHY_CALCULATOR_TYPED=1234.5+20% \
    "THEME=$THEMES/catppuccin-latte/colors.toml"
