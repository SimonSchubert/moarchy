// The clock as its own Quickshell process, for a system without omarchy-shell.
//
//   quickshell -p plugins/moarchy.clock/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Clock.qml itself, keeps it loaded, and decides when the window is up. That
// is not a detail for this app -- `keepLoaded` is the only reason an alarm can
// go off with no window on screen, and here nothing keeps anything loaded, so
// closing the window ends the process. A window that is gone with a process
// still running is how an app becomes a battery bug.
//
// QtQuick is imported for Timer and Connections. An unresolved type fails the
// whole document at load, which is how the first two shell.qml files in this
// repository shipped unable to start at all.
import QtQuick
import Quickshell

ShellRoot {
  Clock {
    id: app
    Component.onCompleted: app.open("{}")

    Connections {
      target: app.appWindow
      // The file is written on unmap. Leaving the event loop one turn later is
      // what lets that write reach the disk.
      function onUnmapped() { Qt.callLater(Qt.quit) }
    }
  }

  // MOARCHY_CLOCK_QUIT_AFTER=6 -- the check harness's clock, for the reason
  // the GTK apps have one: a run that does not end is a run that hangs CI.
  Timer {
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_CLOCK_QUIT_AFTER") || "0", 10)
    running: interval > 0
    onTriggered: Qt.quit()
  }
}
