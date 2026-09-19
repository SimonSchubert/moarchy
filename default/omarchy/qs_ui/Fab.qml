import QtQuick
import "Metrics.js" as Metrics

Rectangle {
  id: root
  // Only for the shape on it: the fill is `accent`, as it always was.
  property var colours: null
  property var names: ["list-add-symbolic"]
  property color accent: "#3584e4"
  property color foreground: "#ffffff"
  property string tooltip: ""

  signal clicked
  // Keep's second note kind is a long press on the same button rather than a
  // second button in the same corner. A caller that adds its own MouseArea on
  // top to get that would also take the press feedback away with it, which is
  // why the signal is here instead.
  signal held

  width: Metrics.FAB
  height: Metrics.FAB
  radius: Metrics.round(root.colours, width)
  color: root.accent
  Accessible.role: Accessible.Button
  Accessible.name: root.tooltip
  Accessible.onPressAction: root.clicked()

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
    onPressAndHold: root.held()
  }
}
