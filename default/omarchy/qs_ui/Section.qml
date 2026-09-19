// A label, and the box it labels.
//
// The one place a loose line of text is right: naming what is in the box under
// it. It sits outside the fill rather than inside it, so the eye reads
// "Description" as a heading and the paragraph under it as the thing being
// described -- which is not what happens when both are the same ink inside the
// same rectangle.
//
// Two weights, because screens want both. `role: "overline"` is the small dim
// caps label for a subordinate group of facts; `role: "subtitle"` is the
// app's own ink at reading size, for a heading that is genuinely the top of a
// part of the screen. Anything louder than that belongs in the AppBar.
//
// Without a `title` this is a Card with an empty label slot, which is what a
// section at the top of a screen usually is. With `boxed: false` it is a
// heading over content that supplies its own boxes -- a list of cards, a grid.
import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme
import "Metrics.js" as Metrics

ColumnLayout {
  id: root

  property var colours: null
  property int bodySize: Metrics.BODY
  property string title: ""
  // "overline" for the small dim label, "subtitle" for a heading in app ink.
  property string role: "overline"
  property string level: "card"
  property color tint: "transparent"
  property int pad: Metrics.PAD
  property int cardSpacing: Metrics.GAP
  property int radius: Metrics.radius(root.colours, Metrics.CARD_RADIUS)
  property bool boxed: true
  property alias titleItem: label
  readonly property int innerRadius: Metrics.inner(root.radius, root.pad)

  default property alias content: body.data

  spacing: Metrics.LABEL_GAP

  TypedText {
    id: label
    Layout.fillWidth: true
    Layout.bottomMargin: root.role === "overline" ? 0 : 1
    visible: root.title.length > 0
    role: root.role
    text: root.title
    color: root.colours
           ? (root.role === "overline" ? root.colours.dim : root.colours.foreground)
           : "#9a9996"
    bodySize: root.bodySize
    elide: Text.ElideRight
  }

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + (root.boxed ? root.pad * 2 : 0)
    radius: root.radius
    color: !root.boxed
           ? "transparent"
           : root.tint.a > 0
             ? Theme.tint(root.colours, root.tint, root.level)
             : Theme.surface(root.colours, root.level)

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: root.boxed ? root.pad : 0
      spacing: root.cardSpacing
    }
  }
}
