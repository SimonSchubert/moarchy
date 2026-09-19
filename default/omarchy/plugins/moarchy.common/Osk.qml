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
// app drawer's search field.
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
// instead — a surface sway arranges below the keyboard's layer comes back
// shorter by the keyboard's reservation. `reserving()` is that question, asked
// once for every surface that needs it (`refactor.md` M2).
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

  // What the keyboard reserves at the bottom, in logical px.
  //
  // Measured, not chosen: it is moarchy-keyboard's panel and this shell does
  // not set it. The same figure `gestures.md` I5b pins the app drawer's reflow to
  // -- at 176 the app drawer settles over the top key row -- and G10 cuts the back
  // edge short by.
  //
  // Deliberately *not* through Style.space, which every other length in the
  // shell goes through. Style.space applies this theme's spacing scale, and the
  // keyboard is a separate client that never sees it.
  readonly property int keyboardPanelHeight: 200

  // I1a, I5e. Is the keyboard reserving space under `win` right now?
  //
  // Read off the compositor's configure for `win`, which only works for a
  // surface sway arranges after the keyboard's zone is taken: sway resolves
  // exclusive zones from Overlay downwards, and the keyboard is on Top. A Top
  // sheet mapped later, or a Bottom one, shrinks with it; an Overlay surface
  // does not, and cannot ask this.
  //
  // Half a panel is the threshold rather than an exact height. Measured on the
  // app drawer, the granted height is 694 or 674 with the keyboard down and 494 or
  // 474 with it up -- each pair being a surface's own strip inset on and off --
  // so the clusters are 180px apart and the 20px an inset moves cannot walk the
  // answer across the line. It has to be nowhere near either cluster, not exact.
  function reserving(win: var): bool {
    return !!win && !!win.screen
        && win.height < win.screen.height - osk.keyboardPanelHeight / 2
  }
}
