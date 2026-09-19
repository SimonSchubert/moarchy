import QtQuick
import "Metrics.js" as Metrics
import "Theme.js" as Theme

Rectangle {
  id: pv
  property color ink
  property bool on: false
  visible: pv.color.a > 0
  color: Theme.alpha(pv.ink, pv.on ? 0.12 : 0)
  Behavior on color {
    enabled: pv.color.a > 0
    ColorAnimation { duration: Metrics.PRESS_MS }
  }
}
