# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# Offline throughout: demo.py writes a pad seconds old, the window only fetches
# when its launches are older than that, and a tracker photographed against the
# real Launch Library disagrees with itself between one shot and the next --
# the countdowns move, and the list is different every week.
THEMES="${THEMES:-/tmp/omarchy-themes}"

# Six in the evening on Monday 14 September 2026, pinned in both halves:
# demo.py dates its pad from it and the app reads its clock from it. Without
# that the countdown beside a launch is a function of when the run happened.
NOW="MOARCHY_LAUNCHES_NOW=1789408800"
OFF="MOARCHY_LAUNCHES_OFFLINE=1"

shot upcoming "$NOW" "$OFF"
shot starred "$NOW" "$OFF" MOARCHY_LAUNCHES_PAGE=starred
shot launch "$NOW" "$OFF" MOARCHY_LAUNCHES_OPEN=Artemis
shot search "$NOW" "$OFF" MOARCHY_LAUNCHES_SEARCH=falcon

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night "$NOW" "$OFF" "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte "$NOW" "$OFF" "THEME=$THEMES/catppuccin-latte/colors.toml"
