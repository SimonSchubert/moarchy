// The pull-down: quick settings and notifications, dragged out of the top edge.
//
// ---------------------------------------------------------------------------
// One surface that grows, not one that is permanently full-screen
// ---------------------------------------------------------------------------
// The obvious way to build a drag-to-reveal is a full-screen surface that is
// always mapped, with its input region masked down to a strip while closed.
// Quickshell supports exactly that -- the notification toasts and the keyboard
// panel both do it -- but it leaves a 720x1440 translucent surface for the
// compositor to blend into every frame, forever, on a Mali-400. That is a
// permanent cost paid so that a gesture can start instantly.
//
// So the surface is anchored top/left/right and *not* bottom, which means
// implicitHeight decides how tall it is, and it is only as tall as the bar
// until a finger starts moving. One resize, at the top of the gesture, and from
// then on the drag is a child item's `y` -- no further Wayland traffic, and
// nothing composited while the control center is shut but a 360x26 band.
//
// The gestures plugin's rule about never widening a surface applies to the idle
// state, not to this: widening steals *new* touches from the app underneath,
// and here the finger is already down and the control center is what should be catching
// everything for the rest of the gesture. The in-flight touch is unaffected
// either way, because Wayland's implicit grab is per-surface, not per-geometry.
//
// ---------------------------------------------------------------------------
// Why the strip sits on top of the bar
// ---------------------------------------------------------------------------
// Overlay outranks the bar's Top, so this strip covers it and every touch along
// the status bar arrives here. That is the reason moarchy.bar is built
// with no tap targets at all -- not a style choice that could be revisited. A
// button added to that bar would be dead on arrival and the cause would not be
// anywhere near it.
//
// ---------------------------------------------------------------------------
// Why the bottom 20px are masked out while open
// ---------------------------------------------------------------------------
// Two Overlay surfaces stack by map order, and map order here comes from
// iterating a JS object of installed plugins -- not something to build a
// gesture on. Rather than hope the gestures strip lands on top, the control center cuts
// the home pill's band out of its own input region, so the pill keeps working
// whichever way the stacking falls.
//
// ---------------------------------------------------------------------------
// Shape
// ---------------------------------------------------------------------------
// Radii here are written out rather than taken from Style.cornerRadius, which
// mirrors Hyprland's `decoration:rounding` and is pinned to 0 on this device by
// the hyprctl shim -- correct for tiled windows under Sway, and wrong for every
// surface in a phone UI. Colours still come from the theme, so a theme switch
// recolours all of this; only the geometry is ours.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
// Networking only, and only for `Networking.wifiEnabled` in the `wifi` IPC
// verb: the Bluetooth adapter, the PipeWire sink and the Wi-Fi device itself
// belong to the widgets that draw them now (docs/widgets.md W3).
import Quickshell.Networking
import qs.Commons
import qs.Ui as Ui
import "../moarchy.common/Theme.js" as Theme
import "../moarchy.common/ShellApps.js" as ShellApps
import "../moarchy.common/Edge.js" as Edge
import "../moarchy.common/Widgets.js" as WidgetList
import "../moarchy.common" as Shared

Item {
  id: root

  // Injected by the host after construction, and not `readonly` or `required` --
  // see the app drawer, which also says why this is the only one declared (J8).
  property var shell: null

  readonly property string pluginId: "moarchy.control-center"
  readonly property string historyDir:
    Quickshell.env("HOME") + "/.local/state/omarchy/notifications/history"

  // ------------------------------------------------------------ geometry
  //
  // The grab strip is exactly the bar, so the whole status bar is the handle.
  // Read live off the bar rather than hardcoded: a bar that changes height and
  // a handle that does not would leave a dead sliver or an overhang.
  readonly property int stripHeight: root.shell && root.shell.bar && root.shell.bar.barSize > 0
    ? root.shell.bar.barSize : Style.space(26)

  // Must match moarchy.gestures' own stripHeight. Duplicated rather than
  // read across plugins because the control center has to know it even when the gestures
  // plugin failed to load, and a control center that swallowed the bottom edge in that
  // case would be much worse than one that leaves 20px unused.
  readonly property int gestureStrip: Style.space(20)

  // Likewise moarchy.gestures' backEdgeWidth -- and its workspaceOverviewEdgeWidth,
  // which is the same number for the same reason (gestures.md G8, P1). The
  // control center is on Overlay and maps when it opens, so it lands *above* the
  // always-mapped edge surfaces and would otherwise swallow every swipe in
  // from either side -- which is exactly what it did on the left: back closed
  // the app drawer and the carousel and left the control center untouched, because those
  // two are on Top and this one is not. The right band had the same fault and
  // nothing to show it until that edge was worth reaching over an open control center.
  readonly property int edgeBand: Style.space(16)

  readonly property int screenHeight: controlCenterWindow.screen ? controlCenterWindow.screen.height : 720

  // Deliberately short of the full screen -- and a cap now, not the height.
  // The band of scrim left underneath is the tap-to-dismiss target, and it is
  // the only workable one: the drag handle is the status bar, so an upward drag
  // to close would start within 26px of the top of the screen and have nowhere
  // to travel. The home swipe closes the control center too, but a phone should not have
  // exactly one way out of a full-screen panel. A sheet shorter than the cap
  // hands back more of that band, never less (docs/control-center.md S22).
  readonly property real sheetFraction: 0.9
  readonly property int sheetMax:
    Math.max(1, Math.round((root.screenHeight - root.gestureStrip) * root.sheetFraction))

  // The sheet's own inset. Named because the cap arithmetic and the layout both
  // need it, and a second copy of Style.space(18) is how those two drift apart.
  readonly property int sheetPadTop: Style.space(8)
  readonly property int sheetPadBottom: Style.space(18)
  readonly property int sheetPadSide: Style.space(12)
  readonly property int sheetGap: Style.space(10)

  // S21. As tall as what is in it. Measured off the Column rather than summed
  // here: the volume slider, the media card and the notifications header each
  // come and go, and a sum written at this end of the file would be a second
  // layout to keep in step with the first.
  readonly property int sheetWanted:
    sheetColumn.implicitHeight + root.sheetPadTop + root.sheetPadBottom

  // S22. The Math.min is belt and braces, not the mechanism. The cap is enforced
  // one level down, on the list, whose own ceiling is derived from sheetMax -- so
  // a sheet that would overrun becomes a sheet at exactly sheetMax with a
  // *scrolling* list inside it, never one with its bottom cut off. The min only
  // bites if the chrome alone outgrows the cap, and it fails safe toward keeping
  // the scrim band.
  readonly property int sheetTarget:
    Math.max(1, Math.min(root.sheetMax, root.sheetWanted))

  // S23. sheetHeight is the divisor for both drag mappings and the multiplier for
  // the sheet's y, so a notification landing mid-drag would rescale the gesture
  // under the finger: the sheet would grow downward as the same millimetre of
  // thumb became worth less of it. Latched when the drag latches, released by
  // this binding when it ends -- a condition stated once, rather than an
  // assignment that a third drag entry point could forget.
  //
  // Latched from sheetHeight and not from sheetTarget, deliberately. If a growth
  // is part-way through its Behavior when the finger arrives, what is on screen
  // is the interpolated value; freezing at the target would snap the sheet at
  // the instant of the press, which is the jump this exists to prevent.
  property int sheetFrozen: 0
  // The fallback is load-bearing, not belt and braces. `dragging` is set by
  // whoever is driving -- and since Q1 that includes moarchy.gestures, which
  // writes it straight from setTargetProgress and has no way to call
  // beginDrag(). Without the `> 0` this read `sheetFrozen` at 0 for the whole
  // of an edge drag: a sheet of zero height behind a live scrim, and a
  // `closeTravel` of 1 that targetTravel() rejects -- so the drag divided by
  // 45% of the screen instead, ran half again too fast, and an ordinary pull
  // landed past the home stop and went home.
  property int sheetHeight: (root.dragging && root.sheetFrozen > 0)
                            ? root.sheetFrozen : root.sheetTarget

  // Both drag entry points go through this. The latch is written *before*
  // `dragging` flips, so there is no frame in which the binding above can read a
  // stale sheetFrozen.
  function beginDrag(): void {
    root.sheetFrozen = root.sheetHeight
    root.dragging = true
  }

  // The third entry point, and the one that is not this file's. An edge drag
  // latches through `warming`, which moarchy.gestures sets at the latch and
  // before the first progress (N3) -- so the freeze happens on the same frame
  // it would for a drag that started here.
  onWarmingChanged: if (root.warming) root.beginDrag()

  // -------------------------------------------------------------- type
  //
  // The same weight the bar runs at. Light text on a dark surface reads thinner
  // than it measures, and a control center whose clock was Regular under a bar whose
  // clock was DemiBold read as two different phones stacked on top of each
  // other. moarchy.bar's textWeight carries the ink measurements.
  readonly property int textWeight: Font.DemiBold

  // Every glyph on this surface gets a fixed square slot and is centred on the
  // ink it actually paints, not on the box the font reserves for it.
  //
  // Both halves are needed. Advance widths differ per glyph in a Nerd Font --
  // the wifi fan is 7px wider than the bluetooth rune -- so intrinsic widths
  // left the two wide tiles' labels starting at different x. And the painted
  // glyph is rarely centred inside its own advance: measured on the gear in the
  // header, the ink sat 4 device pixels right of the circle's centre on a 72px
  // circle, which is small and, with nothing else in the circle to line up
  // against, plainly visible. Ui.OpticalGlyph is the bar's answer to the same
  // problem, and it corrects horizontally only -- rendered both ways here, the
  // vertical correction moved the chevron and the tile glyphs off a line box
  // they were already centred in.
  readonly property int glyphSlot: Math.round(Style.font.iconLarge * 1.35)

  // The square a bare glyph gets to answer in, as opposed to the square it is
  // drawn in (docs/style.md E1, E2, E5). Derived from glyphSlot rather than
  // fixed at 44, because glyphSlot follows the theme's font size: on a theme
  // with a larger base-size the glyph is already over the floor, and a fixed 44
  // would shrink its target back down to meet it.
  readonly property int tapSlot: Math.max(Style.space(44), root.glyphSlot)

  // ------------------------------------------------------------- shape
  Shared.UiFile { id: ui }
  readonly property int radiusSheet: ui.radiusSheet
  readonly property int radiusTile: ui.radiusTile
  readonly property int radiusCard: ui.radiusCard

  // ------------------------------------------------------------ colours
  //
  // Mapped onto the theme's popup role rather than invented, so every Omarchy
  // theme restyles the control center for free. `container` is the tonal fill that most
  // of this is built out of; `textOnAccent` is what has to sit on top of a
  // filled accent surface, and reads off the theme background rather than
  // assuming the accent is dark.
  readonly property color surface: Color.popups.background
  // NOT `onSurface` / `onAccent`, however much the Material role names want to
  // be spelled that way. QML reserves the `on<Uppercase>` prefix for signal
  // handlers, so a property declared there is never readable: the binding
  // evaluates to undefined, undefined assigned to a `color` is #000000, and
  // nothing is logged. The symptom is every glyph and label painted pure black
  // on a dark tile while the properties either side of them are fine.
  readonly property color textOnSurface: Color.popups.text
  readonly property color container: Util.alpha(Color.popups.text, 0.08)
  readonly property color containerHigh: Util.alpha(Color.popups.text, 0.14)
  readonly property color accent: Color.accent
  readonly property color textOnAccent: Color.background
  readonly property color subduedBase: Theme.mix(
    Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 1), Color.popups.text, 0.08)
  readonly property color subdued: Theme.readableOn(root.subduedBase,
                                                   Color.popups.text, 0.55, 4.5)

  // The veil is shared (docs/refactor.md E2); the default ink is this
  // surface's own, which is the half a shared type cannot know (style.md H2).
  component PressVeil: Shared.PressVeil { ink: root.textOnSurface }

  // H3. The seven controls on this sheet that also drag it, bound to the
  // sheet once rather than forwarding four handlers apiece.
  component SheetArea: Shared.SheetDragArea { sheet: root }


  // ---------------------------------------------------------- drag state
  // gestures.md Q2. Which screen edge raised this sheet. Written by
  // moarchy.gestures on a press, and only while the sheet is at rest shut
  // (Q3). The top is where this sheet has always come from, where its own
  // grab band still is whatever this says (Q7), and what it falls back to.
  property string entryEdge: Edge.TOP
  readonly property bool sideways: Edge.horizontal(root.entryEdge)

  property real progress: 0        // 0 shut .. 1 open
  property bool dragging: false
  property bool expanded: false    // the surface is full-screen right now

  // What moarchy.gestures sets when an edge drag latches, so the surface is
  // full-screen on the frame the sheet starts moving rather than one frame
  // later. onProgressChanged below already expands, but it runs *after* the
  // first progress is written -- which was fine while the only way in was
  // this sheet's own band, and a visible first-frame stutter once an edge
  // drives it.
  property bool warming: false

  // D2a, Q2. What one full sheet of travel is worth on the axis the finger
  // moves. Published because moarchy.gestures divides by it: without it
  // targetTravel() falls back to 45% of the screen and this sheet does not
  // follow the finger at all.
  //
  // Sideways it is the sheet's width, which is the screen's: this sheet is
  // as tall as its content (control-center.md S21), and a mirrored width would be a
  // relayout of every tile on it rather than a different path in (Q2a).
  readonly property real closeTravel: Math.max(1, root.sideways
    ? (controlCenterWindow.screen ? controlCenterWindow.screen.width : 360)
    : root.sheetHeight)

  // shell.isPluginOpen() reads this. Mid-drag is neither open nor shut, and
  // reporting "open" there would let a swipe on the home pill try to close a
  // control center the user is still pulling out.
  readonly property bool opened: root.progress >= 1 && !root.dragging

  // Travel that commits a pull-down, as a fraction of the sheet. Deliberately
  // less than half: a control center is cheap to close and annoying to have to drag all
  // the way.
  readonly property real openFraction: 0.35
  readonly property real closeFraction: 0.75
  // Speed that commits regardless of travel, logical px per ms. The strip's
  // `fling` and the app drawer's `sheetFling` are the same number for the same
  // reason: it is matched to what DragTracker's "measuring speed" now reads,
  // and 0.6 was matched to a reading that swung by 5x between identical
  // gestures.
  readonly property real flingVelocity: 0.3
  readonly property int slop: Style.space(6)

  // ------------------------------------------------- H2: dragging the body
  //
  // The 26px grab band at the top is the affordance, not the whole gesture.
  // Dragging up anywhere on the sheet has to close it, and that cannot live on
  // an area behind the content: every tile here is a MouseArea and holds the
  // exclusive grab for the gesture, exactly as the app drawer's app icons do. So
  // the tiles do both jobs -- a touch that never travels activates, one that
  // goes up past the slop drags the sheet.
  readonly property int dragSlop: Style.space(10)

  // Android's long-press interval. Milliseconds, not pixels -- not a Style.space.
  readonly property int holdInterval: 500

  // H2, on the tracker every sheet in this shell now shares
  // (docs/refactor.md F1). The way out is the way back in, reversed:
  // travelling *toward* the entry edge is what closes, and this sheet is
  // already up. From the top that reads `openDirection` +1 and `latchSign`
  // -1, which is what it always was.
  Shared.DragTracker {
    id: sheetDrag
    axis: Edge.axis(root.entryEdge)
    travel: root.closeTravel
    openDirection: Edge.openDirection(root.entryEdge)
    latchSign: Edge.closeLatchSign(root.entryEdge)
    slop: root.dragSlop
    startFrom: root.progress

    onBegan: root.beginDrag()
    onMoved: p => root.progress = p

    // H3, and the thresholds stay here where the numbers are (F3). A short,
    // fast flick means the same as a long slow drag: from 150px down there is
    // not 25% of the sheet left above the finger to travel.
    //
    // `v` is signed toward open. This sheet opens *downward*, so that happens
    // to be the scene sign as well -- unlike the app drawer's, which reads the
    // other way round for the same rule.
    onFinished: (p, v) => {
      root.dragging = false
      if (v <= -root.flingVelocity) root.dismiss()
      else if (v >= root.flingVelocity) root.progress = 1
      else if (p >= root.closeFraction) root.progress = 1
      else root.dismiss()
    }

    onStranded: root.markTrace(-2)
    onCanceled: from => {
      // -1 for a real cancel, against -2 for a stranded one (H5). Only the
      // app drawer's handle marked this, so "a real cancel ends -1" was a check
      // three of the four trackers could not fail.
      root.markTrace(-1)
      root.dragging = false
      root.progress = from >= 0.5 ? 1 : 0
    }
  }

  // The band across the status bar: the same tracker, the other direction.
  //
  // `latchOnPress`, because the whole band is a handle -- there is nothing
  // else a touch on it could mean, and `dragging` from the press is what keeps
  // the input mask off for the length of the pull. The slop is still crossed
  // before anything moves, which is why the tracker keeps those two apart.
  //
  // Shut, the slop applies; open, it does not, because the gesture is already
  // in flight as far as the finger is concerned.
  // Q7, Q3a. The band is the control center's own way in, and it *says so*: a drag
  // that starts here sets `entryEdge` to the top before it moves anything,
  // so the sheet comes down from the status bar the finger is on.
  //
  // Pinning the tracker to the top and leaving `entryEdge` alone was the
  // first version and it was wrong in the hand: with the strip set to raise
  // this sheet, `entryEdge` was left at `bottom` by the last strip press and
  // a pull *down* from the status bar slid the sheet up from the floor. The
  // edge belongs to the gesture doing the raising, not to the setting.
  Shared.DragTracker {
    id: bandDrag
    travel: root.sheetHeight
    openDirection: 1
    latchSign: 0
    latchOnPress: true
    slop: root.progress > 0 ? 0 : root.slop
    startFrom: root.progress

    onBegan: {
      // Only from shut. Part-way up the sheet is already travelling on an
      // axis and this drag is finishing or reversing it -- re-anchoring
      // under the finger is Q3's own rule, read from the other end.
      if (root.progress <= 0) root.entryEdge = Edge.TOP
      root.beginDrag()
    }
    onMoved: p => root.progress = p

    onFinished: (p, v) => {
      var wasOpen = bandDrag.startProgress >= 0.5
      var target
      if (v >= root.flingVelocity) target = 1
      else if (v <= -root.flingVelocity) target = 0
      else if (wasOpen) target = p >= root.closeFraction ? 1 : 0
      else target = p >= root.openFraction ? 1 : 0

      root.dragging = false
      // Through the host, so openPanelIds and this plugin cannot drift apart
      // and leave the next swipe toggling the wrong way.
      if (target === 1 && root.shell) root.shell.summon(root.pluginId, "{}")
      else if (target === 0) root.dismiss()
      else root.progress = target
    }

    onStranded: root.markTrace(-2)
    onCanceled: from => {
      root.markTrace(-1)
      root.dragging = false
      root.progress = from >= 0.5 ? 1 : 0
    }
  }

  // The names the nine controls on this sheet already read. Kept as aliases
  // rather than renamed at the call sites: what moved is where the state is
  // computed, and a rename would bury that under a diff touching every tile.
  readonly property bool sheetDragging: sheetDrag.latched
  readonly property bool sheetWasDrag: sheetDrag.wasDrag
  readonly property real sheetPressY: sheetDrag.startY

  function sheetPress(item, mouse): void {
    root.dragTrace = []
    var p = item.mapToItem(null, mouse.x, mouse.y)
    sheetDrag.press(p.x, p.y)
  }

  function sheetMove(item, mouse): void {
    var p = item.mapToItem(null, mouse.x, mouse.y)
    sheetDrag.move(p.x, p.y)
  }

  function sheetRelease(): void { sheetDrag.release() }
  function sheetCancel(): void { sheetDrag.cancel() }

  function open(payloadJson) {
    // S28. The app drawer is deliberately left alone, where this used to dismiss
    // it. Layer order already does the work: this surface is Overlay and the
    // app drawer is Top, so the control center has always drawn above it and the only thing
    // the hide added was losing what you were looking at.
    //
    // Not symmetrical, and the app drawer's open() keeps hiding *this* for the same
    // reason read the other way: a app drawer raised under a live control center would map
    // invisibly underneath it.
    // Q3a. A summon carries no direction, so it uses this sheet's own edge --
    // but only from rest. `releaseTarget()` commits an edge drag *through*
    // this function with the sheet part-way in, and resetting there would
    // teleport it across the screen on the frame it was let go.
    if (root.progress <= 0 && !root.dragging) root.entryEdge = Edge.TOP

    root.expanded = true
    root.progress = 1

    // Absorb any live toasts. There are none now (S24): moarchy.bar declares
    // notificationPopups false and the patched service writes every
    // notification straight into the history. This stays because it is what
    // makes the transition survivable in both directions -- a shell running
    // with `bar.id` pointed at omarchy.bar, or a popup that was already on
    // screen when the bar changed, still lands in the list rather than
    // floating over it. The service's own popup surface is Overlay too and
    // maps after this one.
    //
    // clearPopups() is not a discard: removePopup archives each row into the
    // history directory, so they land in the list below. That is what Android
    // does when you pull down -- the heads-up notifications become the list.
    if (root.notifications && typeof root.notifications.clearPopups === "function")
      root.notifications.clearPopups()

    root.refresh()
  }

  function close() {
    // F8. A touch can outlive this surface: a long press on a tile opens the
    // Wi-Fi or Bluetooth picker, which hides the control center from under the finger
    // that is still down, and the unmap means the MouseArea never reports a
    // release. The tracker would then sit active until its watchdog fired and
    // put `progress` back -- reopening a control center the picker had just replaced.
    // Measured as S6c: "the picker opened but the control center is open".
    //
    // No-ops on every ordinary path, where release() has already ended it.
    sheetDrag.cancel()
    bandDrag.cancel()
    root.dragging = false
    root.warming = false
    root.progress = 0
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  // Everything that cannot be bound reactively, pulled once per open rather
  // than on a timer: none of it changes while the control center is shut, and a phone
  // that forks rfkill every ten seconds for a panel nobody is looking at is
  // just a slower phone.
  function refresh(): void {
    // Each widget's own probes, through the column: the backlight, the torch
    // and the modem are read by the widget that draws them now, and a host
    // that listed them would be a host that has to be edited to add a widget.
    radios.refresh()
    widgetColumn.refresh()
    // Twice, on purpose, and the deferred one is not the redundant one.
    //
    // Immediately, because the sheet is as tall as its content now, so the
    // height it opens at has to be decided before the open animation starts.
    // Without this the first open after a shell start opens at the
    // no-notifications height and grows 250ms later -- a step the eye reads as a
    // glitch rather than as an arrival.
    //
    // Deferred as well: clearPopups() archives through the service's own
    // serialised file-job queue, so reading the directory in the same tick shows
    // the list as it was a moment before the control center opened. The immediate read
    // gets the height approximately right; the deferred one gets the contents
    // exactly right.
    if (!historyRead.running) historyRead.running = true
    historyRefresh.restart()
  }

  onProgressChanged: {
    // Give the surface back as soon as it is not needed. Until this runs the
    // control center owns the whole screen's input, so leaving it expanded after a
    // snap-back would silently eat the next tap on the app underneath.
    if (root.progress <= 0 && !root.dragging) {
      root.expanded = false
      root.warming = false
    }
    if (root.progress > 0 && !root.expanded) root.expanded = true

    // One integer per frame while a drag is in flight, cleared on the next
    // press. The same diagnostic the app drawer carries, and for the same reason:
    // "does it follow the finger" is a question about the *number of samples*,
    // and polling `state` over IPC answers it at a tenth of the frame rate --
    // which is how a gesture that followed nothing reads as one that tracked.
    //
    // Two details it would be easy to get wrong, and either one makes H2 pass
    // on the bug it exists to catch. Cleared on *press*, not on the drag
    // latching, so a gesture that never latched shows as empty rather than as
    // the previous gesture's trace. And gated on `dragging`, so the 220ms fall
    // after release is not recorded -- that animation runs whether or not the
    // finger ever drove anything, and counting it reports ~14 samples for a
    // control center that jumped shut.
    if (!root.dragging) return
    var next = root.dragTrace.slice()
    if (next.length < 200) next.push(Math.round(root.progress * 100))
    root.dragTrace = next
  }

  property var dragTrace: []

  Behavior on progress {
    enabled: !root.dragging
    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
  }

  // Only while the sheet is parked open. Shut, it is `visible: false` and
  // animating its height is layout work for a surface with no pixels; mid-
  // gesture the 220ms progress ramp already owns the frame budget and a second
  // animated property on top of it buys nothing anyone can see. `opened` is
  // exactly `progress >= 1 && !dragging`, which is both halves of that.
  //
  // 180 rather than the 220 the control center opens with: a list filling in is not a
  // second open, and at 220 it reads as one.
  Behavior on sheetHeight {
    enabled: root.opened
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  // The watchdog against a stranded touch is DragTracker's now (F2), which is
  // how the app drawer finally got one. Left stranded mid-drag this surface stays
  // full-screen and the phone stops responding to touch at all, so it was
  // never optional here -- it was simply written twice and omitted twice.
  //
  // One difference, deliberate: the tracker's timeout springs back to where
  // the drag started rather than to 0. A stranded pull-down used to slam the
  // control center shut even when it had been open before the touch.
  function markTrace(marker): void {
    var next = root.dragTrace.slice()
    next.push(marker)
    root.dragTrace = next
  }

  IpcHandler {
    target: "control-center"

    function state(): string {
      if (root.dragging) return "dragging " + Math.round(root.progress * 100) + "%"
      return root.opened ? "open" : "closed"
    }

    // The samples the last drag actually produced, as the app drawer reports them.
    function dragTrace(): string { return root.dragTrace.join(" ") }

    // S21/S22. The sheet is as tall as its content and no taller, and the list
    // inside it scrolls once that would overrun the cap. Neither half is
    // assertable from outside: `state` says `open` either way, and a capture of
    // a short sheet and a tall one differ only in where a colour stops, which is
    // a pixel comparison against a theme -- the kind of check I1 had to be
    // rewritten to stop being.
    //
    // key=value, the form every other diagnostic line in this shell uses. Each
    // field
    // earns its place:
    //   height/wanted/max  the whole cap story. height == wanted below the cap,
    //                      both == max at it. A sheet that stretched would show
    //                      height > wanted; one truncating its own chrome would
    //                      show wanted > max.
    //   listy/listmax      where the list starts and what it may have. A listmax
    //                      at or near 0 is a control center whose chrome no longer fits
    //                      its own cap -- invisible now that the sheet clips.
    //   list/content       the overflow itself, and the only direct evidence
    //                      that there is more history than is being shown.
    //   scrolls            what the list decided, read from its own binding
    //                      rather than re-derived out here.
    //
    // `content` is the view's estimate for rows it has not built: exact below
    // the cap, approximate above it. Assert `content > list`, never equality.
    function sheet(): string {
      return ["height=" + root.sheetHeight,
              "wanted=" + root.sheetWanted,
              "max=" + root.sheetMax,
              "rows=" + root.historyRows.length,
              "listy=" + Math.round(notificationList.y),
              "listmax=" + notificationList.listMax,
              "list=" + Math.round(notificationList.height),
              "content=" + Math.round(notificationList.contentHeight),
              "scrolls=" + (notificationList.interactive ? 1 : 0),
              // refactor.md F8. Whether a touch is still open on either
              // tracker; `idle` whenever no finger is down. A control that
              // presses without ending leaves it otherwise, and nothing else
              // shows it -- the sheet is where the finger left it either way.
              "drag=" + (sheetDrag.latched || bandDrag.latched ? "latched"
                       : sheetDrag.active || bandDrag.active ? "active" : "idle")
             ].join(" ")
    }

    // S19 by another route. The check for a growing sheet has to start from a
    // known-empty one, and tapping Clear all is not something a test can do
    // without the touch device.
    function clear(): string { root.clearNotifications(); return "ok" }

    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }

    // One line per notification in the history, so a dismissal is assertable
    // by counting -- the same reason the carousel exposes list(). Needed
    // because the swipe (H7) is now the only per-card dismissal there is: with
    // no close button to fall back on, "it renders correctly" stops being
    // evidence that a notification can be got rid of at all.
    function notifications(): string {
      var out = []
      for (var i = 0; i < root.historyRows.length; i++) {
        var r = root.historyRows[i]
        if (r) out.push(root.rowStem(r) + " " + (r.app || "?"))
      }
      return out.join("\n")
    }

    // S25. Where each card's icon came from, one line per row, in list order.
    // The kind rather than the path, because the path is a cache URL for an
    // avatar and an absolute file for everything else -- what a check wants to
    // know is which rule answered, and that `fallback` is not the answer for
    // every row, which is what a broken icon theme looks like from here.
    function icons(): string {
      var out = []
      for (var i = 0; i < root.historyRows.length; i++) {
        var r = root.historyRows[i]
        if (r) out.push(root.rowStem(r) + " " + root.iconFor(r).kind)
      }
      return out.join("\n")
    }

    // S27. What a tap on each card would do, one line per row, in list order.
    // Asking is not doing: this runs nothing, which is what makes it usable
    // from a check that has not decided to lose the notification yet.
    function actions(): string {
      var out = []
      for (var i = 0; i < root.historyRows.length; i++) {
        var r = root.historyRows[i]
        if (r) out.push(root.rowStem(r) + " " + root.actionFor(r))
      }
      return out.join("\n")
    }

    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }

    // W15. The arrangement this surface resolved, one widget per line:
    //
    //     connectivity on available=1
    //     media off available=0
    //
    // The host's answer and not the file's, so a `widgets.toml` the shell has
    // not re-read shows up as a disagreement with `moarchy-widgets list`
    // rather than as agreement with it.
    function widgets(): string {
      var rows = widgetColumn.arrangement
      var out = []
      for (var i = 0; i < rows.length; i++) {
        var live = widgetColumn.instance(rows[i].id)
        out.push(rows[i].id + " " + (rows[i].on ? "on" : "off")
                 + " available=" + (live && live.available ? 1 : 0))
      }
      return out.join("\n")
    }

    // The same list with the names and glyphs on it, as JSON, which is what
    // `moarchy-widgets rows` turns into the Settings page. One list and not
    // two (W8): Settings asks the shell what the shell resolved, rather than
    // keeping a catalogue of its own that would be a version behind.
    function widgetRows(): string {
      var rows = widgetColumn.arrangement
      var out = []
      for (var i = 0; i < rows.length; i++) {
        var live = widgetColumn.instance(rows[i].id)
        out.push({ id: rows[i].id,
                   name: WidgetList.nameFor("control-center", rows[i].id),
                   glyph: WidgetList.glyphFor("control-center", rows[i].id),
                   on: rows[i].on,
                   available: live ? live.available === true : false })
      }
      return JSON.stringify(out)
    }

    // The toggles inside the `toggles` widget, arranged under their own key
    // (docs/widgets.md §E). The same two verbs and the same two shapes as the
    // widgets above, because it is the same mechanism one level down --
    // `moarchy-widgets` addresses this surface as `quick-toggles`.
    function toggles(): string {
      var w = widgetColumn.instance("toggles")
      if (!w) return "absent"
      var rows = togglesFile.resolve("quick-toggles")
      var out = []
      for (var i = 0; i < rows.length; i++)
        out.push(rows[i].id + " " + (rows[i].on ? "on" : "off")
                 + " available=" + (w.usable(rows[i].id) ? 1 : 0))
      return out.join("\n")
    }

    function toggleRows(): string {
      var rows = togglesFile.resolve("quick-toggles")
      var w = widgetColumn.instance("toggles")
      var out = []
      for (var i = 0; i < rows.length; i++)
        out.push({ id: rows[i].id,
                   name: WidgetList.nameFor("quick-toggles", rows[i].id),
                   glyph: WidgetList.glyphFor("quick-toggles", rows[i].id),
                   on: rows[i].on,
                   available: w ? w.usable(rows[i].id) === true : true })
      return JSON.stringify(out)
    }

    // W14. A verb that names a widget answers `absent` when that widget is not
    // in the arrangement -- not "" and not "ok". An empty answer coerces to 0
    // in the selftest's `[[ ]]` comparisons and reads as a pass, which is the
    // failure `empty-ipc-answer-coerces-to-zero` records.
    function widgetCall(id: string, fn: string): string {
      var w = widgetColumn.instance(id)
      if (!w) return "absent"
      if (typeof w[fn] !== "function") return "absent"
      return String(w[fn]())
    }

    // S4, S6a. What the Wi-Fi tile is reading, so a check can tell which branch
    // a tap is about to take without inferring it from the phone's own network
    // -- and can say so when the answer is the surprising one.
    function wifi(): string {
      var w = widgetColumn.instance("connectivity")
      if (!w) return "absent"
      return [Networking.wifiEnabled ? "on" : "off",
              w.wifiDevice && w.wifiDevice.connected ? "connected" : "disconnected",
              w.wifiKnownInRange ? "known-in-range" : "none-known",
              w.wifiStranded ? "stranded" : "ok"].join(" ")
    }

    // The tile's own decision, reached through the tile's own code. Under
    // `dryRun 1` it records and does not act, so S6a is assertable on a phone
    // that is reached over the radio it would otherwise switch off.
    function wifiTap(): string { return widgetCall("connectivity", "wifiTap") }
    function wifiHold(): string { return widgetCall("connectivity", "wifiHold") }
    function btTap(): string { return widgetCall("connectivity", "btTap") }
    function btHold(): string { return widgetCall("connectivity", "btHold") }

    // S29d. `mobile` and not `data`: an IpcHandler is a QtObject and `data` is
    // already one of its properties, so a function of that name would collide
    // with it rather than be reachable.
    function mobile(): string {
      var w = widgetColumn.instance("mobile-data")
      if (!w) return "absent"
      return [w.dataPresent ? "present" : "absent",
              w.dataEnabled ? "on" : "off",
              w.dataConnected ? "connected" : "disconnected",
              w.dataLocked ? "locked" : "unlocked",
              w.dataSimMissing ? "no-sim" : "sim",
              // The latch, which is what decides whether the tile is on
              // screen at all -- and the only way a check can tell a tile
              // that is drawn and disconnected from one that has vanished.
              w.dataSeen ? "drawn" : "hidden"].join(" ")
    }
    function dataTap(): string { return widgetCall("mobile-data", "tap") }
    function dataHold(): string { return widgetCall("mobile-data", "hold") }

    function dryRun(on: string): string {
      root.dryRun = (on === "1" || on === "true" || on === "on")
      return root.dryRun ? "on" : "off"
    }
    function lastLaunch(): string { return root.lastLaunch }
    function lastAction(): string { return root.lastAction }
  }

  // ------------------------------------------------------------- sources

  readonly property var notifications: root.shell && typeof root.shell.serviceFor === "function"
    ? root.shell.serviceFor("omarchy.notifications") : null

  // ------------------------------------------------- the widget contract
  //
  // What a widget draws with, answered by name (docs/widgets.md §C). The
  // colours and the radii above are the same six roles and three radii this
  // file always declared; these are the rest of the contract, and they are
  // deliberately generic names rather than the control center's own -- a
  // widget that read `controlCenterTile` would be a widget that knows which
  // surface it is on.
  readonly property int tileHeight: ui.controlCenterTile
  readonly property int sliderHeight: ui.controlCenterSlider
  readonly property int roundSize: ui.controlCenterRound
  function radiusOn(size) { return ui.radiusOn(size) }

  // The sheet a widget's controls drag (W13, refactor.md H3). This surface is
  // one, so it hands over itself; a host that is not dragged hands over null
  // and SheetDragArea leaves the gesture alone.
  readonly property var sheet: root

  // S8, S9. Airplane is the one piece of state two widgets share -- the tile
  // is in `toggles` and `connectivity` needs it to know whether a tap means
  // unblock or toggle -- so the host owns one and publishes it rather than
  // each of them probing rfkill and holding its own answer.
  Shared.Radios { id: radios }

  // The arrangement file again, for the `toggles` IPC verbs. The toggles
  // widget has its own watch on it; this is the host's, and it is read-only.
  Shared.WidgetsFile { id: togglesFile }
  readonly property bool airplane: radios.airplane
  function setAirplane(on) { radios.setAirplane(on) }
  function enableRadio(kind) { radios.enableRadio(kind) }

  Timer { id: historyRefresh; interval: 250; onTriggered: historyRead.running = true }

  // --------------------------------------------------------- actions

  // Set by `control-center dryRun 1`, the way Settings does it. What the tile
  // decided is recorded either way; only the effect that cannot be taken back
  // -- the radio write -- is held back. Without this a check of S6a would have
  // to switch the radio off on a phone reached over that radio.
  //
  // Read by the widgets off the host (W4), because it is a fact about this
  // surface being under test and not about any one tile.
  //
  // Summoning a picker is deliberately NOT held back, and used to be. The
  // sentence above said "the radio write and the launch", and the launch it
  // meant was `nmtui-connect` in a terminal, from before S6b made the picker a
  // screen. A screen can be closed again, which is the whole test dryRun
  // applies; holding it back made S6 and S6c unpassable by construction --
  // they assert that the picker is on screen, and the setup that let them run
  // was what stopped it opening. Both failed for two releases, reported each
  // time as "the summon was recorded and did not land", which is exactly what
  // was happening and exactly what was being asked for.
  property bool dryRun: false
  property string lastLaunch: ""
  property string lastAction: ""

  // One entry point for every screen a widget asks for, and the host's to
  // decide (W5): the widget says which screen, this says what it costs.
  function openScreen(id) {
    // The control center goes away first -- the same order the gear uses (S2). It is a
    // sheet over whatever workspace this is, and the screen it summons is a
    // window on another one (docs/gestures.md K1), so leaving it up would put
    // the sheet over the workspace the summon just left.
    root.dismiss()
    root.lastAction = "picker"
    root.lastLaunch = id
    if (root.shell && typeof root.shell.summon === "function")
      root.shell.summon(id, JSON.stringify({ returnTo: root.pluginId }))
  }

  // ---------------------------------------------------- notification history
  //
  // Read here rather than through the service's showRecentHistory(): that
  // replays history back into popupModel, and the service's own toast surface
  // is visible whenever popupModel is non-empty -- so asking for history would
  // spray toasts over the top of the control center that is displaying it.
  property var historyRows: []

  Shared.Probe {
    id: historyRead
    command: ["bash", "-c", "cat " + root.historyDir + "/*.json 2>/dev/null | tail -40"]
    onAnswered: {
      var rows = []
      var lines = text.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        try { rows.push(JSON.parse(line)) } catch (e) { /* half-written file */ }
      }
      rows.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
      root.historyRows = rows
    }
  }

  // The service names each file <timestamp>-<originalId>.json (imageStem), so a
  // single row can be dropped without disturbing the rest -- which is what
  // makes per-notification dismissal possible at all from out here.
  function rowStem(row) {
    return String(row.timestamp || 0) + "-" + String(row.originalId || 0)
  }

  // S25. What leads a card, first match wins: the notification's own picture
  // (an avatar, album art -- the service copies these beside the history, so
  // they outlive the sender's temp file), its app icon, the icon of the
  // desktop entry its app name matches, the glyph omarchy-notification-send
  // attaches, and last a bell. `glyph` is always set, because a picture that
  // is named and will not load falls back to it.
  readonly property int cardIcon: Style.space(36)
  readonly property string bellGlyph: "󰂚"

  // Upstream NotificationCard's rule, so a card here and a toast on a desktop
  // resolve one value the same way. The `check` argument is what keeps an
  // unknown themed name from coming back as Qt's missing-texture placeholder.
  function iconSource(value): string {
    var s = String(value || "")
    if (s === "") return ""
    if (s.indexOf("file://") === 0 || s.indexOf("image://") === 0) return s
    if (s.charAt(0) === "/") return Util.fileUrl(s)
    return String(Quickshell.iconPath(s, true) || "")
  }

  // The desktop entry a notification's app name belongs to. Through
  // sortedEntries, which is the list the app drawer's grid is built from -- rows,
  // not entries, so `.entry` is unwrapped here rather than read straight off.
  function entryFor(app) {
    var want = String(app || "").toLowerCase()
    if (!want || !root.shell || !root.shell.appLibrary) return null
    var lib = root.shell.appLibrary
    var rows = lib.sortedEntries("") || []
    for (var i = 0; i < rows.length; i++) {
      var e = rows[i] && rows[i].entry
      if (!e) continue
      var id = String(e.id || "").toLowerCase().replace(/\.desktop$/, "")
      var name = String(lib.entryName(e) || "").toLowerCase()
      // The tail of a reverse-DNS id too: "Web" notifies and the entry is
      // org.gnome.Epiphany.
      if (want === id || want === name || want === id.split(".").pop()) return e
    }
    return null
  }

  function iconFor(row) {
    var r = row || {}
    var glyph = String(r.glyph || "") || root.bellGlyph
    var image = root.iconSource(r.image)
    if (image !== "") return { kind: "image", source: image, glyph: glyph }
    var appIcon = root.iconSource(r.appIcon)
    if (appIcon !== "") return { kind: "appIcon", source: appIcon, glyph: glyph }
    var entry = root.entryFor(r.app)
    var fromEntry = entry && root.shell.appLibrary
      ? String(root.shell.appLibrary.iconSource(entry.icon) || "") : ""
    if (fromEntry !== "") return { kind: "entry", source: fromEntry, glyph: glyph }
    return { kind: r.glyph ? "glyph" : "fallback", source: "", glyph: glyph }
  }

  // S27. What a tap on a card does, first match wins -- the order upstream's
  // toast click takes, less the one step history cannot keep:
  //
  //   exec    Omarchy's own `--exec` argv, which the row carries as data, so
  //           it survives into history. The first-run "Update System" is one.
  //   focus   the sender's window, if it has one open.
  //   launch  the sender's app, if a desktop entry answers to its name --
  //           what a phone does with a notification from an app not running.
  //   none    nothing to do: the card does not light, and a tap leaves it.
  //
  // A libnotify "default" action is the step that is missing. It lives on the
  // sender's live notification, which the service lets go of once the
  // notification is written into history; focusing the sender is upstream's
  // own answer for the many senders that register none.

  // Upstream's parseExecArgv (NotificationLogic.js): a structural check that
  // fails closed. Which senders may set the hint is the notification bus's
  // boundary, not this function's -- the same one upstream's toast has.
  function execArgvFor(row) {
    var text = String((row && row.execArgv) || "")
    if (!text) return null
    var parsed
    try { parsed = JSON.parse(text) } catch (e) { return null }
    if (!Array.isArray(parsed) || parsed.length === 0) return null
    for (var i = 0; i < parsed.length; i++)
      if (typeof parsed[i] !== "string") return null
    if (!parsed[0] || parsed[0].charAt(0) === "-") return null
    return parsed
  }

  // The sender's window: its app id is the notification's app name, the tail
  // of a reverse-DNS one, or the id of the desktop entry the name matches.
  function windowFor(row) {
    var app = String((row && row.app) || "").toLowerCase()
    if (!app) return null
    var entry = root.entryFor(app)
    var entryId = entry ? String(entry.id || "").toLowerCase().replace(/\.desktop$/, "") : ""
    var list = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      var id = String((list[i] && list[i].appId) || "").toLowerCase()
      if (id && (id === app || id === entryId || id.split(".").pop() === app)) return list[i]
    }
    return null
  }

  function actionFor(row): string {
    if (root.execArgvFor(row)) return "exec"
    if (root.windowFor(row)) return "focus"
    return root.entryFor(row ? row.app : "") ? "launch" : "none"
  }

  // The notification is done with once acted on, as on Android: the card goes
  // and the control center with it, so what the tap opened is what is on screen. The
  // row is dropped last -- that destroys the delegate this was called from.
  function runRow(row): void {
    var kind = root.actionFor(row)
    root.lastAction = "card:" + kind
    if (kind === "none") return
    if (kind === "exec") {
      // Through bash's positional parameters, as upstream runs it: never a
      // shell string, so a title or a filename cannot become a command.
      Util.execArgv(root.execArgvFor(row))
    } else if (kind === "focus") {
      // Not toplevel.activate(): the foreign-toplevel request is a no-op on
      // this compositor, and moarchy.gestures is where the swaymsg dispatch
      // that works lives (gestures.md K12).
      ShellApps.focusToplevel(root.shell, root.windowFor(row))
    } else {
      var entry = root.entryFor(row.app)
      // Through appLibrary, so a card's launch draws the same splash a tap in
      // the app drawer draws (windows.md L1).
      root.shell.appLibrary.launch(entry.id, root.shell.appLibrary.entryName(entry))
    }
    root.close()
    root.dismissRow(row)
  }

  function dismissRow(row) {
    if (!row) return
    var stem = root.rowStem(row)
    Quickshell.execDetached(["bash", "-c",
      "rm -f " + root.historyDir + "/" + stem + ".json"])

    // Matched on the stem, not on object identity. This filtered with
    // `historyRows[i] !== row`, and `row` is a delegate's modelData: with a JS
    // array as the model, QML can hand out a fresh wrapper around the same
    // underlying object on each access, so `!==` was true for the very row that
    // had just been tapped and nothing was ever removed. The file was already
    // gone by then, so the card sat there looking dead and the notification was
    // simply absent the next time the control center opened.
    var next = []
    for (var i = 0; i < root.historyRows.length; i++)
      if (root.rowStem(root.historyRows[i]) !== stem) next.push(root.historyRows[i])
    root.historyRows = next
  }

  function clearNotifications() {
    if (!root.notifications) return
    root.notifications.clearPopups()
    root.notifications.clearHistory()
    root.historyRows = []
  }

  // ========================================================== components

  // A tonal icon button, for the two things in the header that are not
  // settings: the Omarchy menu and the power routes. Circle at Large, rounded
  // square at Modest, square at Square -- the same D1 tile radius as the
  // sliders, capped at a half-side.
  component RoundButton: Rectangle {
    id: rb
    property string glyph: ""
    signal activated()
    width: ui.controlCenterRound
    height: width
    radius: ui.radiusOn(width)
    color: root.container

    // Drawn at controlCenterRound, answering at 44 where the neighbours allow it
    // (docs/style.md E1-E3). The pair sits 8px apart, so 4 each is the most
    // either may take without the later one eating the earlier one's edge.
    readonly property int grow:
      Math.min(Style.space(4), Math.max(0, Math.round((root.tapSlot - width) / 2)))

    // The veil takes the drawn circle, not the grown target (docs/style.md H8, E2).
    PressVeil {
      anchors.fill: parent
      radius: parent.radius
      on: rbArea.pressed && !root.sheetDragging
    }

    // Centred on the ink, because neither of the two obvious ways gets there.
    //
    // This used to be a filled Text with AlignHCenter, on the reasoning that it
    // keeps the item on integer coordinates. Rendered on the device and
    // measured against the circle it sits in, that put the gear 3.9 device
    // pixels right of centre -- `Text` aligned the line using the advance of
    // the *primary* family (8.4px of monospace) while painting a fallback glyph
    // 13.4px wide, so the two disagree by half their difference. Plain
    // `anchors.centerIn` does centre the advance, and lands 1.7px the other
    // way, because the ink is not centred inside the advance either.
    //
    // Ui.OpticalGlyph measures the painted bounds and shifts by the difference:
    // 0.3px, on the same capture. It is the bar's component, doing here what it
    // does to the status glyphs there.
    Ui.OpticalGlyph {
      anchors.fill: parent
      text: rb.glyph
      fontFamily: Style.font.family
      fontSize: Style.font.icon
      color: root.textOnSurface
    }

    // Drawn at controlCenterRound, answering toward 44 (docs/style.md E1-E3). The two
    // buttons sit 8px apart, so 4 each is the most either may take without
    // the later one eating the earlier one's edge (E3). Compact's 32 therefore
    // answers over 40, not 44 -- the same E4 trade the transport buttons make.
    SheetArea {
      id: rbArea
      anchors.fill: parent
      anchors.margins: -rb.grow
      onClicked: if (!root.sheetWasDrag) rb.activated()
    }
  }

  // ============================================================== surface

  PanelWindow {
    id: controlCenterWindow

    // Top/left/right only. Anchoring the bottom too would make the surface
    // full-height permanently and implicitHeight would stop meaning anything.
    anchors { top: true; left: true; right: true }
    // `warming` as well as `expanded`: an edge drag latches before it writes
    // a progress, and the surface has to be there for the first frame the
    // sheet is drawn on rather than the one after it.
    implicitHeight: (root.expanded || root.warming) ? root.screenHeight
                                                    : root.stripHeight
    color: "transparent"
    surfaceFormat.opaque: false

    WlrLayershell.namespace: "moarchy-control-center"
    WlrLayershell.layer: WlrLayer.Overlay
    // No text input anywhere in here, and None makes it structurally impossible
    // for the control center to steal focus from the app underneath -- so a pull-down,
    // a tap on a tile and a flick back up leaves you exactly where you were.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Reserve nothing. With Auto, growing the surface would reflow every tiled
    // window at 60Hz for the length of the drag.
    exclusionMode: ExclusionMode.Ignore

    // Cut the two edges that belong to other surfaces out of this one's input
    // region: the home pill along the bottom, and the 16px band down each
    // side. A masked-out band falls through to the next surface in the layer,
    // which is what lets all three keep working with the control center down.
    Region {
      id: openRegion
      x: root.edgeBand
      y: 0
      width: Math.max(1, controlCenterWindow.width - 2 * root.edgeBand)
      height: Math.max(1, controlCenterWindow.height - root.gestureStrip)
    }

    // Only masked once fully open. During the drag the whole surface should
    // catch input -- the finger already owns it, and a stray second touch
    // landing in the app underneath mid-pull would be worse than useless.
    mask: root.opened ? openRegion : null

    // ------------------------------------------------------------ scrim
    Rectangle {
      anchors.fill: parent
      // Alpha on one quad, animated by binding rather than by an opacity
      // property on a subtree -- an `opacity` here would make the renderer
      // group and composite the whole sheet off-screen first.
      // Straight off the theme background rather than Color.menu.scrim: that
      // token is already a composed colour with its own alpha baked in, so
      // re-alpha'ing it produces whatever the theme happened to choose rather
      // than a dim. Over a bright wallpaper that read as flat grey.
      color: Util.alpha(Color.background, 0.72 * root.progress)
      visible: root.progress > 0

      // Tap-to-dismiss *and* the close drag (H2), because the band of scrim
      // left below the sheet is where a thumb starts an up-swipe. That band is
      // no longer a fixed ~70px: the sheet is as tall as its content, so the
      // band is ~70px with the control center full and several hundred with it near
      // empty. Never less -- that is what the cap is for (S22).
      //
      // Wired to the same trio as the sheet rather than to `clicked` alone: a
      // MouseArea that only answers `clicked` still consumes the whole gesture,
      // so an up-drag begun here moved nothing at all and then dismissed the
      // control center outright on release. The control center appeared to have no close
      // animation, and it had none -- it was being closed by a tap that
      // happened to have travelled 250px.
      //
      // Gated on `progress`, NOT on `opened`, and that is the same trap the
      // app drawer's keyboardFocus documents. `opened` goes false on the first
      // frame of the drag; an area that disables mid-gesture delivers
      // `canceled`, which snapped the sheet back to fully open and then dropped
      // it on a canned 220ms ramp. Holding it live until the sheet is all the
      // way down keeps the gesture intact.
      SheetArea {
        // no press state (style.md H7): a dismiss scrim. Lighting the whole
        // screen is not feedback, and the control center leaving is what answers.
        anchors.fill: parent
        enabled: root.progress > 0
        onClicked: if (!root.sheetWasDrag) root.dismiss()
      }
    }

    // ------------------------------------------------------------- sheet
    Item {
      id: sheet
      // Q2a. The size this sheet has always had, on both axes: as wide as
      // the screen and as tall as its content (control-center.md S21). Only the path
      // in changes with the edge -- a mirrored width would be a relayout of
      // every tile on it.
      width: parent.width
      height: root.sheetHeight

      // Q2. Slides in from whichever edge raised it; from the top that is
      // the -sheetHeight * (1 - progress) it always was.
      readonly property var at: Edge.offset(root.entryEdge, root.progress,
                                            parent.width, parent.height,
                                            sheet.width, sheet.height)
      x: sheet.at.x
      y: sheet.at.y
      visible: root.progress > 0

      // The height animates and the content's does not -- the Column's
      // implicitHeight jumps to its new value the instant the model changes --
      // so for the 180ms of a growth the content is taller than the box it sits
      // in, and the newly arrived card would be painted on the scrim below the
      // rounded edge. Axis-aligned and unrotated, so the scene graph does this
      // with a scissor rect rather than a stencil pass or an off-screen render:
      // one GL call per frame, which is the only reason it is affordable on a
      // Mali-400. Rotating or layering this Item would turn it into a real
      // off-screen pass.
      clip: true

      // Rounded on the leading edge only: the sheet slides out from under
      // whichever edge raised it, so the two corners against that edge are
      // never on screen and rounding them would just cut two notches out of
      // whatever is behind during the drag.
      Rectangle {
        anchors.fill: parent
        color: root.surface
        radius: root.radiusSheet
      }
      Shared.TrailingSquare {
        edge: root.entryEdge
        depth: root.radiusSheet
        color: root.surface
      }

      // H2, for a drag that starts on empty sheet rather than on a tile.
      // Declared before the Column so it sits under it: later siblings take
      // input first, so this only sees what nothing else claimed.
      SheetArea {
        // no press state (style.md H7): a drag catcher under the content, not
        // a control.
        anchors.fill: parent
      }

      Column {
        id: sheetColumn
        // Top/left/right, not fill: the sheet's height is derived from this
        // Column's implicitHeight now, and a Column stretched to fill the thing
        // it is measuring is a binding loop -- height -> implicitHeight ->
        // sheetHeight -> height. Qt reports that once and then leaves the
        // property at whatever it last held, which renders as a sheet stuck at
        // one frame's guess.
        //
        // The bottom inset has nowhere to hang without a bottom anchor, so it
        // moves into sheetWanted. Drop it there and the sheet is 18px short and
        // every card sits on the rounded corner.
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.sheetPadSide
        anchors.rightMargin: root.sheetPadSide
        anchors.topMargin: root.sheetPadTop
        spacing: root.sheetGap

        // ------------------------------------------------------- header
        Item {
          width: parent.width
          height: Style.space(44)

          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
              // The sheet covers the status bar, so the time has to reappear
              // here or pulling the control center down loses the one thing a phone
              // user checks most.
              text: Qt.formatDateTime(controlCenterClock.date, "H:mm")
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.weight: root.textWeight
              color: root.textOnSurface
            }
            Text {
              text: Qt.formatDateTime(controlCenterClock.date, "dddd d MMMM")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: root.textWeight
              color: root.subdued
            }
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            RoundButton {
              glyph: ""
              onActivated: root.openSettings()
            }
            RoundButton {
              glyph: ""
              onActivated: root.openSettings("system.power")
            }
          }
        }

        // ------------------------------------------------------ widgets
        //
        // Everything between the header and the notification list is the
        // user's to arrange (docs/widgets.md). This surface names no widget
        // and lays out no tile: it hands the column what a widget draws with,
        // and the column draws what the arrangement says, in the order it
        // says.
        //
        // The header above and the list below are not widgets, and W27/W28
        // say why: the clock is this sheet's answer to covering the status
        // bar, and the list is the only scrolling region on the sheet and the
        // thing its height is derived from (S21, S22).
        Shared.WidgetColumn {
          // `widgetColumn` and not `widgets`: the IPC handler below declares a
          // function of that name, and inside its scope the function would win.
          id: widgetColumn
          width: parent.width
          spacing: root.sheetGap
          host: root
          hostId: "control-center"
        }

        // ------------------------------------------------ notifications
        Item {
          // 24, not 20: Clear-all needs 44 of height, and the Column leaves a
          // 10px gap on each side of this row -- so 24 + 10 + 10 is the floor
          // reached without either overhang running into a neighbour (E3). The
          // label is the size it always was; the row around it is 4px taller
          // (docs/style.md E1-E3).
          width: parent.width
          height: Style.space(24)
          // Off the model, not off `notificationList.count`. The sheet's height
          // is this Column's implicitHeight now, so nothing that decides that
          // height may be read back out of the list item -- model data and
          // static heights only, and the loop cannot be reintroduced by accident.
          visible: root.historyRows.length > 0

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: "Notifications"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: root.textWeight
            color: root.subdued
          }

          // A sibling of the label rather than a child, because the label is
          // this control's only chrome and a veil inside it would be under the
          // words rather than behind them (docs/style.md H8). Veiled toward
          // accent, which the label already is (H4). The 6px is a pill around
          // the word, not the 10px target the MouseArea grew to (E2).
          PressVeil {
            anchors.fill: clearAll
            anchors.margins: -Style.space(6)
            radius: height / 2
            ink: root.accent
            on: clearArea.pressed && !root.sheetDragging
          }

          Text {
            id: clearAll
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear all"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: root.textWeight
            color: root.accent
            SheetArea {
              id: clearArea
              anchors.fill: parent
              anchors.margins: -Style.space(10)
              onClicked: if (!root.sheetWasDrag) root.clearNotifications()
            }
          }
        }

        ListView {
          id: notificationList
          width: parent.width

          // A ListView with an empty model is not a zero-height item: the height
          // below is `contentHeight + bottomMargin`, which with no rows is the
          // margin alone -- and a *visible* zero-height child of a Column still
          // takes a gap above it. That is two stray bands at the foot of a sheet
          // whose whole point is to end where its content does. Read off the
          // model rather than `count`, for the reason the header above states.
          visible: root.historyRows.length > 0

          // The cap, and the reason the sheet's own height appears nowhere in it.
          // The sheet is as tall as this Column now, so a list measured against
          // the sheet would be measured against itself -- a binding loop.
          //
          // `y` is safe where `parent.height` is not: a Column sets each child's
          // y from the heights of the children *before* it, and this is the last
          // one, so y cannot depend on this list's height. Anything added below
          // this item breaks that, which is why nothing is.
          readonly property int listMax: Math.max(0, root.sheetMax
            - root.sheetPadTop - root.sheetPadBottom - notificationList.y)

          // Only as tall as its rows. Stretched to fill, an empty or short
          // list still covers the sheet below it and swallows a drag that
          // starts there -- a Flickable takes the press whether or not it has
          // anything to show at that point. Capped, the sheet's own drag (H2)
          // gets those touches; with more notifications than fit, this is the
          // full height again and scrolls as before.
          //
          // + bottomMargin, or the cap defeats itself. contentHeight is the rows
          // and their spacing alone -- Flickable's margins sit outside it and
          // extend the scrollable range -- so a list that fits becomes scrollable
          // by exactly the margin, interactive where it was not, swallowing the
          // close drag the cap exists to protect. The app drawer's grid carries the
          // same note for the same reason.
          height: Math.min(notificationList.listMax, contentHeight + bottomMargin)
          // H5: while it can scroll, the list owns vertical drags. Closing the
          // control center out from under someone reading their notifications is
          // exactly the conflict this gesture is not allowed to create.
          interactive: contentHeight > height
          // The house default in every other list in this shell, and missing
          // only here: without it a capped list rubber-bands past the sheet's
          // rounded bottom on every overscroll.
          boundsBehavior: Flickable.StopAtBounds
          // contentHeight is an estimate for rows the view has not built, which
          // puts a damped feedback path through C++ polish rather than through
          // bindings -- it never warns, and it can wobble by a delegate right at
          // the cap. A buffer of a whole sheet forces every row within reach of
          // the viewport to exist, so contentHeight is exact across the range
          // that decides the height. ~21 text delegates worst case.
          cacheBuffer: root.sheetMax
          clip: true
          spacing: Style.space(6)
          // Room for the sheet's rounded bottom, so a list that overflows ends
          // in a card fading past the corner rather than one sliced square
          // across the middle.
          bottomMargin: Style.space(10)
          // Rows only, never Notification objects: the service deliberately
          // keeps the live objects out of its ListModel because a stale role
          // read segfaults QQmlListModel::data.
          model: root.historyRows

          delegate: Item {
            id: card
            required property var modelData
            width: notificationList.width
            // S25. The icon is 36 and a one-line card's text is shorter than
            // that, so the card is whichever is taller. Without this a card
            // with a summary and no body drew its icon out of its own bounds.
            height: Math.max(cardBody.implicitHeight, root.cardIcon) + Style.space(20)

            readonly property real dismissAt: card.width * 0.35

            // S25/S27, resolved once per card rather than per binding read.
            // `action` re-evaluates when the window list changes, which is
            // what makes a card whose app has just opened go from launch to
            // focus without the control center being reopened.
            readonly property var icon: root.iconFor(card.modelData)
            readonly property string action: root.actionFor(card.modelData)

            Rectangle {
              id: sheetCard
              width: parent.width
              height: parent.height
              radius: root.radiusCard
              color: root.container
              // Fades as it travels, so a half-swipe reads as "not yet" rather
              // than as a card that has come loose.
              opacity: 1 - Math.min(0.75, Math.abs(sheetCard.x) / card.width)

              // H7. The only way to dismiss a single notification: there was a
              // close button here as well and it has been removed, because two
              // controls for one action on a card this size is one of them in
              // the way of the other. Android does the same.
              //
              // The cost, stated because it is real: a swipe is invisible where
              // a glyph is self-evident, so per-card dismissal is now something
              // you have to know about. Clear-all stays as the tap-reachable
              // path, which is what keeps this from being the only way to empty
              // the control center.
              //
              // Horizontal only, and preventStealing stays false, so the list
              // still takes any drag that turns out to be a scroll (H5). That
              // is the objection this file used to raise against a swipe here
              // -- the answer is to claim one axis rather than the gesture.
              //
              // S27 put a tap on the same area. The two do not need a timer to
              // tell them apart: a swipe has moved the card and a tap has not,
              // which `onClicked` reads off sheetCard.x at release. A card with
              // nothing to do keeps exactly the behaviour it had.
              PressVeil {
                anchors.fill: parent
                radius: root.radiusCard
                on: cardArea.pressed && card.action !== "none"
                    // drag guard (style.md H6): this card's drag is sideways,
                    // so the sheet's own flag never rises for it and the
                    // displacement is what says a swipe has begun.
                    && Math.abs(sheetCard.x) < 2
              }

              MouseArea {
                id: cardArea
                anchors.fill: parent
                drag.target: sheetCard
                drag.axis: Drag.XAxis
                drag.minimumX: -card.width
                drag.maximumX: card.width
                onReleased: {
                  if (Math.abs(sheetCard.x) >= card.dismissAt) root.dismissRow(card.modelData)
                  else springBack.restart()
                }
                onCanceled: springBack.restart()
                // The threshold is the same 2px the veil uses: anything the
                // finger actually moved is a swipe, and springBack has not run
                // yet at this point, so x is still where the finger left it.
                onClicked: if (Math.abs(sheetCard.x) < 2) root.runRow(card.modelData)
              }

              NumberAnimation {
                id: springBack
                target: sheetCard; property: "x"; to: 0
                duration: 140; easing.type: Easing.OutCubic
              }

            // S25. The sender, leading the card the way Android leads one.
            // Every card has one, so the text column starts at the same x on
            // all of them -- a column where some rows start at the edge and
            // some 48px in reads as misaligned, not as information.
            Item {
              id: cardIconSlot
              anchors.left: parent.left
              anchors.leftMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              width: root.cardIcon
              height: root.cardIcon

              Image {
                id: cardImage
                anchors.fill: parent
                source: card.icon.source
                fillMode: Image.PreserveAspectFit
                // Asked for at the size it is drawn: a 512px web app PNG
                // decoded at full size for a 36px slot is 1 MB of texture on
                // a Mali-400, per card.
                sourceSize: Qt.size(root.cardIcon, root.cardIcon)
                visible: status === Image.Ready
                asynchronous: true
              }

              // The glyph is the fallback for both "nothing named an icon"
              // and "something did and it will not load" -- a themed name no
              // theme answers is the second case, and it is the common one.
              Ui.OpticalGlyph {
                anchors.fill: parent
                visible: card.icon.source === "" || cardImage.status === Image.Error
                text: card.icon.glyph
                fontFamily: Style.font.family
                fontSize: Style.font.iconLarge
                color: root.subdued
              }
            }

            Column {
              id: cardBody
              anchors.left: cardIconSlot.right
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              // Was 44, to clear a close button that is no longer there.
              anchors.rightMargin: Style.space(14)
              spacing: Style.space(3)

              Text {
                width: parent.width
                text: card.modelData.app || ""
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: root.subdued
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                visible: text !== ""
                text: card.modelData.summary || ""
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                // A step above the rest of the control center rather than a step above
                // Regular: with everything else at DemiBold, `font.bold` is
                // what still separates the summary from its own body text.
                font.weight: Font.Bold
                color: root.textOnSurface
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                visible: text !== ""
                text: card.modelData.body || ""
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.weight: root.textWeight
                color: Util.alpha(root.textOnSurface, 0.85)
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
              }
            }

            }
          }
        }
      }
    }

    // -------------------------------------------------------- drag handle
    //
    // Always the top band, never the whole surface. Shut, the band is the whole
    // surface and every touch on the bar is a pull. Open, it is above the sheet
    // header, so the same downward-then-up gesture still works there -- and
    // every control below it still gets its taps.
    MultiPointTouchArea {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: root.stripHeight
      maximumTouchPoints: 1

      // sceneX/sceneY are already scene-space, so this hands them straight
      // over where a MouseArea has to map first.
      onPressed: pts => {
        if (pts.length === 0) return
        root.dragTrace = []
        bandDrag.press(pts[0].sceneX, pts[0].sceneY)
      }
      onUpdated: pts => { if (pts.length > 0) bandDrag.move(pts[0].sceneX, pts[0].sceneY) }
      onReleased: pts => bandDrag.release()
      onCanceled: pts => bandDrag.cancel()
    }
  }

  // The gear is the way in to everything the app drawer used to carry across
  // its top row. Android puts Settings behind the gear in the pull-down for the
  // same reason: this is already the surface you open when you want to change
  // something.
  //
  // The power glyph beside it opens the same screen at its Power page rather
  // than summoning omarchy.menu at `system`, which is what it used to do. That
  // menu is a popup with no tap-outside dismiss in this port -- port-4x.sh
  // stubs out HyprlandFocusGrab, which has no Quickshell.I3 counterpart -- so
  // it was the one remaining way to get stuck behind a surface. One
  // implementation, two entry points.
  function openSettings(page) {
    root.dismiss()
    if (root.shell && typeof root.shell.summon === "function")
      root.shell.summon("moarchy.settings",
                        page ? JSON.stringify({ page: page }) : "{}")
  }

  SystemClock {
    id: controlCenterClock
    precision: SystemClock.Minutes
  }
}
