import QtQuick
import QtQuick.Layouts
import "Metrics.js" as Metrics
import "Theme.js" as Theme

// Bottom tab switcher — same job as Adw.ViewSwitcherBar in the GTK apps.
//
// Put BottomNavItem children inside. No JS model: object/array models were
// collapsing to a single tab on Quickshell.
Rectangle {
  id: root
  property int currentIndex: 0
  property color dim: "#9a9996"
  property color accent: "#3584e4"
  property int bodySize: 16
  default property alias content: row.data

  signal activated(int index)

  color: Theme.fallback().background
  implicitHeight: Metrics.BOTTOM_NAV
  height: implicitHeight

  function tabAt(i) {
    var n = 0
    for (var k = 0; k < row.children.length; k++) {
      var c = row.children[k]
      if (!c || c.activated === undefined) continue
      if (n === i) return c
      n++
    }
    return null
  }

  function indexOf(item) {
    var n = 0
    for (var k = 0; k < row.children.length; k++) {
      var c = row.children[k]
      if (!c || c.activated === undefined) continue
      if (c === item) return n
      n++
    }
    return -1
  }

  function sync() {
    var n = 0
    for (var k = 0; k < row.children.length; k++) {
      var c = row.children[k]
      if (!c || c.activated === undefined) continue
      c.selected = (n === root.currentIndex)
      c.dim = root.dim
      c.accent = root.accent
      c.bodySize = root.bodySize
      n++
    }
  }

  function selectItem(item) {
    var i = root.indexOf(item)
    if (i < 0) return
    root.currentIndex = i
    root.activated(i)
    root.sync()
  }

  onCurrentIndexChanged: root.sync()
  onDimChanged: root.sync()
  onAccentChanged: root.sync()
  onBodySizeChanged: root.sync()
  Component.onCompleted: root.sync()

  RowLayout {
    id: row
    anchors.fill: parent
    spacing: 0
  }
}
