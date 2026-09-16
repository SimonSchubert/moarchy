// A Group for content that sizes itself: a ListView, a Flickable, a grid.
//
// Group measures a column of children and grows to fit them, which is right
// for four rows and wrong for four hundred. This one is the other way round --
// it takes the height it is given and the list scrolls inside it.
//
// The children are clipped to a rectangle inset by `pad`, not to the rounded
// shape, because a Rectangle's radius does not clip. It does not need to: with
// the concentric rule the inset rectangle's corner sits *inside* the group's
// own arc (at RADIUS_LG and GROUP_PAD, 19.8px from the centre of a 20px
// curve), so a row scrolling past the top of the frame disappears under a
// corner that is already ahead of it.
import QtQuick
import "Theme.js" as Theme
import "Metrics.js" as Metrics

Rectangle {
  id: root

  property var colours: null
  property string level: "card"
  property int pad: Metrics.GROUP_PAD
  readonly property int innerRadius: Metrics.inner(root.radius, root.pad)

  default property alias content: hold.data

  radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
  color: Theme.surface(root.colours, root.level)

  Item {
    id: hold
    anchors.fill: parent
    anchors.margins: root.pad
    clip: true
  }
}
