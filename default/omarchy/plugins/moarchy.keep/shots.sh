# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# demo.py writes the notes -- the GTK app's own fixture, run through the
# plugin's wrapper -- so the grid in these pictures is the same grid the GTK
# screenshots have, which is the claim this port makes.
THEMES="${THEMES:-/tmp/omarchy-themes}"

shot grid
shot list MOARCHY_KEEP_VIEW=list
shot note MOARCHY_KEEP_OPEN=Sourdough
shot ticks MOARCHY_KEEP_OPEN=Shopping
shot menu MOARCHY_KEEP_MENU=Sourdough
shot search MOARCHY_KEEP_SEARCH=bread

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte "THEME=$THEMES/catppuccin-latte/colors.toml"
