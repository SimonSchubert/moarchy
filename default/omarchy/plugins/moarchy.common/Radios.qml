// Airplane mode: one lever over every radio (docs/control-center.md S8, S9).
//
// In the kit rather than in a widget, and this is the one piece of state that
// had to be. Two widgets read it -- the Airplane tile is in `toggles`, and
// `connectivity` needs it to know whether a tap on Wi-Fi means "unblock" or
// "toggle" -- and two widgets each running their own probe would each hold
// their own answer, so tapping Airplane and then Wi-Fi would toggle a radio
// rfkill still had blocked.
//
// So the host instantiates one of these and publishes it (docs/widgets.md §C):
//
//     Shared.Radios { id: radios }
//     readonly property bool airplane: radios.airplane
//     function setAirplane(on) { radios.setAirplane(on) }
//     function enableRadio(kind) { radios.enableRadio(kind) }
//
// Airplane mode is one lever over wifi, bluetooth and the modem, which is what
// a phone means by it -- `nmcli radio` would leave bluetooth up. The user is in
// group rfkill, so none of this needs root.
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking

Item {
  id: radios

  property bool airplane: false

  // Pulled when the surface opens rather than on a timer: none of it changes
  // while the surface is shut, and a phone that forks rfkill every ten seconds
  // for a panel nobody is looking at is just a slower phone.
  function refresh(): void {
    if (!probe.running) probe.running = true
  }

  Probe {
    id: probe
    command: ["bash", "-c", "cat /sys/class/rfkill/*/soft 2>/dev/null | sort -u | tr -d '\\n'"]
    // "1" means every switch reads blocked. "0" or "01" means at least one
    // radio is live, so this is not airplane mode.
    onAnswered: radios.airplane = text.trim() === "1"
  }

  function setAirplane(on): void {
    radios.airplane = on
    Quickshell.execDetached(["rfkill", on ? "block" : "unblock", "all"])
    recheck.restart()
  }

  // S9. Turning a radio on from inside airplane mode clears airplane mode,
  // rather than leaving the tile lit and the radio dark contradicting each
  // other on screen.
  //
  // Unblocking just that one radio is enough, and is better than `unblock
  // all`: the probe calls it airplane mode only when *every* rfkill switch
  // reads blocked, so freeing one clears the state on the next read -- without
  // switching the other radios back on behind the user, which is not what
  // tapping Wi-Fi asked for.
  property string pendingRadio: ""

  function enableRadio(kind): void {
    Quickshell.execDetached(["rfkill", "unblock", kind])
    radios.pendingRadio = kind
    recheck.restart()
  }

  // The radio is switched on after the unblock has landed, not alongside it:
  // NetworkManager will refuse to enable an interface that rfkill still has
  // blocked, and the write would be silently dropped.
  Timer {
    id: recheck
    interval: 700
    onTriggered: {
      probe.running = true
      if (radios.pendingRadio === "wifi") Networking.wifiEnabled = true
      else if (radios.pendingRadio === "bluetooth" && Bluetooth.defaultAdapter)
        Bluetooth.defaultAdapter.enabled = true
      radios.pendingRadio = ""
    }
  }
}
