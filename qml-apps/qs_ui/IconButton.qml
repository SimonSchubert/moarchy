import QtQuick
import "Metrics.js" as Metrics

Item {
  id: root
  property var names: []
  property color color: "#ffffff"
  property int size: Metrics.ICON_INK
  property int slot: Metrics.TARGET
  property string tooltip: ""
  // Turns the glyph while something is in flight. The control stays live:
  // a refresh you cannot press because it is already refreshing is a button
  // that looks broken.
  property bool spinning: false

  signal clicked

  width: slot
  height: slot
  Accessible.role: Accessible.Button
  Accessible.name: root.tooltip
  Accessible.onPressAction: root.clicked()

  Icon {
    id: glyph
    anchors.centerIn: parent
    names: root.names
    color: root.color
    size: root.size
    slot: root.slot
  }

  // One turn at a time rather than an infinite loop: a request that comes back
  // in 200ms would otherwise leave a twitch on screen and park the glyph at
  // whatever angle it happened to stop at.
  RotationAnimator {
    id: turn
    target: glyph
    from: 0
    to: 360
    duration: Metrics.SPIN_MS
    onFinished: {
      if (root.spinning) turn.restart()
      else glyph.rotation = 0
    }
  }

  onSpinningChanged: if (root.spinning && !turn.running) turn.start()
  Component.onCompleted: if (root.spinning) turn.start()

  PressVeil {
    anchors.fill: parent
    radius: width / 2
    ink: root.color
    on: tap.pressed
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    onClicked: root.clicked()
  }
}
