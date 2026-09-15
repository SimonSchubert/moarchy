// A track-and-knob switch. Same D1 radius rule as Pill: Large is a capsule,
// Modest matches the tiles, Square is square. Colour and size stay with the
// caller -- this is the chrome, not the palette.
import QtQuick
import "Metrics.js" as Metrics

Item {
  id: root

  property bool checked: false
  property bool interactive: true
  property bool veil: root.interactive
  property int hitMargin: 0
  property color accent: "#3584e4"
  property color knobInk: "#ffffff"
  property color dim: "#9a9996"
  property color trackOn: root.accent
  property color trackOff: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.3)
  property color knobOn: root.knobInk
  property color knobOff: root.dim
  property bool pressed: tap.pressed

  signal toggled(bool on)

  UiFile { id: chrome }

  implicitWidth: 52
  implicitHeight: Metrics.TARGET
  width: implicitWidth
  height: implicitHeight

  Accessible.role: Accessible.Switch
  Accessible.checkable: true
  Accessible.checked: root.checked
  Accessible.onPressAction: if (root.interactive) root.toggled(!root.checked)

  Rectangle {
    id: track
    anchors.centerIn: parent
    width: 46
    height: 26
    radius: chrome.radiusOn(height)
    color: root.checked ? root.trackOn : root.trackOff
    border.width: root.checked ? 0 : 1
    border.color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.5)
    Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }

    Rectangle {
      width: 20
      height: 20
      radius: chrome.radiusOn(width)
      y: (parent.height - height) / 2
      x: root.checked ? parent.width - width - 3 : 3
      color: root.checked ? root.knobOn : root.knobOff
      Behavior on x {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
      Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }
    }
  }

  PressVeil {
    anchors.fill: track
    radius: track.radius
    ink: root.checked ? root.knobOn : root.knobOff
    on: root.veil && root.pressed
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    anchors.margins: -root.hitMargin
    enabled: root.interactive
    onClicked: root.toggled(!root.checked)
  }
}
