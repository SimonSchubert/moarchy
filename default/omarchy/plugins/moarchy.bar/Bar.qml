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
// than chosen: moarchy.shade owns the top edge with a layer-shell grab
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
import qs.Ui as Ui

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
  // Declared but read by nothing, on purpose: `configureBar` assigns it under an
  // `in` test, so dropping it would be silently accepted -- and the property is
  // the record that this bar is handed the same config upstream's is, and reads
  // nothing out of it. The one key it used to read was `transparent`.
  property var barConfig: ({})

  // ------------------------------------------------- the shell.bar contract
  //
  // Other parts of the shell reach into `shell.bar` by name, and a replacement
  // bar that omits any of this degrades something elsewhere rather than failing
  // loudly. Read directly:
  //   barSize, barHidden  notifications/Service.qml positions toasts under the bar
  //   fontFamily          notifications/Service.qml renders toast text
  //   notificationPopups  false, so notifications/Service.qml puts every
  //                       notification straight into the history the shade
  //                       lists and toasts none of them (docs/shade.md S24,
  //                       pkgbuilds/omarchy-config/notification-popups-bar-opt-out.patch)
  // Called behind a typeof guard, so a missing one is survivable but leaves the
  // caller returning "no-bar" forever:
  //   summonBarWidget / hideBarWidget / isBarWidgetOpen   shell.summon routing
  //   panelWidgetIdAt                                     togglePanelAt IPC
  //   debugBarGeometry                                    debug IPC
  // Deliberately absent, so `omarchy-shell shell toggleBarTransparency` answers
  // "no-bar" and stops there:
  //   toggleTransparency                                  omarchy-shell IPC
  // Ours, not upstream's, called by the Settings battery-percentage switch
  // through `omarchy-shell -q bar syncFlags`:
  //   syncFlags                                           re-read the toggle flags
  readonly property int barSize: Style.bar.sizeHorizontal
  readonly property string position: "top"
  readonly property string fontFamily: Style.font.family

  // Constant, and readonly to keep it that way. `bar-off` was a Settings switch
  // and a $mod+Shift+space binding until 2026-09-08, and neither ever moved the
  // bar: both flipped the flag and then told `omarchy.bar` -- upstream's plugin
  // id, and upstream's bar is the one this phone replaces -- to re-read it, so
  // every attempt answered "Target not found" behind a `-q`. The row went rather
  // than the name being fixed: the shade's grab strip owns the top edge whether
  // or not this draws, so a hidden bar leaves 26px still eating drags with
  // nothing on screen to say why, and the switch that undid it lived inside the
  // screen it had just made harder to reach. docs/settings.md C4a.
  //
  // Reading no flag also means a phone left with `bar-off` set comes back with
  // its bar. The property stays because the shell.bar contract is read by name:
  // notifications/Service.qml drops toasts to the top of the screen when it is
  // true, and a bar that omits it is a bar with no toast offset.
  readonly property bool barHidden: false

  // S24. No toasts: a phone reads its notifications in the shade, and a toast
  // here is an Overlay surface across the top of every app and every sheet
  // that takes their touches until it expires -- which upstream's first-run
  // ones never do. Every notification goes to the history instead, whatever
  // its urgency, and the bell below says one is waiting.
  //
  // Read by the patched notifications/Service.qml. Pointing `bar.id` back at
  // `omarchy.bar` brings the toasts back with the rest of the desktop.
  readonly property bool notificationPopups: false

  // This bar hosts no widgets at all, so every widget-routing call has exactly
  // one honest answer. Returning false (rather than omitting the function) is
  // what makes shell.summon log "no live bar widget for: x" instead of throwing.
  function summonBarWidget(id: string): bool { return false }
  function hideBarWidget(id: string): bool { return false }
  function isBarWidgetOpen(id: string): bool { return false }
  function panelWidgetIdAt(section: string, index: string): string { return "" }
  function debugBarGeometry(): var { return [] }

  // `omarchy-toggle battery-percentage-off` flips a flag file, and this is how
  // the bar learns it moved. Two ways in, because either alone has a hole:
  //
  //   The directory watch catches every writer -- the Settings row, the CLI, a
  //   hand-run `omarchy-toggle` over ssh -- without anybody having to know this
  //   plugin exists. The parent directory, not the file: FileView cannot watch a
  //   path that does not exist yet, and a flag file is created and deleted
  //   rather than edited.
  //
  //   syncFlags is the nudge for when it misses one. Upstream's own bar carries
  //   the same pair for the same reason: flag changes landing in quick
  //   succession can stop the watch delivering, and there the symptom was a bar
  //   stranded off screen until the shell restarted.
  //
  // Read as a file test rather than through omarchy-toggle-enabled so a shell
  // started with a short PATH answers from an actual test rather than from a
  // 127 that looks exactly the same.
  property bool batteryPercentShown: true

  readonly property string togglesDir:
    (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    + "/omarchy/toggles"

  Process {
    id: flagProbe
    running: true
    command: ["bash", "-c",
      "[[ -f \"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/battery-percentage-off\" ]] " +
      "&& echo pct=off || echo pct=on"]
    stdout: StdioCollector {
      onStreamFinished: root.batteryPercentShown = String(text || "").indexOf("pct=on") >= 0
    }
  }

  // printErrors off because the directory is absent on a phone that has never
  // toggled anything, and that is not a fault worth a line in the journal.
  FileView {
    path: root.togglesDir
    watchChanges: true
    printErrors: false
    onFileChanged: flagProbe.running = true
  }

  // ------------------------------------------------------------- appearance
  readonly property color background: Color.bar.background
  readonly property color foreground: Color.bar.text
  readonly property color dim: Util.alpha(Color.bar.text, 0.55)
  readonly property int edgePad: Style.space(8)

  // DemiBold, not Regular. Light text on a dark bar reads thinner than it
  // measures, and at 12px on the one surface that is always on screen that
  // showed as a clock you had to look at twice.
  //
  // Measured on the device rather than guessed, against the same string at the
  // same minute: Medium puts 15% more ink on the panel than Regular and
  // DemiBold 47%, and at this size 15% is not a change anyone notices -- the
  // two captures were indistinguishable side by side. DemiBold is where "a bit
  // thicker" actually lands.
  //
  // Both are real faces (`JetBrainsMono NF Medium`, `SemiBold`), installed
  // alongside Regular, so this picks a different font file rather than
  // synthesising an embolden -- which at 12px only thickens the antialiasing.
  readonly property int textWeight: Font.DemiBold

  // Glyphs match the clock's size rather than sitting a point under it. At
  // iconSmall the right-hand side read as a footnote to the left-hand side;
  // the two ends of a status bar should carry the same weight.
  readonly property int iconSize: Style.font.body

  // Each glyph gets a fixed square slot, and the gap is what is left between
  // slots. Two things that fixes, neither of which a constant `spacing` could:
  //
  //   Advance widths differ per glyph in a Nerd Font -- the wifi fan is wider
  //   than the bluetooth rune -- so one spacing value produced visibly uneven
  //   gaps. Equal slots make equal gaps.
  //
  //   The painted glyph is rarely centred inside its own advance, so even equal
  //   slots would have looked ragged. Ui.OpticalGlyph re-centres on the painted
  //   bounds -- horizontally only, and that restraint is the point: correcting
  //   vertically too drifts each glyph off the shared baseline, and a shared
  //   baseline is what actually makes a row of icons look level.
  readonly property int glyphSlot: Math.round(root.iconSize * 1.35)
  readonly property int glyphGap: Style.space(4)

  component StatusGlyph: Ui.OpticalGlyph {
    width: root.glyphSlot
    height: root.glyphSlot
    fontFamily: Style.font.family
    fontSize: root.iconSize
    color: root.foreground
    visible: text !== ""
  }

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

  // S26. What is waiting in the shade, counted off the history directory.
  //
  // It used to be `notifications.popupModel.count` -- what is on screen right
  // now -- and S24 leaves that permanently empty: with no toasts there is
  // never a live popup to count, so the one state worth showing in a bar with
  // nothing under it would have been invisible. The service writes one .json
  // per notification into this directory and removes it on dismissal, so the
  // count is the list the shade shows.
  //
  // The service's own path, which does not read XDG_STATE_HOME.
  readonly property string historyDir:
    Quickshell.env("HOME") + "/.local/state/omarchy/notifications/history"

  property int historyCount: 0
  readonly property bool bellShown: !root.dnd && root.historyCount > 0

  // The directory is made before it is watched: FileView cannot watch a path
  // that does not exist, and on a first boot this runs before the service has
  // made it. So the watch is armed by the first count, not before.
  property bool historyWatched: false

  Process {
    id: historyProbe
    running: true
    command: ["bash", "-c", "mkdir -p \"$1\" && ls -1 \"$1\" | grep -c '\\.json$'", "--", root.historyDir]
    stdout: StdioCollector {
      onStreamFinished: {
        // grep -c with no match exits 1 and prints 0, which is the count we
        // want -- but `set -e` semantics elsewhere have made that exit code
        // look like a failure before now, so the number is read and nothing
        // reads the status.
        var n = parseInt(String(text || "").trim(), 10)
        root.historyCount = isFinite(n) ? n : 0
        root.historyWatched = true
      }
    }
  }

  // Debounced: Clear all, and the service's own history trim, touch several
  // files in one burst.
  Timer {
    id: historyRecount
    interval: 150
    onTriggered: {
      if (historyProbe.running) historyRecount.restart()
      else historyProbe.running = true
    }
  }

  FileView {
    path: root.historyWatched ? root.historyDir : ""
    watchChanges: true
    printErrors: false
    onFileChanged: historyRecount.restart()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  // Proof that this file loaded, which nothing else on the phone can give.
  // shell.json's `bar.id` still names this plugin when its QML fails to
  // compile, so `omarchy-shell shell listPlugins` goes on reporting it active
  // while the host has quietly fallen back to omarchy.bar and the surface draws
  // nothing. An answer here comes from an instantiated component or not at all.
  //
  // The metrics are the ones that decide how the bar looks, so a regression in
  // any of them is a failing check rather than a screenshot nobody takes.
  IpcHandler {
    target: "bar"

    // `pct` rather than `hidden`: the bar cannot be hidden any more, and this
    // is the one thing about it a setting still changes -- so it is the one
    // thing worth being able to ask about from outside. docs/settings.md C4
    // checks the switch against this string.
    function metrics(): string {
      return "height=" + root.barSize
           + " icon=" + root.iconSize
           + " slot=" + root.glyphSlot
           + " gap=" + root.glyphGap
           + " weight=" + root.textWeight
           + " pct=" + (root.batteryPercentShown ? "on" : "off")
           // S26, and the only way to ask: the bell is a glyph in a layer
           // surface, so a screenshot is the alternative.
           + " dnd=" + (root.dnd ? "on" : "off")
           + " bell=" + (root.bellShown ? "shown" : "none")
           + " history=" + root.historyCount
    }

    // Declared here, not just on the root item: a function the root happens to
    // own is not reachable over IPC, and `omarchy-shell bar <it>` answers
    // "Function not found" -- which behind the `-q` a settings row uses is
    // indistinguishable from success. That was half of the bug this replaced.
    //
    // Start rather than restart, as upstream does: a probe already in flight
    // was launched by the directory watch after the same flag moved, so its
    // answer is current, and killing it here can swallow the result entirely.
    function syncFlags(): string {
      flagProbe.running = true
      return "ok"
    }
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
        // Opaque, and `bar.transparent` in shell.json is ignored on purpose:
        // the only thing that writes that flag is `omarchy-bar transparent`,
        // whose config reload takes this bar down and leaves upstream's in its
        // place. Honouring a flag we refuse to let anything set would only
        // strand a phone whose shell.json still carries it from before.
        color: root.background
        surfaceFormat.opaque: false

        WlrLayershell.namespace: "moarchy-bar"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Reserved, not floating: an app that draws under the status bar has
        // its first line of text hidden, and on a phone that is usually the
        // only heading on screen. Unconditional since the bar stopped being
        // hideable (barHidden, above) -- there is no state in which this
        // surface is on screen and not reserving its own height.
        exclusionMode: ExclusionMode.Auto

        // ---------------------------------------------------------- left
        Row {
          anchors.left: parent.left
          anchors.leftMargin: root.edgePad
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.glyphGap

          Text {
            anchors.verticalCenter: parent.verticalCenter
            // H, not HH: a phone clock reads "0:06", not "00:06". The padded
            // form is a desktop habit that comes from wanting a fixed-width
            // clock in a centre-anchored bar; this bar is anchored left, so
            // nothing moves when the hour loses a digit.
            text: Qt.formatDateTime(clock.date, "H:mm")
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: root.textWeight
            color: root.foreground
          }

          // S26. One of these at a time, never both: silenced says only that
          // you asked not to be told, and the list still fills underneath it.
          //
          // The bell replaced a 5px dot when the toasts went (S24). A dot was
          // the right weight while it meant "and there is one on screen right
          // now"; as the only indication a notification exists at all it was
          // too quiet to find, and the count it drew is the same count, so
          // nothing is lost by drawing the glyph the shade's own list is full
          // of instead.
          StatusGlyph {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.dnd
            text: "󰂛"
            color: root.dim
          }

          StatusGlyph {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.bellShown
            text: "󰂚"
          }
        }

        // --------------------------------------------------------- right
        Row {
          anchors.right: parent.right
          anchors.rightMargin: root.edgePad
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.glyphGap

          StatusGlyph {
            anchors.verticalCenter: parent.verticalCenter
            text: root.cellGlyph
            color: root.simMissing ? root.dim : root.foreground
          }

          StatusGlyph {
            anchors.verticalCenter: parent.verticalCenter
            text: root.wifiGlyph
          }

          StatusGlyph {
            anchors.verticalCenter: parent.verticalCenter
            text: root.btGlyph
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.batteryPresent
            // No spacing: the glyph's slot already carries its own padding, and
            // adding more here detached the percentage from the battery it
            // belongs to -- the pair should read as one item against the
            // glyphGap that separates it from bluetooth.
            spacing: 0

            StatusGlyph {
              anchors.verticalCenter: parent.verticalCenter
              text: root.batteryGlyph
              color: root.batteryLow ? Color.bar.active : root.foreground
            }

            // Shown unless turned off, so this changes nothing until asked.
            // The flag is `battery-percentage-off` rather than
            // `battery-percentage` for that reason -- same negative polarity as
            // screensaver-off and suspend-off, where the file existing means
            // the feature is off. Upstream's own row for this drives a
            // desktop-bar widget we never instantiate.
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.batteryPercentShown
              text: root.batteryPercent + "%"
              font.family: Style.font.family
              // bodySmall, not caption: next to a Medium clock at body size, a
              // 10px percentage read as a different bar's worth of text.
              font.pixelSize: Style.font.bodySmall
              font.weight: root.textWeight
              color: root.batteryLow ? Color.bar.active : root.foreground
            }
          }
        }
      }
    }
  }
}
