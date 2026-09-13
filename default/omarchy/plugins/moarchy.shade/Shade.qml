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
// nothing composited while the shade is shut but a 360x26 band.
//
// The gestures plugin's rule about never widening a surface applies to the idle
// state, not to this: widening steals *new* touches from the app underneath,
// and here the finger is already down and the shade is what should be catching
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
// gesture on. Rather than hope the gestures strip lands on top, the shade cuts
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
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui as Ui
import "../moarchy.common/Theme.js" as Theme
import "../moarchy.common/ShellApps.js" as ShellApps
import "../moarchy.common" as Shared

Item {
  id: root

  // Injected by the host. Not readonly, not required -- see the drawer.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
                               || (Quickshell.env("HOME") + "/.local/share/omarchy")
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.shade"
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
  // read across plugins because the shade has to know it even when the gestures
  // plugin failed to load, and a shade that swallowed the bottom edge in that
  // case would be much worse than one that leaves 20px unused.
  readonly property int gestureStrip: Style.space(20)

  // Likewise moarchy.gestures' backEdgeWidth. The shade is on Overlay
  // and maps when it opens, so it lands *above* the always-mapped back-edge
  // surface and would otherwise swallow every left-edge swipe -- which is
  // exactly what it did: back closed the drawer and the carousel and left the
  // shade untouched, because those two are on Top and this one is not.
  readonly property int backEdge: Style.space(16)

  readonly property int screenHeight: shadeWindow.screen ? shadeWindow.screen.height : 720

  // Deliberately short of the full screen -- and a cap now, not the height.
  // The band of scrim left underneath is the tap-to-dismiss target, and it is
  // the only workable one: the drag handle is the status bar, so an upward drag
  // to close would start within 26px of the top of the screen and have nowhere
  // to travel. The home swipe closes the shade too, but a phone should not have
  // exactly one way out of a full-screen panel. A sheet shorter than the cap
  // hands back more of that band, never less (docs/shade.md S22).
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
  property int sheetHeight: root.dragging ? root.sheetFrozen : root.sheetTarget

  // Both drag entry points go through this. The latch is written *before*
  // `dragging` flips, so there is no frame in which the binding above can read a
  // stale sheetFrozen.
  function beginDrag(): void {
    root.sheetFrozen = root.sheetHeight
    root.dragging = true
  }

  // -------------------------------------------------------------- type
  //
  // The same weight the bar runs at. Light text on a dark surface reads thinner
  // than it measures, and a shade whose clock was Regular under a bar whose
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
  readonly property int radiusSheet: Style.space(28)
  readonly property int radiusTile: Style.space(20)
  readonly property int radiusCard: Style.space(18)

  // ------------------------------------------------------------ colours
  //
  // Mapped onto the theme's popup role rather than invented, so every Omarchy
  // theme restyles the shade for free. `container` is the tonal fill that most
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


  // ---------------------------------------------------------- drag state
  property real progress: 0        // 0 shut .. 1 open
  property bool dragging: false
  property bool expanded: false    // the surface is full-screen right now
  property real startProgress: 0
  property real startY: 0
  property real velocity: 0
  property real lastY: 0
  property real lastT: 0

  // shell.isPluginOpen() reads this. Mid-drag is neither open nor shut, and
  // reporting "open" there would let a swipe on the home pill try to close a
  // shade the user is still pulling out.
  readonly property bool opened: root.progress >= 1 && !root.dragging

  // Travel that commits a pull-down, as a fraction of the sheet. Deliberately
  // less than half: a shade is cheap to close and annoying to have to drag all
  // the way.
  readonly property real openFraction: 0.35
  readonly property real closeFraction: 0.75
  // Speed that commits regardless of travel, logical px per ms.
  readonly property real flingVelocity: 0.6
  readonly property int slop: Style.space(6)

  // ------------------------------------------------- H2: dragging the body
  //
  // The 26px grab band at the top is the affordance, not the whole gesture.
  // Dragging up anywhere on the sheet has to close it, and that cannot live on
  // an area behind the content: every tile here is a MouseArea and holds the
  // exclusive grab for the gesture, exactly as the drawer's app icons do. So
  // the tiles do both jobs -- a touch that never travels activates, one that
  // goes up past the slop drags the sheet.
  readonly property int dragSlop: Style.space(10)

  // Android's long-press interval. Milliseconds, not pixels -- not a Style.space.
  readonly property int holdInterval: 500

  // Scene coordinates, because every one of those MouseAreas is a child of the
  // sheet and the sheet is what moves. A delta measured in a frame that moves
  // with the thing it is driving feeds back into itself.
  property real sheetPressY: 0
  property real sheetStartProgress: 0
  property bool sheetDragging: false

  // Cleared on the next press rather than on release: Qt delivers `released`
  // then `clicked`, so a flag cleared on release is already false by the time
  // the click lands, and the tile fires the action the drag started on.
  property bool sheetWasDrag: false

  // A short, fast flick means the same as a long slow drag. Without this a
  // gesture that starts near the top of the sheet cannot commit at all: from
  // 150px down there is not 25% of the sheet left above it to travel.
  property real sheetVelocity: 0
  property real sheetLastY: 0
  property real sheetLastT: 0

  function sheetPress(item, mouse): void {
    root.dragTrace = []
    root.sheetPressY = item.mapToItem(null, mouse.x, mouse.y).y
    root.sheetStartProgress = root.progress
    root.sheetDragging = false
    root.sheetWasDrag = false
    root.sheetVelocity = 0
    root.sheetLastY = root.sheetPressY
    root.sheetLastT = Date.now()
  }

  function sheetMove(item, mouse): void {
    var dy = item.mapToItem(null, mouse.x, mouse.y).y - root.sheetPressY
    if (!root.sheetDragging) {
      // Upward only. A downward drag on an open shade means nothing, and
      // claiming it would fight the notification list (H5).
      if (dy >= -root.dragSlop) return
      root.sheetDragging = true
      root.beginDrag()
    }
    var nowY = item.mapToItem(null, mouse.x, mouse.y).y
    var now = Date.now()
    var dt = Math.max(1, now - root.sheetLastT)
    // Negative is upward, which for this sheet is the closing direction.
    root.sheetVelocity = root.sheetVelocity * 0.6 + ((nowY - root.sheetLastY) / dt) * 0.4
    root.sheetLastY = nowY
    root.sheetLastT = now
    root.progress = Math.max(0, Math.min(1,
      root.sheetStartProgress + dy / root.sheetHeight))
  }

  function sheetRelease(): void {
    if (!root.sheetDragging) return
    root.sheetWasDrag = true
    root.sheetDragging = false
    root.dragging = false
    if (root.sheetVelocity <= -root.flingVelocity) root.dismiss()
    else if (root.sheetVelocity >= root.flingVelocity) root.progress = 1
    else if (root.progress >= root.closeFraction) root.progress = 1
    else root.dismiss()
  }

  function sheetCancel(): void {
    if (!root.sheetDragging) return
    root.sheetDragging = false
    root.dragging = false
    root.progress = root.sheetStartProgress >= 0.5 ? 1 : 0
  }

  function open(payloadJson) {
    if (root.shell && typeof root.shell.isPluginOpen === "function"
        && root.shell.isPluginOpen("moarchy.drawer"))
      root.shell.hide("moarchy.drawer")
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
    root.dragging = false
    root.progress = 0
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  // Everything that cannot be bound reactively, pulled once per open rather
  // than on a timer: none of it changes while the shade is shut, and a phone
  // that forks rfkill every ten seconds for a panel nobody is looking at is
  // just a slower phone.
  function refresh(): void {
    if (!airplaneProbe.running) airplaneProbe.running = true
    if (!brightnessProbe.running) brightnessProbe.running = true
    if (!torchProbe.running) torchProbe.running = true
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
    // the list as it was a moment before the shade opened. The immediate read
    // gets the height approximately right; the deferred one gets the contents
    // exactly right.
    if (!historyRead.running) historyRead.running = true
    historyRefresh.restart()
  }

  onProgressChanged: {
    // Give the surface back as soon as it is not needed. Until this runs the
    // shade owns the whole screen's input, so leaving it expanded after a
    // snap-back would silently eat the next tap on the app underneath.
    if (root.progress <= 0 && !root.dragging) root.expanded = false
    if (root.progress > 0 && !root.expanded) root.expanded = true

    // One integer per frame while a drag is in flight, cleared on the next
    // press. The same diagnostic the drawer carries, and for the same reason:
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
    // shade that jumped shut.
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
  // 180 rather than the 220 the shade opens with: a list filling in is not a
  // second open, and at 220 it reads as one.
  Behavior on sheetHeight {
    enabled: root.opened
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  // A touch sequence normally ends in released or canceled, but a compositor
  // restart or a lost seat can strand one. Left stranded mid-drag the surface
  // stays full-screen and the phone stops responding to touch entirely, which
  // is a great deal worse than the stranded pill the gestures plugin guards
  // against -- so this watchdog is not optional.
  Timer {
    id: watchdog
    interval: 4000
    onTriggered: { root.dragging = false; root.progress = 0 }
  }

  IpcHandler {
    target: "shade"

    function state(): string {
      if (root.dragging) return "dragging " + Math.round(root.progress * 100) + "%"
      return root.opened ? "open" : "closed"
    }

    // The samples the last drag actually produced, as the drawer reports them.
    function dragTrace(): string { return root.dragTrace.join(" ") }

    // S21/S22. The sheet is as tall as its content and no taller, and the list
    // inside it scrolls once that would overrun the cap. Neither half is
    // assertable from outside: `state` says `open` either way, and a capture of
    // a short sheet and a tall one differ only in where a colour stops, which is
    // a pixel comparison against a theme -- the kind of check I1 had to be
    // rewritten to stop being.
    //
    // key=value, the form the carousel's preview line already uses. Each field
    // earns its place:
    //   height/wanted/max  the whole cap story. height == wanted below the cap,
    //                      both == max at it. A sheet that stretched would show
    //                      height > wanted; one truncating its own chrome would
    //                      show wanted > max.
    //   listy/listmax      where the list starts and what it may have. A listmax
    //                      at or near 0 is a shade whose chrome no longer fits
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
              "scrolls=" + (notificationList.interactive ? 1 : 0)].join(" ")
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

    // S4, S6a. What the Wi-Fi tile is reading, so a check can tell which branch
    // a tap is about to take without inferring it from the phone's own network
    // -- and can say so when the answer is the surprising one.
    function wifi(): string {
      var device = root.wifiDevice
      return [Networking.wifiEnabled ? "on" : "off",
              device && device.connected ? "connected" : "disconnected",
              root.wifiKnownInRange ? "known-in-range" : "none-known",
              root.wifiStranded ? "stranded" : "ok"].join(" ")
    }

    // The tile's own decision, reached through the tile's own code. Under
    // `dryRun 1` it records and does not act, so S6a is assertable on a phone
    // that is reached over the radio it would otherwise switch off.
    function wifiTap(): string { root.wifiTap(); return root.lastAction }
    function wifiHold(): string { root.wifiHold(); return root.lastAction }
    function btTap(): string { root.btTap(); return root.lastAction }
    function btHold(): string { root.btHold(); return root.lastAction }

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
  readonly property var media: root.shell && typeof root.shell.serviceFor === "function"
    ? root.shell.serviceFor("omarchy.media") : null

  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property var sink: Pipewire.defaultAudioSink
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }

  readonly property var wifiDevice: {
    var devices = Networking.devices ? Networking.devices.values : []
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].type === DeviceType.Wifi) return devices[i]
    return null
  }

  // The tiles say what they are connected to, not just on or off -- which is
  // the difference between a switch and a status panel.
  readonly property string wifiLabel: {
    if (!Networking.wifiEnabled) return "Off"
    var device = root.wifiDevice
    if (!device || !device.connected) return "Not connected"
    var networks = device.networks ? device.networks.values : []
    for (var i = 0; i < networks.length; i++)
      if (networks[i] && networks[i].connected) return String(networks[i].name || "Connected")
    return "Connected"
  }

  // S6a. "Nothing a tap could usefully do." Known means NetworkManager holds a
  // saved connection for it, so a known network in range is one the phone is
  // about to join by itself -- and toggling the radio off mid-reconnect is the
  // last thing the tap should mean. With none in range there is nothing to
  // wait for, and the picker is the only way out.
  readonly property bool wifiKnownInRange: {
    var device = root.wifiDevice
    var networks = device && device.networks ? device.networks.values : []
    for (var i = 0; i < networks.length; i++)
      if (networks[i] && networks[i].known) return true
    return false
  }

  readonly property bool wifiStranded:
    Networking.wifiEnabled && !root.airplane
    && !(root.wifiDevice && root.wifiDevice.connected)
    && !root.wifiKnownInRange

  readonly property string btLabel: {
    if (!root.btAdapter) return "No adapter"
    if (!root.btAdapter.enabled) return "Off"
    var devices = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].connected) return String(devices[i].name || "Connected")
    return "On"
  }

  property bool airplane: false
  property int brightness: 50
  property bool torchAvailable: false
  property bool torchOn: false

  // Airplane mode is one lever over wifi, bluetooth and the modem, which is
  // what a phone means by it -- `nmcli radio` would leave bluetooth up. The
  // user is in group rfkill, so none of this needs root.
  Process {
    id: airplaneProbe
    command: ["bash", "-c", "cat /sys/class/rfkill/*/soft 2>/dev/null | sort -u | tr -d '\\n'"]
    stdout: StdioCollector {
      // "1" means every switch reads blocked. "0" or "01" means at least one
      // radio is live, so this is not airplane mode.
      onStreamFinished: root.airplane = String(text || "").trim() === "1"
    }
  }

  Process {
    id: brightnessProbe
    command: ["bash", "-c", "brightnessctl -d backlight -m | cut -d, -f4 | tr -d '%\\n'"]
    stdout: StdioCollector {
      onStreamFinished: {
        var v = parseInt(String(text || "").trim(), 10)
        if (isFinite(v)) root.brightness = Math.max(1, Math.min(100, v))
      }
    }
  }

  // The flash LED is root:feedbackd 0664 and feedbackd is an empty group on a
  // bare install, so the tile is dead until install/session.sh has added the
  // user and they have logged in again. Probe rather than assume: a tile that
  // is drawn but does nothing is worse than one that is not drawn.
  Process {
    id: torchProbe
    command: ["bash", "-c", "[ -w /sys/class/leds/white:flash/brightness ] && cat /sys/class/leds/white:flash/brightness || echo unavailable"]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = String(text || "").trim()
        root.torchAvailable = out !== "unavailable" && out !== ""
        root.torchOn = root.torchAvailable && out !== "0"
      }
    }
  }

  // --------------------------------------------------------- actions

  function setAirplane(on) {
    root.airplane = on
    Quickshell.execDetached(["rfkill", on ? "block" : "unblock", "all"])
    airplaneRecheck.restart()
  }
  // S9. Turning a radio on from inside airplane mode clears airplane mode,
  // rather than leaving the tile lit and the radio dark contradicting each
  // other on screen.
  //
  // Unblocking just that one radio is enough, and is better than `unblock
  // all`: airplaneProbe calls it airplane mode only when *every* rfkill switch
  // reads blocked, so freeing one clears the state on the next read -- without
  // switching the other radios back on behind the user, which is not what
  // tapping Wi-Fi asked for.
  property string pendingRadio: ""

  function enableRadio(kind) {
    Quickshell.execDetached(["rfkill", "unblock", kind])
    root.pendingRadio = kind
    airplaneRecheck.restart()
  }

  // The radio is switched on after the unblock has landed, not alongside it:
  // NetworkManager will refuse to enable an interface that rfkill still has
  // blocked, and the write would be silently dropped.
  Timer {
    id: airplaneRecheck
    interval: 700
    onTriggered: {
      airplaneProbe.running = true
      if (root.pendingRadio === "wifi") Networking.wifiEnabled = true
      else if (root.pendingRadio === "bluetooth" && root.btAdapter)
        root.btAdapter.enabled = true
      root.pendingRadio = ""
    }
  }
  Timer { id: historyRefresh; interval: 250; onTriggered: historyRead.running = true }

  // S6, S6a, S6b, S6c. Each wide tile toggles a radio and holds to open the
  // thing that radio is for. Both open the same screen the matching Settings
  // row opens (`net.wifi`, `net.bluetooth`), so there is one picker behind two
  // entry points rather than two that drift.
  //
  // Neither is a terminal any more, and the two lost the argument differently.
  // nmtui-connect fits the 60x41 grid -- its list and buttons are all on
  // screen -- and none of them can be pressed, because nmtui never asks for
  // mouse reporting and foot's tap-to-click has nothing to deliver the tap to.
  // bluetui does ask, and was genuinely operable; it was still a list whose
  // rows are one terminal line, ~17 logical px against the 44 style.md E1
  // asks for, in a window carrying its own workspace, its own carousel card
  // and foot's palette instead of the shell's. moarchy.wifi and
  // moarchy.bluetooth are the same two lists with tap targets
  // (docs/shade.md S6b, S6c, S6d).

  // Set by `shade dryRun 1`, the way Settings does it. What the tile decided is
  // recorded either way; only the effect that cannot be taken back -- the radio
  // write -- is held back. Without this a check of S6a would have to switch the
  // radio off on a phone reached over that radio.
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

  function wifiTap() {
    if (root.airplane) {
      root.lastAction = "unblock"
      if (!root.dryRun) root.enableRadio("wifi")
      return
    }
    if (root.wifiStranded) {
      root.openWifi()
      return
    }
    root.lastAction = "toggle"
    if (!root.dryRun) Networking.wifiEnabled = !Networking.wifiEnabled
  }

  function wifiHold() { root.openWifi() }

  // One entry point for both tiles: they summon a plugin rather than spawning
  // a process, so lastLaunch carries the plugin id -- not a command -- and
  // lastAction records the same "picker" the tile checks assert.
  function openScreen(id) {
    // The shade goes away first -- the same order the gear uses (S2). It is a
    // sheet over whatever workspace this is, and the screen it summons is a
    // window on another one (docs/gestures.md K1), so leaving it up would put
    // the sheet over the workspace the summon just left.
    root.dismiss()
    root.lastAction = "picker"
    root.lastLaunch = id
    if (root.shell && typeof root.shell.summon === "function")
      root.shell.summon(id, JSON.stringify({ returnTo: "moarchy.shade" }))
  }

  function openWifi() { root.openScreen("moarchy.wifi") }
  function openBluetooth() { root.openScreen("moarchy.bluetooth") }

  // S6c. The pair behaves the same way. No stranded case here: a Bluetooth
  // adapter with nothing paired in range is the normal resting state of one,
  // not a dead end worth re-routing the tap for.
  function btTap() {
    if (root.airplane) {
      root.lastAction = "unblock"
      if (!root.dryRun) root.enableRadio("bluetooth")
      return
    }
    root.lastAction = "toggle"
    if (!root.dryRun && root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
  }

  function btHold() { root.openBluetooth() }

  function setBrightness(percent) {
    var v = Math.max(1, Math.min(100, Math.round(percent)))
    root.brightness = v
    Quickshell.execDetached(["brightnessctl", "-d", "backlight", "set", v + "%"])
  }

  function setTorch(on) {
    if (!root.torchAvailable) return
    root.torchOn = on
    Quickshell.execDetached(["bash", "-c",
      "echo " + (on ? "1" : "0") + " > /sys/class/leds/white:flash/brightness"])
  }

  function rotate() {
    // S11. Portrait and one landscape, toggled -- not a cycle through all four
    // transforms. This is a portrait phone: 180 is upside-down and 270 is the
    // other landscape, so cycling made the landscape you wanted three taps
    // away and put upside-down on the route there.
    //
    // Sway has no "rotate by 90" verb, so read the current transform and pick
    // the other one. Detached and fire-and-forget: the output reconfigure is
    // what tells us it worked, and there is nothing useful to do if it did not.
    Quickshell.execDetached(["bash", "-c",
      "t=$(swaymsg -t get_outputs | python3 -c 'import json,sys;print(json.load(sys.stdin)[0].get(\"transform\",\"normal\"))'); " +
      "case $t in normal) n=90;; *) n=normal;; esac; " +
      "swaymsg output DSI-1 transform $n"])
  }

  // ---------------------------------------------------- notification history
  //
  // Read here rather than through the service's showRecentHistory(): that
  // replays history back into popupModel, and the service's own toast surface
  // is visible whenever popupModel is non-empty -- so asking for history would
  // spray toasts over the top of the shade that is displaying it.
  property var historyRows: []

  Process {
    id: historyRead
    command: ["bash", "-c", "cat " + root.historyDir + "/*.json 2>/dev/null | tail -40"]
    stdout: StdioCollector {
      onStreamFinished: {
        var rows = []
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (!line) continue
          try { rows.push(JSON.parse(line)) } catch (e) { /* half-written file */ }
        }
        rows.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
        root.historyRows = rows
      }
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
  // sortedEntries, which is the list the drawer's grid is built from -- rows,
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
  // and the shade with it, so what the tap opened is what is on screen. The
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
      // the drawer draws (windows.md L1).
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
    // simply absent the next time the shade opened.
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

  // A quick-settings tile with room for a state line. Two of these fit across
  // the screen, which is the layout Android settled on: the two radios you
  // actually want to read, then a row of plain toggles under them.
  component WideTile: Rectangle {
    id: tile
    property string glyph: ""
    property string label: ""
    property string detail: ""
    property bool on: false
    signal activated()

    // S6. Opt-in, and off by default: a tile with no long press must keep the
    // tap it always had. Were the hold armed everywhere, holding the Bluetooth
    // tile would swallow its own click and the tile would do nothing at all --
    // which is worse than not having the gesture.
    property bool holdable: false
    signal held()

    // Fired while the finger is still down, as Android does, so the surface
    // answers the gesture rather than the lift. Cleared on the next press
    // rather than on release, for the reason sheetWasDrag is (Qt delivers
    // released before clicked, so a flag cleared on release is already false
    // when the click lands and the tile fires both actions).
    property bool heldFired: false

    height: Style.space(62)
    radius: root.radiusTile
    color: tile.on ? root.accent : root.container
    Behavior on color { ColorAnimation { duration: 140 } }

    // Its own 120 rather than the 140 above (docs/style.md H5, G1): a tile
    // lighting up and a tile acknowledging a thumb are two different state
    // changes, and one property cannot carry two durations. Veiled toward
    // whichever ink the tile is carrying, so a lit one still reads as lit (H4).
    //
    // Guarded on the drag (H6): these tiles *are* the sheet's drag handle, so
    // `pressed` stays true for the whole gesture and an unguarded veil would
    // light every tile a scrolling thumb crossed.
    PressVeil {
      anchors.fill: parent
      radius: parent.radius
      ink: tile.on ? root.textOnAccent : root.textOnSurface
      on: tileArea.pressed && !root.sheetDragging
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Ui.OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        width: root.glyphSlot
        height: root.glyphSlot
        text: tile.glyph
        fontFamily: Style.font.family
        fontSize: Style.font.iconLarge
        color: tile.on ? root.textOnAccent : root.textOnSurface
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        // Exact rather than estimated, now the glyph has a width of its own
        // instead of whatever the font gave it.
        width: parent.width - root.glyphSlot - Style.space(10)
        spacing: 0

        Text {
          width: parent.width
          text: tile.label
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.weight: root.textWeight
          color: tile.on ? root.textOnAccent : root.textOnSurface
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          visible: tile.detail !== ""
          text: tile.detail
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: root.textWeight
          color: tile.on ? Util.alpha(root.textOnAccent, 0.75) : root.subdued
          elide: Text.ElideRight
        }
      }
    }

    Timer {
      id: hold
      interval: root.holdInterval
      onTriggered: { tile.heldFired = true; tile.held() }
    }

    MouseArea {
      id: tileArea
      anchors.fill: parent
      onPressed: mouse => {
        root.sheetPress(this, mouse)
        tile.heldFired = false
        if (tile.holdable) hold.restart()
      }
      onPositionChanged: mouse => {
        root.sheetMove(this, mouse)
        // Cancelled by the sheet drag latching, not by any movement at all: a
        // thumb held still for half a second still travels a few pixels, and a
        // hold that a steady hand cannot complete is not a gesture.
        if (root.sheetDragging) hold.stop()
      }
      onReleased: { hold.stop(); root.sheetRelease() }
      onCanceled: { hold.stop(); root.sheetCancel() }
      onClicked: if (!root.sheetWasDrag && !tile.heldFired) tile.activated()
    }
  }

  // The compact form, for toggles whose whole state is "on" or "off".
  component SmallTile: Rectangle {
    id: small
    property string glyph: ""
    property string label: ""
    property bool on: false
    signal activated()

    height: Style.space(62)
    radius: root.radiusTile
    color: small.on ? root.accent : root.container
    Behavior on color { ColorAnimation { duration: 140 } }

    // As WideTile. Rotate is the one instance pinned `on: false` -- a momentary
    // action wearing a toggle's chrome -- so until now a tap on it drew nothing
    // at all, and this is the only response it has.
    PressVeil {
      anchors.fill: parent
      radius: parent.radius
      ink: small.on ? root.textOnAccent : root.textOnSurface
      on: smallArea.pressed && !root.sheetDragging
    }

    Column {
      anchors.centerIn: parent
      spacing: Style.space(3)

      Ui.OpticalGlyph {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.glyphSlot
        height: root.glyphSlot
        text: small.glyph
        fontFamily: Style.font.family
        fontSize: Style.font.iconLarge
        color: small.on ? root.textOnAccent : root.textOnSurface
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: small.label
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.weight: root.textWeight
        color: small.on ? Util.alpha(root.textOnAccent, 0.75) : root.subdued
      }
    }

    MouseArea {
      id: smallArea
      anchors.fill: parent
      onPressed: mouse => root.sheetPress(this, mouse)
      onPositionChanged: mouse => root.sheetMove(this, mouse)
      onReleased: root.sheetRelease()
      onCanceled: root.sheetCancel()
      onClicked: if (!root.sheetWasDrag) small.activated()
    }
  }

  // A track you can put a thumb on rather than a hairline with a knob. The
  // glyph rides inside it, so the control is its own label and the row costs
  // one height instead of two.
  component FatSlider: Item {
    id: slider
    property real value: 0        // 0..1
    property string glyph: ""
    // Whether to report every step of the drag or only the end of it. Volume is
    // in-process and free to follow the finger; brightness forks brightnessctl
    // per write, so it waits for the release.
    property bool live: false
    signal committed(real value)

    height: Style.space(48)
    readonly property real clamped: Math.max(0, Math.min(1, slider.value))
    property real dragValue: slider.clamped
    property bool dragging: false
    readonly property real shown: slider.dragging ? slider.dragValue : slider.clamped

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: root.container

      Rectangle {
        height: parent.height
        // Never narrower than the corner diameter: below that a rounded fill
        // collapses into a lens and reads as a rendering fault rather than a
        // low value.
        width: Math.max(parent.height, parent.width * slider.shown)
        radius: parent.radius
        color: root.accent
        Behavior on width {
          enabled: !slider.dragging
          NumberAnimation { duration: 120 }
        }
      }

      // Over the track and the fill together, so it says "engaged" without
      // saying anything about the value. This looks like the one control that
      // does not need a press state -- the fill follows the thumb -- but that
      // fails at exactly one point: tap a slider at its current value and
      // nothing whatever happens. Guarded on the handover rather than on
      // sheetDragging, because this one hands the gesture over itself (H6).
      PressVeil {
        anchors.fill: parent
        radius: parent.radius
        on: sliderArea.pressed && !sliderArea.handedOver
      }

      // Positioned by where the glyph's centre should land, not by where its
      // box starts: the brightness sun is 3px wider than the speaker, so two
      // sliders given the same left margin had their glyphs on different
      // vertical lines.
      Ui.OpticalGlyph {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(20) - Math.round(root.glyphSlot / 2)
        anchors.verticalCenter: parent.verticalCenter
        width: root.glyphSlot
        height: root.glyphSlot
        text: slider.glyph
        fontFamily: Style.font.family
        fontSize: Style.font.icon
        color: root.textOnAccent
      }
    }

    // The one control on the sheet that cannot simply add the sheet drag
    // alongside its own, because it commits on *press*: this is a tap-to-set
    // slider, so the value has already moved by the time it is known whether
    // the finger is going sideways or up. So it hands over instead -- and puts
    // the value back, which for a live slider means undoing a commit it has
    // already sent.
    MouseArea {
      id: sliderArea
      anchors.fill: parent
      property real preValue: 0
      property real pressX: 0
      property bool handedOver: false
      function valueAt(x) { return Math.max(0, Math.min(1, x / Math.max(1, width))) }

      onPressed: mouse => {
        preValue = slider.value
        pressX = mouse.x
        handedOver = false
        root.sheetPress(this, mouse)
        slider.dragging = true
        slider.dragValue = valueAt(mouse.x)
        if (slider.live) slider.committed(slider.dragValue)
      }

      onPositionChanged: mouse => {
        if (handedOver) { root.sheetMove(this, mouse); return }
        if (!slider.dragging) return
        // Vertical and clearly not a slider adjustment: give the gesture to
        // the sheet and restore what the press already changed.
        var dyScene = mapToItem(null, mouse.x, mouse.y).y - root.sheetPressY
        if (dyScene < -root.dragSlop && Math.abs(dyScene) > Math.abs(mouse.x - pressX)) {
          slider.dragging = false
          handedOver = true
          if (slider.live) slider.committed(preValue)
          slider.dragValue = preValue
          root.sheetMove(this, mouse)
          return
        }
        slider.dragValue = valueAt(mouse.x)
        if (slider.live) slider.committed(slider.dragValue)
      }

      onReleased: mouse => {
        if (handedOver) { root.sheetRelease(); handedOver = false; return }
        if (!slider.dragging) return
        slider.dragging = false
        slider.committed(valueAt(mouse.x))
      }

      onCanceled: {
        if (handedOver) { root.sheetCancel(); handedOver = false }
        slider.dragging = false
      }
    }
  }

  // A circular tonal button, for the two things in the header that are not
  // settings: the Omarchy menu and the power routes.
  component RoundButton: Rectangle {
    id: rb
    property string glyph: ""
    signal activated()
    width: Style.space(36)
    height: width
    radius: width / 2
    color: root.container

    // 36 drawn, 44 answering: the veil takes the 36 (docs/style.md H8, E2).
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

    // 36 drawn, 44 answering (docs/style.md E1-E3). The two buttons
    // sit 8px apart, so 4 each is the most either may take without the later
    // one eating the earlier one's edge (E3) -- and 4 is exactly what 36 needs.
    // Vertically it fills the 44px header the pair is centred in.
    MouseArea {
      id: rbArea
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      onPressed: mouse => root.sheetPress(this, mouse)
      onPositionChanged: mouse => root.sheetMove(this, mouse)
      onReleased: root.sheetRelease()
      onCanceled: root.sheetCancel()
      onClicked: if (!root.sheetWasDrag) rb.activated()
    }
  }

  // ============================================================== surface

  PanelWindow {
    id: shadeWindow

    // Top/left/right only. Anchoring the bottom too would make the surface
    // full-height permanently and implicitHeight would stop meaning anything.
    anchors { top: true; left: true; right: true }
    implicitHeight: root.expanded ? root.screenHeight : root.stripHeight
    color: "transparent"
    surfaceFormat.opaque: false

    WlrLayershell.namespace: "moarchy-shade"
    WlrLayershell.layer: WlrLayer.Overlay
    // No text input anywhere in here, and None makes it structurally impossible
    // for the shade to steal focus from the app underneath -- so a pull-down,
    // a tap on a tile and a flick back up leaves you exactly where you were.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Reserve nothing. With Auto, growing the surface would reflow every tiled
    // window at 60Hz for the length of the drag.
    exclusionMode: ExclusionMode.Ignore

    // Cut the two edges that belong to other surfaces out of this one's input
    // region: the home pill along the bottom, and the back edge down the left.
    // A masked-out band falls through to the next surface in the layer, which
    // is what lets both of those keep working with the shade down.
    Region {
      id: openRegion
      x: root.backEdge
      y: 0
      width: Math.max(1, shadeWindow.width - root.backEdge)
      height: Math.max(1, shadeWindow.height - root.gestureStrip)
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
      // band is ~70px with the shade full and several hundred with it near
      // empty. Never less -- that is what the cap is for (S22).
      //
      // Wired to the same trio as the sheet rather than to `clicked` alone: a
      // MouseArea that only answers `clicked` still consumes the whole gesture,
      // so an up-drag begun here moved nothing at all and then dismissed the
      // shade outright on release. The shade appeared to have no close
      // animation, and it had none -- it was being closed by a tap that
      // happened to have travelled 250px.
      //
      // Gated on `progress`, NOT on `opened`, and that is the same trap the
      // drawer's keyboardFocus documents. `opened` goes false on the first
      // frame of the drag; an area that disables mid-gesture delivers
      // `canceled`, which snapped the sheet back to fully open and then dropped
      // it on a canned 220ms ramp. Holding it live until the sheet is all the
      // way down keeps the gesture intact.
      MouseArea {
        // no press state (style.md H7): a dismiss scrim. Lighting the whole
        // screen is not feedback, and the shade leaving is what answers.
        anchors.fill: parent
        enabled: root.progress > 0
        onPressed: mouse => root.sheetPress(this, mouse)
        onPositionChanged: mouse => root.sheetMove(this, mouse)
        onReleased: root.sheetRelease()
        onCanceled: root.sheetCancel()
        onClicked: if (!root.sheetWasDrag) root.dismiss()
      }
    }

    // ------------------------------------------------------------- sheet
    Item {
      id: sheet
      width: parent.width
      height: root.sheetHeight
      y: -root.sheetHeight * (1 - root.progress)
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

      // Rounded at the bottom only: the sheet slides out from under the top
      // edge, so its top corners are never on screen and rounding them would
      // just cut two notches out of the status bar area during the drag.
      Rectangle {
        anchors.fill: parent
        color: root.surface
        radius: root.radiusSheet
      }
      Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: root.radiusSheet
        color: root.surface
      }

      // H2, for a drag that starts on empty sheet rather than on a tile.
      // Declared before the Column so it sits under it: later siblings take
      // input first, so this only sees what nothing else claimed.
      MouseArea {
        // no press state (style.md H7): a drag catcher under the content, not
        // a control.
        anchors.fill: parent
        onPressed: mouse => root.sheetPress(this, mouse)
        onPositionChanged: mouse => root.sheetMove(this, mouse)
        onReleased: root.sheetRelease()
        onCanceled: root.sheetCancel()
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
              // here or pulling the shade down loses the one thing a phone
              // user checks most.
              text: Qt.formatDateTime(shadeClock.date, "H:mm")
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.weight: root.textWeight
              color: root.textOnSurface
            }
            Text {
              text: Qt.formatDateTime(shadeClock.date, "dddd d MMMM")
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

        // ---------------------------------------------------- wide tiles
        Row {
          width: parent.width
          spacing: Style.space(8)
          readonly property int cell: Math.floor((width - spacing) / 2)

          WideTile {
            width: parent.cell
            glyph: "󰤨"
            label: "Wi-Fi"
            detail: root.wifiLabel
            on: Networking.wifiEnabled
            holdable: true
            onActivated: root.wifiTap()
            onHeld: root.wifiHold()
          }

          WideTile {
            width: parent.cell
            glyph: "󰂯"
            label: "Bluetooth"
            detail: root.btLabel
            on: root.btAdapter ? root.btAdapter.enabled : false
            holdable: true
            onActivated: root.btTap()
            onHeld: root.btHold()
          }
        }

        // --------------------------------------------------- small tiles
        Row {
          id: smallTiles
          width: parent.width
          spacing: Style.space(8)
          // The torch tile is the one that can be missing rather than off, so
          // the row divides by what is actually shown.
          readonly property int shown: root.torchAvailable ? 4 : 3
          readonly property int cell: Math.floor((width - spacing * (shown - 1)) / shown)

          SmallTile {
            width: smallTiles.cell
            glyph: "󰂛"
            label: "Silent"
            on: root.notifications ? root.notifications.doNotDisturb : false
            onActivated: if (root.notifications)
              root.notifications.setDoNotDisturb(!root.notifications.doNotDisturb)
          }
          SmallTile {
            width: smallTiles.cell
            glyph: "󰀝"
            label: "Airplane"
            on: root.airplane
            onActivated: root.setAirplane(!root.airplane)
          }
          SmallTile {
            width: smallTiles.cell
            visible: root.torchAvailable
            glyph: "󰉄"
            label: "Torch"
            on: root.torchOn
            onActivated: root.setTorch(!root.torchOn)
          }
          SmallTile {
            width: smallTiles.cell
            glyph: "󰑥"
            label: "Rotate"
            on: false
            onActivated: root.rotate()
          }
        }

        // ------------------------------------------------------ sliders
        FatSlider {
          width: parent.width
          glyph: "󰃟"
          value: root.brightness / 100
          onCommitted: v => root.setBrightness(v * 100)
        }

        FatSlider {
          width: parent.width
          visible: root.sink && root.sink.audio
          glyph: "󰕾"
          live: true
          value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
          onCommitted: v => { if (root.sink && root.sink.audio) root.sink.audio.volume = v }
        }

        // -------------------------------------------------------- media
        Rectangle {
          width: parent.width
          height: Style.space(56)
          visible: root.media && root.media.hasMedia
          radius: root.radiusCard
          color: root.container

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(10)

            Column {
              // Whatever the transport block and the one gap before it leave.
              width: parent.width - root.tapSlot * 3 - Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                width: parent.width
                text: root.media ? root.media.title : ""
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.weight: root.textWeight
                color: root.textOnSurface
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.media ? root.media.artist : ""
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: root.subdued
                elide: Text.ElideRight
              }
            }

            // Three tapSlot squares butted together with the glyph centred in
            // each, rather than three glyphs on a shared 10px spacing with the
            // hit areas grown outward (docs/style.md E4).
            //
            // Grown outward they could not get there. On 34px centres -- a 24px
            // glyph plus the Row's 10px gap -- the middle button can claim 5 on
            // each side before it starts eating its neighbours (E3), which tops
            // out at 34 and leaves play the smallest target on the sheet.
            // Carrying the gap *inside* the slot is what buys the floor, and it
            // costs the title 40px of width: the one place where 44 was not
            // free. Nested in its own Row so the outer 10px spacing applies
            // once, between the title and the block, and not between buttons.
            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Repeater {
                model: [
                  { glyph: "󰒮", action: "previous" },
                  { glyph: "󰒧", action: "playPause" },
                  { glyph: "󰒜", action: "next" }
                ]
                delegate: Item {
                  required property var modelData
                  width: root.tapSlot
                  height: root.tapSlot

                  // These have never had chrome, so the veil is the chrome
                  // (docs/style.md H8) -- and it is drawn at tapSlot minus the
                  // Row gap E4 moved *inside* the target, not at the full
                  // tapSlot, which would butt three circles edge to edge and
                  // undo what E4 bought.
                  PressVeil {
                    anchors.centerIn: parent
                    width: root.tapSlot - Style.space(10)
                    height: width
                    radius: width / 2
                    on: mediaArea.pressed && !root.sheetDragging
                  }

                  Ui.OpticalGlyph {
                    anchors.centerIn: parent
                    width: root.glyphSlot
                    height: root.glyphSlot
                    text: modelData.glyph
                    fontFamily: Style.font.family
                    fontSize: Style.font.iconLarge
                    color: root.textOnSurface
                  }

                  MouseArea {
                    id: mediaArea
                    anchors.fill: parent
                    onPressed: mouse => root.sheetPress(this, mouse)
                    onPositionChanged: mouse => root.sheetMove(this, mouse)
                    onReleased: root.sheetRelease()
                    onCanceled: root.sheetCancel()
                    onClicked: if (!root.sheetWasDrag
                                   && root.media && typeof root.media.runAction === "function")
                      root.media.runAction(modelData.action)
                  }
                }
              }
            }
          }
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
            MouseArea {
              id: clearArea
              anchors.fill: parent
              anchors.margins: -Style.space(10)
              onPressed: mouse => root.sheetPress(this, mouse)
              onPositionChanged: mouse => root.sheetMove(this, mouse)
              onReleased: root.sheetRelease()
              onCanceled: root.sheetCancel()
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
          // close drag the cap exists to protect. The drawer's grid carries the
          // same note for the same reason.
          height: Math.min(notificationList.listMax, contentHeight + bottomMargin)
          // H5: while it can scroll, the list owns vertical drags. Closing the
          // shade out from under someone reading their notifications is
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
            // focus without the shade being reopened.
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
              // the shade.
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
                // A step above the rest of the shade rather than a step above
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

      onPressed: pts => {
        if (pts.length === 0) return
        root.dragTrace = []
        root.startY = pts[0].sceneY
        root.lastY = pts[0].sceneY
        root.lastT = Date.now()
        root.startProgress = root.progress
        root.velocity = 0
        root.beginDrag()
        watchdog.restart()
      }

      onUpdated: pts => {
        if (pts.length === 0 || !root.dragging) return
        var y = pts[0].sceneY
        var dy = y - root.startY
        if (Math.abs(dy) < root.slop && root.startProgress === 0) return

        var now = Date.now()
        var dt = Math.max(1, now - root.lastT)
        // Smoothed, so one jittery frame at the end of a slow drag cannot read
        // as a fling and open something the user was putting back.
        root.velocity = root.velocity * 0.6 + ((y - root.lastY) / dt) * 0.4
        root.lastY = y
        root.lastT = now

        root.progress = Math.max(0, Math.min(1, root.startProgress + dy / root.sheetHeight))
        watchdog.restart()
      }

      onReleased: pts => {
        if (!root.dragging) return
        var wasOpen = root.startProgress >= 0.5
        var target
        if (root.velocity >= root.flingVelocity) target = 1
        else if (root.velocity <= -root.flingVelocity) target = 0
        else if (wasOpen) target = root.progress >= root.closeFraction ? 1 : 0
        else target = root.progress >= root.openFraction ? 1 : 0

        root.dragging = false
        watchdog.stop()
        // Through the host, so openPanelIds and this plugin cannot drift apart
        // and leave the next swipe toggling the wrong way.
        if (target === 1 && root.shell) root.shell.summon(root.pluginId, "{}")
        else if (target === 0) root.dismiss()
        else root.progress = target
      }

      onCanceled: pts => {
        root.dragging = false
        watchdog.stop()
        root.progress = root.startProgress >= 0.5 ? 1 : 0
      }
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
    id: shadeClock
    precision: SystemClock.Minutes
  }
}
