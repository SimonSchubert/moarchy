# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# demo.py writes a week of texts and the contacts file beside them, so the
# conversation list has names and unread counts in it, and one conversation
# has a text that did not go -- the one state with a button in a bubble.
THEMES="${THEMES:-/tmp/omarchy-themes}"

shot threads
shot thread MOARCHY_MESSAGES_THREAD="+44 7700 900030"
shot compose MOARCHY_MESSAGES_THREAD="+49 30 5550188" MOARCHY_MESSAGES_TYPED="Is Thursday at 9 still free?"
shot new MOARCHY_MESSAGES_PAGE=new MOARCHY_MESSAGES_TYPED="j"
shot new-number MOARCHY_MESSAGES_PAGE=new MOARCHY_MESSAGES_TYPED="+49 152 909"

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night-thread MOARCHY_MESSAGES_THREAD="+44 7700 900030" "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte-threads "THEME=$THEMES/catppuccin-latte/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte-thread MOARCHY_MESSAGES_THREAD="+44 7700 900030" "THEME=$THEMES/catppuccin-latte/colors.toml"
shot square-thread MOARCHY_MESSAGES_THREAD="+44 7700 900030" CORNERS=square
