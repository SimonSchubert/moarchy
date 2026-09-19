// Mail as its own Quickshell process, for a system without omarchy-shell.
//
//   quickshell -p plugins/org.moarchy.mail/shell.qml
//
// Inside the shell this file is never read: the host keeps Mail.qml loaded,
// and it looks at the Inbox every fifteen minutes with its window closed.
// Here nothing does, so the window opens at startup and closing it ends the
// process -- and with it, the looking.
//
// MOARCHY_MAIL_HIDDEN=1 loads it without opening it, which is how the shell
// runs it: use that to see what it burns while nobody is reading mail.
import QtQuick
import Quickshell

ShellRoot {
  Mail {
    id: app

    Component.onCompleted: {
      if ((Quickshell.env("MOARCHY_MAIL_HIDDEN") || "") === "")
        app.open(Quickshell.env("MOARCHY_MAIL_PAYLOAD") || "{}")
    }

    Connections {
      target: app.appWindow
      function onUnmapped() { Qt.callLater(Qt.quit) }
    }
  }

  Timer {
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_MAIL_QUIT_AFTER") || "0", 10)
    running: interval > 0
    onTriggered: Qt.quit()
  }
}
