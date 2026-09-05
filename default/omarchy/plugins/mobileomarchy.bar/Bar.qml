// The phone status bar.
//
// ---------------------------------------------------------------------------
// Why a whole bar rather than a different widget list
// ---------------------------------------------------------------------------
// The desktop bar is a general-purpose widget host: drag-to-rearrange, hover
// peek, per-widget popouts, tooltips, drag ghosts on every screen. All of that
// is ~1800 lines serving a pointer that this device does not have, and none of
// it survives contact with a 360px-wide screen -- upstream's default layout
// puts thirteen widgets in that space.
//
// The shell already supports swapping the whole bar out: shell.json's `bar.id`
// picks any plugin declaring kind "bar", and `omarchy.bar` steps aside
// (shell.qml, activeBarId). So this is a plugin, not a patch.
//
// ---------------------------------------------------------------------------
// Why nothing here is tappable
// ---------------------------------------------------------------------------
// Android's status bar is not tappable either, and here that is forced rather
// than chosen: mobileomarchy.shade owns the top edge with a layer-shell grab
// strip on Overlay so a downward drag anywhere along the bar opens the shade.
// Overlay outranks this surface's Top, so a tap here would never arrive. Rather
// than fight for it, this surface draws and nothing else -- no HoverHandler, no
// TapHandler, keyboardFocus None.
//
// ---------------------------------------------------------------------------
// Where the numbers come from
// ---------------------------------------------------------------------------
// Battery, wifi and bluetooth all come from Quickshell's own services, so they
// are event-driven and cost nothing at rest. Only the modem is polled, because
// ModemManager has no Quickshell binding -- and it backs off hard when there is
// no SIM to report on. See modemPoll.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.UPower
import qs.Commons

Item {
  id: root

  // ------------------------------------------------------------- injected
  //
  // shell.qml's configureBar() assigns each of these by name. NOT `readonly`,
  // any of them: the assignment throws against a read-only declaration and the
  // whole plugin fails to load, silently, with the host falling back to
  // omarchy.bar. Same trap the gestures plugin documents.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
                               || (Quickshell.env("HOME") + "/.local/share/omarchy")
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var barConfig: ({})

  // ------------------------------------------------- the shell.bar contract
  //
  // Other parts of the shell reach into `shell.bar` by name, and a replacement
  // bar that omits any of this degrades something elsewhere rather than failing
  // loudly. Read directly:
  //   barSize, barHidden  notifications/Service.qml positions toasts under the bar
  //   fontFamily          notifications/Service.qml renders toast text
  // Called behind a typeof guard, so a missing one is survivable but leaves the
  // caller returning "no-bar" forever:
  //   summonBarWidget / hideBarWidget / isBarWidgetOpen   shell.summon routing
  //   toggleTransparency                                  omarchy-shell IPC
  //   panelWidgetIdAt                                     togglePanelAt IPC
  //   debugBarGeometry                                    debug IPC
  // Ours, not upstream's, called by bin/mobileomarchy-toggle-bar:
  //   syncHidden                                          re-read the bar-off flag
  readonly property int barSize: Style.bar.sizeHorizontal
  property bool barHidden: false
  readonly property string position: "top"
  readonly property string fontFamily: Style.font.family
  // Bound, not assigned. `omarchy-bar transparent` commits to shell.json and the
  // host re-assigns barConfig, so the config is the single source of truth.
  // This was a plain `property bool transparent: false`, which meant the write
  // landed in the file and the bar never changed -- and a settings switch
  // reading the file then disagreed with one reading the bar.
  property bool transparent: root.barConfig && root.barConfig.transparent === true

  // This bar hosts no widgets at all, so every widget-routing call has exactly
  // one honest answer. Returning false (rather than omitting the function) is
  // what makes shell.summon log "no live bar widget for: x" instead of throwing.
  function summonBarWidget(id: string): bool { return false }
  function hideBarWidget(id: string): bool { return false }
  function isBarWidgetOpen(id: string): bool { return false }
  function panelWidgetIdAt(section: string, index: string): string { return "" }
  function debugBarGeometry(): var { return [] }
  // Writes through to the config instead of assigning `transparent`, which would
  // break the binding above and strand the bar on whatever it happened to be.
  // omarchy-bar only mutates shell.json -- it never calls back into the shell --
  // so there is no loop here.
  function toggleTransparency(): void {
    Quickshell.execDetached(["omarchy-bar", "transparent", "toggle"])
  }

  // barHidden is what the shell.bar contract exposes and what the exclusive zone
  // and top margin read, and until now nothing ever set it. `omarchy-toggle
  // bar-off` flips a flag file; this is how the bar learns the flag moved.
  //
  // Read as a file test rather than through omarchy-toggle-enabled so a shell
  // started with a short PATH answers "shown" from an actual test rather than
  // from a 127 that looks the same.
  function syncHidden(): string {
    hiddenProbe.running = true
    return "ok"
  }

  Process {
    id: hiddenProbe
    running: true
    command: ["bash", "-c",
      "[[ -f \"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/bar-off\" ]] " +
      "&& echo hidden || echo shown"]
    stdout: StdioCollector {
      onStreamFinished: root.barHidden = String(text || "").trim() === "hidden"
    }
  }

  // ------------------------------------------------------------- appearance
  readonly property color background: Color.bar.background
  readonly property color foreground: Color.bar.text
  readonly property color dim: Util.alpha(Color.bar.text, 0.55)
  readonly property int edgePad: Style.space(8)
  readonly property int glyphGap: Style.space(7)

  // ------------------------------------------------------------- battery
  //
  // UPower.displayDevice is the aggregate the desktop bar uses too, so the
  // glyph ramps below are lifted verbatim from plugins/panels/power/Model.js --
  // a phone that charges should look like the rest of Omarchy, not like a
  // second icon set.
  readonly property var batteryDevice: UPower.displayDevice
  readonly property bool batteryPresent: batteryDevice && batteryDevice.isPresent
  readonly property real batteryFraction: batteryPresent ? Number(batteryDevice.percentage || 0) : 0
  readonly property int batteryPercent: Math.round(root.batteryFraction * 100)
  readonly property bool charging: !UPower.onBattery

  readonly property string batteryGlyph: {
    if (!root.batteryPresent) return ""
    var charge = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
    var drain  = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    var i = Math.max(0, Math.min(9, Math.floor(root.batteryFraction * 10)))
    if (root.batteryDevice.state === UPowerDeviceState.FullyCharged) return "󰂅"
    return root.charging ? charge[i] : drain[i]
  }

  // Below this the percentage goes urgent. Matches the battery service's own
  // low-battery notification threshold so the bar and the toast agree.
  readonly property bool batteryLow: root.batteryPresent && !root.charging && root.batteryPercent <= 10

  // ------------------------------------------------------------- wifi
  //
  // Quickshell.Networking is event-driven off NetworkManager, so this costs
  // nothing between state changes -- which is the whole reason not to poll
  // omarchy-network-status here the way the desktop network panel does.
  readonly property var wifiDevice: {
    var devices = Networking.devices ? Networking.devices.values : []
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].type === DeviceType.Wifi) return devices[i]
    return null
  }

  readonly property real wifiStrength: {
    var device = root.wifiDevice
    if (!device || !device.connected) return -1
    var networks = device.networks ? device.networks.values : []
    for (var i = 0; i < networks.length; i++) {
      if (!networks[i] || !networks[i].connected) continue
      var raw = Number(networks[i].signalStrength)
      if (!isFinite(raw)) return 0
      // The binding reports a double whose scale is not documented; treat
      // anything at or below 1 as a fraction rather than a dead signal.
      return raw <= 1 ? raw * 100 : raw
    }
    return 0
  }

  readonly property string wifiGlyph: {
    if (!root.wifiDevice) return ""
    if (!Networking.wifiEnabled) return "󰤮"
    if (root.wifiStrength < 0) return "󰤯"
    var ramp = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    return ramp[Math.max(0, Math.min(4, Math.ceil(root.wifiStrength / 20) - 1))]
  }

  // ------------------------------------------------------------- bluetooth
  //
  // Hidden entirely when the adapter is off, the way a phone does it: an
  // always-lit "bluetooth is off" glyph is a permanent 12px of nothing on a
  // 360px bar.
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool btOn: root.btAdapter && root.btAdapter.enabled
  readonly property bool btConnected: {
    if (!root.btOn) return false
    var devices = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].connected) return true
    return false
  }
  readonly property string btGlyph: !root.btOn ? "" : (root.btConnected ? "󰂱" : "󰂯")

  // ------------------------------------------------------------- cellular
  //
  // ModemManager has no Quickshell binding, so this is the one polled value on
  // the bar. `sim-missing` is the steady state on a phone with no SIM, and
  // polling a modem that has nothing to say every 20s for the life of the
  // session is pure waste -- so the poll backs off to two minutes and the glyph
  // disappears rather than sitting there as a permanent zero-bars scold.
  property string modemState: ""
  property string modemFailedReason: ""
  property int modemSignal: -1

  readonly property bool simMissing: root.modemFailedReason === "sim-missing"
  readonly property bool modemUsable: root.modemState !== "" && !root.simMissing

  readonly property string cellGlyph: {
    if (root.modemState === "") return ""       // no modem at all: draw nothing
    if (root.simMissing) return "󰓥"
    if (root.modemState === "failed" || root.modemState === "disabled") return "󰞃"
    if (root.modemSignal < 0) return "󰣂"
    var ramp = ["󰣂", "󰢿", "󰣀", "󰣁"]
    return ramp[Math.max(0, Math.min(3, Math.ceil(root.modemSignal / 25)))]
  }

  Process {
    id: modemProbe
    command: ["mmcli", "-m", "any", "--output-keyvalue"]
    stdout: StdioCollector {
      onStreamFinished: {
        var state = ""
        var reason = ""
        var signal = -1
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split(":")
          if (parts.length < 2) continue
          var key = parts[0].trim()
          var value = parts.slice(1).join(":").trim()
          if (key === "modem.generic.state") state = value
          else if (key === "modem.generic.state-failed-reason") reason = value
          else if (key === "modem.generic.signal-quality.value") signal = parseInt(value, 10)
        }
        root.modemState = state
        root.modemFailedReason = reason === "--" ? "" : reason
        root.modemSignal = isFinite(signal) ? signal : -1
      }
    }
    // mmcli exits non-zero with no modem present, and StdioCollector still
    // fires with empty text -- which clears modemState and hides the glyph.
    // That is the behaviour we want, so there is nothing to handle here.
  }

  Timer {
    id: modemPoll
    interval: root.modemUsable ? 20000 : 120000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!modemProbe.running) modemProbe.running = true
  }

  // ------------------------------------------------------------- notifications
  //
  // Reached through the host rather than by importing the service: relative
  // imports do not share singleton state, so a second import would hand this
  // bar its own empty copy. shell.serviceFor is the supported way in.
  readonly property var notifications: root.shell && typeof root.shell.serviceFor === "function"
    ? root.shell.serviceFor("omarchy.notifications") : null
  readonly property bool dnd: root.notifications ? root.notifications.doNotDisturb === true : false
  readonly property int pendingCount: root.notifications && root.notifications.popupModel
    ? root.notifications.popupModel.count : 0

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: barWindow

        required property var modelData
        screen: modelData

        anchors { top: true; left: true; right: true }
        implicitHeight: root.barSize
        color: root.transparent ? "transparent" : root.background
        surfaceFormat.opaque: false

        WlrLayershell.namespace: "mobileomarchy-bar"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Reserved, not floating: an app that draws under the status bar has
        // its first line of text hidden, and on a phone that is usually the
        // only heading on screen.
        exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Auto
        margins.top: root.barHidden ? -root.barSize : 0

        // ---------------------------------------------------------- left
        Row {
          anchors.left: parent.left
          anchors.leftMargin: root.edgePad
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            // H, not HH: a phone clock reads "0:06", not "00:06". The padded
            // form is a desktop habit that comes from wanting a fixed-width
            // clock in a centre-anchored bar; this bar is anchored left, so
            // nothing moves when the hour loses a digit.
            text: Qt.formatDateTime(clock.date, "H:mm")
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: root.foreground
          }

          // Silenced is worth a glyph; a pending count is worth a dot. Drawing
          // the count itself would need a second font metric on a bar that has
          // room for one.
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.dnd
            text: "󰂛"
            font.family: Style.font.family
            font.pixelSize: Style.font.iconSmall
            color: root.dim
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.dnd && root.pendingCount > 0
            width: Style.space(5)
            height: width
            radius: width / 2
            color: Color.bar.active
          }
        }

        // --------------------------------------------------------- right
        Row {
          anchors.right: parent.right
          anchors.rightMargin: root.edgePad
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.glyphGap

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            text: root.cellGlyph
            font.family: Style.font.family
            font.pixelSize: Style.font.iconSmall
            color: root.simMissing ? root.dim : root.foreground
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            text: root.wifiGlyph
            font.family: Style.font.family
            font.pixelSize: Style.font.iconSmall
            color: root.foreground
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            text: root.btGlyph
            font.family: Style.font.family
            font.pixelSize: Style.font.iconSmall
            color: root.foreground
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.batteryPresent
            spacing: Style.space(3)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.batteryGlyph
              font.family: Style.font.family
              font.pixelSize: Style.font.iconSmall
              color: root.batteryLow ? Color.bar.active : root.foreground
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.batteryPercent + "%"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: root.batteryLow ? Color.bar.active : root.foreground
            }
          }
        }
      }
    }
  }
}
