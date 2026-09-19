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
# 21 names are shared -- omarchy-toggle-nightlight, omarchy-system-lock,
# omarchy-launch-browser and the rest -- and two packages cannot own one path in
# /usr/bin, so ours live in their own directory and win by PATH order instead.
MOARCHY_PATH=/usr/share/moarchy
export MOARCHY_PATH

case ":$PATH:" in
  *":/usr/lib/moarchy/bin:"*) ;;
  *) PATH="/usr/lib/moarchy/bin${PATH:+:$PATH}" ;;
esac
export PATH

# linux-aarch64 grok 1.0.30 TUI executes sha512su0 (SIGILL on sargo/pinephone).
# The wrapper pins 1.0.25; this stops that pin from replacing itself.
export GROK_DISABLE_AUTOUPDATER=1

# --- the session -----------------------------------------------------------
# Last in this file, and this file sorts last: everything above has to be in
# place before sway inherits it.
#
# Guarded on XDG_VTNR so an SSH login stays a plain shell, and on
# WAYLAND_DISPLAY so re-sourcing inside the session cannot recurse.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "${XDG_VTNR:-}" = "1" ]; then
  export XDG_SESSION_TYPE=wayland
  export MOZ_ENABLE_WAYLAND=1
  export QT_QPA_PLATFORM=wayland
  export ELECTRON_OZONE_PLATFORM_HINT=wayland

  # --- Hyprland, one shot ----------------------------------------------------
  # While the port is in progress this image can boot either compositor, and
  # which one is decided by a file rather than by a rebuild.
  #
  # The flag is removed BEFORE the exec, and that ordering is the whole safety
  # property: a Hyprland that fails to start, or that exits, lands back on sway
  # at the next login with nothing to undo and no cable. `touch` the flag and
  # end the session to try one.
  #
  # This block goes away when Hyprland becomes the default -- at which point
  # the sway exec below is what is deleted, not this.
  if [ -e "$HOME/.local/state/moarchy/try-hyprland" ]; then
    rm -f "$HOME/.local/state/moarchy/try-hyprland"
    export XDG_CURRENT_DESKTOP=Hyprland
    export XDG_SESSION_DESKTOP=Hyprland
    # -c for the same reason as sway's: ~/.config/hypr is upstream's, and
    # docs/structure.md P1 keeps this package out of $HOME.
    exec Hyprland -c /usr/share/moarchy/config/hypr/hyprland.lua
  fi

  export XDG_CURRENT_DESKTOP=sway
  # -c because /etc/sway/config belongs to the sway package.
  exec sway -c /usr/share/moarchy/config/sway/config
fi
