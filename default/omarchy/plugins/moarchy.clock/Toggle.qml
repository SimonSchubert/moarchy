// The switch on an alarm.
//
// Not the kit's Check, which is a tick box, and the difference is not
// decoration: a tick box says *this one is selected* and a switch says *this
// one is on*. An alarm is the second, and it is the one control on the screen
// somebody uses without reading anything, so it has to be the shape their
// thumb already knows.
//
// One control in one app, which is why it lives here rather than in
// shared/qs_ui. If a second plugin needs a switch it should move, and that is
// what the kit's README means by "the half that is genuinely the same".
import QtQuick
import "ui/Metrics.js" as Metrics
import "ui/Theme.js" as Theme

Item {
  id: root

  // Only for the shape: a switch is a capsule at large corners and a box at
  // the other two, like every other control on the phone.
  property var colours: null
  property bool checked: false
  property color accent: "#3584e4"
  property color knobInk: "#ffffff"
  property color dim: "#9a9996"

  signal toggled(bool checked)

  implicitWidth: 52
  implicitHeight: Metrics.TARGET
  width: implicitWidth
  height: implicitHeight

  Accessible.role: Accessible.Switch
  Accessible.checkable: true
  Accessible.checked: root.checked
  Accessible.onPressAction: root.flip()

  function flip(): void {
    root.toggled(!root.checked)
  }

  Rectangle {
    id: track
    anchors.centerIn: parent
    width: 46
    height: 26
    radius: Metrics.round(root.colours, height)
    // Off is a filled track one control center darker, not an outlined one. The
    // outline was a 1px border that a phone screen loses outdoors, and a
    // switch whose off state is invisible is a switch with one state.
    color: root.checked ? root.accent : Theme.alpha(root.dim, 0.34)

    Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }

    Rectangle {
      id: knob
      width: 20
      height: 20
      radius: Metrics.round(root.colours, height)
      y: (parent.height - height) / 2
      x: root.checked ? parent.width - width - 3 : 3
      color: root.checked ? root.knobInk : root.dim

      Behavior on x {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
      Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.flip()
  }
}
