// A number that does not move while it counts.
//
// Adwaita Sans is proportional, so "11" is narrower than "00" and a stopwatch
// drawn with a plain Text jitters left and right ten times a second -- every
// digit that changes shifts every digit after it, and on a centred number it
// shifts the whole thing. Tabular figures would fix it in one line if the font
// on the far end were guaranteed to have them, and the phone's font is
// whatever the image shipped.
//
// So each character gets a cell of its own, all the digit cells the width of
// the widest digit, and the separators a narrower one. TextMetrics measures
// that width without drawing anything. The result is a number that changes in
// place, which is the only reason anybody notices this file exists.
pragma ComponentBehavior: Bound

import QtQuick
import "ui/Metrics.js" as Metrics

Item {
  id: root

  property string text: ""
  // Drawn smaller and dimmer after the main run -- the tenths on the
  // stopwatch, which are a detail of the number rather than part of it.
  property string tail: ""

  property int pixelSize: 48
  property int weight: Font.Light
  property color color: "#ffffff"
  property color tailColor: root.color
  // Characters before this index are drawn in `dimColor`. It is how the
  // timer's keypad shows 00:05:00 with the two leading zeros still grey: the
  // untyped part of the entry is visibly not part of the number yet.
  property int litFrom: 0
  property color dimColor: root.color
  property real tailScale: 0.62

  readonly property int tailSize: Math.max(8, Math.round(root.pixelSize * root.tailScale))

  TextMetrics {
    id: wide
    font.family: Metrics.FONT
    font.pixelSize: root.pixelSize
    font.weight: root.weight
    text: "0"
  }

  TextMetrics {
    id: narrow
    font.family: Metrics.FONT
    font.pixelSize: root.pixelSize
    font.weight: root.weight
    text: ":"
  }

  TextMetrics {
    id: wideTail
    font.family: Metrics.FONT
    font.pixelSize: root.tailSize
    font.weight: root.weight
    text: "0"
  }

  // Where the baseline sits inside a Text of each size. TextMetrics measures
  // advances and not baselines, and the tenths have to sit *on* the line the
  // big digits sit on -- centred in the taller box instead, they ride up and
  // read as an exponent. `baselineOffset` is a Text's own distance from its
  // top to its baseline, which is exactly the number needed, so the two
  // references below are Texts that are never drawn.
  Text {
    id: baseRef
    visible: false
    text: "0"
    font.family: Metrics.FONT
    font.pixelSize: root.pixelSize
    font.weight: root.weight
  }

  Text {
    id: tailRef
    visible: false
    text: "0"
    font.family: Metrics.FONT
    font.pixelSize: root.tailSize
    font.weight: root.weight
  }

  TextMetrics {
    id: narrowTail
    font.family: Metrics.FONT
    font.pixelSize: root.tailSize
    font.weight: root.weight
    text: ":"
  }

  // A colon and a full stop are punctuation between digits; everything else is
  // treated as a digit, because a stopwatch has nothing else in it.
  function separator(c: string): bool {
    return c === ":" || c === "." || c === " "
  }

  function cells(source: string): var {
    var out = []
    for (var i = 0; i < source.length; i++) out.push(source.charAt(i))
    return out
  }

  implicitHeight: Math.ceil(wide.height)
  implicitWidth: row.implicitWidth

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Repeater {
      model: root.cells(root.text)

      Item {
        id: cell
        required property string modelData
        required property int index
        width: root.separator(cell.modelData)
               ? Math.round(narrow.advanceWidth)
               : Math.round(wide.advanceWidth)
        height: Math.ceil(wide.height)

        Text {
          anchors.centerIn: parent
          text: cell.modelData
          color: cell.index >= root.litFrom ? root.color : root.dimColor
          font.family: Metrics.FONT
          font.pixelSize: root.pixelSize
          font.weight: root.weight
        }
      }
    }

    Repeater {
      model: root.cells(root.tail)

      Item {
        id: tailCell
        required property string modelData
        width: root.separator(tailCell.modelData)
               ? Math.round(narrowTail.advanceWidth)
               : Math.round(wideTail.advanceWidth)
        height: Math.ceil(wide.height)

        Text {
          // Sat on the baseline of the big run rather than centred on it, the
          // way a decimal is written.
          anchors.horizontalCenter: parent.horizontalCenter
          y: Math.round(baseRef.baselineOffset - tailRef.baselineOffset)
          text: tailCell.modelData
          color: root.tailColor
          font.family: Metrics.FONT
          font.pixelSize: root.tailSize
          font.weight: root.weight
        }
      }
    }
  }
}
