// A labeled button. Radius follows corners: Large is a capsule, Modest
// matches the tiles, Square is square. Colour and size stay with the
// caller -- this is the chrome, not the palette.
import QtQuick
import "Metrics.js" as Metrics

Rectangle {
  id: root

  property string text: ""
  property var names: []
  property color ink: "#ffffff"
  property int bodySize: Metrics.BODY
  property string role: "body"
  property int pad: 16
  property bool outlined: false
  property color line: "#333333"

  signal clicked
  signal pressAndHold

  UiFile { id: chrome }

  implicitHeight: Metrics.PILL
  implicitWidth: Math.round(content.implicitWidth + root.pad * 2)
  radius: chrome.radiusOn(height)
  border.width: root.outlined ? 1 : 0
  border.color: root.line
  opacity: root.enabled ? 1 : 0.38

  Accessible.role: Accessible.Button
  Accessible.name: root.text
  Accessible.onPressAction: root.clicked()

  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.names.length && root.text.length ? 8 : 0

    Icon {
      visible: root.names.length > 0
      anchors.verticalCenter: parent.verticalCenter
      slot: 22
      size: Metrics.ICON_INK
      color: root.ink
      names: root.names
    }

    TypedText {
      visible: root.text.length > 0
      anchors.verticalCenter: parent.verticalCenter
      role: root.role
      text: root.text
      color: root.ink
      bodySize: root.bodySize
    }
  }

  PressVeil {
    anchors.fill: parent
    radius: parent.radius
    ink: root.ink
    on: tap.pressed
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    onClicked: root.clicked()
    onPressAndHold: root.pressAndHold()
  }
}
