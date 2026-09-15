// One touch sequence turned into progress, velocity and a latch
// (docs/refactor.md F1).
//
// Usage:
//     import "../moarchy.common" as Shared
//     Shared.DragTracker {
//       id: sheetDrag
//       travel: root.closeTravel
//       openDirection: -1
//       latchSign: +1
//       slop: root.dragSlop
//       startFrom: root.progress
//       onBegan: root.dragging = true
//       onMoved: p => root.progress = p
//       onFinished: (p, v) => { ... the surface's own commit rule ... }
//     }
//
// Four surfaces each wrote this out: the gesture strip, the wallpaper, the
// drawer's sheet and handle, and the shade's sheet and band. Each had its own
// copy of the start coordinates, `lastY`/`lastT`, the identical smoothing
// `v * 0.6 + (dy / dt) * 0.4`, a slop latch, a 0..1 clamp, and the
// cleared-on-press flag that stops a drag ending as a tap. Two of the four had
// a watchdog and two did not, so a stranded touch left the drawer parked where
// it left the shade recovered (F2).
//
// A fifth wrote it out and was missed: the back edge, which travels sideways
// (refactor.md H1). It is the reason `axis` exists. It was not a Y-axis
// component that grew an X one -- it was a component that had assumed an axis
// without saying so, and the one gesture on the other axis kept its own copy of
// everything here including, alone among the six, no watchdog at all.
//
// ---------------------------------------------------------------------------
// What it does not own
// ---------------------------------------------------------------------------
// **Thresholds** (F3). `drawerCommit`, `closeCommit`, `openFraction`,
// `closeFraction`, `homeCommit` and the fling limits are per-gesture decisions
// recorded in docs/gestures.md, and they belong to the surface that makes
// them. `finished` hands back progress and velocity and says nothing about
// what they mean.
//
// **Travel** (F4). `targetTravel()`, `closeTravel` and `sheetHeight` are three
// different measurements with three different reasons. This takes one as an
// input rather than choosing it.
//
// **The progress property.** This publishes a number; the surface assigns it.
// That is what keeps the gestures plugin's path intact: it drives the drawer
// through a direct object reference frame by frame, and a shared component
// that reached for the host would marshal a string per touch event on the one
// path that cannot afford it (refactor.md Constraints).
//
// **The trace.** `dragTrace` hangs off each surface's own `onProgressChanged`
// and records what that surface drew, which is the point of it -- the drawer
// traces `homeHint` beside it, and neither is a property of the touch.
// `stranded()` and `canceled()` fire so the surface can mark its own.
//
// ---------------------------------------------------------------------------
// Scene coordinates, and why the caller passes them
// ---------------------------------------------------------------------------
// Every input item on a sheet is a child of the sheet, so its frame moves as
// the sheet does and a delta measured in it feeds back into itself. The
// callers map to the scene before calling in -- `MouseArea` through
// `mapToItem(null, ...)`, `MultiPointTouchArea` through `sceneX`/`sceneY`,
// which is already scene-space. Taking plain numbers rather than an item and
// an event is what lets both kinds of area share this.
import QtQuick

Item {
  id: drag

  // Not drawn, never laid out, and it must not take part in a Column or a Row
  // that happens to contain it.
  visible: false
  width: 0
  height: 0

  // ------------------------------------------------------------ inputs

  // The distance, in scene px, that carries progress from 0 to 1. F4.
  property real travel: 1

  // +1 when travelling *down* raises progress (the shade), -1 when travelling
  // up does (the drawer, the strip). One signed factor rather than a branch:
  // the four surfaces differ only in this.
  property int openDirection: -1

  // Which axis this gesture travels on: "y" or "x". Everything below is
  // written in terms of *along* and *across* rather than dy and dx, so the
  // back edge is this component with one property set rather than a second copy
  // of it (H1, H2).
  property string axis: "y"

  // How far along the axis a finger has to go before this claims the gesture:
  // +1 claims a positive delta only (down on Y, right on X), -1 a negative one
  // (up, left), 0 either. Read every frame rather than once, so a surface whose
  // answer depends on its own state -- the shade's band latches either way once
  // open and downward only while shut -- expresses that as a binding.
  //
  // A sign rather than the compass word this took until H2, for the reason
  // `openDirection` is one: "up" says nothing on the axis the back edge
  // travels, and a component that takes a direction as a number takes both axes
  // without a translation table in the middle.
  property int latchSign: 0

  // Also require the travel to be more along the axis than across it. The strip
  // and the wallpaper set it, because a sideways swipe on the strip is a
  // different gesture (B2) and must not latch this one; the back edge sets it
  // because a vertical scroll that begins at the edge is not a back (G6).
  property bool axisDominant: false

  // The surface's own veto, tested at the moment of latching rather than at
  // press: the strip refuses once a hold has fired or when it has no target.
  property bool latchable: true

  // Travel past which movement stops being a tap.
  property int slop: 0

  // Claim the gesture on the press rather than on the first movement past the
  // slop. For a surface whose whole area is a handle -- the drawer's grab bar,
  // the shade's band across the status bar -- there is nothing else the finger
  // could have meant, and both of those already set `dragging` from the press.
  //
  // It is not cosmetic. `dragging` gates the shade's input mask and the
  // drawer's `opened`, so latching a frame later than the touch would change
  // which surface a second finger reaches mid-pull.
  property bool latchOnPress: false

  // Where this drag starts from -- sampled on press, so an already-open sheet
  // continues rather than restarting at 0.
  property real startFrom: 0

  // A touch sequence normally ends in released or canceled, but a compositor
  // restart or a lost seat can strand one. Left stranded mid-drag a sheet
  // stays where the finger left it and, for a full-screen one, keeps the whole
  // screen's input. F2: this arrives with the tracker rather than with two of
  // the four surfaces.
  property int watchdogMs: 4000

  property bool enabled: true

  // ----------------------------------------------------------- outputs
  //
  // Written here and read by the surface. Not `readonly`: QML forbids
  // assigning to one at all, including from inside the component that declares
  // it, and the alternative -- a shadow property per output -- would double
  // every line below for no reader's benefit.

  // A touch is down. True from the press, whether or not it ever latches, so a
  // handle can light under a thumb that has not moved yet (style.md H1).
  property bool active: false

  // The gesture has been claimed. This is what `dragging` is bound to, and it
  // is deliberately not `active`: `opened` and `keyboardFocus` read `dragging`
  // on the drawer, so a mere touch flipping it would tell the rest of the
  // shell the sheet had stopped being open.
  property bool latched: false

  // Clamped to 0..1: what a sheet's own progress is assigned from.
  property real progress: 0

  // The same number unclamped, which the strip needs and the sheets do not.
  // Its second stop is *past* fully open -- the drag continues into the home
  // band at pull 1.15 (A4) -- so a clamp here would make the home gesture
  // unreachable while every sheet went on working, which is the shape of bug
  // that gets found by hand a week later.
  property real travelled: 0

  // Scene-signed along the axis: positive is downward on Y and rightward on X,
  // because that is what the coordinates do. Almost nothing wants it in these
  // terms -- read `openVelocity`.
  property real velocity: 0

  // The same speed signed **toward open**, which is what a fling test means on
  // every surface: positive is "let go now and it should end up more open".
  //
  // It exists because the six areas this replaced did not agree. Four measured
  // `nowY - lastY` and two -- the strip and the wallpaper, the two whose sheet
  // opens *upward* -- measured `lastY - y`, flipping the sign so that "faster
  // open" was positive in their own release rule. Unifying on the scene sign
  // without flipping those two back inverted their fling test: a quick flick
  // up produced a large negative number, which is neither `>= fling` nor
  // `> -fling`, so the drawer sprang shut from above halfway. A slow drag past
  // the commit still opened, which is why a 2000ms synthetic drag never caught
  // it.
  //
  // So the sign lives here, once, derived from the direction the surface has
  // already declared -- rather than in each surface's head.
  readonly property real openVelocity: drag.velocity * drag.openDirection
  property real dx: 0
  property real dy: 0

  // The same two deltas as along-the-axis and across-it. Everything that
  // decides anything reads these; `dx` and `dy` stay because a surface's own
  // commit rule may want a named axis -- the back edge's does (G6).
  readonly property real along: drag.axis === "x" ? drag.dx : drag.dy
  readonly property real across: drag.axis === "x" ? drag.dy : drag.dx

  property real startProgress: 0

  // Cleared on the next press, never on release, and that ordering is the
  // whole point. Qt delivers `released` and *then* `clicked`, so a flag
  // cleared in the release handler is already false when the click arrives --
  // and the control launches the app the finger started its drag on. Three
  // surfaces each carried this with its own paragraph explaining it.
  property bool wasDrag: false

  // Whether anything has moved yet. Separate from `latched`, because a surface
  // that claims the gesture on the press still has a slop to cross before it
  // moves: the shade's band owns the status bar from the touch, and a 2px
  // wobble on it must not start opening the shade.
  property bool travelling: false

  // ----------------------------------------------------------- signals

  // The gesture latched. Where a surface freezes anything for the duration --
  // the shade latches its own height (S23) -- this is the frame to do it on.
  signal began()

  // Per frame, after the state above is updated. The velocity is
  // `openVelocity`, signed toward open.
  signal moved(real progress, real velocity)

  // The finger lifted after a latched drag. The surface decides commit versus
  // spring-back; this knows neither (F3). The velocity is `openVelocity`.
  signal finished(real progress, real velocity)

  // The gesture ended without a decision: the compositor took the touch, or
  // the watchdog fired. `startProgress` is where it began, which is what a
  // spring-back goes to.
  signal canceled(real from)

  // Fired before `canceled` when the watchdog is what ended it, so a trace can
  // tell a stranded touch from a real cancel -- they leave a sheet in the same
  // place and want opposite fixes.
  signal stranded()

  // ----------------------------------------------------------- driving

  // The last sample on the axis, whichever axis that is.
  property real lastPos: 0
  property real lastT: 0
  property real startX: 0
  property real startY: 0

  function press(sceneX: real, sceneY: real): void {
    if (!drag.enabled) return
    drag.active = true
    drag.latched = false
    drag.travelling = false
    drag.wasDrag = false
    drag.startX = sceneX
    drag.startY = sceneY
    drag.lastPos = drag.axis === "x" ? sceneX : sceneY
    drag.lastT = Date.now()
    drag.dx = 0
    drag.dy = 0
    drag.velocity = 0
    drag.startProgress = drag.startFrom
    drag.progress = drag.startFrom
    drag.travelled = drag.startFrom
    watchdog.restart()
    if (drag.latchOnPress && drag.latchable) {
      drag.latched = true
      drag.began()
    }
  }

  function move(sceneX: real, sceneY: real): void {
    if (!drag.active) return
    var now = Date.now()
    drag.dx = sceneX - drag.startX
    drag.dy = sceneY - drag.startY

    if (!drag.latched) {
      if (!drag.latchable) { watchdog.restart(); return }
      // Re-tested every frame rather than only on the first movement, so a
      // thumb that starts its arc across the axis still latches once the travel
      // along it dominates (B2).
      var far = drag.latchSign === 0 ? Math.abs(drag.along) > drag.slop
                                     : drag.along * drag.latchSign > drag.slop
      if (!far || (drag.axisDominant && Math.abs(drag.along) <= Math.abs(drag.across))) {
        watchdog.restart()
        return
      }
      drag.latched = true
      drag.began()
    }

    // Latched is not moving. A drag claimed on the press has not crossed
    // anything yet, and a drag claimed by travel crossed it in the branch
    // above -- so this is a no-op for the second kind and the gate for the
    // first.
    if (!drag.travelling) {
      if (Math.abs(drag.along) <= drag.slop) { watchdog.restart(); return }
      drag.travelling = true
    }

    // Smoothed, so one jittery frame at the end of a slow drag cannot read as
    // a fling. Signed in scene coordinates -- positive is downward -- and the
    // surface reads it against its own fling limit in the same frame.
    //
    // The floor is one frame, not one millisecond. Two move events delivered
    // closer together than the compositor can draw say nothing about how fast
    // the finger is going, and dividing by the gap between them multiplies the
    // answer by up to 16: measured, a deliberately slow 8% drag came through
    // as two samples and opened the drawer as though it had been flung. A real
    // 60Hz gesture sits at ~16ms and never meets this floor; what does meet it
    // is a burst after a stalled frame, and a burst is exactly the thing that
    // should not be read as speed.
    var pos = drag.axis === "x" ? sceneX : sceneY
    var dt = Math.max(16, now - drag.lastT)
    drag.velocity = drag.velocity * 0.6 + ((pos - drag.lastPos) / dt) * 0.4
    drag.lastPos = pos
    drag.lastT = now

    drag.travelled = drag.startProgress
                     + drag.openDirection * drag.along / Math.max(1, drag.travel)
    drag.progress = Math.max(0, Math.min(1, drag.travelled))
    drag.moved(drag.progress, drag.openVelocity)
    watchdog.restart()
  }

  function release(): void {
    watchdog.stop()
    if (!drag.active) return
    drag.active = false
    if (!drag.latched) return
    drag.latched = false
    drag.wasDrag = true
    drag.finished(drag.progress, drag.openVelocity)
  }

  // Fired whether or not the gesture ever latched, unlike `finished`. A
  // surface's cancel path is where it gets back to rest, and a touch that was
  // taken away before it latched still has state to clear -- the strip's does,
  // and losing that was how a cancelled sideways swipe left the pill offset.
  function cancel(): void {
    watchdog.stop()
    if (!drag.active) return
    drag.active = false
    drag.latched = false
    drag.canceled(drag.startProgress)
  }

  Timer {
    id: watchdog
    interval: drag.watchdogMs
    onTriggered: {
      if (!drag.active) return
      drag.stranded()
      drag.cancel()
    }
  }
}
