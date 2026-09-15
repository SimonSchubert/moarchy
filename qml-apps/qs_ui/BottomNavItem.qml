import QtQuick
import QtQuick.Layouts
import "Metrics.js" as Metrics

// One tab in a BottomNav. Width is shared equally via the parent RowLayout.
Item {
  id: root
  property var names: []
  property string text: ""
  property bool selected: false
  property color dim: "#9a9996"
  property color accent: "#3584e4"
  property int bodySize: 16

  signal activated

  Layout.fillWidth: true
  Layout.fillHeight: true

  readonly property color ink: root.selected ? root.accent : root.dim

  Accessible.role: Accessible.PageTab
  Accessible.name: root.text
  Accessible.checkable: true
  Accessible.checked: root.selected
  Accessible.onPressAction: root.activated()

  Column {
    anchors.centerIn: parent
    spacing: 2

    Icon {
      anchors.horizontalCenter: parent.horizontalCenter
      slot: 28
      size: Metrics.ICON_INK
      color: root.ink
      names: root.names
    }

    TypedText {
      anchors.horizontalCenter: parent.horizontalCenter
      role: "caption"
      text: root.text
      color: root.ink
      bodySize: root.bodySize
      horizontalAlignment: Text.AlignHCenter
    }
  }

  PressVeil {
    anchors.fill: parent
    ink: root.ink
    on: tap.pressed
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    onClicked: root.activated()
  }
}
