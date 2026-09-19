// Contacts as its own Quickshell process, for a system without omarchy-shell.
//
//   quickshell -p plugins/moarchy.contacts/shell.qml
import QtQuick
import Quickshell

ShellRoot {
  Contacts {
    id: app

    Component.onCompleted: {
      if ((Quickshell.env("MOARCHY_CONTACTS_HIDDEN") || "") === "") app.open("{}")
    }

    Connections {
      target: app.appWindow
      function onUnmapped() { Qt.callLater(Qt.quit) }
    }
  }

  Timer {
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_CONTACTS_QUIT_AFTER") || "0", 10)
    running: interval > 0
    onTriggered: Qt.quit()
  }
}
