// A column of numbers you drag to the one you want, and it wraps.
//
// This is the alarm editor's whole interaction, and it wraps because that is
// the difference between setting 23:55 and scrolling through a whole day to
// get there. A PathView wraps for nothing: its model is a ring rather than a
// list, so dragging past the last item arrives at the first. A ListView would
// have needed the model tripled and an index modulo to fake the same thing.
//
// Not QtQuick.Controls' Tumbler, which is this with a style engine behind it.
// Nothing else in this repository's Quickshell half imports Controls, and one
// picker is not the reason to start.
//
// The fade and the shrink towards the ends are computed from where the
// delegate has been put rather than declared as PathAttributes. Same picture,
// and it keeps the delegate's properties ones qmllint can resolve -- an
// attached `PathView.fade` is a member lookup on a type that has no such
// member, which `-W 0` treats as the error it usually is.
pragma ComponentBehavior: Bound

import QtQuick
import "ui" as Chrome
import "ui/Metrics.js" as Metrics
import "ui/Theme.js" as Theme

Item {
  id: root

  property int count: 60
  property int from: 0
  property int value: 0
  // Two digits, zero-padded. An hour wheel in twelve-hour mode runs 1 to 12
  // and should not read "01".
  property bool pad: true

  property color ink: "#ffffff"
  property color dim: "#9a9996"
  property int bodySize: Metrics.BODY
  property int rowHeight: 46

  signal picked(int value)

  implicitWidth: 74
  implicitHeight: root.rowHeight * 3

  function label(index: int): string {
    var n = root.from + index
    return root.pad && n < 10 ? "0" + n : String(n)
  }

  // The view's index is written by dragging, so it cannot also be a binding on
  // `value`: the first drag would break the binding and every later change
  // from outside would be silently ignored. It is pushed instead, and never
  // while a thumb is on it -- moving the view mid-flick is how a picker comes
  // to feel broken.
  function sync(): void {
    if (view.moving || view.flicking) return
    var index = root.value - root.from
    if (index < 0 || index >= root.count) return
    if (view.currentIndex !== index) view.currentIndex = index
  }

  onValueChanged: root.sync()
  onCountChanged: root.sync()
  Component.onCompleted: root.sync()

  PathView {
    id: view
    anchors.fill: parent
    model: root.count
    clip: true

    // Five on the path and three over the window, so the two that are fading
    // are doing it out of sight.
    pathItemCount: 5
    preferredHighlightBegin: 0.5
    preferredHighlightEnd: 0.5
    highlightRangeMode: PathView.StrictlyEnforceRange
    snapMode: PathView.SnapToItem
    // The whole column is the handle. Without this a drag has to begin on a
    // row and the gaps between them are dead.
    dragMargin: root.width
    flickDeceleration: 900
    highlightMoveDuration: 180

    onCurrentIndexChanged: root.picked(root.from + view.currentIndex)

    path: Path {
      startX: view.width / 2
      startY: view.height / 2 - root.rowHeight * 2.5
      PathLine { x: view.width / 2; y: view.height / 2 + root.rowHeight * 2.5 }
    }

    delegate: Item {
      id: cell
      required property int index

      width: view.width
      height: root.rowHeight

      // How far this row is from the middle, in rows.
      readonly property real away:
        Math.abs(cell.y + cell.height / 2 - view.height / 2) / root.rowHeight

      opacity: Math.max(0, 1 - cell.away * 0.62)
      scale: 1 - Math.min(1, cell.away / 2) * 0.3

      Chrome.TypedText {
        anchors.centerIn: parent
        role: "title"
        text: root.label(cell.index)
        color: view.currentIndex === cell.index ? root.ink : root.dim
        bodySize: root.bodySize
      }

      MouseArea {
        anchors.fill: parent
        // A tap on a neighbour brings it to the middle, which is quicker than a
        // flick for the one step people most often want.
        onClicked: view.currentIndex = cell.index
      }
    }
  }

  // The two rules that say which row counts. Over the view rather than in it,
  // so they do not travel with the numbers.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    y: Math.round((root.height - root.rowHeight) / 2)
    height: 1
    color: Theme.alpha(root.dim, 0.45)
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    y: Math.round((root.height + root.rowHeight) / 2)
    height: 1
    color: Theme.alpha(root.dim, 0.45)
  }
}
