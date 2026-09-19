// The on-screen keyboard, asked to show. The kit's copy of moarchy's
// default/omarchy/plugins/moarchy.common/Osk.qml: plugins here cannot import
// that, and the shell's plugins cannot import this.
//
// A field does not get a keyboard by taking focus. moarchy-keyboard writes its
// visibility from two things only, its restore handle and SetVisible (its
// SPEC.md AC 50), so a tap on a field has to ask. Show is that tap (moarchy's
// gestures.md G14). Hide is not this file's: the back swipe is the one way
// down, and it lives in the shell.
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
