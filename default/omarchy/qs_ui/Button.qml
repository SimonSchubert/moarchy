// A word you can press.
//
// Files' Pill.qml said it plainly, and then deleted itself saying it: four apps
// had drawn four slightly different buttons, and picking one of them to be the
// button was "a decision for whoever reviews all four". This is that decision.
// Start, Stop, Lap, Reset, Snooze, Dismiss, Save, Delete, the weather's unit
// switches and the clock's presets are one control at three weights.
//
//   filled  the one thing to press on this screen. The accent, or a hue.
//   tonal   a real action that is not the main one. A raised surface.
//   plain   a way out. Nothing behind the word.
//
// No borders anywhere. A 1px outline is a hairline by another name, and it is
// the first thing to disappear on a phone screen in sunlight; a fill one step
// up the ramp is legible in both directions and in both themes.
import QtQuick
import "Theme.js" as Theme
import "Metrics.js" as Metrics

Rectangle {
  id: root

  property var colours: null
  property string text: ""
  property var names: []
  property int bodySize: Metrics.BODY
  // "filled" | "tonal" | "plain"
  property string kind: "tonal"
  property bool destructive: false
  // Overrides the accent for a filled button that is neither the accent nor a
  // refusal -- a green Start, a yellow Lap.
  property color hue: "transparent"
  property int pad: 18
  property string role: "body"

  signal clicked

  readonly property color fill: root.hue.a > 0
                                ? root.hue
                                : root.destructive
                                  ? (root.colours && root.colours.hues
                                     ? root.colours.hues.red : "#e01b24")
                                  : (root.colours ? root.colours.accent : "#3584e4")

  readonly property color ink: {
    if (root.kind === "filled") return Theme.inkOn(root.colours, root.fill)
    if (root.destructive || root.hue.a > 0) return root.fill
    return root.colours ? root.colours.foreground : "#ffffff"
  }

  implicitHeight: Metrics.TARGET + 6
  implicitWidth: Math.round(content.implicitWidth + root.pad * 2)
  radius: Metrics.round(root.colours, height)

  color: {
    if (root.kind === "filled") return root.fill
    if (root.kind === "plain") return "transparent"
    if (root.destructive || root.hue.a > 0)
      return Theme.tint(root.colours, root.fill, "well")
    return Theme.surface(root.colours, "raised")
  }

  // Dimmed rather than hidden. A Start key that vanishes until a duration is
  // typed is a keypad with a hole in it, and nothing to say what would fill it.
  opacity: root.enabled ? 1 : 0.38

  Accessible.role: Accessible.Button
  Accessible.name: root.text
  Accessible.onPressAction: root.clicked()

  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.names.length && root.text.length ? 8 : 0

    Icon {
      visible: root.names.length > 0
      anchors.verticalCenter: parent.verticalCenter
      slot: 22
      size: Metrics.ICON_INK
      color: root.ink
      names: root.names
    }

    TypedText {
      visible: root.text.length > 0
      anchors.verticalCenter: parent.verticalCenter
      role: root.role
      text: root.text
      color: root.ink
      font.weight: Font.DemiBold
      bodySize: root.bodySize
    }
  }

  PressVeil {
    anchors.fill: parent
    radius: parent.radius
    ink: root.ink
    on: tap.pressed
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    enabled: root.enabled
    onClicked: root.clicked()
  }
}
