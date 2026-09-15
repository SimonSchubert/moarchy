// A track-and-knob switch. Same D1 radius rule as Pill: Large is a capsule,
// Modest matches the tiles, Square is square. Colour and size stay with the
// caller -- this is the chrome, not the palette.
import QtQuick
import qs.Commons

Item {
  id: root

  property bool checked: false
  property bool interactive: true
  property bool veil: root.interactive
  property int hitMargin
  property color trackOn
  property color trackOff
  property color knobOn
  property color knobOff
  property bool pressed: tap.pressed

  signal toggled(bool on)

  UiFile { id: ui }

  implicitWidth: Style.space(52)
  implicitHeight: Style.space(30)

  Accessible.role: Accessible.Switch
  Accessible.checkable: true
  Accessible.checked: root.checked
  Accessible.onPressAction: if (root.interactive) root.toggled(!root.checked)

  Rectangle {
    id: track
    anchors.fill: parent
    radius: ui.radiusOn(height)
    color: root.checked ? root.trackOn : root.trackOff
    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
      width: parent.height - Style.space(6)
      height: width
      radius: ui.radiusOn(width)
      anchors.verticalCenter: parent.verticalCenter
      x: root.checked ? parent.width - width - Style.space(3) : Style.space(3)
      color: root.checked ? root.knobOn : root.knobOff
      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 120 } }
    }

    PressVeil {
      anchors.fill: parent
      radius: parent.radius
      ink: root.checked ? root.knobOn : root.knobOff
      on: root.veil && root.pressed
    }
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    anchors.margins: -root.hitMargin
    enabled: root.interactive
    onClicked: root.toggled(!root.checked)
  }
}
