// The Wi-Fi and Bluetooth tiles (docs/control-center.md S4-S6d).
//
// One widget and not two, because the pair is a row: they share a width and
// neither is half a row on its own. A user who wants only one of them has a
// row with a hole in it, which is not a thing this arrangement offers -- W7,
// the widget decides nothing about its own shape.
import QtQuick
import Quickshell.Bluetooth
import Quickshell.Networking
import qs.Commons
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

  readonly property bool available: true

  implicitHeight: row.height

  // What the tile decided, for the host's IPC verb (docs/widgets.md W14). The
  // host reads it off this instance rather than keeping its own copy, so an
  // arrangement with no connectivity in it answers `absent` instead of
  // whatever the last tap happened to leave behind.
  property string lastAction: ""

  readonly property var btAdapter: Bluetooth.defaultAdapter

  readonly property var wifiDevice: {
    var devices = Networking.devices ? Networking.devices.values : []
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].type === DeviceType.Wifi) return devices[i]
    return null
  }

  // The tiles say what they are connected to, not just on or off -- which is
  // the difference between a switch and a status panel.
  readonly property string wifiLabel: {
    if (widget.preview) return "Home"
    if (!Networking.wifiEnabled) return "Off"
    var device = widget.wifiDevice
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
    var device = widget.wifiDevice
    var networks = device && device.networks ? device.networks.values : []
    for (var i = 0; i < networks.length; i++)
      if (networks[i] && networks[i].known) return true
    return false
  }

  readonly property bool wifiStranded:
    Networking.wifiEnabled && !widget.host.airplane
    && !(widget.wifiDevice && widget.wifiDevice.connected)
    && !widget.wifiKnownInRange

  readonly property string btLabel: {
    if (widget.preview) return "Pixel Buds"
    if (!widget.btAdapter) return "No adapter"
    if (!widget.btAdapter.enabled) return "Off"
    var devices = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].connected) return String(devices[i].name || "Connected")
    return "On"
  }

  // S6, S6a, S6b, S6c. Each tile toggles a radio and holds to open the thing
  // that radio is for. Both open the same screen the matching Settings row
  // opens (`net.wifi`, `net.bluetooth`), so there is one picker behind two
  // entry points rather than two that drift.
  //
  // `host.openScreen` and never `shell.summon` directly (W5): what closing the
  // surface on the way costs is the host's question, and a host that must not
  // open a screen at all -- a lock screen -- has to be able to say no.
  function wifiTap(): string {
    if (widget.preview) return "preview"
    if (widget.host.airplane) {
      widget.lastAction = "unblock"
      if (!widget.host.dryRun) widget.host.enableRadio("wifi")
      return widget.lastAction
    }
    if (widget.wifiStranded) return widget.wifiHold()
    widget.lastAction = "toggle"
    if (!widget.host.dryRun) Networking.wifiEnabled = !Networking.wifiEnabled
    return widget.lastAction
  }

  function wifiHold(): string {
    if (widget.preview) return "preview"
    widget.host.openScreen("moarchy.wifi")
    widget.lastAction = "picker"
    return widget.lastAction
  }

  // S6c. The pair behaves the same way. No stranded case here: a Bluetooth
  // adapter with nothing paired in range is the normal resting state of one,
  // not a dead end worth re-routing the tap for.
  function btTap(): string {
    if (widget.preview) return "preview"
    if (widget.host.airplane) {
      widget.lastAction = "unblock"
      if (!widget.host.dryRun) widget.host.enableRadio("bluetooth")
      return widget.lastAction
    }
    widget.lastAction = "toggle"
    if (!widget.host.dryRun && widget.btAdapter)
      widget.btAdapter.enabled = !widget.btAdapter.enabled
    return widget.lastAction
  }

  function btHold(): string {
    if (widget.preview) return "preview"
    widget.host.openScreen("moarchy.bluetooth")
    widget.lastAction = "picker"
    return widget.lastAction
  }

  Row {
    id: row
    width: widget.width
    spacing: Style.space(8)
    readonly property int cell: Math.floor((width - spacing) / 2)

    Shared.WideTile {
      host: widget.host
      width: row.cell
      glyph: "󰤨"
      label: "Wi-Fi"
      detail: widget.wifiLabel
      on: widget.preview || Networking.wifiEnabled
      holdable: true
      onActivated: widget.wifiTap()
      onHeld: widget.wifiHold()
    }

    Shared.WideTile {
      host: widget.host
      width: row.cell
      glyph: "󰂯"
      label: "Bluetooth"
      detail: widget.btLabel
      on: widget.preview || (widget.btAdapter ? widget.btAdapter.enabled : false)
      holdable: true
      onActivated: widget.btTap()
      onHeld: widget.btHold()
    }
  }
}
