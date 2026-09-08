// Pairing and connecting a Bluetooth device, with a finger.
//
// ---------------------------------------------------------------------------
// Why not the TUI
// ---------------------------------------------------------------------------
// The Bluetooth tile used to open `bluetui` in a terminal, and bluetui is not
// a bad program -- unlike nmtui it enables mouse reporting, so foot's
// tap-to-click reaches it, and its bindings are all keys the on-screen
// keyboard has. Operable is not the same as usable (docs/shade.md S6c):
//
//   * a list row is one terminal line, ~17 logical px on the 60x41 grid
//     moarchy-launch-tui gives, against the 44 docs/style.md E1 asks for;
//   * a terminal is a *window* -- its own workspace, its own card in the
//     carousel, foot's palette instead of Color.popups.*, so holding one wide
//     tile gave you a screen and holding the other gave you an app;
//   * and it cannot show what BlueZ already knows and this shell already
//     draws: battery level, "Connecting...", which device owns the audio.
//
// ---------------------------------------------------------------------------
// Why not upstream's Bluetooth panel
// ---------------------------------------------------------------------------
// The same reason moarchy.wifi is not upstream's network panel. Omarchy ships
// a complete one at plugins/panels/bluetooth -- 1045 lines, scan, pair,
// battery, PipeWire sink handoff -- and its manifest declares one kind,
// `bar-widget`. This phone replaces the bar wholesale with moarchy.bar, so the
// widget is never instantiated and the panel it owns can never be summoned.
//
// So this is a screen of its own, the same shape as moarchy.wifi: an overlay
// plugin, summoned by the shade's tile and by Settings, with a back chevron.
//
// ---------------------------------------------------------------------------
// The one place this differs from moarchy.wifi
// ---------------------------------------------------------------------------
// Wi-Fi touches no nmcli: Quickshell.Networking exposes connect(),
// connectWithPsk(), disconnect() and forget() and they all work. This screen
// READS Quickshell.Bluetooth the same way -- every property below is a BlueZ
// property, nothing parses `bluetoothctl` output -- but three of the four
// actions shell out to `omarchy-bluetooth-device`, and it is worth being exact
// about why rather than leaving it looking like laziness (docs/shade.md
// S6d-6):
//
//   Quickshell registers no org.bluez.Agent1. Its pair() is a bare
//   Device1.Pair(), and BlueZ answers a pairing that needs an agent with "No
//   agent available" -- into the journal, where nobody reads it. bluetoothctl
//   registers an agent; omarchy-bluetooth-device wraps it, and adds the two
//   steps a bare Pair() also skips: rfkill unblock first, because BlueZ will
//   not power an adapter up underneath a soft block, and `trust` afterwards,
//   without which the device will not reconnect itself.
//
// It is on PATH from omarchy-config (which installs upstream's bin/ into
// /usr/bin), and upstream's own panel calls it for exactly these reasons.
//
// Disconnect is the exception and stays native: it needs no agent and no
// power-up, which is the whole of what the wrapper adds.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui as Ui
import "../moarchy.common/Theme.js" as Theme
import "../moarchy.common" as Shared

Item {
  id: root

  // Injected by the host, the same set every moarchy overlay takes.
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.bluetooth"

  // Whether the window is mapped (docs/gestures.md K1). Read off the window,
  // never assigned -- see moarchy.common/AppWindow.qml for why that direction.
  //
  // There is no `running` beside it any more. That property stood for "off
  // screen but still an app", which is what a layer surface needed and what a
  // window has a workspace for.
  //
  // The third shell app, after Settings and Wi-Fi. K10 asks for that to be a
  // decision rather than a discovery that the machinery allows it: pairing is
  // a screen you sit in -- wait for the device to appear, hold its button
  // down, try again -- which is the shape of Settings and nothing like a sheet
  // dismissed in one motion.
  readonly property bool opened: bluetoothWindow.visible

  // How moarchy.recents and the back gesture find this plugin from its window
  // (moarchy.common/ShellApps.js).
  readonly property var appWindow: bluetoothWindow

  // The card shows the device you are on, which is the useful thing to see on
  // a card, and nothing when there is none.
  readonly property string pageTitle: {
    for (var i = 0; i < root.rows.length; i++)
      if (root.rows[i].connected) return root.rows[i].name
    if (!root.adapter) return "No adapter"
    return root.adapter.enabled ? "Not connected" : "Off"
  }

  // Where Back goes, set by whoever summoned this screen, so the chevron
  // returns to the shade or the Settings page you came from rather than
  // dropping you on the home screen.
  property string returnTo: ""
  property string returnPage: ""

  // --------------------------------------------------------------- palette
  // The card radius, from the four this shell has (docs/style.md D1).
  readonly property int radiusCard: Style.space(18)

  readonly property int textWeight: Font.DemiBold
  readonly property color surface: Color.popups.background
  readonly property color textOnSurface: Color.popups.text
  readonly property color container: Util.alpha(Color.popups.text, 0.08)
  readonly property color containerHigh: Util.alpha(Color.popups.text, 0.14)
  readonly property color accent: Color.accent
  readonly property color textOnAccent: Color.background

  // C3, not a flat alpha. `container` is painted with alpha over the surface,
  // so the background this text actually lands on is the blend of the two, and
  // a constant 0.62 falls below AA on six of the 22 themes. Same computation
  // as the shade, which is the surface this screen matches.
  readonly property color subduedBase: Theme.mix(
    Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 1), Color.popups.text, 0.08)
  readonly property color subdued: Theme.readableOn(root.subduedBase,
                                                   Color.popups.text, 0.55, 4.5)

  // The veil is shared (docs/refactor.md E2); the default ink is this
  // surface's own, which is the half a shared type cannot know (style.md H2).
  component PressVeil: Shared.PressVeil { ink: root.textOnSurface }

  // ------------------------------------------------------------------ data
  readonly property var adapter: Bluetooth.defaultAdapter

  // PRIMITIVES ONLY in this list, and it is not a style preference.
  //
  // These rows become delegate data. A BluetoothDevice put here leaves a live
  // QObject wrapper in every delegate's `var` property, and BlueZ churn -- a
  // discovery timeout dropping an unpaired device, a forget removing one --
  // can destroy that object while a delegate is still incubating, which
  // segfaults quickshell on the dangling wrapper rather than throwing anything
  // catchable. moarchy.wifi carries the same warning, and so does upstream's
  // own Bluetooth panel. Actions resolve the object again, by address, at the
  // moment they run.
  property var frozenRows: []

  // S6d-4. The list holds still while a row is open or an action is in flight.
  //
  // Wi-Fi freezes for a related but different reason -- reassigning a
  // ListView's model rebuilds its delegates and the focused passphrase field
  // dies with them. There is no text field here. The reason here is aim:
  // discovery reorders this list every few seconds, and a row that moves under
  // a finger travelling toward Forget is a mis-tap with no undo.
  readonly property bool listFrozen: root.expandedAddress !== "" || root.busyAddress !== ""
  readonly property var rows: root.listFrozen ? root.frozenRows : root.liveRows

  onListFrozenChanged: if (root.listFrozen) root.frozenRows = root.liveRows

  // The expanded row's action strip, registered by the delegate that owns it
  // (docs/style.md E1). Ids declared inside a delegate are scoped to it, so
  // the IpcHandler out here cannot reach them any other way. One row expands
  // at a time, so there is only ever one to hold.
  property var actionRowItem: null

  readonly property var liveRows: {
    var objs = Bluetooth.devices ? Bluetooth.devices.values : []
    var out = []
    for (var i = 0; i < objs.length; i++) {
      var d = objs[i]
      if (!d || !d.address) continue
      var label = String(d.name || d.deviceName || "").trim()
      if (!root.hasHumanName(label, d.address)) continue
      out.push({
        address: String(d.address),
        name: label,
        icon: String(d.icon || ""),
        connected: !!d.connected,
        // "Remembered" is any of the three: BlueZ pairs, bonds and trusts
        // separately, and a device can carry the pairing record without the
        // bond after a controller change.
        known: !!(d.paired || d.bonded || d.trusted),
        pairing: !!d.pairing,
        blocked: !!d.blocked,
        batteryAvailable: !!d.batteryAvailable,
        battery: Math.round((d.battery || 0) * 100)
      })
    }
    // S6d-1. Connected, then remembered, then whatever the scan turned up;
    // each group by name. There is no RSSI to sort discovered devices by --
    // BlueZ publishes one, Quickshell.Bluetooth does not expose it -- and
    // alphabetical at least holds still between scans, which "whatever order
    // BlueZ answered in" does not.
    out.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      if (a.known !== b.known) return a.known ? -1 : 1
      return a.name.localeCompare(b.name)
    })
    return out
  }

  // S6d-1. A device whose name is only its own address, or a bare UUID, is not
  // a device anybody chose to call anything -- it is a beacon, a fitness
  // tracker advertising, a car. A phone in a café sees dozens, and every one
  // of them pushes the headset you are looking for off the screen. Ported from
  // upstream's Model.js, which learned it the same way.
  function hasHumanName(label, address) {
    if (!label) return false
    var flat = label.toLowerCase().replace(/[^0-9a-f]/g, "")
    if (flat === String(address).toLowerCase().replace(/[^0-9a-f]/g, "")) return false
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(label)) return false
    if (/^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(label)) return false
    return true
  }

  function deviceForAddress(address) {
    var objs = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < objs.length; i++)
      if (objs[i] && String(objs[i].address) === String(address)) return objs[i]
    return null
  }

  // BlueZ's `Icon` is a freedesktop icon name, so it is a vocabulary rather
  // than a free-text field, and this maps the part of it a phone actually
  // meets. Codepoints are resolved from the Nerd Font glyph catalogue by name
  // rather than typed: a codepoint typed by hand is how the Wi-Fi rows once
  // drew a calendar and a bicycle where the signal bars belonged.
  //
  //   󰂯  U+F00AF  bluetooth              󰋎  U+F02CE  headset
  //   󰋋  U+F02CB  headphones             󰓃  U+F04C3  speaker
  //   󰝚  U+F075A  music                  󰍬  U+F036C  microphone
  //   󰌌  U+F030C  keyboard               󰍽  U+F037D  mouse
  //   󰊗  U+F0297  gamepad                󰄜  U+F011C  cellphone
  //   󰌢  U+F0322  laptop                 󰍹  U+F0379  monitor
  //   󰐪  U+F042A  printer                󰄀  U+F0100  camera
  //   󰖉  U+F0589  watch                  󰓶  U+F04F6  tablet
  //   󰄋  U+F010B  car
  function deviceGlyph(icon) {
    var name = String(icon || "")
    if (name === "audio-headset") return "󰋎"
    if (name === "audio-headphones") return "󰋋"
    if (name === "audio-speakers" || name === "audio-card") return "󰓃"
    if (name === "multimedia-player") return "󰝚"
    if (name === "audio-input-microphone") return "󰍬"
    if (name === "input-keyboard") return "󰌌"
    if (name === "input-mouse") return "󰍽"
    if (name === "input-gaming") return "󰊗"
    if (name === "input-tablet") return "󰓶"
    if (name === "phone") return "󰄜"
    if (name === "computer") return "󰌢"
    if (name === "video-display") return "󰍹"
    if (name === "printer" || name === "scanner") return "󰐪"
    if (name === "camera-photo" || name === "camera-video") return "󰄀"
    if (name === "phone-car" || name === "car") return "󰄋"
    if (name.indexOf("watch") !== -1) return "󰖉"
    // Unrecognised stays the bluetooth rune rather than guessing at a shape.
    // A wrong picture of a device is worse than no picture of it.
    return "󰂯"
  }

  // ----------------------------------------------------------- interaction
  // The row currently expanded, by address rather than by object for the same
  // reason the rows are primitives. One at a time, so the list never grows two
  // open drawers on a screen this size.
  property string expandedAddress: ""

  // The action in flight, and what to call it while it is. Held by address.
  property string busyAddress: ""
  property string busyVerb: ""
  property string busyName: ""

  property string errorAddress: ""
  property string errorText: ""

  // S6d-3. Nothing acts on a tap of the row itself. Wi-Fi joins an open
  // network on the tap because there is exactly one thing that tap could mean;
  // no Bluetooth device is that unambiguous -- a paired headset in reach could
  // as easily be one you are about to forget as one you are about to connect
  // -- so every device opens its drawer and the drawer carries the verbs.
  function rowTapped(row) {
    if (root.busyAddress !== "") return          // one action at a time
    root.errorAddress = ""
    root.errorText = ""
    root.expandedAddress = root.expandedAddress === row.address ? "" : row.address
  }

  // S6d-6. The three that need bluetoothctl's agent, its rfkill unblock and
  // its `trust`. Detached and fire-and-forget: the device's own properties
  // coming good is what tells us it worked, and there is nothing useful to do
  // with an exit status that is 0 whatever happened (the script swallows every
  // failure with `|| true` so a half-done pair does not abort the rest).
  function runAction(row, verb, label) {
    root.busyAddress = row.address
    root.busyVerb = label
    root.busyName = row.name
    root.errorAddress = ""
    root.errorText = ""
    actionTimeout.restart()
    Quickshell.execDetached(["omarchy-bluetooth-device", verb, row.address])
  }

  function connectRow(row) {
    if (row.connected) return
    // pair for a device BlueZ has no record of, connect for one it has. The
    // script's `pair` does both -- pair, trust, connect -- so a device that
    // has drifted out of its bond still lands connected.
    root.runAction(row, row.known ? "connect" : "pair", row.known ? "Connecting" : "Pairing")
  }

  // Native, unlike the other three: Device1.Disconnect() needs no agent, no
  // power-up and no trust, so the wrapper would add a fork and a 10s timeout
  // and nothing else.
  function disconnectRow(row) {
    var dev = root.deviceForAddress(row.address)
    if (!dev) return
    root.busyAddress = row.address
    root.busyVerb = "Disconnecting"
    root.busyName = row.name
    root.errorAddress = ""
    root.errorText = ""
    actionTimeout.restart()
    dev.disconnect()
  }

  function forgetRow(row) {
    root.runAction(row, "forget", "Forgetting")
  }

  // Success is observed rather than reported: the device's own BlueZ
  // properties arriving where we asked them to go is the only signal that
  // means it worked. liveRows, NOT rows -- `rows` is frozen while an action is
  // in flight, which is what keeps the list still under the finger, so
  // watching it means the success this looks for can never arrive, the timeout
  // fires, and an action that worked reports that it did not.
  onLiveRowsChanged: {
    if (root.busyAddress === "") return
    var found = null
    for (var i = 0; i < root.liveRows.length; i++)
      if (root.liveRows[i].address === root.busyAddress) { found = root.liveRows[i]; break }

    var done = false
    if (root.busyVerb === "Forgetting") done = !found || !found.known
    else if (root.busyVerb === "Disconnecting") done = !found || !found.connected
    else done = !!(found && found.connected)

    if (!done) return
    actionTimeout.stop()
    root.busyAddress = ""
    root.busyVerb = ""
    root.busyName = ""
    root.expandedAddress = ""
  }

  // S6d-7. No failure reason is exposed here that is worth trusting -- the
  // script swallows them and BlueZ's own errors go to the journal -- so this
  // reports what it actually knows: it did not land in time. Guessing "wrong
  // PIN" at a headset that was simply switched off sends somebody to re-pair
  // for no reason. 25s, the same patience Wi-Fi's join has, and comfortably
  // past the 20s bluetoothctl itself waits.
  // Spelled out rather than derived from the verb. "Forgetting" minus a
  // trailing "ing" is "forgett", which is what a rule that looked clever
  // actually printed.
  function failureText(verb) {
    if (verb === "Pairing")
      return "Could not pair — put the device in pairing mode and try again"
    if (verb === "Forgetting")
      return "Could not forget this device"
    if (verb === "Disconnecting")
      return "Could not disconnect — the device may already be gone"
    return "Could not connect — check the device is on and in range"
  }

  Timer {
    id: actionTimeout
    interval: 25000
    onTriggered: {
      if (root.busyAddress === "") return
      root.errorAddress = root.busyAddress
      root.errorText = root.failureText(root.busyVerb)
      root.expandedAddress = root.busyAddress
      root.busyAddress = ""
      root.busyVerb = ""
      root.busyName = ""
    }
  }

  // ------------------------------------------------------------- the radio
  // S6d-8. Unblock first when the adapter reads blocked, then write `enabled`
  // once the unblock has landed -- the same order and the same 700ms the shade
  // uses (docs/shade.md S9), because BlueZ will not power an adapter up
  // underneath an rfkill soft block and drops the write with nothing on
  // screen to show for it. The user is in group rfkill, so none of this needs
  // root.
  function setEnabled(on) {
    if (!root.adapter) return
    if (on && root.adapter.state === BluetoothAdapterState.Blocked) {
      Quickshell.execDetached(["rfkill", "unblock", "bluetooth"])
      unblockThenEnable.restart()
      return
    }
    root.adapter.enabled = on
  }

  Timer {
    id: unblockThenEnable
    interval: 700
    onTriggered: if (root.adapter) root.adapter.enabled = true
  }

  // ---------------------------------------------------------- discovery
  // S6d-2. Scan only while the screen is up. A scan left running costs radio
  // time and battery for a list nobody is reading, and BlueZ keeps it going
  // across clients until somebody stops it.
  //
  // Retried rather than written once: BlueZ rejects StartDiscovery on an
  // adapter that is still powering on, and a discovery session times out on
  // its own after a couple of minutes. `running` falls to false the moment
  // BlueZ confirms discovery is up, and comes back the moment it lapses.
  property bool owesDiscoveryStop: false

  Timer {
    id: discoveryStart
    interval: 1500
    repeat: true
    triggeredOnStart: true
    running: root.opened && root.adapter !== null
             && root.adapter.enabled && !root.adapter.discovering
    onTriggered: {
      root.owesDiscoveryStop = true
      root.adapter.discovering = true
    }
  }

  // The way back down, and why it is a timer bound to the confirmed state
  // rather than one write at close time: quickshell only forwards a
  // `discovering` write that differs from the last state BlueZ reported, so a
  // stop issued while a just-fired StartDiscovery is still in flight is
  // dropped. Bound to `discovering`, a confirmation landing at any point
  // re-arms this. Capped, so a session some other client holds -- which was
  // never ours to stop -- cannot draw StopDiscovery fire forever.
  Timer {
    id: discoveryStop
    interval: 400
    repeat: true
    property int attempts: 0
    running: !root.opened && root.owesDiscoveryStop
             && root.adapter !== null && root.adapter.discovering
    onTriggered: {
      discoveryStop.attempts += 1
      if (discoveryStop.attempts > 4) {
        root.owesDiscoveryStop = false
        discoveryStop.attempts = 0
        return
      }
      root.adapter.discovering = false
    }
  }

  // The debt is settled the moment BlueZ reports discovery down, whoever put
  // it down. While the screen is still open discoveryStart re-incurs it.
  Connections {
    target: root.adapter
    ignoreUnknownSignals: true
    function onDiscoveringChanged() {
      if (root.adapter && !root.adapter.discovering) {
        root.owesDiscoveryStop = false
        discoveryStop.attempts = 0
      }
    }
  }

  // ------------------------------------------------------------- lifecycle
  function open(payloadJson) {
    if (root.shell && typeof root.shell.isPluginOpen === "function") {
      if (root.shell.isPluginOpen("moarchy.shade")) root.shell.hide("moarchy.shade")
      if (root.shell.isPluginOpen("moarchy.drawer")) root.shell.hide("moarchy.drawer")
    }
    bluetoothWindow.show()
    root.returnTo = ""
    root.returnPage = ""
    root.expandedAddress = ""
    root.errorAddress = ""
    root.errorText = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload && payload.returnTo) root.returnTo = String(payload.returnTo)
      if (payload && payload.page) root.returnPage = String(payload.page)
    } catch (e) {
      // A malformed payload is not worth refusing to open over.
    }
  }

  function close() { bluetoothWindow.hide() }

  // K6. Kept as a name because the carousel and the back gesture ask for it by
  // name. Unmapping the window is closing the app, and there is no second,
  // gentler thing it could mean now that it is a window.
  function quit(): void { root.close() }

  function dismiss() {
    var back = root.returnTo
    var page = root.returnPage
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, page ? JSON.stringify({ page: page }) : "{}")
  }

  // Driven by moarchy-selftest and by the Settings row, the same contract
  // every other moarchy plugin exposes.
  IpcHandler {
    target: "bluetooth"

    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function enabled(): string {
      if (!root.adapter) return "no-adapter"
      return root.adapter.enabled ? "on" : "off"
    }

    // S6d-2, assertable without a screenshot: the scan is up while the screen
    // is and down after it.
    function scanning(): string {
      return root.adapter && root.adapter.discovering ? "on" : "off"
    }

    // One line per device, so a check can assert the list without a
    // screenshot.
    function list(): string {
      var out = []
      for (var i = 0; i < root.rows.length; i++) {
        var r = root.rows[i]
        out.push([r.name, r.address,
                  r.connected ? "connected" : "-",
                  r.known ? "known" : "new",
                  r.batteryAvailable ? r.battery + "%" : "-"].join("\t"))
      }
      return out.join("\n")
    }

    // docs/style.md E1. Same job as `wifi passTarget`: an action strip draws
    // identically whether or not it is 44px tall, so the rect has to be read
    // rather than photographed. Surface coordinates; bin/moarchy-touch takes
    // these doubled. Empty until a row is expanded -- there are no actions
    // before that.
    function actionTarget(): string {
      if (!root.actionRowItem) return ""
      var p = root.actionRowItem.mapToItem(null, 0, 0)
      return "actions=" + Math.round(p.x) + "," + Math.round(p.y)
           + " " + Math.round(root.actionRowItem.width)
           + "x" + Math.round(root.actionRowItem.height)
           + " row=" + root.expandedAddress
    }
  }

  // ----------------------------------------------------------------- window
  //
  // docs/gestures.md K. An ordinary toplevel, so sway gives it a workspace and
  // the strip's swipes reach it as one more app. The strip inset and the
  // keyboard inset the layer surface had to compute are the compositor's.
  Shared.AppWindow {
    id: bluetoothWindow

    shell: root.shell
    appName: "Bluetooth"
    pageTitle: root.pageTitle
    pluginId: root.pluginId
    // The literal character, not an escape: JavaScript's \u takes exactly four
    // hex digits, so "\uF00AF" is U+F00A followed by an "F". U+F00AF,
    // md-bluetooth -- the same rune the shade's tile and the Settings row wear.
    glyph: "󰂯"
    color: root.surface

    onUnmapped: {
      root.expandedAddress = ""
      root.errorAddress = ""
      root.errorText = ""
    }

    Rectangle {
      anchors.fill: parent
      color: root.surface

      focus: true
      Keys.onEscapePressed: root.dismiss()

      Column {
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        anchors.topMargin: Style.space(8)
        anchors.bottomMargin: Style.space(8)
        spacing: Style.space(10)

        // --------------------------------------------------------- header
        Item {
          width: parent.width
          height: Style.space(44)

          Rectangle {
            id: backButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(38)
            height: width
            radius: width / 2
            color: root.container

            PressVeil { anchors.fill: parent; radius: parent.radius; on: backArea.pressed }

            Ui.OpticalGlyph {
              anchors.fill: parent
              text: ""
              fontFamily: Style.font.family
              fontSize: Style.font.icon
              color: root.textOnSurface
            }
            // 38 drawn, 44 answering -- the same 3px as the Settings header,
            // and for the same reasons (docs/style.md E1, E2).
            MouseArea {
              id: backArea
              anchors.fill: parent
              anchors.margins: -Style.space(3)
              onClicked: root.dismiss()
            }
          }

          Text {
            anchors.left: backButton.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "Bluetooth"
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: root.textWeight
            color: root.textOnSurface
          }

          // The radio switch, drawn exactly as Wi-Fi's is: it is the one
          // control on this screen that is not a list row, and the two screens
          // have to read as the same app.
          Rectangle {
            id: radioSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(52)
            height: Style.space(30)
            radius: height / 2
            // No adapter is not "off" -- there is nothing to switch -- so the
            // track goes quiet and the tap below does nothing.
            opacity: root.adapter ? 1 : 0.4
            color: root.adapter && root.adapter.enabled ? root.accent : root.containerHigh
            Behavior on color { ColorAnimation { duration: 120 } }

            // Veiled toward whichever ink the track is carrying (docs/style.md
            // H4): on a theme whose accent is close to its text, one fixed ink
            // would show nothing in one of the two states.
            PressVeil {
              anchors.fill: parent
              radius: parent.radius
              ink: root.adapter && root.adapter.enabled ? root.textOnAccent
                                                        : root.textOnSurface
              on: radioArea.pressed
            }

            Rectangle {
              width: parent.height - Style.space(6)
              height: width
              radius: width / 2
              y: Style.space(3)
              x: root.adapter && root.adapter.enabled
                 ? parent.width - width - Style.space(3) : Style.space(3)
              color: root.adapter && root.adapter.enabled ? root.textOnAccent
                                                          : root.textOnSurface
              Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
            // A switch is 30 tall because that is what a switch looks like,
            // and 30 is not a target (docs/style.md E1, E2). The 7px fills
            // the 44px header it sits in and reaches past both ends of the
            // track; the only thing to its left is the title, which is text.
            MouseArea {
              id: radioArea
              anchors.fill: parent
              anchors.margins: -Style.space(7)
              enabled: root.adapter !== null
              onClicked: root.setEnabled(!root.adapter.enabled)
            }
          }
        }

        // ---------------------------------------------------------- status
        Text {
          width: parent.width
          text: {
            if (!root.adapter) return "No Bluetooth adapter"
            if (!root.adapter.enabled) return "Bluetooth is off"
            if (root.busyAddress !== "") return root.busyVerb + " " + root.busyName + "…"
            if (root.rows.length === 0) return "Scanning…"
            if (root.rows.length === 1) return "1 device"
            return root.rows.length + " devices"
          }
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: root.textWeight
          color: root.subdued
        }

        // ------------------------------------------------------------ list
        ListView {
          id: list
          width: parent.width
          height: Math.max(0, parent.height - y)
          clip: true
          spacing: Style.space(6)
          model: root.adapter && root.adapter.enabled ? root.rows : []
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            id: rowItem
            required property var modelData

            readonly property bool isExpanded: root.expandedAddress === rowItem.modelData.address
            readonly property bool isBusy: root.busyAddress === rowItem.modelData.address
            readonly property bool hasError: root.errorAddress === rowItem.modelData.address

            width: list.width
            // Tall enough for a finger, and taller again when the drawer is
            // open: 44 of actions plus 8 above and 8 below.
            height: Style.space(58)
                    + (rowItem.isExpanded ? Style.space(60) : 0)
                    + (rowItem.hasError ? Style.space(30) : 0)
            Behavior on height { NumberAnimation { duration: 120 } }
            radius: root.radiusCard
            color: rowItem.isExpanded ? root.containerHigh : root.container

            Item {
              id: rowHead
              width: parent.width
              height: Style.space(58)

              // Sized to the head and not to the delegate (docs/style.md H8):
              // the MouseArea is the head, and an expanded row is up to 148
              // tall, so veiling the card would say "you pressed the card"
              // while the finger is about to collapse it. D2's squaring
              // rectangle is not available here -- two translucent quads stack
              // to 0.23 where they overlap -- so while expanded the veil's
              // bottom corners round inward, invisibly at this alpha.
              PressVeil {
                anchors.fill: parent
                radius: root.radiusCard
                on: headArea.pressed
              }

              Text {
                id: kindGlyph
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                text: root.deviceGlyph(rowItem.modelData.icon)
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
                color: rowItem.modelData.connected ? root.accent : root.textOnSurface
              }

              Text {
                id: nameText
                anchors.left: kindGlyph.right
                anchors.leftMargin: Style.space(14)
                anchors.right: batteryText.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -Style.space(7)
                text: rowItem.modelData.name
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: root.textWeight
                color: root.textOnSurface
              }

              Text {
                anchors.left: nameText.left
                anchors.right: nameText.right
                anchors.top: nameText.bottom
                anchors.topMargin: Style.space(2)
                text: rowItem.isBusy ? root.busyVerb + "…"
                    : rowItem.modelData.pairing ? "Pairing…"
                    : rowItem.modelData.blocked ? "Blocked"
                    : rowItem.modelData.connected ? "Connected"
                    : rowItem.modelData.known ? "Paired"
                    : "Available"
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: rowItem.modelData.connected ? root.accent : root.subdued
              }

              // S6d-5. The one thing the shade's tile cannot show, and the
              // reason to open this screen when everything is already
              // connected. A number rather than a battery glyph: a 12px icon
              // that has to distinguish five levels says less than "62%".
              Text {
                id: batteryText
                anchors.right: parent.right
                anchors.rightMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                visible: rowItem.modelData.batteryAvailable
                width: visible ? implicitWidth : 0
                text: rowItem.modelData.battery + "%"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: root.subdued
              }

              MouseArea {
                id: headArea
                anchors.fill: parent
                onClicked: root.rowTapped(rowItem.modelData)
              }
            }

            // ------------------------------------------------- error line
            Text {
              visible: rowItem.hasError
              anchors.top: rowHead.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(16)
              anchors.rightMargin: Style.space(16)
              text: root.errorText
              wrapMode: Text.WordWrap
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: root.textWeight
              color: root.accent
            }

            // ----------------------------------------------------- drawer
            // One row of verbs, right-aligned, at most two of them visible at
            // once: Connect/Pair with Forget for a remembered device that is
            // off, Disconnect with Forget for one that is on. They fit on a
            // 360px line, which is why this is one row where Wi-Fi needs two.
            Row {
              id: actionRow
              visible: rowItem.isExpanded
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(8)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(8)
              height: Style.space(44)

              // Registered on visibility, because every row builds one of these
              // and only the expanded row shows it -- registering all of them
              // on completion would leave the last delegate built holding the
              // slot. And ALSO on completion when already visible, which is
              // not belt and braces: a delegate built with `visible` already
              // true never emits visibleChanged, so a row rebuilt while it was
              // open would draw its actions and report none. Found on the
              // phone, 2026-09-07, with a fixture that pinned isExpanded true:
              // the strip was on screen at its right size and `actionTarget`
              // answered the empty string.
              onVisibleChanged: {
                if (visible) root.actionRowItem = actionRow
                else if (root.actionRowItem === actionRow) root.actionRowItem = null
              }
              Component.onCompleted: if (visible) root.actionRowItem = actionRow
              Component.onDestruction:
                if (root.actionRowItem === actionRow) root.actionRowItem = null

              Rectangle {
                visible: !rowItem.modelData.connected
                width: Style.space(110)
                height: parent.height
                radius: height / 2
                // A blocked device rejects every connection attempt at the
                // system level, so offering the verb would be offering a
                // failure. Forget is still there, which is the way out.
                readonly property bool ready: !rowItem.modelData.blocked
                                              && root.busyAddress === ""
                color: ready ? root.accent : root.containerHigh
                opacity: ready ? 1 : 0.6
                PressVeil {
                  anchors.fill: parent
                  radius: parent.radius
                  ink: parent.ready ? root.textOnAccent : root.textOnSurface
                  on: connectArea.pressed
                }
                Text {
                  anchors.centerIn: parent
                  text: rowItem.modelData.known ? "Connect" : "Pair"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.weight: root.textWeight
                  color: parent.ready ? root.textOnAccent : root.subdued
                }
                MouseArea {
                  id: connectArea
                  anchors.fill: parent
                  enabled: parent.ready
                  onClicked: root.connectRow(rowItem.modelData)
                }
              }

              Rectangle {
                visible: rowItem.modelData.connected
                width: Style.space(120)
                height: parent.height
                radius: height / 2
                color: root.containerHigh
                PressVeil { anchors.fill: parent; radius: parent.radius; on: disconnectArea.pressed }
                Text {
                  anchors.centerIn: parent
                  text: "Disconnect"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.weight: root.textWeight
                  color: root.textOnSurface
                }
                MouseArea {
                  id: disconnectArea
                  anchors.fill: parent
                  onClicked: root.disconnectRow(rowItem.modelData)
                }
              }

              Rectangle {
                visible: rowItem.modelData.known
                width: Style.space(96)
                height: parent.height
                radius: height / 2
                color: root.containerHigh
                PressVeil { anchors.fill: parent; radius: parent.radius; on: forgetArea.pressed }
                Text {
                  anchors.centerIn: parent
                  text: "Forget"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.weight: root.textWeight
                  color: root.textOnSurface
                }
                MouseArea {
                  id: forgetArea
                  anchors.fill: parent
                  onClicked: root.forgetRow(rowItem.modelData)
                }
              }
            }
          }
        }
      }
    }
  }
}
