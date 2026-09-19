// The calendar as its own Quickshell process, for a system without
// omarchy-shell.
//
//   quickshell -p plugins/org.moarchy.calendar/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Calendar.qml itself, keeps it loaded, and decides when the window is up.
// Here nothing does, so the window opens at startup and closing it ends the
// process -- a window that is gone with a process still running is how an app
// becomes a battery bug.
//
// QtQuick is imported for Timer and Connections. An unresolved type fails the
// whole document at load, which is how the first two shell.qml files in this
// repo shipped unable to start at all.
import QtQuick
import Quickshell

ShellRoot {
  Calendar {
    id: app

    // MOARCHY_CALENDAR_HIDDEN=1 loads the app and does not open it, which is
    // the shape the shell runs it in: `keepLoaded` instantiates every plugin
    // at startup and opens none of them. Standalone, this file used to open
    // the window immediately and so never once exercised that state -- which
    // is how a pager that laid itself out in an unopened window reached a
    // phone and took the shell down with it.
    //
    //   MOARCHY_CALENDAR_HIDDEN=1 MOARCHY_CALENDAR_QUIT_AFTER=20 run-local.sh
    //
    // and watch what the process burns. It should be nothing.
    Component.onCompleted: {
      if ((Quickshell.env("MOARCHY_CALENDAR_HIDDEN") || "") === "") app.open("{}")
    }

    Connections {
      target: app.appWindow
      // A half-written event is not saved and never was, but the file is
      // written on every change, so there is nothing to flush here. Leaving
      // the event loop one turn later is what lets any write in flight reach
      // the disk before the process goes.
      function onUnmapped() { Qt.callLater(Qt.quit) }
    }
  }

  // MOARCHY_CALENDAR_QUIT_AFTER=6 -- the check harness's clock, for the reason
  // the GTK apps have one: a run that does not end is a run that hangs CI.
  Timer {
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_CALENDAR_QUIT_AFTER") || "0", 10)
    running: interval > 0
    onTriggered: Qt.quit()
  }
}
