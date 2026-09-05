# Start the session on the phone's own screen, and only there.
#
# This was appended to ~/.bash_profile by the installer. It is a file under
# /etc now, so a fresh user gets a working session with nothing copied into
# their home directory -- which is the difference between an installer and a
# package.
#
# Guarded on XDG_VTNR so an SSH login stays a plain shell. Guarded on
# WAYLAND_DISPLAY so re-sourcing inside the session does not recurse.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "${XDG_VTNR:-}" = "1" ]; then
  export XDG_CURRENT_DESKTOP=sway
  export XDG_SESSION_TYPE=wayland
  export MOZ_ENABLE_WAYLAND=1
  export QT_QPA_PLATFORM=wayland
  export ELECTRON_OZONE_PLATFORM_HINT=wayland
  # -c because /etc/sway/config belongs to the sway package. Ours is a package
  # file too, named here rather than copied over someone else's.
  exec sway -c /usr/share/moarchy/config/sway/config
fi
