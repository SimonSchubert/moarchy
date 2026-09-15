// A button, because the kit has none.
//
// Every app here that needed one drew its own -- the clock has Pill.qml and
// Toggle.qml, the weather has its two scale pills -- and this is that shape
// again: a 40px capsule with a word in it. It stays local rather than going
// into shared/qs_ui for the reason the kit's README gives for what belongs
// there, which is the half that is *genuinely* the same. Four apps have drawn
// four slightly different buttons, and picking one of them to be the button
// is a decision for whoever reviews all four, not for this plugin.
import QtQuick
import "ui" as Chrome
import "ui/Metrics.js" as Metrics

Rectangle {
  id: root

  property string text: ""
  property color ink: "#ffffff"
  property bool filled: false
  property color accent: "#3584e4"
  property color line: "#333333"
  property bool destructive: false
  property int bodySize: Metrics.BODY

  signal clicked

  implicitWidth: label.implicitWidth + 32
  implicitHeight: Metrics.PILL
  radius: height / 2
  color: root.filled ? root.accent : "transparent"
  border.width: root.filled ? 0 : 1
  border.color: root.line

  Accessible.role: Accessible.Button
  Accessible.name: root.text
  Accessible.onPressAction: root.clicked()

  Chrome.TypedText {
    id: label
    anchors.centerIn: parent
    role: "body"
    text: root.text
    color: root.ink
    bodySize: root.bodySize
  }

  Chrome.PressVeil {
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
