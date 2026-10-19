// The quick toggles (docs/control-center.md S7-S11, docs/widgets.md §E).
//
// One widget and not one per tile, for the reason the radio pair is one: the
// row divides a width between the tiles that are showing, so a tile on its own
// is not a row. What the user arranges here is which tiles and in what order --
// the same catalogue/order/on-off shape as the widgets themselves, resolved by
// the same code, under the key `quick_toggles`.
//
// Four of the tiles are wired in QML because their state is something the shell
// already holds: do-not-disturb, rfkill, the flash LED, the compositor's
// transform. The rest are a `read` that prints true/false and two commands, so
// adding a fifth is a row in the catalogue and no QML at all -- which is why
// the catalogue carries the commands rather than this file carrying a switch
// with eight arms.
import QtQuick
import Quickshell
import qs.Commons
import ".." as Shared
import "../Widgets.js" as Catalogue

Item {
  id: widget

  property var host: null
  property var shell: null
  property bool preview: false

  readonly property bool available: true

  implicitHeight: grid.height

  readonly property var notifications: widget.shell && typeof widget.shell.serviceFor === "function"
    ? widget.shell.serviceFor("omarchy.notifications") : null

  // Its own watch on the arrangement file. The host's column has one too, and
  // two FileViews on one small path is cheaper than threading the text down
  // through a property that every other widget would carry and ignore.
  Shared.WidgetsFile { id: arrangement }

  // The tiles that are on, in the user's order. In preview this is the same
  // list -- the Settings page arranges the real thing, so it has to show the
  // real thing.
  readonly property var tiles: arrangement.shown("quick-toggles")

  property bool torchAvailable: false
  property bool torchOn: false

  // Every shell-backed tile's state, by id, as the probes answer. A map and
  // not a property apiece so a ninth toggle needs no property.
  property var shellState: ({})

  function refresh(): void {
    if (widget.preview) return
    if (!torchProbe.running) torchProbe.running = true
    for (var i = 0; i < readers.count; i++) {
      var r = readers.itemAt(i)
      if (r) r.reread()
    }
  }

  Component.onCompleted: widget.refresh()

  // S10. The flash LED is root:feedbackd 0664 and feedbackd is an empty group
  // on a bare install, so the tile is dead until install/session.sh has added
  // the user and they have logged in again. Probe rather than assume: a tile
  // that is drawn but does nothing is worse than one that is not drawn.
  Shared.Probe {
    id: torchProbe
    command: ["bash", "-c", "[ -w /sys/class/leds/white:flash/brightness ] && cat /sys/class/leds/white:flash/brightness || echo unavailable"]
    onAnswered: {
      var out = text.trim()
      widget.torchAvailable = out !== "unavailable" && out !== ""
      widget.torchOn = widget.torchAvailable && out !== "0"
    }
  }

  // One probe per shell-backed tile that is actually on. A tile the user has
  // not added costs nothing, which is the point of arranging them: this used to
  // be four fixed tiles and a fifth would have been a fifth fork on every open
  // whether or not anybody wanted it.
  Repeater {
    id: readers
    model: widget.preview ? [] : widget.tiles
    // `reader.def`, never `parent.def`: a Probe is a Process and therefore a
    // QObject, so it has no visual parent to reach back through -- the
    // binding would simply be undefined and every shell-backed tile would
    // read its state from `true`.
    delegate: Item {
      id: reader
      required property string modelData
      readonly property var def: Catalogue.entry("quick-toggles", reader.modelData)
      function reread() {
        if (reader.def && reader.def.read && !probe.running) probe.running = true
      }
      Component.onCompleted: reader.reread()
      Shared.Probe {
        id: probe
        command: ["bash", "-lc", (reader.def && reader.def.read) ? reader.def.read : "true"]
        onAnswered: {
          if (!reader.def || !reader.def.read) return
          var next = ({})
          for (var k in widget.shellState) next[k] = widget.shellState[k]
          next[reader.modelData] = text.trim() === "true" || text.trim() === "1"
          widget.shellState = next
        }
      }
    }
  }

  // Whether a tile is lit. Native tiles answer from the shell's own services;
  // the rest from whatever their `read` last printed. A momentary tile -- one
  // with no `read` at all -- is never lit: Rotate has always been that, a
  // one-shot action wearing a toggle's chrome.
  function lit(id) {
    if (widget.preview) return id === "torch" || id === "nightlight"
    switch (id) {
    case "silent":   return widget.notifications ? widget.notifications.doNotDisturb : false
    case "airplane": return widget.host.airplane
    case "torch":    return widget.torchOn
    case "rotate":   return false
    }
    return widget.shellState[id] === true
  }

  // W6's rule applied one level down: a tile the phone cannot honour is absent
  // rather than drawn dead. Only the torch has ever been in that position.
  function usable(id) {
    if (widget.preview) return true
    if (id === "torch") return widget.torchAvailable
    return true
  }

  function tap(id): void {
    if (widget.preview) return
    switch (id) {
    case "silent":
      if (widget.notifications)
        widget.notifications.setDoNotDisturb(!widget.notifications.doNotDisturb)
      return
    case "airplane":
      widget.host.setAirplane(!widget.host.airplane)
      return
    case "torch":
      widget.setTorch(!widget.torchOn)
      return
    case "rotate":
      widget.rotate()
      return
    }
    var def = Catalogue.entry("quick-toggles", id)
    if (!def) return
    var cmd = (def.read && widget.lit(id)) ? def.cmdOff : def.cmdOn
    if (!cmd) return
    Quickshell.execDetached(["bash", "-lc", String(cmd)])
    // Read back rather than assume, and after a beat: the same shape the radio
    // tiles use. A write that did not take must not leave the tile lit.
    recheck.restart()
  }

  Timer { id: recheck; interval: 700; onTriggered: widget.refresh() }

  function setTorch(on): void {
    if (!widget.torchAvailable) return
    widget.torchOn = on
    Quickshell.execDetached(["bash", "-c",
      "echo " + (on ? "1" : "0") + " > /sys/class/leds/white:flash/brightness"])
  }

  function rotate(): void {
    // S11. Portrait and one landscape, toggled -- not a cycle through all four
    // transforms. This is a portrait phone: 180 is upside-down and 270 is the
    // other landscape, so cycling made the landscape you wanted three taps
    // away and put upside-down on the route there.
    //
    // There is no "rotate by 90" verb, so read the current transform and pick
    // the other one. Detached and fire-and-forget: the output reconfigure is
    // what tells us it worked, and there is nothing useful to do if it did not.
    //
    // The output is asked for by the same call that reads its transform, not
    // named (refactor.md N2, devices.md D3). This said `DSI-1` until then --
    // the panel this was written on -- which made it the one hardcoded output
    // name in the tree and a silent no-op on any phone whose panel is called
    // something else.
    //
    // `hyprctl eval` and not `hyprctl keyword`: under a Lua config the latter
    // refuses outright -- "keyword can't work with non-legacy parsers" -- and
    // hl.monitor() takes a whole monitor line, so the SCALE has to be restated
    // or the rotate would silently reset the phone to scale 1. It is read back
    // from the compositor for the same reason the name is: the device package
    // owns that number (devices.md D3) and this file must not carry a second
    // copy of it.
    //
    // Transform is an integer here where sway used words: 0 is normal and 1 is
    // 90 degrees.
    //
    // The TOUCH DEVICES get the same transform, and that is not optional.
    // Hyprland does not carry an output's transform across to the touchscreen
    // pointed at it: a touch device has its own, and until it is set the touch
    // coordinate space stays in the panel's native orientation. The screen
    // turns, the touches do not, and everything lands 90 degrees out --
    // reported on an fp4 2026-09-22 (defects.md D2).
    //
    // Enumerated, not named. The touchscreen here is `himax-touchscreen-1`,
    // which is an fp4 fact and has no business in a file every device shares
    // -- the same reason the output name is read back rather than written as
    // DSI-1. Note the panel ALSO registers a keyboard called
    // `himax-touchscreen`; only the touch device is in devices.touch, which is
    // what this iterates.
    Quickshell.execDetached(["bash", "-c",
      "s=$(hyprctl monitors -j | python3 -c 'import json,sys;d=json.load(sys.stdin)[0];print(d[\"name\"], d[\"transform\"], d[\"scale\"])'); " +
      "set -- $s; " +
      "case $2 in 0) n=1;; *) n=0;; esac; " +
      "hyprctl eval \"hl.monitor({ output = \\\"$1\\\", mode = \\\"preferred\\\", position = \\\"auto\\\", scale = $3, transform = $n })\"; " +
      "for d in $(hyprctl devices -j | python3 -c 'import json,sys;[print(t[\"name\"]) for t in json.load(sys.stdin).get(\"touch\", [])]'); do " +
      "hyprctl eval \"hl.device({ name = \\\"$d\\\", transform = $n })\"; " +
      "done"])
  }

  // The tiles that will actually be drawn, after the absent ones are dropped.
  readonly property var drawn: {
    var out = []
    for (var i = 0; i < widget.tiles.length; i++)
      if (widget.usable(widget.tiles[i])) out.push(widget.tiles[i])
    return out
  }

  // Four across, wrapping. `Math.min(4, count)` rather than a fixed four, so a
  // row that is not full still fills the width -- which is what the three-tile
  // case has always looked like on a phone with no torch, and what one tile
  // would look absurd not doing.
  Grid {
    id: grid
    width: widget.width
    columns: Math.max(1, Math.min(4, widget.drawn.length))
    spacing: Style.space(8)
    readonly property int cell:
      Math.floor((width - spacing * (columns - 1)) / columns)

    Repeater {
      model: widget.drawn
      delegate: Shared.SmallTile {
        required property string modelData
        host: widget.host
        width: grid.cell
        glyph: Catalogue.glyphFor("quick-toggles", modelData)
        label: Catalogue.nameFor("quick-toggles", modelData)
        on: widget.lit(modelData)
        onActivated: widget.tap(modelData)
      }
    }

  }
}
