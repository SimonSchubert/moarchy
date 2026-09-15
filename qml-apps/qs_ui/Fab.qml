import QtQuick
import "Metrics.js" as Metrics

Rectangle {
  id: root
  property var names: ["list-add-symbolic"]
  property color accent: "#3584e4"
  property color foreground: "#ffffff"
  property string tooltip: ""

  signal clicked
  signal pressAndHold

  width: Metrics.FAB
  height: Metrics.FAB
  radius: chrome.radiusOn(width)
  color: root.accent
  Accessible.role: Accessible.Button
  Accessible.name: root.tooltip
  Accessible.onPressAction: root.clicked()

  UiFile { id: chrome }

  Icon {
    anchors.centerIn: parent
    slot: 24
    size: Metrics.ICON_INK
    color: root.foreground
    names: root.names
  }

  PressVeil {
    anchors.fill: parent
    radius: parent.radius
    ink: root.foreground
    on: tap.pressed
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    onClicked: root.clicked()
    onPressAndHold: root.pressAndHold()
  }
}
