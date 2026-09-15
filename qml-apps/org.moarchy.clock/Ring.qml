// One arc, for the stopwatch's minute and the timer's countdown.
//
// A Canvas and not a Shape: QtQuick.Shapes would be declarative and would
// animate itself, and it also brings a triangulator and a second rendering
// path onto a phone whose GPU is already falling back to software. Two arcs
// and a repaint the caller controls is the whole of what this needs, and the
// caller controls it on purpose -- the stopwatch redraws this once a second
// while its digits move ten times a second, because a ring 220px across
// cannot show a tenth of a degree.
import QtQuick
import "ui/Theme.js" as Theme

Canvas {
  id: root

  // 0 empty, 1 full, clockwise from twelve.
  property real progress: 0
  property color ink: "#3584e4"
  property color track: "#9a9996"
  property real thickness: 8
  // Draws the arc back from twelve instead of forward, which is what a
  // countdown looks like when it is emptying rather than filling.
  property bool reverse: false

  implicitWidth: 220
  implicitHeight: 220

  antialiasing: true
  renderStrategy: Canvas.Cooperative

  onProgressChanged: root.requestPaint()
  onInkChanged: root.requestPaint()
  onTrackChanged: root.requestPaint()
  onThicknessChanged: root.requestPaint()
  onReverseChanged: root.requestPaint()
  onWidthChanged: root.requestPaint()
  onHeightChanged: root.requestPaint()

  onPaint: {
    var ctx = root.getContext("2d")
    var size = Math.min(root.width, root.height)
    ctx.reset()
    if (size <= 0) return

    var mid = size / 2
    var radius = mid - root.thickness / 2 - 1
    if (radius <= 0) return

    ctx.lineWidth = root.thickness
    ctx.lineCap = "round"

    ctx.beginPath()
    ctx.arc(mid, mid, radius, 0, Math.PI * 2)
    ctx.strokeStyle = Theme.alpha(root.track, 0.18)
    ctx.stroke()

    var fraction = Math.max(0, Math.min(1, root.progress))
    // Nothing at all rather than a round cap sitting at twelve like a bead: an
    // empty ring has to look empty or a finished timer looks like a stalled
    // one.
    if (fraction <= 0.0005) return

    var top = -Math.PI / 2
    var span = Math.PI * 2 * fraction
    ctx.beginPath()
    if (root.reverse) ctx.arc(mid, mid, radius, top - span, top)
    else ctx.arc(mid, mid, radius, top, top + span)
    ctx.strokeStyle = root.ink
    ctx.stroke()
  }
}
