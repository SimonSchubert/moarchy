// Coins as its own Quickshell process, for a system without omarchy-shell.
//
//   quickshell -p plugins/moarchy.coins/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Coins.qml itself, keeps it loaded, and decides when the window is up. Here
// nothing does, so the window opens at startup and closing it ends the process
// -- a window that is gone with a process still running is how an app becomes
// a battery bug.
//
// QtQuick is imported for Timer and Connections. An unresolved type fails the
// whole document at load, which is how the first two shell.qml files in this
// repo shipped unable to start at all.
import QtQuick
import Quickshell

ShellRoot {
  Coins {
    id: app
    Component.onCompleted: app.open("{}")

    Connections {
      target: app.appWindow
      // The cache is written on unmap. Leaving the event loop one turn later
      // is what lets that write reach the disk.
      function onUnmapped() { Qt.callLater(Qt.quit) }
    }
  }

  // MOARCHY_COINS_QUIT_AFTER=6 -- the check harness's clock, for the reason the
  // GTK app has one: a run that does not end is a run that hangs CI.
  Timer {
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_COINS_QUIT_AFTER") || "0", 10)
    running: interval > 0
    onTriggered: Qt.quit()
  }
}
