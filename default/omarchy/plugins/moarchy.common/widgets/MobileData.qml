// The mobile data tile (docs/control-center.md S29-S29d).
//
// Full width, and that is the shape rather than a default. A third half-width
// cell beside Wi-Fi and Bluetooth leaves a hole, and a fifth SMALL tile does
// not fit: the toggles row's label has no width and no elide, so a fifth cell
// makes "Airplane" spill into its neighbour. This tile also has a second line
// genuinely worth reading -- the operator, or the reason there is no data --
// which is the wide tile's shape and not the small one's.
import QtQuick
import Quickshell
import ".." as Shared

Item {
  id: widget

  property var host: null
  property var shell: null

  // W37. Drawn in the Settings arrangement list rather than on the surface.
  // The values are canned and every action is a no-op: the list is a list of
  // real widgets, so without this, arranging them would toggle the radio,
  // move the brightness and open screens from inside a settings page.
  property bool preview: false

  // S29, and W6's general form. Absent, not disabled, where NetworkManager
  // sees no gsm device at all -- the row is not there and the column closes
  // the gap.
  readonly property bool available: widget.preview || widget.dataSeen

  implicitHeight: tile.height

  property string lastAction: ""

  // S29d. The one tile whose whole state comes out of a moarchy script.
  // Quickshell.Networking knows about wifi devices and nothing else, and the
  // two writes need root -- NetworkManager's settings.modify.system is
  // auth_admin, and a polkit prompt raised from a sheet would land on top of
  // the sheet that asked for it.
  property bool dataPresent: false
  // Latched, and the latch is the point. Switching data on can make
  // ModemManager re-enumerate -- one off/on took this modem from Modem/1 to
  // Modem/0 -- and NetworkManager has no gsm device at all for a few seconds
  // either side of that. Bound straight to dataPresent, the tile disappeared
  // from under the finger that had just tapped it and came back a moment
  // later. Having a modem is a fact about the hardware, so it is remembered
  // rather than re-asked: a phone with none never sets this, and a phone whose
  // modem has gone keeps a tile that says "Not connected", which is the better
  // of the two wrong answers (S29).
  property bool dataSeen: false
  property bool dataEnabled: false
  property bool dataConnected: false
  property bool dataLocked: false
  property bool dataSimMissing: false
  property string dataOperator: ""

  // Absolute, and moarchy.sim/Sim.qml's own header has the whole reason: a
  // shell restarted from anywhere but a login session comes up without
  // /usr/lib/moarchy/bin on PATH, a Process that cannot find its binary does
  // not throw, and the StdioCollector still fires with empty text. A bare name
  // here would leave this tile absent on precisely the phones that have a
  // modem, with one line in the shell log to say why.
  readonly property string dataTool: "/usr/lib/moarchy/bin/moarchy-data"

  // S29a. S4's ordering discipline, applied to the other radio: what is wrong
  // first, then what is connected, then the bare fact that it is on. "SIM
  // locked" is the line this phone shows on every boot -- the SIM re-locks at
  // power-on and nothing but the keypad can answer it (docs/devices.md D33).
  readonly property string dataLabel:
    widget.preview ? "Vodafone"
    : !widget.dataEnabled ? "Off"
    : widget.dataSimMissing ? "No SIM"
    : widget.dataLocked ? "SIM locked"
    : widget.dataConnected ? (widget.dataOperator !== "" ? widget.dataOperator : "Connected")
    : "Not connected"

  function refresh(): void {
    if (widget.preview) return
    if (!probe.running) probe.running = true
  }

  Component.onCompleted: widget.refresh()

  Shared.Probe {
    id: probe
    command: [widget.dataTool, "status"]
    onAnswered: {
      var lines = text.trim().split("\n")
      // A one-line answer is a script that did not run -- an empty text is
      // what a Process that failed to start hands back, and blanking the tile
      // on that would hide mobile data on a working phone. Leave what was
      // there and let the next open ask again.
      if (lines.length < 2) return
      var kv = ({})
      for (var i = 0; i < lines.length; i++) {
        var at = lines[i].indexOf("=")
        if (at > 0) kv[lines[i].slice(0, at)] = lines[i].slice(at + 1)
      }
      widget.dataPresent = kv.present === "yes"
      if (widget.dataPresent) widget.dataSeen = true
      widget.dataEnabled = kv.enabled === "yes"
      widget.dataConnected = kv.connected === "yes"
      widget.dataLocked = kv.locked === "yes"
      widget.dataSimMissing = kv.sim === "missing"
      widget.dataOperator = kv.operator ? kv.operator : ""
    }
  }

  // Optimistic, then read back 700ms later: the same shape and the same reason
  // as airplane. moarchy-data returns in well under a second even against a
  // locked SIM -- it passes nmcli --wait 0 rather than sitting out the 90s
  // secrets timeout -- but what it returns to is a state still settling, which
  // is why the tile draws `enabled` (the setting) and not `connected` (S29).
  // moarchy-data writes the profile's autoconnect too, which is what makes an
  // `off` survive a reboot (S29c).
  function set(on): void {
    widget.dataEnabled = on
    Quickshell.execDetached([widget.dataTool, on ? "on" : "off"])
    recheck.restart()
  }

  Timer { id: recheck; interval: 700; onTriggered: probe.running = true }

  // S29b. A tap on a locked SIM opens the keypad rather than toggling, which is
  // S6a's reasoning reached for the second time: the switch is a dead end
  // while the SIM is locked. Turning data off changes nothing anybody can see,
  // turning it on cannot connect, and the keypad is the only thing on this
  // phone that gets you from here to online.
  function tap(): string {
    if (widget.preview) return "preview"
    if (widget.dataLocked) return widget.hold()
    widget.lastAction = "toggle"
    if (!widget.host.dryRun) widget.set(!widget.dataEnabled)
    return widget.lastAction
  }

  // S29b. Held, it is the keypad whatever the SIM is doing -- the same "hold
  // for the thing the radio is for" as the two tiles above (S6, S6c).
  function hold(): string {
    if (widget.preview) return "preview"
    widget.host.openScreen("moarchy.sim")
    widget.lastAction = "picker"
    return widget.lastAction
  }

  // The glyph is md-network_strength_4, held at full strength the way the
  // Wi-Fi tile holds md-wifi_strength_4 -- the tile says whether data is ON,
  // and the bar is where strength is drawn.
  //
  // Picked by reading the font's cmap and NOT by copying a neighbour, which is
  // how this arrived at an icon of two arrows: the glyphs are not in
  // omarchy.ttf at all but in JetBrainsMono Nerd Font, by fontconfig fallback,
  // and the Nerd Font's Material range does not sit where moarchy.bar's
  // comments say it does. U+F08C1, the top of the bar's own signal ramp, is
  // md-swap_horizontal_variant there.
  Shared.WideTile {
    id: tile
    host: widget.host
    width: widget.width
    glyph: "󰣺"
    label: "Mobile data"
    detail: widget.dataLabel
    on: widget.preview || widget.dataEnabled
    holdable: true
    onActivated: widget.tap()
    onHeld: widget.hold()
  }
}
