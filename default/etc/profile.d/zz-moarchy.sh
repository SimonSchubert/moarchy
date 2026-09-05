# moarchy's Sway counterparts, ahead of upstream Omarchy's Hyprland scripts.
#
# Sorted after omarchy.sh on purpose: that file sets OMARCHY_PATH and PATH, and
# this one has to run afterwards to end up in front of it.
#
# The shadowing is the whole mechanism. moarchy ships 19 scripts whose names
# upstream also uses -- omarchy-toggle-bar, omarchy-system-lock,
# omarchy-launch-browser and the rest -- and they have to win. Two packages
# cannot both own /usr/bin/omarchy-toggle-bar, so ours live in their own
# directory and take precedence by PATH order instead. This is what the old
# installer arranged in ~/.profile with MOARCHY_PATH/bin ahead of
# OMARCHY_PATH/bin; the arrangement has not changed, only where it is written.
MOARCHY_PATH=/usr/share/moarchy
export MOARCHY_PATH

case ":$PATH:" in
  *":/usr/lib/moarchy/bin:"*) ;;
  *) PATH="/usr/lib/moarchy/bin${PATH:+:$PATH}" ;;
esac
export PATH
