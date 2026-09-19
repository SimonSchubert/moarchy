// One key of a phone keypad: the digit, and the letters under it.
//
// Calculator's key, at Calculator's height and for Calculator's reason: this
// is a surface where a slip costs a wrong number rather than a wrong screen.
// The letters are there because people still dial "0800 FLOWERS", and because
// a keypad without them does not read as a phone's.
import QtQuick
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics

Rectangle {
  id: key

  property var colours: null
  property int bodySize: Metrics.BODY
  property string digit: ""
  property string letters: ""
  property string level: "card"

  signal clicked
  signal held

  implicitHeight: 62
  radius: Metrics.radius(key.colours, Metrics.RADIUS_LG)
  color: Theme.surface(key.colours, tap.pressed ? "pressed" : key.level)
  Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }

  Accessible.role: Accessible.Button
  Accessible.name: key.digit
  Accessible.onPressAction: key.clicked()

  Column {
    anchors.centerIn: parent
    spacing: -2

    Chrome.TypedText {
      anchors.horizontalCenter: parent.horizontalCenter
      role: "title"
      text: key.digit
      color: key.colours ? key.colours.foreground : "#ffffff"
      font.weight: Font.Medium
      font.pixelSize: Math.round(key.bodySize * 1.6)
      bodySize: key.bodySize
    }

    Chrome.TypedText {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: key.letters.length > 0
      role: "overline"
      text: key.letters
      color: key.colours ? key.colours.dim : "#9a9996"
      bodySize: key.bodySize
    }
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    onClicked: key.clicked()
    onPressAndHold: key.held()
  }
}
