// Keep as its own Quickshell process, for a system without omarchy-shell.
//
//   quickshell -p plugins/org.moarchy.keep/shell.qml
//
// This file is why the re-port happened at all: Keep was written against
// qs.Commons and qs.Ui, so it could only ever run inside the shell, and
// nothing -- not the checks, not the screenshots, not a laptop -- could open
// it. Coming off those two imports is what made this possible.
import QtQuick
import Quickshell

ShellRoot {
  Keep {
    id: app
    Component.onCompleted: app.open("{}")

    Connections {
      target: app.appWindow
      // Notes are written on a debounce; leaving the event loop one turn later
      // is what lets the last one reach the disk.
      function onUnmapped() { Qt.callLater(Qt.quit) }
    }
  }

  Timer {
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_KEEP_QUIT_AFTER") || "0", 10)
    running: interval > 0
    onTriggered: Qt.quit()
  }
}
