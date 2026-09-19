// The compact tile, for toggles whose whole state is "on" or "off".
//
// WideTile's sibling, and out of ControlCenter.qml for the same reason (W1).
import QtQuick
import qs.Commons
import qs.Ui as Ui

Rectangle {
  id: small

  property var host: null
  property string glyph: ""
  property string label: ""
  property bool on: false
  signal activated()

  // Published, not just set. A Rectangle's implicitHeight is 0 unless it
  // says otherwise, and that is what a Loader wrapping this reports as its
  // own size -- which collapsed every toggle in the Settings arrangement
  // list to a bare handle with nothing beside it.
  implicitHeight: small.host.tileHeight
  height: implicitHeight
  radius: small.host.radiusTile
  color: small.on ? small.host.accent : small.host.container
  Behavior on color { ColorAnimation { duration: 140 } }

  // As WideTile. Rotate is the one instance pinned `on: false` -- a momentary
  // action wearing a toggle's chrome -- so until this existed a tap on it drew
  // nothing at all, and this is the only response it has.
  PressVeil {
    anchors.fill: parent
    radius: parent.radius
    ink: small.on ? small.host.textOnAccent : small.host.textOnSurface
    on: smallArea.pressed && !small.host.sheetDragging
  }

  Column {
    anchors.centerIn: parent
    // Bounded, so the label can elide. It could not before and did not need
    // to: there were four fixed tiles with one short word each. The toggles
    // are arranged now (docs/widgets.md §E) and "Night light" in a quarter of
    // a 360px screen is exactly the spill the old comment warned a fifth tile
    // would cause.
    width: small.width - Style.space(6)
    spacing: Style.space(3)

    Ui.OpticalGlyph {
      anchors.horizontalCenter: parent.horizontalCenter
      width: small.host.glyphSlot
      height: small.host.glyphSlot
      text: small.glyph
      fontFamily: Style.font.family
      fontSize: Style.font.iconLarge
      color: small.on ? small.host.textOnAccent : small.host.textOnSurface
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: small.label
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.weight: small.host.textWeight
      color: small.on ? Util.alpha(small.host.textOnAccent, 0.75) : small.host.subdued
      elide: Text.ElideRight
    }
  }

  SheetDragArea {
    id: smallArea
    sheet: small.host.sheet
    anchors.fill: parent
    onClicked: if (!small.host.sheetWasDrag) small.activated()
  }
}
