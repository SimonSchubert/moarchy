import QtQuick
import "Metrics.js" as Metrics

// Checkbox with optional label. The whole row toggles — a label you cannot
// tap is a desktop habit, and on 360px the box alone is easy to miss.
Item {
  id: root
  property bool checked: false
  property string text: ""
  property color foreground: "#ffffff"
  // Not named onAccent: QML reserves onFoo for signal handlers.
  property color tickColor: "#ffffff"
  property color accent: "#3584e4"
  property color dim: "#9a9996"
  property bool interactive: true
  property int bodySize: 16

  signal toggled(bool checked)

  implicitWidth: root.text.length
                 ? box.width + 12 + label.implicitWidth
                 : Metrics.TARGET
  implicitHeight: Metrics.TARGET
  width: implicitWidth
  height: implicitHeight

  Accessible.role: Accessible.CheckBox
  Accessible.checkable: true
  Accessible.checked: root.checked
  Accessible.name: root.text
  Accessible.onPressAction: root._flip()

  function _flip() {
    if (!root.interactive) return
    root.checked = !root.checked
    root.toggled(root.checked)
  }

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.text.length ? 12 : 0

    Item {
      id: box
      width: Metrics.TARGET
      height: Metrics.TARGET

      Rectangle {
        width: Metrics.CHECK
        height: Metrics.CHECK
        anchors.centerIn: parent
        radius: 4
        color: root.checked ? root.accent : "transparent"
        border.color: root.checked ? root.accent : root.dim
        border.width: 1.5

        Icon {
          visible: root.checked
          anchors.centerIn: parent
          slot: 16
          size: 12
          color: root.tickColor
          names: ["object-select-symbolic"]
        }
      }
    }

    TypedText {
      id: label
      visible: root.text.length > 0
      anchors.verticalCenter: parent.verticalCenter
      role: "body"
      text: root.text
      color: root.interactive ? root.foreground : root.dim
      bodySize: root.bodySize
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.interactive
    onClicked: root._flip()
  }
}
