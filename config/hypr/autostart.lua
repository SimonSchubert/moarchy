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

  -- The geoclue agent. geoclue hands a position only to a client whose
  -- session has an agent registered (or that is on its system whitelist), so
  -- without one GNOME Maps, the browser and every other location client time
  -- out ("Failed to connect to GeoClue2 service") and the modem's GPS is never
  -- even switched on (D8). GNOME and Phosh bring their own; this session has
  -- none, so it runs the one geoclue ships, which is on geoclue.conf's agent
  -- whitelist as geoclue-demo-agent. It needs libnotify (a dependency of
  -- moarchy for that reason), and without it exits at once.
  hl.exec_cmd("/usr/lib/geoclue-2.0/demos/agent")

  -- No wallpaper process. In 4.x the wallpaper is a shell plugin --
  -- shell/plugins/background/Background.qml -- and it reads the same
  -- ~/.local/state/omarchy/current/background that swaybg was pointed at, so
  -- the background-switching script that writes that file is unaffected.
  --
  -- swaybg was here because that plugin imports Quickshell.Hyprland and could
  -- not initialise under sway, which docs/upstream.md logged as the wallpaper
  -- shipping unported. Hyprland closes it, and running both would be two
  -- clients painting one output.

  -- The on-screen keyboard. It does not raise itself: it comes up when its
  -- restore handle is tapped, when a text field is tapped, or when something
  -- drives sm.puri.OSK0. A keyboard that appeared whenever anything took
  -- focus covered half the screen for the appDrawer's own search field.
  hl.exec_cmd("moarchy-keyboard")

  -- Idle behaviour: at 600 s lock the panel and suspend to s2idle, so idle
  -- actually sleeps the phone instead of running at full power behind a dark
  -- screen (docs/fp4-defects.md D28). One timeout runs moarchy-idle-action, which
  -- locks and then suspends in a single action -- rather than a second swayidle
  -- timeout for the suspend, so it does not depend on two independent timeouts
  -- firing in sequence. before-sleep locks first, so every suspend path -- idle
  -- here, or the power button -- wakes to the PIN pad. swayidle is an
  -- ext-idle-notify-v1 client and carries across unchanged, like swaybg.
  --
  -- This MUST be launched in-session (hl.exec_cmd here runs it as a Hyprland
  -- child on seat0): polkit grants suspend to an active seated session without a
  -- prompt but denies it to a seatless one, so an ssh-launched swayidle silently
  -- fails to suspend (auth_admin) even though everything else is right -- D28.
  --
  -- All commands go through moarchy-* wrappers rather than straight at the
  -- compositor: the action honours the Stay Awake flag (and moarchy-idle-suspend
  -- also skips a call/active audio/sleep inhibitor), and the resume must not
  -- light a panel the power button deliberately blanked.
  hl.exec_cmd("swayidle -w timeout 600 'moarchy-idle-action' resume 'moarchy-screen wake' before-sleep 'moarchy-lock'")
end)
