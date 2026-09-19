// Files as its own Quickshell process, for a system without omarchy-shell.
//
//   quickshell -p plugins/moarchy.files/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Files.qml itself, keeps it loaded, and decides when the window is up. Here
// nothing does, so the window opens at startup and closing it ends the process
// -- a window that is gone with a process still running is how an app becomes
// a battery bug.
//
// QtQuick is imported for Timer and Connections. An unresolved type fails the
// whole document at load.
import QtQuick
import Quickshell

ShellRoot {
  Files {
    id: app

    // MOARCHY_FILES_HIDDEN=1 loads the app and does not open it, which is the
    // shape the shell runs it in: `keepLoaded` instantiates every plugin at
    // startup and opens none of them. Standalone, this file opens the window
    // immediately and so would never once exercise that state -- which is how
    // a list that laid itself out in an unopened window reached a phone and
    // took the shell down with it.
    //
    //   MOARCHY_FILES_HIDDEN=1 MOARCHY_FILES_QUIT_AFTER=20 run-local.sh
    //
    // and watch what the process burns. It should be nothing: no directory is
    // read before open(), and the browse list has no model until the window is
    // mapped.
    Component.onCompleted: {
      if ((Quickshell.env("MOARCHY_FILES_HIDDEN") || "") === "") app.open("{}")
    }

    Connections {
      target: app.appWindow
      // The folder is written down on unmap, which has already happened by the
      // time this runs. Leaving the event loop one turn later is what lets that
      // write reach the disk before the process goes.
      function onUnmapped() { Qt.callLater(Qt.quit) }
    }
  }

  // MOARCHY_FILES_QUIT_AFTER=6 -- the check harness's clock, for the reason the
  // GTK apps have one: a run that does not end is a run that hangs CI.
  Timer {
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_FILES_QUIT_AFTER") || "0", 10)
    running: interval > 0
    onTriggered: Qt.quit()
  }
}
