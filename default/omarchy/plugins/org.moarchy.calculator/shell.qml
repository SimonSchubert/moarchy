// The calculator as its own Quickshell process, for a system without
// omarchy-shell.
//
//   quickshell -p plugins/org.moarchy.calculator/shell.qml
//
// Inside the shell this file is never read: the plugin host instantiates
// Calculator.qml itself, keeps it loaded, and decides when the window is up.
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
  Calculator {
    id: app
    Component.onCompleted: {
      app.open("{}")
      // What to have typed on arrival, for the screenshot harness and for
      // anybody who wants to see a particular sum without a keyboard. Pressed
      // through the keys rather than assigned, so the picture can only show a
      // state the keypad can actually reach.
      var typed = Quickshell.env("MOARCHY_CALCULATOR_TYPED") || ""
      if (typed.length) Qt.callLater(function () { app.keysFrom(typed) })
    }

    Connections {
      target: app.appWindow
      // The half-typed sum is written on unmap. Leaving the event loop one turn
      // later is what lets that write reach the disk.
      function onUnmapped() { Qt.callLater(Qt.quit) }
    }
  }

  // MOARCHY_CALCULATOR_QUIT_AFTER=6 -- the check harness's clock, for the
  // reason the GTK apps have one: a run that does not end is a run that hangs
  // CI.
  Timer {
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_CALCULATOR_QUIT_AFTER") || "0", 10)
    running: interval > 0
    onTriggered: Qt.quit()
  }
}
