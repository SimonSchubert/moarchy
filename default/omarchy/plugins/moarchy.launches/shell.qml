// Launches as its own Quickshell process, for a system without omarchy-shell.
//
//   quickshell -p plugins/moarchy.launches/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Launches.qml itself, keeps it loaded, and decides when the window is up.
// Here nothing does, so the window opens at startup and closing it ends the
// process -- a window that is gone with a process still running is how an app
// becomes a battery bug.
//
// Everything else is the same file the phone runs. The shell-only parts of
// Launches.qml are already written to be absent: `shell` stays null, so the
// summon/hide calls it guards are skipped, and the theme FileView on
// colors.toml simply never loads, which leaves the fallback palette.
import QtQuick
import Quickshell

ShellRoot {
  Launches {
    id: app
    Component.onCompleted: app.open("{}")

    Connections {
      target: app.appWindow
      // The cache is written on unmap. Leaving the event loop one turn later
      // is what lets that write reach the disk.
      function onUnmapped() { Qt.callLater(Qt.quit) }
    }
  }
}
