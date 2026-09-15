import QtQuick
import "Metrics.js" as Metrics

// One row in a ContextMenu. Icon optional; whole row is the hit target.
Item {
  id: root
  property var names: []
  property string text: ""
  property color foreground: "#ffffff"
  property color danger: "#e01b24"
  property bool destructive: false
  property int bodySize: 16

  signal clicked

  width: parent ? parent.width : 200
  height: Metrics.MENU_ROW
  Accessible.role: Accessible.MenuItem
  Accessible.name: root.text
  Accessible.onPressAction: root.clicked()

  Row {
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: 8
    anchors.right: parent.right
    anchors.rightMargin: 8
    spacing: 10

    Icon {
      visible: root.names.length > 0
      anchors.verticalCenter: parent.verticalCenter
      slot: 28
      size: Metrics.ICON_INK
      color: root.destructive ? root.danger : root.foreground
      names: root.names
    }

    TypedText {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - (root.names.length > 0 ? 38 : 0)
      role: "body"
      text: root.text
      color: root.destructive ? root.danger : root.foreground
      bodySize: root.bodySize
      elide: Text.ElideRight
    }
  }

  PressVeil {
    anchors.fill: parent
    radius: 8
    ink: root.destructive ? root.danger : root.foreground
    on: tap.pressed
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    onClicked: root.clicked()
  }
}
