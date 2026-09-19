// Messages as its own Quickshell process, for a system without omarchy-shell.
//
//   quickshell -p plugins/moarchy.messages/shell.qml
//
// Inside the shell this file is never read: the host keeps Messages.qml
// loaded and listening. Here nothing does, so the window opens at
// startup and closing it ends the process -- which also ends the listening,
// so texts only arrive while its window is up.
//
// MOARCHY_MESSAGES_HIDDEN=1 loads it without opening it, which is how the shell
// runs it: use that to see what it burns while nobody is texting.
import QtQuick
import Quickshell

ShellRoot {
  Messages {
    id: app

    Component.onCompleted: {
      if ((Quickshell.env("MOARCHY_MESSAGES_HIDDEN") || "") === "") app.open("{}")
    }

    Connections {
      target: app.appWindow
      function onUnmapped() { Qt.callLater(Qt.quit) }
    }
  }

  Timer {
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_MESSAGES_QUIT_AFTER") || "0", 10)
    running: interval > 0
    onTriggered: Qt.quit()
  }
}
