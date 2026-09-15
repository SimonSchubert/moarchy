// The on-screen keyboard, asked to show. App-side copy of
// default/omarchy/plugins/moarchy.common/Osk.qml -- plugins cannot import qs_ui
// and apps cannot import moarchy.common.
//
// Show is a tap on a text field (G14). Hide is not this file's: the back swipe
// is the one way down, and it lives in the shell.
import QtQuick
import Quickshell

Item {
  id: osk

  visible: false
  width: 0
  height: 0

  function show(): void {
    Quickshell.execDetached(["busctl", "--user", "call", "sm.puri.OSK0",
                             "/sm/puri/OSK0", "sm.puri.OSK0", "SetVisible",
                             "b", "true"])
  }
}
