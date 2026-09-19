// Reversi as its own Quickshell process, for a system without omarchy-shell.
//
//   quickshell -p plugins/org.moarchy.reversi/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Reversi.qml itself, keeps it loaded, and decides when the window is up. Here
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
  Reversi {
    id: app
    Component.onCompleted: app.open("{}")

    Connections {
      target: app.appWindow
      // The cache is written on unmap. Leaving the event loop one turn later
      // is what lets that write reach the disk -- and `shutdown()` joins the
      // search thread, without which the process crashes on the way out
      // rather than exiting.
      function onUnmapped() { app.shutdown(); Qt.callLater(Qt.quit) }
    }
  }

  // MOARCHY_REVERSI_QUIT_AFTER=6 -- the check harness's clock, for the reason the
  // GTK app has one: a run that does not end is a run that hangs CI.
  //
  // It waits for the search rather than cutting it off, and then takes the
  // search thread down before the engine. See Reversi.qml's Loader: a
  // WorkerScript that is still alive when the engine goes turns a clean exit
  // into a crash report. WorkerScript cannot be interrupted, so a search in
  // flight has to be allowed to land first.
  Timer {
    id: quitter
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_REVERSI_QUIT_AFTER") || "0", 10)
    running: interval > 0
    repeat: true
    onTriggered: {
      if (app.thinking) { quitter.interval = 250; return }
      quitter.running = false
      app.shutdown()
      Qt.callLater(Qt.quit)
    }
  }
}
