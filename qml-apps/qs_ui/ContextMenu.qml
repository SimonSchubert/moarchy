import QtQuick
import "Theme.js" as Theme
import "Metrics.js" as Metrics

// A popover menu over a scrim — Keep's card/overflow menus, not a sheet.
//
// Caller owns `open`. Tap outside closes via dismissed(); do not write open
// from here or a parent's binding breaks.
Item {
  id: root
  property bool open: false
  property var colours: null
  property color background: "#1d1d20"
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

  // A scrim, and not a 1px outline, is what separates a popover from the
  // screen under it. The outline was the last hairline in the kit, and it was
  // also the thing that made a menu read as a dialog from 2009.
  Rectangle {
    anchors.fill: parent
    color: Theme.alpha(root.background, 0.55)

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  Rectangle {
    id: panel
    width: root.menuWidth
    height: menuCol.height + 16
    radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
    color: root.colours ? Theme.surface(root.colours, "raised") : root.background

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
      spacing: 2
    }
  }
}
