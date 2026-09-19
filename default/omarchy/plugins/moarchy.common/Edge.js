// Which screen edge a sheet arrives from, and all the arithmetic that follows.
//
//     import "../moarchy.common/Edge.js" as Edge
//
// `gestures.md` Q2 is one rule -- a sheet enters from the edge that raised it
// and closes back along the same axis -- and before this file three sheets
// each spelled their half of it out of their own anchors. That was fine while
// each had exactly one edge. It stops being fine the moment the edge is a
// setting, because the three spellings do not generalise the same way.
//
// `.pragma library` for the reason Sheet.js and Theme.js are: pure functions of
// their arguments, one shared instance, and `node scripts/edge-test.js` can run
// the table without a phone.
.pragma library

var BOTTOM = "bottom"
var TOP = "top"
var RIGHT = "right"
var LEFT = "left"

// All four, although only three can be configured today: the left edge is the
// back gesture's (G9) and is never a target. Writing three rows of a table
// whose fourth is obvious is the asymmetry that costs an afternoon the first
// time somebody asks why it is missing.
//
//   axis  which of x/y the finger travels on
//   sign  the direction that *opens*, as a scene delta. Away from the edge:
//         up off the bottom is -y, in off the right is -x. It doubles as
//         which end of the axis the sheet rests at -- negative rests at the
//         far end (`box - size`), positive at the origin.
//   near  the side the sheet rests against, whose corners are never seen
//         (TrailingSquare.qml)
//   far   the opposite side: the anchor a shut one-pixel band does *not* take
//
// Every function below reads this table rather than branching on the name, so
// a wrong row is wrong in several places at once and `scripts/edge-test.js`
// says so. Two of them used to switch on the edge themselves, and flipping a
// row then broke two cases out of forty-five.
var EDGES = {
  bottom: { axis: "y", sign: -1, near: "bottom", far: "top" },
  top:    { axis: "y", sign:  1, near: "top",    far: "bottom" },
  right:  { axis: "x", sign: -1, near: "right",  far: "left" },
  left:   { axis: "x", sign:  1, near: "left",   far: "right" }
}

// Anything unknown is the caller's own edge rather than a fixed one: a sheet
// that cannot read the setting keeps the edge it was written for, which is the
// shipped behaviour (Q1) and not a fourth answer nobody chose.
function norm(name, fallback) {
  var n = String(name || "").toLowerCase().trim()
  if (EDGES[n]) return n
  var f = String(fallback || "").toLowerCase().trim()
  return EDGES[f] ? f : BOTTOM
}

function of(edge) {
  return EDGES[norm(edge)]
}

function axis(edge) {
  return of(edge).axis
}

function horizontal(edge) {
  return of(edge).axis === "x"
}

// DragTracker's `openDirection`: the sign of a scene delta that raises
// progress. The gesture that opens travels away from the edge.
function openDirection(edge) {
  return of(edge).sign
}

// DragTracker's `latchSign` for a sheet's *own* close drag, which is the way
// back: the exact opposite, and never a fifth number to keep in step.
function closeLatchSign(edge) {
  return -of(edge).sign
}

// The side a sheet rests against, as an anchor name.
function near(edge) {
  return of(edge).near
}

// N3, P8. Which of a PanelWindow's four anchors are set. Shut, the surface is
// a one-pixel band along `edge`, so every side but the opposite one is
// anchored. Grown, all four are.
function anchors(edge, grown) {
  var a = { top: true, bottom: true, left: true, right: true }
  if (!grown) a[of(edge).far] = false
  return a
}

// Q2a. Where the sheet sits at `progress`, given the surface it is in and its
// own size. Only the entry axis moves: on the cross axis a sheet keeps the
// position it has, because the control center is as tall as its content (control-center.md S21)
// and mirroring that into a width would be a relayout of every tile on it
// rather than a different path in.
//
// Translation and never a scale: this is a Mali-400 at GLES 2.0, where an `x`
// costs nothing and a `scale` re-rasters everything on the sheet.
function offset(edge, progress, boxW, boxH, sheetW, sheetH) {
  var e = of(edge)
  var p = Number(progress) || 0
  var sideways = e.axis === "x"
  var box = sideways ? boxW : boxH
  // Clamped to the surface, because a sheet bigger than the box cannot rest
  // inside it: it rests flush against the entry edge and overflows the far
  // one. The app drawer does exactly that for one drag per session -- its size
  // falls back to the *screen* until the surface has been up once (D2b), and
  // the screen is taller than the surface by the bar's exclusive zone. Without
  // the clamp that first sheet sits a few pixels high and loses the top of its
  // search field, where overflowing under the strip costs nothing.
  var size = Math.min(box, sideways ? sheetW : sheetH)
  // Resting at the far end of the axis (bottom, right) or at its origin
  // (top, left) -- which is the same question `sign` already answers.
  var at = e.sign < 0 ? box - size * p : -size * (1 - p)
  return sideways ? { x: at, y: 0 } : { x: 0, y: at }
}

// D2a, Q2. What one full sheet of travel is worth on this edge: the sheet's
// own extent along the axis the finger moves on.
function travel(edge, sheetW, sheetH) {
  return of(edge).axis === "x" ? sheetW : sheetH
}
