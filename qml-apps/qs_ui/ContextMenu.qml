import QtQuick
import "Metrics.js" as Metrics

// A popover menu over a scrim — Keep's card/overflow menus, not a sheet.
//
// Caller owns `open`. Tap outside closes via dismissed(); do not write open
// from here or a parent's binding breaks.
Item {
  id: root
  property bool open: false
  property color background: "#1d1d20"
  property color line: "#333"
  property color foreground: "#ffffff"
  property color danger: "#e01b24"
  property int bodySize: 16
  property int menuWidth: Metrics.MENU_WIDTH
  // "topEnd" | "center"
  property string placement: "topEnd"
  property int topMargin: Metrics.TARGET + 8
  property int sideMargin: 8
  default property alias content: menuCol.data

  anchors.fill: parent
  visible: root.open
  z: 100

  signal dismissed

  function close() {
    root.dismissed()
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.close()
  }

  Rectangle {
    id: panel
    width: root.menuWidth
    height: menuCol.height + 16
    radius: Metrics.CARD_RADIUS
    color: root.background
    border.color: root.line
    border.width: 1

    x: root.placement === "center"
       ? Math.round((root.width - width) / 2)
       : root.width - width - root.sideMargin
    y: root.placement === "center"
       ? Math.round((root.height - height) / 2)
       : root.topMargin

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onClicked: {}
    }

    Column {
      id: menuCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 8
      spacing: 4
    }
  }
}
