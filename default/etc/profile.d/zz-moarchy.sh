# moarchy's environment, and the session that depends on it.
#
# ONE file, deliberately. This was two -- zz-moarchy.sh set PATH and
# zz-moarchy-session.sh exec'd sway -- and /etc/profile sources profile.d in
# sorted order, where "zz-moarchy-session.sh" sorts BEFORE "zz-moarchy.sh"
# ('-' is 0x2D, '.' is 0x2E). So the session exec'd sway and replaced the shell
# before the PATH file ever ran.
#
# On the device that looked like a broken shell: swaybg is /usr/bin so the
# wallpaper painted, while moarchy-restart-shell is /usr/lib/moarchy/bin and was
# simply not found -- no bar, no gesture strip, and not one line of log, because
# the script that writes the log is the one that was missing. Observed on
# hardware 2026-09-06.
#
# Keeping the exec in the same file as the environment it needs is what makes
# that unrepresentable, rather than relying on two filenames sorting the way
# someone intended.

# --- environment -----------------------------------------------------------
# moarchy's Sway counterparts go ahead of upstream Omarchy's Hyprland scripts.
# 19 names are shared -- omarchy-toggle-bar, omarchy-system-lock,
# omarchy-launch-browser and the rest -- and two packages cannot own one path in
# /usr/bin, so ours live in their own directory and win by PATH order instead.
MOARCHY_PATH=/usr/share/moarchy
export MOARCHY_PATH

case ":$PATH:" in
  *":/usr/lib/moarchy/bin:"*) ;;
  *) PATH="/usr/lib/moarchy/bin${PATH:+:$PATH}" ;;
esac
export PATH

# --- the session -----------------------------------------------------------
# Last in this file, and this file sorts last: everything above has to be in
# place before sway inherits it.
#
# Guarded on XDG_VTNR so an SSH login stays a plain shell, and on
# WAYLAND_DISPLAY so re-sourcing inside the session cannot recurse.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "${XDG_VTNR:-}" = "1" ]; then
  export XDG_CURRENT_DESKTOP=sway
  export XDG_SESSION_TYPE=wayland
  export MOZ_ENABLE_WAYLAND=1
  export QT_QPA_PLATFORM=wayland
  export ELECTRON_OZONE_PLATFORM_HINT=wayland
  # -c because /etc/sway/config belongs to the sway package.
  exec sway -c /usr/share/moarchy/config/sway/config
fi
