// A box. The one thing every screen on this phone is made of.
//
// Content on a phone is either inside a box or it is a loose sentence floating
// on the background, and loose sentences are how a screen stops looking like
// it was designed. So: a fill one step lighter than the page, a radius from
// the one scale, and padding that `Metrics.inner()` can subtract from to give
// anything nested inside it a concentric corner.
//
// Children go in a vertical stack, because that is what a card is -- a
// paragraph, a list of rows, a label over a value. A card that wants a row
// puts a RowLayout in it. Nothing here anchors to the card itself, which is
// what keeps `implicitHeight` a measurement rather than a loop.
//
//   Chrome.Card {
//     Layout.fillWidth: true
//     colours: root.colours
//     Chrome.TypedText { Layout.fillWidth: true; text: "…" }
//   }
import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme
import "Metrics.js" as Metrics

Rectangle {
  id: root

  property var colours: null
  // "well" | "card" | "raised" -- Theme.LEVEL. A card dropped inside another
  // card takes "raised", which is the only way the two read as two.
  property string level: "card"
  // A hue name's colour, when this row is an event, a streak or a warning
  // rather than a neutral box. Empty leaves the neutral ramp alone.
  property color tint: "transparent"
  property bool down: false
  property int pad: Metrics.PAD
  property int spacing: Metrics.GAP
  // Where a nested box's radius comes from, so a call site never subtracts by
  // hand: `radius: card.innerRadius`.
  readonly property int innerRadius: Metrics.inner(root.radius, root.pad)

  default property alias content: body.data

  radius: Metrics.radius(root.colours, Metrics.CARD_RADIUS)
  implicitWidth: body.implicitWidth + root.pad * 2
  implicitHeight: body.implicitHeight + root.pad * 2
  color: root.tint.a > 0
         ? Theme.tint(root.colours, root.tint, root.down ? "pressed" : root.level)
         : Theme.surface(root.colours, root.down ? "pressed" : root.level)

  Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }

  ColumnLayout {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: root.pad
    spacing: root.spacing
  }
}
