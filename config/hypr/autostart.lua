-- What starts with the session, on top of upstream's default/hypr/autostart
-- .lua -- which already imports the systemd/D-Bus environment and launches the
-- shell through omarchy-launch-shell.
--
-- hl.on("hyprland.start") fires once, at startup, and NOT on `hyprctl reload`.
-- The sway config this replaced used `exec_always` for the shell and the
-- keyboard so that a config reload restarted a dead one; upstream's
-- omarchy-launch-shell supervises the shell itself, which is strictly better,
-- and the keyboard loses that safety net -- a dead keyboard stays dead until
-- moarchy-toggle-keyboard. Worth knowing; not worth an exec_always that runs
-- on every theme change.

hl.on("hyprland.start", function()
  -- Nothing else pulls graphical-session.target up. Hyprland is started from
  -- a login shell rather than uwsm or a display manager (uwsm is not in Arch
  -- Linux ARM), so every user unit hanging off that target would otherwise be
  -- enabled, correct, and never started. moarchy-session.target BindsTo it.
  --
  -- Upstream's autostart has already run the import-environment and
  -- dbus-update-activation-environment pair by the time this handler fires,
  -- so the units inherit a populated environment.
  hl.exec_cmd("systemctl --user start moarchy-session.target")

  -- The polkit agent. Upstream leaves this to its own session plumbing.
  hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

  -- The wallpaper. swaybg is not a sway component -- it is a wlr-layer-shell
  -- client, and Hyprland implements that protocol -- so it carries across the
  -- compositor change unchanged, and so does the background-switching script
  -- that writes the file it reads.
  hl.exec_cmd("swaybg -i " .. (os.getenv("HOME") or "") ..
              "/.local/state/omarchy/current/background -m fill")

  -- The on-screen keyboard. It does not raise itself: it comes up when its
  -- restore handle is tapped, when a text field is tapped, or when something
  -- drives sm.puri.OSK0. A keyboard that appeared whenever anything took
  -- focus covered half the screen for the drawer's own search field.
  hl.exec_cmd("moarchy-keyboard")

  -- Blank the screen when idle, but never lock it. swayidle is an
  -- ext-idle-notify-v1 client and carries across unchanged, like swaybg.
  --
  -- Both commands go through moarchy-* wrappers rather than straight at the
  -- compositor: the timeout has to honour the Stay Awake flag, and the resume
  -- must not light a panel the power button deliberately blanked.
  hl.exec_cmd("swayidle -w timeout 600 'moarchy-idle-blank' resume 'moarchy-screen wake'")
end)
