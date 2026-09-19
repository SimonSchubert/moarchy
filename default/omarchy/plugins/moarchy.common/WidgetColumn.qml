// The widgets one host draws, in the user's order (docs/widgets.md §C).
//
//     Shared.WidgetColumn {
//       id: widgets
//       width: parent.width
//       spacing: root.sheetGap
//       host: root
//       hostId: "control-center"
//     }
//
// The *host* is the surface -- `root` above -- and this is the column it drops
// in. Everything a widget draws with comes off the host by name (W4), so the
// contract is the property list below and not an argument list that grows by
// one every time a widget wants something.
//
// ---------------------------------------------------------------------------
// What the host must answer
// ---------------------------------------------------------------------------
//   colours (style.md C2)  surface textOnSurface container containerHigh
//                          accent textOnAccent subdued
//   shape (style.md D1)    radiusTile radiusCard radiusOn(size)
//   metrics                glyphSlot tapSlot textWeight
//                          tileHeight sliderHeight roundSize
//   touch                  sheet holdInterval dragSlop
//   the shell              shell openScreen(id) dryRun
//
// A host that omits one gets an undefined binding in whichever widget wanted
// it, which QML reports per property and per frame. That is a worse failure
// than a missing argument and it is the price of not threading twenty
// properties through two levels by hand; `checkHost()` below turns it into one
// warning naming the host and the property, once, at load.
import QtQuick
import "Widgets.js" as Widgets

Column {
  id: column

  // The surface. Not `readonly`, and not `required`: the host assigns it the
  // way the shell assigns `shell` into a plugin root (docs/refactor.md J8).
  property var host: null
  property string hostId: ""

  // W37. Handed down to every widget. The arrangement list in Settings draws
  // the real widgets rather than a picture of them, and a real widget on a
  // settings page must not be able to switch a radio.
  property bool preview: false

  // W15. The resolved arrangement, for the host's IPC verb. Both states, not
  // just the drawn ones, because "off" and "absent" are different answers and
  // a verb that could not tell them apart would be the one that gets believed.
  readonly property var arrangement: widgetsFile.resolve(column.hostId)

  WidgetsFile { id: widgetsFile }

  // W14. The live item for an id, or null -- what a host's IPC verb calls into
  // when it names a widget. Off and absent both answer null here; the verb is
  // what turns that into `absent` rather than into an empty string.
  function instance(id) {
    for (var i = 0; i < slots.count; i++) {
      var s = slots.itemAt(i)
      if (s && s.widgetId === id && s.item) return s.item
    }
    return null
  }

  // What the host calls when its surface opens. A widget with something that
  // cannot be bound reactively -- a probe of rfkill, of the backlight, of the
  // modem -- declares `refresh()` and gets it here, once per open rather than
  // on a timer: none of it changes while the surface is shut, and a phone that
  // forks four processes every ten seconds for a panel nobody is looking at is
  // just a slower phone.
  function refresh(): void {
    for (var i = 0; i < slots.count; i++) {
      var s = slots.itemAt(i)
      if (s && s.item && typeof s.item.refresh === "function") s.item.refresh()
    }
  }

  // One warning naming the host and the property, rather than a binding error
  // per widget per frame.
  function checkHost() {
    var need = ["surface", "textOnSurface", "container", "containerHigh",
                "accent", "textOnAccent", "subdued", "radiusTile", "radiusCard",
                "glyphSlot", "tapSlot", "textWeight", "tileHeight",
                "sliderHeight", "roundSize", "holdInterval", "dragSlop"]
    if (!column.host) { console.warn("WidgetColumn: no host for " + column.hostId); return }
    // W9a. An unregistered surface resolves to an empty catalogue, which draws
    // exactly like a surface whose widgets are all switched off. Said out loud
    // here, because "my new host renders nothing" is otherwise a morning.
    if (Widgets.catalogue(column.hostId).length === 0)
      console.warn("WidgetColumn: " + column.hostId
                   + " is not in Widgets.js SURFACES, so it can draw nothing")
    for (var i = 0; i < need.length; i++)
      if (column.host[need[i]] === undefined)
        console.warn("WidgetColumn: host " + column.hostId
                     + " does not answer " + need[i])
    var calls = ["radiusOn", "openScreen"]
    for (var j = 0; j < calls.length; j++)
      if (typeof column.host[calls[j]] !== "function")
        console.warn("WidgetColumn: host " + column.hostId
                     + " has no " + calls[j] + "()")
  }

  Component.onCompleted: column.checkHost()

  Repeater {
    id: slots
    // W11. Only what is on. An off widget costs a catalogue entry and no QML
    // object at all -- which is the difference between a switch that hides a
    // row and a switch that stops it being built.
    model: widgetsFile.shown(column.hostId)

    delegate: Loader {
      id: slot
      required property string modelData
      readonly property string widgetId: slot.modelData

      width: column.width

      // W6. `available` false closes the gap: no disabled tile, no blank card.
      // Bound rather than read once, because the two widgets that use it change
      // their answer while the surface is up -- media when something starts
      // playing, mobile-data when NetworkManager finds the modem.
      //
      // The height comes off `present`, NOT off `visible`. In QML `visible` is
      // **inherited**, so every one of these reads false while the sheet is
      // down -- and the sheet is measured while it is down: `sheetWanted` is
      // read from this column's implicitHeight to decide what height to open
      // at, and `beginDrag()` latches it before the first frame of the pull.
      // Bound to `visible`, the whole column measured 0 whenever it was shut,
      // so the control center latched a 70px sheet and dragged down a header
      // with everything under it clipped away, then snapped to full height on
      // release. The same trap as the volume panel's `fill=0`
      // (qml-visible-is-inherited), one layer further in.
      readonly property bool present: slot.status === Loader.Ready && slot.item
                                      && slot.item.available
      visible: slot.present
      height: slot.present ? slot.item.implicitHeight : 0

      // W7. The widget takes its width from here and sets no position of its
      // own. A Loader with an explicit size resizes its item to match, so this
      // is also what stops a widget deciding how wide it is.
      //
      // setSource() with the properties rather than a `source` binding and an
      // onLoaded: bindings inside the widget evaluate on construction, and a
      // widget constructed with a null host spends its first frame logging one
      // error per role it reads. Handed in here, there is no such frame.
      Component.onCompleted: {
        var file = Widgets.fileFor(slot.widgetId)
        if (file === "") return
        slot.setSource(Qt.resolvedUrl("widgets/" + file),
                       { host: column.host,
                         shell: column.host ? column.host.shell : null,
                         preview: column.preview })
      }

      // W12. A widget that will not load leaves its row empty and the surface
      // standing. The id and the error go to the journal -- which is where Qt
      // messages on this phone go, never to a redirected file
      // (qt-on-arch-logs-to-journald).
      //
      // The id and the path, not an error string: a Loader given a URL has no
      // `errorString()` -- that belongs to a Component -- and the engine has
      // already printed the parse error by the time this runs. What it cannot
      // say is which widget it was, because the arrangement is not in the file
      // it failed to parse.
      onStatusChanged: if (slot.status === Loader.Error)
        console.warn("WidgetColumn: " + column.hostId + " could not load widget "
                     + slot.widgetId + " from " + slot.source)
    }
  }
}
