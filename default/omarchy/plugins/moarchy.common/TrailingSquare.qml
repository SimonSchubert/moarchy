// The rectangle that squares a sheet's trailing corners back off.
//
// A sheet is one radius on all four corners, and two of them sit against the
// screen edge it arrived from -- where a rounded corner is not a rounded
// corner but a pair of notches cut out of whatever is behind. Three sheets
// each carried this block, each against a different edge and each with the
// same four lines in it. On an edge that is a setting (gestures.md Q2) it is
// the same block with the edge in it, so it is one component.
//
// Sized by anchors on the cross axis and by `depth` on the entry axis, which
// is why `depth` is not called `radius`: the sheet's radius is how deep this
// has to reach, not a radius of its own -- this rectangle has square corners,
// which is the whole point of it.
import QtQuick
import "Edge.js" as Edge

Rectangle {
  id: square

  // The edge the sheet enters from. Its two corners are the ones never seen.
  property string edge: Edge.BOTTOM
  // How far in to cover: the sheet's own corner radius.
  property int depth: 0

  readonly property bool sideways: Edge.horizontal(square.edge)
  readonly property string side: Edge.near(square.edge)

  anchors.left: (!square.sideways || square.side === Edge.LEFT) ? parent.left : undefined
  anchors.right: (!square.sideways || square.side === Edge.RIGHT) ? parent.right : undefined
  anchors.top: (square.sideways || square.side === Edge.TOP) ? parent.top : undefined
  anchors.bottom: (square.sideways || square.side === Edge.BOTTOM) ? parent.bottom : undefined

  // Only the unanchored axis reads these; the anchored one derives its own.
  implicitWidth: square.sideways ? square.depth : 0
  implicitHeight: square.sideways ? 0 : square.depth
}
