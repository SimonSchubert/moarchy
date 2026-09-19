// A quick-settings tile with a second line (docs/style.md, docs/widgets.md §C).
//
// Lifted out of ControlCenter.qml, where it was an inline component, because
// two widgets draw one -- connectivity draws two and mobile-data draws one --
// and a widget is a file (W1). The colours, the radii and the touch seam come
// off the host by name (W4), which is the same reason SettingsRow takes its
// colours as properties: one component, two palettes.
import QtQuick
import qs.Commons
import qs.Ui as Ui

Rectangle {
  id: tile

  property var host: null
  property string glyph: ""
  property string label: ""
  property string detail: ""
  property bool on: false
  signal activated()

  // S6. Opt-in, and off by default: a tile with no long press must keep the
  // tap it always had. Were the hold armed everywhere, holding the Bluetooth
  // tile would swallow its own click and the tile would do nothing at all --
  // which is worse than not having the gesture.
  property bool holdable: false
  signal held()

  // Fired while the finger is still down, as Android does, so the surface
  // answers the gesture rather than the lift. Cleared on the next press
  // rather than on release, for the reason sheetWasDrag is (Qt delivers
  // released before clicked, so a flag cleared on release is already false
  // when the click lands and the tile fires both actions).
  property bool heldFired: false

  // Published, not just set. A Rectangle's implicitHeight is 0 unless it
  // says otherwise, and that is what a Loader wrapping this reports as its
  // own size -- which collapsed every toggle in the Settings arrangement
  // list to a bare handle with nothing beside it.
  implicitHeight: tile.host.tileHeight
  height: implicitHeight
  radius: tile.host.radiusTile
  color: tile.on ? tile.host.accent : tile.host.container
  Behavior on color { ColorAnimation { duration: 140 } }

  // Its own 120 rather than the 140 above (docs/style.md H5, G1): a tile
  // lighting up and a tile acknowledging a thumb are two different state
  // changes, and one property cannot carry two durations. Veiled toward
  // whichever ink the tile is carrying, so a lit one still reads as lit (H4).
  //
  // Guarded on the drag (H6): these tiles *are* the sheet's drag handle, so
  // `pressed` stays true for the whole gesture and an unguarded veil would
  // light every tile a scrolling thumb crossed.
  PressVeil {
    anchors.fill: parent
    radius: parent.radius
    ink: tile.on ? tile.host.textOnAccent : tile.host.textOnSurface
    on: tileArea.pressed && !tile.host.sheetDragging
  }

  Row {
    anchors.fill: parent
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(10)

    Ui.OpticalGlyph {
      anchors.verticalCenter: parent.verticalCenter
      width: tile.host.glyphSlot
      height: tile.host.glyphSlot
      text: tile.glyph
      fontFamily: Style.font.family
      fontSize: Style.font.iconLarge
      color: tile.on ? tile.host.textOnAccent : tile.host.textOnSurface
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      // Exact rather than estimated, now the glyph has a width of its own
      // instead of whatever the font gave it.
      width: parent.width - tile.host.glyphSlot - Style.space(10)
      spacing: 0

      Text {
        width: parent.width
        text: tile.label
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.weight: tile.host.textWeight
        color: tile.on ? tile.host.textOnAccent : tile.host.textOnSurface
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: tile.detail !== ""
        text: tile.detail
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.weight: tile.host.textWeight
        color: tile.on ? Util.alpha(tile.host.textOnAccent, 0.75) : tile.host.subdued
        elide: Text.ElideRight
      }
    }
  }

  Timer {
    id: hold
    interval: tile.host.holdInterval
    onTriggered: { tile.heldFired = true; tile.held() }
  }

  SheetDragArea {
    id: tileArea
    sheet: tile.host.sheet
    anchors.fill: parent
    onGrabbed: (area, mouse) => {
      tile.heldFired = false
      if (tile.holdable) hold.restart()
    }
    // Cancelled by the sheet drag latching, not by any movement at all: a
    // thumb held still for half a second still travels a few pixels, and a
    // hold that a steady hand cannot complete is not a gesture.
    onDragged: (area, mouse) => { if (tile.host.sheetDragging) hold.stop() }
    onUngrabbed: hold.stop()
    onClicked: if (!tile.host.sheetWasDrag && !tile.heldFired) tile.activated()
  }
}
