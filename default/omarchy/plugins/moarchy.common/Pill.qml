// A labeled button for shell surfaces. Same D1 radius rule as qs_ui/Pill:
// Large is a capsule, Modest matches the tiles, Square is square.
import QtQuick
import qs.Commons
import qs.Ui as Ui

Rectangle {
  id: root

  property string text: ""
  property color ink
  property int textWeight: Font.DemiBold
  property int pixelSize: Style.font.bodySmall

  signal clicked

  UiFile { id: ui }

  radius: ui.radiusOn(height)

  PressVeil {
    anchors.fill: parent
    radius: parent.radius
    ink: root.ink
    on: tap.pressed
  }

  Text {
    anchors.centerIn: parent
    text: root.text
    font.family: Style.font.family
    font.pixelSize: root.pixelSize
    font.weight: root.textWeight
    color: root.ink
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    onClicked: root.clicked()
  }
}
