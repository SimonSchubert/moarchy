// A fact in a box: what it is, small and dim, over what it says, large.
//
// Wind, humidity, sunrise, load average, a streak, a countdown. Every app here
// had a few of these and each drew them differently -- a column with a caption
// over a number, four of them sharing one card, a label and a value on one
// line with a rule between. This is the shape, and it tiles: two across on a
// 360px screen with GAP between them, or four in two rows.
import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme
import "Metrics.js" as Metrics

Rectangle {
  id: root

  property var colours: null
  property int bodySize: Metrics.BODY
  property string label: ""
  property string value: ""
  property string footnote: ""
  property var names: []
  property color valueColour: root.colours ? root.colours.foreground : "#ffffff"
  property string level: "card"
  property color tint: "transparent"
  property int pad: Metrics.PAD
  // "subtitle" for a number that is the point of the screen, "body" for one
  // that is a supporting fact.
  property string valueRole: "subtitle"
  property alias extra: extraSlot.data

  radius: Metrics.radius(root.colours, Metrics.CARD_RADIUS)
  implicitWidth: Math.max(96, body.implicitWidth + root.pad * 2)
  implicitHeight: body.implicitHeight + root.pad * 2
  color: root.tint.a > 0
         ? Theme.tint(root.colours, root.tint, root.level)
         : Theme.surface(root.colours, root.level)

  ColumnLayout {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: root.pad
    anchors.rightMargin: root.pad
    spacing: 2

    RowLayout {
      Layout.fillWidth: true
      visible: root.label.length > 0 || root.names.length > 0
      spacing: 5

      Icon {
        visible: root.names.length > 0
        Layout.preferredWidth: 15
        Layout.preferredHeight: 15
        slot: 15
        size: 14
        color: root.colours ? root.colours.dim : "#9a9996"
        names: root.names
      }

      TypedText {
        Layout.fillWidth: true
        visible: root.label.length > 0
        role: "caption"
        text: root.label
        color: root.colours ? root.colours.dim : "#9a9996"
        bodySize: root.bodySize
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }

    TypedText {
      Layout.fillWidth: true
      Layout.topMargin: 1
      visible: root.value.length > 0
      role: root.valueRole
      text: root.value
      color: root.valueColour
      bodySize: root.bodySize
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    TypedText {
      Layout.fillWidth: true
      visible: root.footnote.length > 0
      role: "caption"
      text: root.footnote
      color: root.colours ? root.colours.dim : "#9a9996"
      bodySize: root.bodySize
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    Item {
      id: extraSlot
      Layout.fillWidth: true
      implicitHeight: childrenRect.height
      visible: children.length > 0
    }
  }
}
