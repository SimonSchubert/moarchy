// The two things every plugin in this repo does identically.
//
// Both were byte-for-byte the same in nine files before they lived here, which
// is the repo's own test for what belongs in shared/. Neither is a policy
// decision an app should be free to get subtly different: where a note is
// written, and what gets out of the way when a window opens.
.pragma library

// Where an app's own files live.
//
// `$XDG_DATA_HOME` when it is set and `~/.local/share` when it is not -- the
// same place the GTK half writes, which is the whole reason a game left in one
// is the game found in the other. `override` is the harness's
// MOARCHY_<APP>_DIR, so a screenshot run can be pointed at a fixture without
// touching anybody's real notes.
function dataDir(app, home, xdg, override) {
  if (override && override.length) return override
  var base = (xdg && xdg.length) ? xdg : ((home || "") + "/.local/share")
  return base + "/moarchy-" + app
}

// What an app's window pushes out of the way as it opens.
//
// The control center, the app drawer, the workspace overview and the theme picker are the four
// surfaces that can be up when somebody taps an app, and all four are modal in
// the sense that matters: they cover the screen. Leaving one of them open
// behind a window is how a back swipe ends up dismissing the wrong thing.
//
// It is the shell's own Sheet.js list, read from the other side of the repo
// boundary -- an app cannot import moarchy.common, so this is the one copy the
// rule is allowed. A sheet added there and not here is a sheet left standing
// over a window that has just opened.
//
// A no-op off the shell, where `shell` is null and there is nothing to hide.
var OVERLAYS = ["moarchy.control-center", "moarchy.app-drawer", "moarchy.workspace-overview",
                "moarchy.themes"]

function hideOverlays(shell) {
  if (!shell || typeof shell.isPluginOpen !== "function") return
  for (var i = 0; i < OVERLAYS.length; i++)
    if (shell.isPluginOpen(OVERLAYS[i])) shell.hide(OVERLAYS[i])
}
