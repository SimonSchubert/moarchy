// The one button shape this app uses, at whatever weight the caller wants.
//
// Start, Stop, Lap, Reset, +1 min, Snooze, Dismiss, and the five preset chips
// are all the same control: a rounded rectangle with a word in it, a fill the
// caller chooses, and a press that darkens rather than moves. They are not the
// kit's IconButton, because every one of them says what it does in a word -- a
// stopwatch whose two controls are a triangle and a square is a stopwatch
// somebody has to learn.
//
// The fill comes in from outside rather than being worked out here. Which
// button is the one to press is a decision about the whole screen, and the
// screen is the only thing that can see all of them at once.
import QtQuick
import "ui" as Chrome
import "ui/Metrics.js" as Metrics

Rectangle {
  id: root

  property string text: ""
  property var names: []
  property color ink: "#ffffff"
  property int bodySize: Metrics.BODY
  property string role: "body"
  // A word reads better with air around it than centred in a box two sizes too
  // big, so the width is the word plus this and the height is the thumb floor.
  property int pad: 18

  signal clicked

  implicitHeight: Metrics.TARGET + 6
  implicitWidth: Math.round(content.implicitWidth + root.pad * 2)
  radius: height / 2

  // Dimmed rather than hidden. A Start key that vanishes until a duration is
  // typed is a keypad with a hole in it, and nothing to say what would fill it.
  opacity: root.enabled ? 1 : 0.38

  Accessible.role: Accessible.Button
  Accessible.name: root.text
  Accessible.onPressAction: root.clicked()

  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.names.length && root.text.length ? 8 : 0

    Chrome.Icon {
      visible: root.names.length > 0
      anchors.verticalCenter: parent.verticalCenter
      slot: 22
      size: Metrics.ICON_INK
      color: root.ink
      names: root.names
    }

    Chrome.TypedText {
      visible: root.text.length > 0
      anchors.verticalCenter: parent.verticalCenter
      role: root.role
      text: root.text
      color: root.ink
      bodySize: root.bodySize
    }
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
