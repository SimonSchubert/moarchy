// One choice in a strip of them: a filter, a scale, a preset, a tab that is
// not important enough to be a tab.
//
// Smaller than a Button and it carries a state rather than an action -- on or
// off, and the strip decides which. Off is the group's own surface so the
// strip reads as one object; on is the accent, because the point of a strip
// is telling at a glance which of six it is.
import QtQuick
import "Theme.js" as Theme
import "Metrics.js" as Metrics

Rectangle {
  id: root

  property var colours: null
  property string text: ""
  property var names: []
  property bool on: false
  property int bodySize: Metrics.BODY
  property int pad: 14
  property color hue: "transparent"

  signal clicked

  readonly property color fill: root.hue.a > 0
                                ? root.hue
                                : (root.colours ? root.colours.accent : "#3584e4")

  readonly property color ink: root.on
                               ? Theme.inkOn(root.colours, root.fill)
                               : (root.colours ? root.colours.dim : "#9a9996")

  implicitHeight: 34
  implicitWidth: Math.round(content.implicitWidth + root.pad * 2)
  radius: Metrics.round(root.colours, height)
  color: root.on ? root.fill : Theme.surface(root.colours, "raised")

  Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }

  Accessible.role: Accessible.RadioButton
  Accessible.name: root.text
  Accessible.checkable: true
  Accessible.checked: root.on
  Accessible.onPressAction: root.clicked()

  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.names.length && root.text.length ? 6 : 0

    Icon {
      visible: root.names.length > 0
      anchors.verticalCenter: parent.verticalCenter
      slot: 18
      size: 15
      color: root.ink
      names: root.names
    }

    TypedText {
      visible: root.text.length > 0
      anchors.verticalCenter: parent.verticalCenter
      role: "caption"
      text: root.text
      color: root.ink
      font.weight: Font.DemiBold
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
  }
}
