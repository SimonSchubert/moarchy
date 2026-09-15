// The on-screen keyboard, asked to show or hide (docs/gestures.md G14, G14a).
//
// Usage:
//     Shared.Osk { id: osk }
//     ...
//     osk.show()   // a tap on a text field
//     osk.hide()   // the back swipe, and nowhere else
//
// `moarchy-keyboard` owns `sm.puri.OSK0` and the only way in is DBus, so this is
// the one place the incantation is written. It stood in `moarchy.gestures` and in
// `bin/moarchy-toggle-keyboard`, and a third copy was about to be written for the
// drawer's search field.
//
// Visibility is sticky. Show is a person tapping a field or the restore handle;
// hide is the back swipe (G2). Overlay open/close and app switches write
// nothing -- that is the flap G14 exists to stop.
//
// ---------------------------------------------------------------------------
// It asks; it does not know
// ---------------------------------------------------------------------------
// There is deliberately no `visible` property here. `sm.puri.OSK0`'s own
// `Visible` reports the keyboard's *intent* and has been observed both ways
// against reality in one evening: `b true` with `grim` showing no keyboard at
// all, and `b false` straight after a tap that left the field focused. A caller
// that wants to know whether the keyboard is really up asks the compositor
// instead — the focused workspace drops by the keyboard's reservation, which is
// what `gestures.md` I5e gates the drawer's inset on.
//
// `execDetached` and not a `Process`: nothing here waits for an answer, and the
// gestures plugin's own note gives the reason — a Process would tie the call to
// this item's lifetime, and the back gesture's hide has to survive the surface
// that asked for it going away.
import QtQuick
import Quickshell

Item {
  id: osk

  visible: false
  width: 0
  height: 0

  function set(up: bool): void {
    Quickshell.execDetached(["busctl", "--user", "call", "sm.puri.OSK0",
                             "/sm/puri/OSK0", "sm.puri.OSK0", "SetVisible",
                             "b", up ? "true" : "false"])
  }

  function show(): void { osk.set(true) }
  function hide(): void { osk.set(false) }
}
