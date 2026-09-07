// The pressed state, drawn once (docs/style.md H, docs/refactor.md E2).
//
// Reached as a directory import, which needs no qmldir -- the component is
// named by this file:
//
//     import "../moarchy.common" as Shared
//     component PressVeil: Shared.PressVeil { ink: root.textOnSurface }
//
// That one-line inline component is the point of the shape. `ink` has to
// default to the *surface's own* text colour (H2), and a shared type cannot
// know which surface it is on -- so each plugin declares the default once and
// its call sites stay exactly as they were. Nine copies of 27 lines became
// nine lines that each say something true about their own screen.
import QtQuick
import qs.Commons

Rectangle {
  id: pv

  // The control's own ink. No default worth having: a shared component that
  // guessed one would paint the wrong colour on the surface that forgot to
  // pass it, which is worse than the binding error of leaving it unset.
  property color ink

  property bool on: false

  // One blended quad the size of the chrome, the control's own ink at 12%
  // composited over whatever the resting fill is -- so a control whose colour
  // already says something keeps saying it while pressed (H2).
  //
  // Both ends are one ink at two alphas, never "transparent". That is
  // #00000000 and it carries black: a ColorAnimation to it would fade through
  // a grey wash, and Qt.tint over it returns 12% grey rather than 12% ink (H3).
  //
  // Culled at rest rather than drawn transparent: nothing in the scene graph
  // culls an alpha-0 rectangle, and this is a Mali-400.
  visible: pv.color.a > 0
  color: Util.alpha(pv.ink, pv.on ? 0.12 : 0)

  // Instant in, 120 out (H5). A Behavior reads `enabled` at the moment of the
  // write, when the property still holds the *old* colour -- so this is false
  // arriving and true leaving, with no second binding to order against.
  Behavior on color {
    enabled: pv.color.a > 0
    ColorAnimation { duration: 120 }
  }
}
