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
// the status bar arrives here. That is the reason mobileomarchy.bar is built
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

  readonly property string pluginId: "mobileomarchy.shade"
  readonly property string historyDir:
    Quickshell.env("HOME") + "/.local/state/omarchy/notifications/history"

  // ------------------------------------------------------------ geometry
  //
  // The grab strip is exactly the bar, so the whole status bar is the handle.
  // Read live off the bar rather than hardcoded: a bar that changes height and
  // a handle that does not would leave a dead sliver or an overhang.
  readonly property int stripHeight: root.shell && root.shell.bar && root.shell.bar.barSize > 0
    ? root.shell.bar.barSize : Style.space(26)

  // Must match mobileomarchy.gestures' own stripHeight. Duplicated rather than
  // read across plugins because the shade has to know it even when the gestures
  // plugin failed to load, and a shade that swallowed the bottom edge in that
  // case would be much worse than one that leaves 20px unused.
  readonly property int gestureStrip: Style.space(20)

  // Likewise mobileomarchy.gestures' backEdgeWidth. The shade is on Overlay
  // and maps when it opens, so it lands *above* the always-mapped back-edge
  // surface and would otherwise swallow every left-edge swipe -- which is
  // exactly what it did: back closed the drawer and the carousel and left the
  // shade untouched, because those two are on Top and this one is not.
  readonly property int backEdge: Style.space(16)

  readonly property int screenHeight: shadeWindow.screen ? shadeWindow.screen.height : 720

  // Deliberately short of the full screen. The band of scrim left underneath is
  // the tap-to-dismiss target, and it is the only workable one: the drag handle
  // is the status bar, so an upward drag to close would start within 26px of the
  // top of the screen and have nowhere to travel. The home swipe closes the
  // shade too, but a phone should not have exactly one way out of a full-screen
  // panel.
  readonly property real sheetFraction: 0.9
  readonly property int sheetHeight:
    Math.max(1, Math.round((root.screenHeight - root.gestureStrip) * root.sheetFraction))

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
  readonly property color subdued: Util.alpha(Color.popups.text, 0.62)

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
      root.dragging = true
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
        && root.shell.isPluginOpen("mobileomarchy.drawer"))
      root.shell.hide("mobileomarchy.drawer")
    root.expanded = true
    root.progress = 1

    // Absorb any live toasts. The service's own popup surface is Overlay too
    // and maps after this one, so anything still on screen floats over the
    // shade that is supposed to be showing it. clearPopups() is not a discard:
    // removePopup archives each row into the history directory, so they land in
    // the list below instead. That is what Android does when you pull down --
    // the heads-up notifications become the list.
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
    // Deferred: clearPopups() archives through the service's own serialised
    // file-job queue, so reading the directory in the same tick shows the list
    // as it was a moment before the shade opened.
    historyRefresh.restart()
  }

  onProgressChanged: {
    // Give the surface back as soon as it is not needed. Until this runs the
    // shade owns the whole screen's input, so leaving it expanded after a
    // snap-back would silently eat the next tap on the app underneath.
    if (root.progress <= 0 && !root.dragging) root.expanded = false
    if (root.progress > 0 && !root.expanded) root.expanded = true
  }

  Behavior on progress {
    enabled: !root.dragging
    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
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
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
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
  Timer { id: airplaneRecheck; interval: 700; onTriggered: airplaneProbe.running = true }
  Timer { id: historyRefresh; interval: 250; onTriggered: historyRead.running = true }

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
    // Sway has no "rotate by 90" verb, so read the current transform and pick
    // the next one. Detached and fire-and-forget: the output reconfigure is
    // what tells us it worked, and there is nothing useful to do if it did not.
    Quickshell.execDetached(["bash", "-c",
      "t=$(swaymsg -t get_outputs | python3 -c 'import json,sys;print(json.load(sys.stdin)[0].get(\"transform\",\"normal\"))'); " +
      "case $t in normal) n=90;; 90) n=180;; 180) n=270;; *) n=normal;; esac; " +
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
  function dismissRow(row) {
    if (!row) return
    var stem = String(row.timestamp || 0) + "-" + String(row.originalId || 0)
    Quickshell.execDetached(["bash", "-c",
      "rm -f " + root.historyDir + "/" + stem + ".json"])
    var next = []
    for (var i = 0; i < root.historyRows.length; i++)
      if (root.historyRows[i] !== row) next.push(root.historyRows[i])
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

    height: Style.space(62)
    radius: root.radiusTile
    color: tile.on ? root.accent : root.container
    Behavior on color { ColorAnimation { duration: 140 } }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: tile.glyph
        font.family: Style.font.family
        font.pixelSize: Style.font.iconLarge
        color: tile.on ? root.textOnAccent : root.textOnSurface
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(34)
        spacing: 0

        Text {
          width: parent.width
          text: tile.label
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          color: tile.on ? root.textOnAccent : root.textOnSurface
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          visible: tile.detail !== ""
          text: tile.detail
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: tile.on ? Util.alpha(root.textOnAccent, 0.75) : root.subdued
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      onPressed: mouse => root.sheetPress(this, mouse)
      onPositionChanged: mouse => root.sheetMove(this, mouse)
      onReleased: root.sheetRelease()
      onCanceled: root.sheetCancel()
      onClicked: if (!root.sheetWasDrag) tile.activated()
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

    Column {
      anchors.centerIn: parent
      spacing: Style.space(3)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: small.glyph
        font.family: Style.font.family
        font.pixelSize: Style.font.iconLarge
        color: small.on ? root.textOnAccent : root.textOnSurface
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: small.label
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: small.on ? Util.alpha(root.textOnAccent, 0.75) : root.subdued
      }
    }

    MouseArea {
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

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        text: slider.glyph
        font.family: Style.font.family
        font.pixelSize: Style.font.icon
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

    // Filled and aligned, not centred as a shrink-wrapped item.
    //
    // `anchors.centerIn` sizes the Text to the glyph and then centres that
    // item, which puts its origin at a fractional position -- (36 - 13.39) / 2
    // -- and the glyph lands a pixel or so off. Measured on the gear and the
    // power icon, the ink sat 1.5 device pixels left of the circle's centre in
    // both: small, and on a 72px circle with nothing else to line up against,
    // plainly visible.
    //
    // Filling the button and letting Text align inside it keeps the item on
    // integer coordinates and hands the centring to the font's own metrics.
    // (TextMetrics was tried first and reported the ink as already centred
    // *within the item* -- which is what pointed at the item's placement
    // rather than the glyph's bearings.)
    Text {
      anchors.fill: parent
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: rb.glyph
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
      color: root.textOnSurface
    }

    MouseArea {
      anchors.fill: parent
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

    WlrLayershell.namespace: "mobileomarchy-shade"
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

      // Only live once the shade is all the way open. During the drag the
      // finger already owns the surface, and a MouseArea competing for it would
      // fire a dismiss the moment the drag ended anywhere over the scrim.
      MouseArea {
        anchors.fill: parent
        enabled: root.opened
        onClicked: root.dismiss()
      }
    }

    // ------------------------------------------------------------- sheet
    Item {
      id: sheet
      width: parent.width
      height: root.sheetHeight
      y: -root.sheetHeight * (1 - root.progress)
      visible: root.progress > 0

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
        anchors.fill: parent
        onPressed: mouse => root.sheetPress(this, mouse)
        onPositionChanged: mouse => root.sheetMove(this, mouse)
        onReleased: root.sheetRelease()
        onCanceled: root.sheetCancel()
      }

      Column {
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        anchors.topMargin: Style.space(8)
        anchors.bottomMargin: Style.space(18)
        spacing: Style.space(10)

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
              color: root.textOnSurface
            }
            Text {
              text: Qt.formatDateTime(shadeClock.date, "dddd d MMMM")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
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
              onActivated: root.openMenu("system")
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
            onActivated: Networking.wifiEnabled = !Networking.wifiEnabled
          }

          WideTile {
            width: parent.cell
            glyph: "󰂯"
            label: "Bluetooth"
            detail: root.btLabel
            on: root.btAdapter ? root.btAdapter.enabled : false
            onActivated: if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
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
              width: parent.width - Style.space(108)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                width: parent.width
                text: root.media ? root.media.title : ""
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: root.textOnSurface
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.media ? root.media.artist : ""
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: root.subdued
                elide: Text.ElideRight
              }
            }

            Repeater {
              model: [
                { glyph: "󰒮", action: "previous" },
                { glyph: "󰒧", action: "playPause" },
                { glyph: "󰒜", action: "next" }
              ]
              delegate: Text {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.glyph
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
                color: root.textOnSurface
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
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

        // ------------------------------------------------ notifications
        Item {
          width: parent.width
          height: Style.space(20)
          visible: notificationList.count > 0

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: "Notifications"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: root.subdued
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear all"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: root.accent
            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(8)
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
          // Only as tall as its rows. Stretched to fill, an empty or short
          // list still covers the sheet below it and swallows a drag that
          // starts there -- a Flickable takes the press whether or not it has
          // anything to show at that point. Capped, the sheet's own drag (H2)
          // gets those touches; with more notifications than fit, this is the
          // full height again and scrolls as before.
          height: Math.min(Math.max(0, parent.height - y), contentHeight)
          // H5: while it can scroll, the list owns vertical drags. Closing the
          // shade out from under someone reading their notifications is
          // exactly the conflict this gesture is not allowed to create.
          interactive: contentHeight > height
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

          delegate: Rectangle {
            id: card
            required property var modelData
            width: notificationList.width
            height: cardBody.implicitHeight + Style.space(20)
            radius: root.radiusCard
            color: root.container

            Column {
              id: cardBody
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(14)
              anchors.rightMargin: Style.space(38)
              spacing: Style.space(3)

              Text {
                width: parent.width
                text: card.modelData.app || ""
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: root.subdued
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                visible: text !== ""
                text: card.modelData.summary || ""
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                color: root.textOnSurface
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                visible: text !== ""
                text: card.modelData.body || ""
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: Util.alpha(root.textOnSurface, 0.85)
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
              }
            }

            // Per-card dismissal. A swipe would be the phone idiom, but this
            // list already sits inside a surface whose top band is a drag
            // handle, and adding a second horizontal gesture to the same
            // stack is how you end up dismissing notifications while trying
            // to scroll. A target is unambiguous.
            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.top: parent.top
              anchors.topMargin: Style.space(12)
              text: "󰅖"
              font.family: Style.font.family
              font.pixelSize: Style.font.iconSmall
              color: root.subdued
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(10)
                onClicked: root.dismissRow(card.modelData)
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
        root.startY = pts[0].sceneY
        root.lastY = pts[0].sceneY
        root.lastT = Date.now()
        root.startProgress = root.progress
        root.velocity = 0
        root.dragging = true
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

  function openMenu(route) {
    root.dismiss()
    if (root.shell && typeof root.shell.summon === "function")
      root.shell.summon("omarchy.menu", JSON.stringify({ menu: route }))
  }

  // The gear is the way in to everything the app drawer used to carry across
  // its top row. Android puts Settings behind the gear in the pull-down for the
  // same reason: this is already the surface you open when you want to change
  // something.
  function openSettings() {
    root.dismiss()
    if (root.shell && typeof root.shell.summon === "function")
      root.shell.summon("mobileomarchy.settings", "{}")
  }

  SystemClock {
    id: shadeClock
    precision: SystemClock.Minutes
  }
}
