// The shell's own screens that are windows, and how to get from one to the
// other. docs/gestures.md K10.
//
//     import "../moarchy.common/ShellApps.js" as ShellApps
//
// One list, in one file. It used to be two: `shellAppIds` in moarchy.gestures
// and three named properties in moarchy.recents, kept in step by hand. They
// went out of step -- gestures named only `moarchy.settings` for a release
// after Wi-Fi and Bluetooth had become shell apps, which is what sent a back
// swipe over Wi-Fi through to closing the window *behind* it. A second list is
// how that happens; this is the file that stops there being one.
.pragma library

var IDS = ["moarchy.settings", "moarchy.wifi", "moarchy.bluetooth"]

function ids() {
  return IDS.slice()
}

// The live plugin instance behind an id, or null when the plugin failed to
// load or has not been constructed yet. Plugins are built in shell.json order,
// so a plugin listed after the one asking will answer null for a while.
function item(shell, id) {
  if (!shell || !shell.panelLoaders) return null
  var loader = shell.panelLoaders[id]
  return loader && loader.item ? loader.item : null
}

// The plugin whose window is this toplevel, or null for anybody else's window.
//
// Compared on the handle rather than on the title: the title is how the window
// finds its own handle once (moarchy.common/AppWindow.qml), and doing it again
// here would be a second matcher with its own way of being subtly wrong.
function forToplevel(shell, tl) {
  if (!tl) return null
  for (var i = 0; i < IDS.length; i++) {
    var plugin = item(shell, IDS[i])
    if (plugin && plugin.appWindow && plugin.appWindow.toplevel === tl)
      return plugin
  }
  return null
}

// Focus a window -- any window, not only a shell app.
//
// It lives beside the shell-app helpers because both of this file's importers
// need it and neither owns a compositor connection: moarchy.recents when a card
// is tapped, moarchy.common/AppWindow when a screen that is already running is
// summoned again. The call is handed to moarchy.gestures, which is where every
// other compositor call in this shell already lives.
//
// The fallback is the request that does not work on this compositor -- see
// focusToplevel() in moarchy.gestures -- and is here only so that a shell whose
// gestures plugin failed to load does something rather than nothing.
function focusToplevel(shell, tl) {
  if (!tl) return false
  var gestures = item(shell, "moarchy.gestures")
  if (gestures && typeof gestures.focusToplevel === "function")
    return gestures.focusToplevel(tl)
  tl.activate()
  return false
}
