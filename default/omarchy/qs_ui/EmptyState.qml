// What a screen says when there is nothing on it.
//
// Eight apps had a grey sentence floating in the middle of a black rectangle.
// That reads as a screen that failed to load rather than as a screen with
// nothing on it yet, and it is the one moment an app has to say what it is
// for. So: a box, because everything here is in a box; a glyph, because a
// sentence alone on a phone screen is a error message; a line that names the
// state and a line that says what to do about it.
import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme
import "Metrics.js" as Metrics

Card {
  id: root

  property int bodySize: Metrics.BODY
  property string title: ""
  property string detail: ""
  property var names: []

  pad: 22
  spacing: 4
  radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)

  Item {
    Layout.alignment: Qt.AlignHCenter
    Layout.bottomMargin: 6
    visible: root.names.length > 0
    implicitWidth: 52
    implicitHeight: 52

    Rectangle {
      anchors.fill: parent
      radius: Metrics.radius(root.colours, Metrics.RADIUS_MD)
      color: Theme.surface(root.colours, "raised")
    }

    Icon {
      anchors.centerIn: parent
      slot: 26
      size: 24
      color: root.colours ? root.colours.dim : "#9a9996"
      names: root.names
    }
  }

  TypedText {
    Layout.fillWidth: true
    visible: root.title.length > 0
    role: "subtitle"
    text: root.title
    color: root.colours ? root.colours.foreground : "#ffffff"
    bodySize: root.bodySize
    horizontalAlignment: Text.AlignHCenter
  }

  TypedText {
    Layout.fillWidth: true
    visible: root.detail.length > 0
    role: "body"
    text: root.detail
    color: root.colours ? root.colours.dim : "#9a9996"
    bodySize: root.bodySize
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
  }
}
