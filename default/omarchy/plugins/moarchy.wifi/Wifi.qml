// Joining a Wi-Fi network, with a finger.
//
// ---------------------------------------------------------------------------
// Why not the TUI
// ---------------------------------------------------------------------------
// The Wi-Fi tile used to launch `nmtui-connect` in a floating terminal, and it
// genuinely fits the 60x41 grid -- the network list and its buttons are all on
// screen. But a TUI's buttons are drawn text, not surfaces: touch cannot press
// them. Driving them needs Tab, arrows and Enter, and the on-screen keyboard
// has no Tab and no arrow cluster, so the list was reachable and the join was
// not. You could see your network and could not connect to it.
//
// ---------------------------------------------------------------------------
// Why not upstream's network panel
// ---------------------------------------------------------------------------
// Omarchy ships a complete one at plugins/panels/network -- scan, passphrase,
// forget, error mapping, 1970 lines of it. It is a `bar-widget`, though: its
// manifest declares one kind and the panel opens from that widget. This phone
// replaces the bar wholesale with moarchy.bar, so the widget is never
// instantiated and the panel it owns can never be summoned. Adding upstream's
// widget back to a 360px bar to reach its popup is not a trade worth making.
//
// So this is a screen of its own, the same shape as moarchy.themes: an overlay
// plugin, summoned by the shade's tile and by Settings, with a back chevron.
//
// ---------------------------------------------------------------------------
// What it does NOT reimplement
// ---------------------------------------------------------------------------
// Nothing talks to nmcli. Quickshell.Networking exposes the whole model --
// devices, per-network signal/security/known/connected, and connect(),
// connectWithPsk(), disconnect() and forget() as methods. Shelling out would
// mean parsing output that already arrives as properties.
//
// Enterprise (802.1X) networks are deliberately out of scope: they need an
// identity as well as a passphrase, and upstream reaches them through a
// scripted `nmcli connection edit` because the secret must not become argv.
// A phone that needs one can still use the terminal; guessing at a two-field
// form nobody here can test would be worse than not offering it.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Networking
import qs.Commons
import qs.Ui as Ui

Item {
  id: root

  // Injected by the host, the same set every moarchy overlay takes.
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.wifi"

  property bool opened: false

  // The app-like half of this screen (docs/gestures.md K).
  //
  // `running` is "summoned and not yet closed", which outlives any number of
  // hides -- swiping away to another app leaves Wi-Fi running, so the carousel
  // keeps a card for it and coming back resumes where you were. `opened` is
  // only whether the surface is on screen right now.
  //
  // Settings established this contract; moarchy.recents reads exactly these
  // four things off a shell app: running, opened, pageTitle and quit().
  property bool running: false

  // The card shows the network you are on, which is the useful thing to see on
  // a card, and nothing when there is none.
  readonly property string pageTitle: {
    for (var i = 0; i < root.rows.length; i++)
      if (root.rows[i].connected) return root.rows[i].ssid
    return Networking.wifiEnabled ? "Not connected" : "Off"
  }

  // Where Back goes, set by whoever summoned this screen, so the chevron
  // returns to the shade or the Settings page you came from rather than
  // dropping you on the home screen.
  property string returnTo: ""
  property string returnPage: ""

  // --------------------------------------------------------------- palette
  // Matches the shade, which is where the tile that opens this lives.
  readonly property int gestureStrip: Style.space(20)
  readonly property int textWeight: Font.DemiBold
  readonly property color surface: Color.popups.background
  readonly property color textOnSurface: Color.popups.text
  readonly property color container: Util.alpha(Color.popups.text, 0.08)
  readonly property color containerHigh: Util.alpha(Color.popups.text, 0.14)
  readonly property color accent: Color.accent
  readonly property color textOnAccent: Color.background
  readonly property color subdued: Util.alpha(Color.popups.text, 0.62)
  readonly property color danger: Color.popups.text

  // ------------------------------------------------------------------ data
  readonly property var wifiDevice: {
    var devices = Networking.devices ? Networking.devices.values : []
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].type === DeviceType.Wifi) return devices[i]
    return null
  }

  // PRIMITIVES ONLY in this list, and it is not a style preference.
  //
  // These rows become delegate data. A WifiNetwork put here leaves a live
  // QObject wrapper in every delegate's `var` property, and a scan that removes
  // an access point can destroy that object while a delegate is still
  // incubating -- which segfaults quickshell on the dangling wrapper rather
  // than throwing anything catchable. Upstream's Model.js carries the same
  // warning. Actions resolve the object again, by ssid, at the moment they run.
  // The list is frozen while a row is open, and that is the whole fix for
  // "the keyboard loses focus every time the list refreshes".
  //
  // `rows` recomputes on every scan result. Reassigning a ListView's model
  // rebuilds its delegates, the focused TextField is destroyed with them, and
  // the on-screen keyboard retracts mid-passphrase. Holding the array
  // reference steady while a drawer is open keeps the delegate -- and its focus
  // -- alive. Signal strengths going stale for the few seconds someone is
  // typing is not a cost worth mentioning next to that.
  property var frozenRows: []
  readonly property bool listFrozen: root.expandedSsid !== "" || root.busySsid !== ""
  readonly property var rows: root.listFrozen ? root.frozenRows : root.liveRows

  onListFrozenChanged: if (root.listFrozen) root.frozenRows = root.liveRows

  // The expanded row's passphrase pill and field, registered by the delegate
  // that owns them (docs/touch-targets.md B3, B4). Ids declared inside a
  // delegate are scoped to it, so the IpcHandler out here cannot reach them any
  // other way -- and a rect published once on expansion would be read before
  // the layout that produced it had settled. One row expands at a time, so
  // there is only ever one pair to hold.
  property var passPillItem: null
  property var passFieldItem: null

  readonly property var liveRows: {
    var objs = root.wifiDevice && root.wifiDevice.networks
             ? root.wifiDevice.networks.values : []
    var out = []
    for (var i = 0; i < objs.length; i++) {
      var n = objs[i]
      if (!n || !n.name) continue
      out.push({
        ssid: String(n.name),
        signal: Math.round((n.signalStrength || 0) * 100),
        security: n.security,
        known: !!n.known,
        connected: !!n.connected
      })
    }
    out.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      if (a.known !== b.known) return a.known ? -1 : 1
      return b.signal - a.signal
    })
    return out
  }

  // Whether a row should offer a passphrase field: any secured network that is
  // not currently connected, INCLUDING one already saved.
  //
  // Saved-but-wrong is the ordinary case after a typo, and the first version
  // sent you to Forget first: a known network only ever offered
  // Disconnect/Forget, so correcting a passphrase meant deleting the network
  // and starting again. NetworkManager will happily replace the stored secret,
  // so there is no reason to make anyone do that.
  function offersPassphrase(row) {
    return !row.connected && root.needsPassphrase(row.security)
  }

  function networkForSsid(ssid) {
    var objs = root.wifiDevice && root.wifiDevice.networks
             ? root.wifiDevice.networks.values : []
    for (var i = 0; i < objs.length; i++)
      if (objs[i] && String(objs[i].name) === String(ssid)) return objs[i]
    return null
  }

  // OWE (Enhanced Open) encrypts without authenticating, so it has no
  // credentials to ask for. Anything unrecognised stays credentialed, which is
  // the conservative way to be wrong: a needless prompt beats a silent failure.
  function needsPassphrase(security) {
    return security !== WifiSecurityType.Open && security !== WifiSecurityType.Owe
  }

  function isEnterprise(security) {
    return security === WifiSecurityType.Wpa2Eap || security === WifiSecurityType.WpaEap
  }

  function signalGlyph(strength) {
    // Codepoints U+F092F, U+F091F, U+F0922, U+F0925, U+F0928 -- upstream's
    // exact array. Typed by hand the first time as U+F11xx, which is a real
    // glyph range in this font, so the rows rendered a calendar and a bicycle
    // instead of signal bars rather than showing tofu.
    var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    return icons[Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1))]
  }

  // ----------------------------------------------------------- interaction
  // The row currently expanded: either into a passphrase field, or into
  // Disconnect/Forget for one already joined. One at a time, so the list never
  // grows two open drawers on a screen this size.
  property string expandedSsid: ""
  property string passphrase: ""

  // The join in flight. Held by ssid rather than by object for the same reason
  // the rows are primitives.
  property string busySsid: ""

  // Whether the passphrase field currently holds focus, tracked here rather
  // than read off the field.
  //
  // The field lives inside a ListView delegate, so it does not exist at the
  // window's scope -- and there is not one of it, there is one per row. The
  // drawer can write `searchField.activeFocus` because its search field is a
  // sibling in the same Column; copying that shape here produced
  //   ReferenceError: passField is not defined
  // at load, which cost the surface its bottom margin binding.
  property bool passphraseFocused: false

  // Whether the passphrase is shown in the clear. Off by default; the eye in
  // the field turns it on. A phone keyboard has no key feedback worth the name,
  // and a wrong character is otherwise only discoverable 25 seconds later.
  property bool showPassphrase: false
  property string errorSsid: ""
  property string errorText: ""

  onExpandedSsidChanged: if (root.expandedSsid === "") root.passphraseFocused = false

  function rowTapped(row) {
    if (root.busySsid !== "") return          // one join at a time
    root.errorSsid = ""
    root.errorText = ""

    if (root.isEnterprise(row.security)) {
      root.errorSsid = row.ssid
      root.errorText = "Enterprise networks need the terminal"
      return
    }
    // An open network nobody has joined is the one case with nothing to ask:
    // connect on the tap. Everything else opens its drawer, which carries the
    // passphrase field when the network is secured and not connected, and the
    // Disconnect/Forget actions when they apply.
    if (!row.connected && !row.known && !root.needsPassphrase(row.security)) {
      root.join(row.ssid, "")
      return
    }
    root.passphrase = ""
    root.showPassphrase = false
    root.expandedSsid = root.expandedSsid === row.ssid ? "" : row.ssid
  }

  function joinRow(row) {
    if (root.offersPassphrase(row) && root.passphrase.length >= 8)
      root.join(row.ssid, root.passphrase)
    else if (row.known || !root.needsPassphrase(row.security))
      root.join(row.ssid, "")
  }

  function join(ssid, psk) {
    var net = root.networkForSsid(ssid)
    if (!net) return
    root.busySsid = ssid
    root.errorSsid = ""
    root.errorText = ""
    joinTimeout.restart()
    if (psk === "") net.connect()
    else net.connectWithPsk(psk)
  }

  function disconnectSsid(ssid) {
    var net = root.networkForSsid(ssid)
    if (net) net.disconnect()
    root.expandedSsid = ""
  }

  function forgetSsid(ssid) {
    var net = root.networkForSsid(ssid)
    if (net) net.forget()
    root.expandedSsid = ""
  }

  // Success is observed rather than reported: the device's connected network
  // becoming the one we asked for is the only signal that means it worked.
  // liveRows, NOT rows. `rows` is frozen while a join is in flight -- that is
  // what keeps the keyboard's focus -- so watching it means the success this
  // looks for can never arrive, the timeout fires, and a connection that
  // worked reports "check the passphrase". The freeze is for the delegates;
  // the observation has to come from the live data.
  onLiveRowsChanged: {
    if (root.busySsid === "") return
    // The live list here too, for the same reason the signal is on it.
    for (var i = 0; i < root.liveRows.length; i++) {
      if (root.liveRows[i].ssid === root.busySsid && root.liveRows[i].connected) {
        joinTimeout.stop()
        root.busySsid = ""
        root.expandedSsid = ""
        root.passphrase = ""
        return
      }
    }
  }

  // No failure reason is exposed here that is worth trusting, so this reports
  // what it actually knows: it did not come up in time. Guessing "wrong
  // password" at a network that was simply out of range would send someone to
  // retype a passphrase that was right.
  Timer {
    id: joinTimeout
    interval: 25000
    onTriggered: {
      if (root.busySsid === "") return
      root.errorSsid = root.busySsid
      root.errorText = "Could not join — check the passphrase, or move closer"
      root.expandedSsid = root.busySsid
      root.passphrase = ""
      root.showPassphrase = false
      root.busySsid = ""
    }
  }

  // Scan only while the screen is up. A scanner left running costs radio time
  // and battery for a list nobody is reading.
  function setScanning(on) {
    if (root.wifiDevice) root.wifiDevice.scannerEnabled = on
  }
  onOpenedChanged: root.setScanning(root.opened)
  onWifiDeviceChanged: root.setScanning(root.opened)

  // ------------------------------------------------------------- lifecycle
  function open(payloadJson) {
    if (root.shell && typeof root.shell.isPluginOpen === "function") {
      if (root.shell.isPluginOpen("moarchy.shade")) root.shell.hide("moarchy.shade")
      if (root.shell.isPluginOpen("moarchy.drawer")) root.shell.hide("moarchy.drawer")
    }
    root.opened = true
    root.running = true
    root.returnTo = ""
    root.returnPage = ""
    root.expandedSsid = ""
    root.passphrase = ""
    root.errorSsid = ""
    root.errorText = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload && payload.returnTo) root.returnTo = String(payload.returnTo)
      if (payload && payload.page) root.returnPage = String(payload.page)
    } catch (e) {
      // A malformed payload is not worth refusing to open over.
    }
  }

  function close() { root.opened = false }

  // Swiping the card away in the carousel. Distinct from close(): this ends the
  // app rather than putting its surface down.
  function quit(): void {
    root.running = false
    root.expandedSsid = ""
    root.passphrase = ""
    root.showPassphrase = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  function dismiss() {
    var back = root.returnTo
    var page = root.returnPage
    root.passphrase = ""
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, page ? JSON.stringify({ page: page }) : "{}")
  }

  // Driven by moarchy-selftest and by the Settings row, the same contract every
  // other moarchy plugin exposes.
  IpcHandler {
    target: "wifi"

    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function enabled(): string { return Networking.wifiEnabled ? "on" : "off" }

    // One line per network, so a check can assert the list without a screenshot.
    function list(): string {
      var out = []
      for (var i = 0; i < root.rows.length; i++) {
        var r = root.rows[i]
        out.push([r.ssid, r.signal,
                  root.needsPassphrase(r.security) ? "secured" : "open",
                  r.known ? "known" : "new",
                  r.connected ? "connected" : "-"].join("\t"))
      }
      return out.join("\n")
    }

    // docs/touch-targets.md B3, B4. Same job as the drawer's searchTarget():
    // the pill and the field draw identically whether or not they are the same
    // rectangle, so the rects have to be read rather than photographed.
    // Surface coordinates; bin/moarchy-touch takes these doubled.
    //
    // Empty until a secured row is expanded -- there is no field before that.
    function passTarget(): string {
      if (!root.passPillItem || !root.passFieldItem) return ""
      var box = it => {
        var p = it.mapToItem(null, 0, 0)
        return Math.round(p.x) + "," + Math.round(p.y)
             + " " + Math.round(it.width) + "x" + Math.round(it.height)
      }
      return "pill=" + box(root.passPillItem)
           + " field=" + box(root.passFieldItem)
           + " focused=" + root.passphraseFocused
           + " revealed=" + root.showPassphrase
    }
  }

  // ----------------------------------------------------------------- chrome
  PanelWindow {
    id: wifiWindow

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "moarchy-wifi"
    WlrLayershell.layer: WlrLayer.Top

    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    // Draw under the gesture strip, except while the passphrase field has
    // focus -- then the on-screen keyboard needs the space and the inset has to
    // go, or the field ends up behind it. Keyed on activeFocus rather than on
    // the keyboard's visibility, because focus is the signal that arrives
    // first. Same arrangement as the drawer's search field.
    margins.bottom: root.passphraseFocused ? 0 : -root.gestureStrip

    // Exclusive, not OnDemand: the passphrase field needs the surface to hold
    // keyboard focus for Qt to activate text-input-v3, and moarchy-keyboard
    // raises itself off that activation. Without it the field takes taps and
    // no keyboard ever appears.
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive
                                             : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: root.surface
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140 } }

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

            Ui.OpticalGlyph {
              anchors.fill: parent
              text: ""
              fontFamily: Style.font.family
              fontSize: Style.font.icon
              color: root.textOnSurface
            }
            // 38 drawn, 44 answering -- the same 3px as the Settings header,
            // and for the same reasons (docs/touch-targets.md C1).
            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(3)
              onClicked: root.dismiss()
            }
          }

          Text {
            anchors.left: backButton.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "Wi-Fi"
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: root.textWeight
            color: root.textOnSurface
          }

          // The radio switch. A pill rather than a checkbox: it is the one
          // control on this screen that is not a list row, and it has to read
          // as a switch at a glance.
          Rectangle {
            id: radioSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(52)
            height: Style.space(30)
            radius: height / 2
            color: Networking.wifiEnabled ? root.accent : root.containerHigh
            Behavior on color { ColorAnimation { duration: 120 } }

            Rectangle {
              width: parent.height - Style.space(6)
              height: width
              radius: width / 2
              y: Style.space(3)
              x: Networking.wifiEnabled ? parent.width - width - Style.space(3) : Style.space(3)
              color: Networking.wifiEnabled ? root.textOnAccent : root.textOnSurface
              Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
            // A switch is 30 tall because that is what a switch looks like,
            // and 30 is not a target (docs/touch-targets.md C5). The 7px fills
            // the 44px header it sits in and reaches past both ends of the
            // track; the only thing to its left is the title, which is text.
            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(7)
              onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            }
          }
        }

        // ---------------------------------------------------------- status
        Text {
          width: parent.width
          text: {
            if (!Networking.wifiEnabled) return "Wi-Fi is off"
            if (root.busySsid !== "") return "Joining " + root.busySsid + "…"
            if (root.rows.length === 0) return "Scanning…"
            return root.rows.length + " networks"
          }
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
          model: Networking.wifiEnabled ? root.rows : []
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            id: rowItem
            required property var modelData

            readonly property bool isExpanded: root.expandedSsid === rowItem.modelData.ssid
            readonly property bool isBusy: root.busySsid === rowItem.modelData.ssid
            readonly property bool hasError: root.errorSsid === rowItem.modelData.ssid

            width: list.width
            // Tall enough for a finger, and taller again when a drawer is open.
            height: Style.space(58)
                    + (rowItem.isExpanded
                       ? Style.space(60)
                         + (root.offersPassphrase(rowItem.modelData) ? Style.space(52) : 0)
                       : 0)
                    + (rowItem.hasError ? Style.space(30) : 0)
            Behavior on height { NumberAnimation { duration: 120 } }
            radius: Style.space(14)
            color: rowItem.isExpanded ? root.containerHigh : root.container

            Item {
              id: rowHead
              width: parent.width
              height: Style.space(58)

              Text {
                id: sig
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                text: root.signalGlyph(rowItem.modelData.signal)
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
                color: rowItem.modelData.connected ? root.accent : root.textOnSurface
              }

              Text {
                id: ssidText
                anchors.left: sig.right
                anchors.leftMargin: Style.space(14)
                anchors.right: lock.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -Style.space(7)
                text: rowItem.modelData.ssid
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: root.textWeight
                color: root.textOnSurface
              }

              Text {
                anchors.left: ssidText.left
                anchors.right: ssidText.right
                anchors.top: ssidText.bottom
                anchors.topMargin: Style.space(2)
                text: rowItem.isBusy ? "Joining…"
                    : rowItem.modelData.connected ? "Connected"
                    : rowItem.modelData.known ? "Saved"
                    : root.needsPassphrase(rowItem.modelData.security) ? "Secured"
                    : "Open"
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: rowItem.modelData.connected ? root.accent : root.subdued
              }

              Text {
                id: lock
                anchors.right: parent.right
                anchors.rightMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                text: root.needsPassphrase(rowItem.modelData.security) ? "󰌾" : ""
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: root.subdued
              }

              MouseArea {
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
            // Two rows, not one: at 360px a passphrase field, a Join and a
            // Forget do not fit on a line, and shrinking the field is the wrong
            // thing to shrink.
            Column {
              visible: rowItem.isExpanded
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(8)
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(8)

              // --- passphrase, for any secured network not connected --------
              Rectangle {
                id: passPill
                visible: root.offersPassphrase(rowItem.modelData)
                width: parent.width
                height: Style.space(44)
                radius: height / 2
                color: root.surface

                // Visible, not completed: every row builds one of these and
                // only the expanded row shows it, so registering on completion
                // would leave the last delegate built holding the slot.
                onVisibleChanged: {
                  if (visible) {
                    root.passPillItem = passPill
                    root.passFieldItem = passField
                  } else if (root.passPillItem === passPill) {
                    root.passPillItem = null
                    root.passFieldItem = null
                  }
                }
                Component.onDestruction: if (root.passPillItem === passPill) {
                  root.passPillItem = null
                  root.passFieldItem = null
                }

                // Fills its half of the pill, with the lead-in as padding
                // rather than an anchor margin (docs/touch-targets.md B1-B3).
                // Anchored by verticalCenter with verticalPadding 0 and no
                // background, this control was one line of text tall -- about
                // 20px of a 44px pill -- and the 16px lead-in was outside it as
                // well, so most of the drawn field did not take a tap. Padding
                // draws the same and is inside the hit area, and pinning it
                // stops the text shifting sideways on focus, which the base
                // type's border-width-dependent padding caused (B5).
                //
                // Left/right, not fill: the eye keeps its own 44px square (B4).
                Ui.TextField {
                  id: passField
                  anchors.left: parent.left
                  anchors.right: revealButton.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  leftPadding: Style.space(16)
                  rightPadding: Style.space(4)
                  verticalAlignment: TextInput.AlignVCenter
                  password: !root.showPassphrase
                  placeholderText: rowItem.modelData.known ? "New passphrase" : "Passphrase"
                  background: null
                  verticalPadding: 0
                  text: root.passphrase
                  onTextChanged: root.passphrase = text
                  onAccepted: root.joinRow(rowItem.modelData)
                  onActiveFocusChanged: root.passphraseFocused = activeFocus
                  // A delegate destroyed while focused never reports losing it,
                  // which would strand the surface with no bottom inset.
                  Component.onDestruction: if (activeFocus) root.passphraseFocused = false
                }

                // Reveal. Square on the field's height so the tap target is the
                // whole end of the pill rather than the glyph.
                Rectangle {
                  id: revealButton
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(44)
                  height: width
                  radius: width / 2
                  color: "transparent"
                  Text {
                    anchors.centerIn: parent
                    text: root.showPassphrase ? "󰛐" : "󰛑"   // eye / eye-off
                    font.family: Style.font.family
                    font.pixelSize: Style.font.icon
                    color: root.showPassphrase ? root.accent : root.subdued
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.showPassphrase = !root.showPassphrase
                  }
                }
              }

              // --- actions --------------------------------------------------
              Row {
                anchors.right: parent.right
                spacing: Style.space(8)
                height: Style.space(44)

                Rectangle {
                  visible: !rowItem.modelData.connected
                  width: Style.space(96)
                  height: parent.height
                  radius: height / 2
                  // A saved network can be rejoined with no passphrase typed --
                  // NetworkManager still holds one. A new secured one cannot.
                  readonly property bool ready:
                    rowItem.modelData.known
                    || !root.offersPassphrase(rowItem.modelData)
                    || root.passphrase.length >= 8
                  color: ready ? root.accent : root.containerHigh
                  opacity: ready ? 1 : 0.6
                  Text {
                    anchors.centerIn: parent
                    text: "Join"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.weight: root.textWeight
                    color: parent.ready ? root.textOnAccent : root.subdued
                  }
                  MouseArea {
                    anchors.fill: parent
                    enabled: parent.ready
                    onClicked: root.joinRow(rowItem.modelData)
                  }
                }

                Rectangle {
                  visible: rowItem.modelData.connected
                  width: Style.space(120)
                  height: parent.height
                  radius: height / 2
                  color: root.containerHigh
                  Text {
                    anchors.centerIn: parent
                    text: "Disconnect"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.weight: root.textWeight
                    color: root.textOnSurface
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.disconnectSsid(rowItem.modelData.ssid)
                  }
                }

                Rectangle {
                  visible: rowItem.modelData.known
                  width: Style.space(96)
                  height: parent.height
                  radius: height / 2
                  color: root.containerHigh
                  Text {
                    anchors.centerIn: parent
                    text: "Forget"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.weight: root.textWeight
                    color: root.textOnSurface
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.forgetSsid(rowItem.modelData.ssid)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
