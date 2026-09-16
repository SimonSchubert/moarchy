// A round button with a word under it: Answer, Decline, Mute, Speaker.
//
// Round because these are the buttons every phone has drawn as circles since
// there were touchscreens, and a green or red disc is read before its word is.
// The word is under the disc and not in it, so a thumb over the disc does not
// cover what it is about to press. A toggle (Mute, Speaker) fills with the
// foreground while it is on.
import QtQuick
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics

Item {
  id: button

  property var colours: null
  property int bodySize: Metrics.BODY
  property var names: []
  property string text: ""
  // A hue for Answer and Decline; transparent for the neutral toggles.
  property color hue: "transparent"
  property bool on: false
  property int size: 64

  signal clicked

  readonly property color fill: button.hue.a > 0
                                ? button.hue
                                : button.on
                                  ? (button.colours ? button.colours.foreground : "#ffffff")
                                  : Theme.surface(button.colours, "raised")
  readonly property color ink: button.hue.a > 0 || button.on
                               ? Theme.inkOn(button.colours, button.fill)
                               : (button.colours ? button.colours.foreground : "#ffffff")

  implicitWidth: Math.max(button.size, label.implicitWidth)
  implicitHeight: button.size + 6 + label.implicitHeight
  opacity: button.enabled ? 1 : 0.38

  Accessible.role: Accessible.Button
  Accessible.name: button.text
  Accessible.onPressAction: button.clicked()

  Rectangle {
    id: disc
    anchors.horizontalCenter: parent.horizontalCenter
    width: button.size
    height: button.size
    radius: Metrics.round(button.colours, button.size)
    color: button.fill
    Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }

    Chrome.Icon {
      anchors.centerIn: parent
      slot: 28
      size: 24
      color: button.ink
      names: button.names
    }

    Chrome.PressVeil {
      anchors.fill: parent
      radius: parent.radius
      ink: button.ink
      on: tap.pressed
    }
  }

  Chrome.TypedText {
    id: label
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: disc.bottom
    anchors.topMargin: 6
    role: "caption"
    text: button.text
    color: button.colours ? button.colours.foreground : "#ffffff"
    bodySize: button.bodySize
  }

  MouseArea {
    id: tap
    anchors.fill: disc
    enabled: button.enabled
    onClicked: button.clicked()
  }
}
