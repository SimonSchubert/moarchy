// An OWL widget, drawn in a tile (docs/owl.md §A).
//
// The runtime's own board (runtimes/quickshell/shell.qml) is the model: an
// OwlWidget that compiles and runs the file, an OwlNode that draws its tree,
// and the widget's padding as the margin. HomeTile draws the frame around it.
//
// Touch is the part that is home's (OW5). OWL's nodes take a tap on press, so
// home's router, a MouseArea under the tiles, would never see a drag that
// starts on one. So a passive point handler hands every touch to the router as
// well, and a drag handler takes the touch from the widget once the router has
// made it a swipe -- which cancels the widget's tap, as a long press does by
// switching the widget's input off for the rest of that touch.
import QtQuick
import Quickshell
import "../moarchy.owl" as Owl

Item {
  id: tile

  property var home: null
  property var owlHost: null
  property string path: ""
  // OW4: home on screen, and this tile's page the one showing.
  property bool active: false
  property int cols: 3
  property int rows: 2

  readonly property string error: widget.error
  readonly property bool ready: !!widget.tree && widget.error === ""

  // Under the widget: a press none of its nodes took stops here instead of
  // reaching home's own touch area below the tiles, so the router hears each
  // touch once -- from the feed above -- and not twice.
  MouseArea {
    anchors.fill: parent
    // no press state (style.md H7): swallows what the widget did not take
  }

  Owl.OwlWidget {
    id: widget
    anchors.fill: parent
    anchors.margins: (widget.program ? widget.program.padding : 12) * widget.dp
    path: tile.path
    host: tile.owlHost
    palette: tile.owlHost ? tile.owlHost.palette : ({})
    active: tile.active
    cols: tile.cols
    rows: tile.rows
    dp: tile.owlHost ? tile.owlHost.dp : 1
    screenWidth: tile.home ? tile.home.width : 360
    screenHeight: tile.home ? tile.home.height : 720
  }

  // The widget's own input, off for the rest of a touch home has taken: a
  // swipe or a long press is not also a tap on whatever was under the finger.
  readonly property bool inputOn: !(tile.home && tile.home.sheet
                                    && (tile.home.sheet.sheetDragging || tile.home.arranging))

  // The whole tile's tap, for a widget whose `onTap` is on the widget itself.
  TapHandler {
    enabled: tile.inputOn && !!(widget.tree && widget.tree.onTap)
    gesturePolicy: TapHandler.ReleaseWithinBounds
    onTapped: (p) => widget.tree.onTap(p.position.x / widget.dp, p.position.y / widget.dp)
  }

  Owl.OwlNode {
    anchors.fill: widget
    visible: widget.error === "" && !!widget.tree
    enabled: tile.inputOn
    widget: widget
    node: !widget.tree ? null : widget.tree.children.length === 1 ? widget.tree.children[0]
      : { kind: "Column", p: { gap: 0 }, h: {}, a: {}, c: widget.tree.children }
  }

  // OW5. Every touch, to home's router as well. On an item over the widget
  // rather than on the tile: a handler that takes a press exclusively stops it
  // there, and a passive one on an ancestor below would never see it. This one
  // is passive, so the press goes on to the widget's own handlers.
  Item {
    anchors.fill: parent
    z: 2

    PointHandler {
      id: feed
      target: null
      property bool down: false
      onActiveChanged: {
        if (!tile.home || !tile.home.sheet) return
        var p = feed.point.scenePosition
        if (feed.active) {
          feed.down = true
          tile.home.sheet.sheetPress(null, { x: p.x, y: p.y })
        } else if (feed.down) {
          feed.down = false
          tile.home.sheet.sheetRelease()
        }
      }
      onPointChanged: {
        if (!feed.active || !tile.home || !tile.home.sheet) return
        var p = feed.point.scenePosition
        tile.home.sheet.sheetMove(null, { x: p.x, y: p.y })
      }
      onCanceled: if (feed.down && tile.home && tile.home.sheet) {
        feed.down = false
        tile.home.sheet.sheetCancel()
      }
    }
  }
}
