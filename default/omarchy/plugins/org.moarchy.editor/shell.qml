// Text Editor as its own Quickshell process, for a system without omarchy-shell.
//
//   quickshell -p plugins/org.moarchy.editor/shell.qml
//   MOARCHY_EDITOR_OPEN=/etc/hostname run-local.sh
//
// Inside the shell this file is never read: the plugin host instantiates
// Editor.qml itself, keeps it loaded, and decides when the window is up. Here
// nothing does, so the window opens at startup and closing it ends the process.
//
// QtQuick is imported for Timer and Connections. An unresolved type fails the
// whole document at load.
import QtQuick
import Quickshell

ShellRoot {
  Editor {
    id: app

    // MOARCHY_EDITOR_HIDDEN=1 loads the app and does not open it, which is the
    // shape the shell runs it in: `keepLoaded` instantiates every plugin at
    // startup and opens none of them. It should cost nothing -- one small JSON
    // file is read, and no text file is until somebody asks for one.
    Component.onCompleted: {
      if ((Quickshell.env("MOARCHY_EDITOR_HIDDEN") || "") === "") app.open("{}")
    }

    Connections {
      target: app.appWindow
      // The list of files is written as a file opens, which has happened by
      // the time this runs. Leaving the event loop one turn later is what lets
      // that write reach the disk before the process goes.
      function onUnmapped() { Qt.callLater(Qt.quit) }
    }
  }

  // MOARCHY_EDITOR_QUIT_AFTER=6 -- the check harness's clock: a run that does
  // not end is a run that hangs CI.
  Timer {
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_EDITOR_QUIT_AFTER") || "0", 10)
    running: interval > 0
    onTriggered: Qt.quit()
  }
}
