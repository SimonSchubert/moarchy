# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# The palettes come from scripts/fetch-themes.sh, and the two themed shots are
# skipped when they have not been fetched -- a screenshot run should not need
# the network to take the ones that matter.
THEMES="${THEMES:-/tmp/omarchy-themes}"

# Tuesday 15 September 2026, pinned in both halves: demo.py dates its fixture
# from it and the app reads its day from it. A calendar photographed on
# whatever day the run happens is a calendar whose pictures all disagree, and a
# Tuesday is the one day of the week with a week either side of it.
TODAY="MOARCHY_CALENDAR_TODAY=2026-09-15"

# The week starts on Monday in these pictures because it starts on Monday on
# the phone. Qt reads that off the system locale and a container has none
# generated, so without this the grid would open on a Sunday it never opens on.
WEEK="MOARCHY_CALENDAR_WEEK_START=1"

shot month "$TODAY" "$WEEK"
shot agenda "$TODAY" "$WEEK" MOARCHY_CALENDAR_PAGE=agenda
shot editor "$TODAY" "$WEEK" MOARCHY_CALENDAR_EDIT=Dentist
shot picker "$TODAY" "$WEEK" MOARCHY_CALENDAR_EDIT=Dentist MOARCHY_CALENDAR_PICKING=1
shot empty "$TODAY" "$WEEK" MOARCHY_CALENDAR_DAY=2026-09-16

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night "$TODAY" "$WEEK" "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte "$TODAY" "$WEEK" "THEME=$THEMES/catppuccin-latte/colors.toml"
