# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# demo.py writes five files under the data directory's home/ and a list of
# them, and MOARCHY_EDITOR_HOME points ~ there, so a row reads
# ~/Documents rather than the scratch directory's full path. $WORK is the
# harness's own, and the data directory under it is the one demo.py wrote to.
THEMES="${THEMES:-/tmp/omarchy-themes}"
FIXTURE="MOARCHY_EDITOR_HOME=$WORK/data/moarchy-editor/home"

shot list "$FIXTURE"
shot file "$FIXTURE" MOARCHY_EDITOR_OPEN=recent
shot config "$FIXTURE" MOARCHY_EDITOR_OPEN=recent:1
shot menu "$FIXTURE" MOARCHY_EDITOR_OPEN=recent MOARCHY_EDITOR_MENU=1
shot unsaved "$FIXTURE" MOARCHY_EDITOR_OPEN=recent "MOARCHY_EDITOR_TYPE=- sun cream" \
  MOARCHY_EDITOR_DIALOG=unsaved
shot saveas "$FIXTURE" MOARCHY_EDITOR_OPEN=new MOARCHY_EDITOR_DIALOG=saveas
shot readonly "$FIXTURE" MOARCHY_EDITOR_OPEN=recent:3
shot empty MOARCHY_EDITOR_EMPTY=1

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night "$FIXTURE" MOARCHY_EDITOR_OPEN=recent "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte "$FIXTURE" "THEME=$THEMES/catppuccin-latte/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte-file "$FIXTURE" MOARCHY_EDITOR_OPEN=recent \
    "THEME=$THEMES/catppuccin-latte/colors.toml"
