// The frame every home surface wears: a tile, the recent strip, the prompt bar
// (docs/home.md HM10, HM10a).
//
// Omalauncher's `Modifier.tile()`: the theme's background at the tile opacity,
// a border in the theme's muted colour, and a radius that is 16px times the
// user's corner scale. One component, so the three things on home cannot come
// to disagree about what a frame is -- and the one `border.width` in this
// directory, which style-check.sh holds it to.
//
// It takes its numbers from the host rather than reading Color or UiFile
// itself, for W4's reason: the host is what knows which palette it is on.
import QtQuick

Rectangle {
  id: frame

  property var host: null

  color: frame.host ? frame.host.surface : "transparent"
  radius: frame.host ? frame.host.radiusFrame : 0
  border.width: frame.host ? frame.host.frameBorder : 0
  border.color: frame.host ? frame.host.frameBorderColor : "transparent"

  // How far content stays in from the edge so a square corner of it never
  // pokes past a rounded one. Not `clip`: that clips to the bounding box, and
  // a true rounded clip is a layer and a mask per tile, every frame of a page
  // turn. A third of the radius clears the curve for anything not drawn right
  // into the corner, and a widget's own margin covers the rest.
  readonly property int inset: Math.max(frame.border.width, Math.ceil(frame.radius / 3))
}
