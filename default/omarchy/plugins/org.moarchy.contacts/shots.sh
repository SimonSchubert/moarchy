# Which screens to photograph. The harness is scripts/qml-shot.sh.
THEMES="${THEMES:-/tmp/omarchy-themes}"

shot list
shot editor-new MOARCHY_CONTACTS_PAGE=editor
shot editor MOARCHY_CONTACTS_EDIT="Ada Okonkwo"

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte "THEME=$THEMES/catppuccin-latte/colors.toml"
