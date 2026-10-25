// Arranging tiles: what is drawn over home while one is selected or carried,
// and the touch area that owns home's touches meanwhile (docs/home.md §K).
//
// Omalauncher's editor (`HomeGrid.kt`): faint guides on every cell, the
// selected tile in an `accent` frame with a handle at the middle of each edge,
// an outline where a carried tile would land, and the action bar. The state is
// home's (`editing`, `carry`, `live`); this file draws it and turns touches
// into calls on home, and decides nothing about the layout itself -- the
// geometry is Layout.js's, so it is tested without a screen (HM50).
import QtQuick
import qs.Commons
import qs.Commons as Upstream
import "../moarchy.common" as Shared
import "Layout.js" as Layout

Item {
  id: arrange

  property var host: null

  readonly property bool carrying: !!arrange.host && arrange.host.carry !== null && arrange.host.carry.moved
  visible: !!arrange.host && (arrange.host.editing !== null || arrange.carrying)

  // Omalauncher's numbers (HM45).
  readonly property int grab: Style.space(20)
  readonly property int sideGrab: Style.space(36)
  readonly property int handle: Style.space(14)

  // The page the guides and outlines are drawn for: where a carried tile is
  // going, else the selected tile's own.
  readonly property int guidePage: !arrange.host ? -1
    : arrange.carrying ? arrange.host.carry.target
    : arrange.host.editing ? arrange.host.editing.page : -1
  readonly property bool guideTiles: !!arrange.host && arrange.guidePage >= 0
    && !!arrange.host.pages[arrange.guidePage] && arrange.host.pages[arrange.guidePage].kind === "tiles"
  readonly property real guideOffset: arrange.host ? arrange.host.pageOffset(arrange.guidePage) : 0

  // ----------------------------------------------------------------- guides
  // HM42. Every cell outlined faintly, so where a tile can go is visible.
  Repeater {
    model: arrange.guideTiles ? arrange.host.grid.columns * arrange.host.grid.rows : 0
    delegate: Rectangle {
      required property int index
      readonly property var r: Layout.rect(arrange.host.grid, {
        x: index % arrange.host.grid.columns, y: Math.floor(index / arrange.host.grid.columns), w: 1, h: 1 })
      x: r.x + arrange.guideOffset
      y: r.y
      width: r.width
      height: r.height
      color: "transparent"
      border.width: 1
      border.color: Util.alpha(arrange.host.frameBorderColor, 0.35)
    }
  }

  // HM44. Where a carried tile would land, or the tile it would swap with.
  Rectangle {
    readonly property var cell: !arrange.carrying ? null
      : arrange.host.carry.preview ? arrange.host.carry.preview
      : arrange.host.carry.swap >= 0 ? arrange.host.cellOf(arrange.host.carry.target, arrange.host.carry.swap)
      : null
    readonly property var r: cell ? Layout.rect(arrange.host.grid, cell) : null
    visible: r !== null
    x: r ? r.x + arrange.guideOffset : 0
    y: r ? r.y : 0
    width: r ? r.width : 0
    height: r ? r.height : 0
    radius: arrange.host ? arrange.host.radiusFrame : 0
    color: arrange.host ? Util.alpha(arrange.host.accent, 0.12) : "transparent"
    border.width: Style.space(2)
    border.color: arrange.host ? arrange.host.accent : "transparent"
  }

  // ---------------------------------------------------------- the selection
  readonly property var sel: arrange.carrying || !arrange.host ? null : arrange.host.selectedRect

  Rectangle {
    visible: arrange.sel !== null
    x: arrange.sel ? arrange.sel.x : 0
    y: arrange.sel ? arrange.sel.y : 0
    width: arrange.sel ? arrange.sel.width : 0
    height: arrange.sel ? arrange.sel.height : 0
    radius: arrange.host ? arrange.host.radiusFrame : 0
    color: "transparent"
    border.width: Style.space(3)
    border.color: arrange.host ? arrange.host.accent : "transparent"
  }
  Repeater {
    // The middle of each edge: top, bottom, left, right.
    model: arrange.sel ? 4 : 0
    delegate: Rectangle {
      required property int index
      readonly property real cx: index < 2 ? arrange.sel.x + arrange.sel.width / 2
                                           : (index === 2 ? arrange.sel.x : arrange.sel.x + arrange.sel.width)
      readonly property real cy: index >= 2 ? arrange.sel.y + arrange.sel.height / 2
                                            : (index === 0 ? arrange.sel.y : arrange.sel.y + arrange.sel.height)
      width: arrange.handle
      height: arrange.handle
      x: cx - width / 2
      y: cy - height / 2
      radius: width / 2
      color: arrange.host.accent
      border.width: Style.space(2)
      border.color: Upstream.Color.background
    }
  }

  // ------------------------------------------------------------ the editor
  // HM43. Every touch on home while a tile is selected: the frame resizes, the
  // tile moves, and a tap anywhere else ends edit mode. Not while a long press
  // is still carrying the tile it lifted -- that finger is the router's.
  MouseArea {
    id: editor
    anchors.fill: parent
    enabled: !!arrange.host && arrange.host.editing !== null && arrange.host.carry === null
             || editor.mode === "move"
    // no press state (style.md H7): the editor's whole-surface drag area

    property string mode: ""         // "resize" | "move" | "outside"
    property var edges: null
    property var base: null
    property real pressX: 0
    property real pressY: 0
    property bool travelled: false

    onPressed: mouse => {
      var h = arrange.host
      var r = h.selectedRect
      editor.pressX = mouse.x
      editor.pressY = mouse.y
      editor.travelled = false
      if (!r) { editor.mode = "outside"; return }
      var e = Layout.edgesAt(r, mouse.x, mouse.y, arrange.grab, arrange.sideGrab)
      if (e.any) {
        editor.mode = "resize"
        editor.edges = e
        editor.base = h.cellOf(h.editing.page, h.editing.i)
      } else if (mouse.x >= r.x && mouse.x < r.x + r.width && mouse.y >= r.y && mouse.y < r.y + r.height) {
        editor.mode = "move"
        h.carryStart(h.editing.page, h.editing.i, h.cellOf(h.editing.page, h.editing.i), mouse.x, mouse.y)
      } else {
        editor.mode = "outside"
      }
    }

    onPositionChanged: mouse => {
      var h = arrange.host
      if (Math.max(Math.abs(mouse.x - editor.pressX), Math.abs(mouse.y - editor.pressY)) > h.dragSlopPx)
        editor.travelled = true
      if (editor.mode === "resize" && editor.base) {
        var others = h.placedOn(h.editing.page).tiles.filter(function (t) { return t.i !== h.editing.i })
        var c = Layout.resized(h.grid, editor.base, editor.edges,
                               mouse.x - h.pageOffset(h.editing.page), mouse.y, others)
        if (c) h.resizeTo(c)
      } else if (editor.mode === "move") {
        h.carryMove(mouse.x, mouse.y)
      }
    }

    onReleased: {
      var h = arrange.host
      if (editor.mode === "resize") h.resizeEnd()
      else if (editor.mode === "move") h.carryEnd()
      // A tap off the tile ends edit mode; a drag there does nothing (HM43).
      else if (editor.mode === "outside" && !editor.travelled) h.endEdit()
      editor.mode = ""
    }

    onCanceled: {
      var h = arrange.host
      if (editor.mode === "move") h.liftCancel()
      h.live = null
      editor.mode = ""
    }
  }

  // ---------------------------------------------------------- the action bar
  // HM46. Above the tile, below it where there is no room above, inside its
  // top where there is room on neither side. Lined up with its left edge, and
  // pulled in when that would run off the grid.
  Rectangle {
    id: bar
    readonly property var r: arrange.sel
    readonly property int barGap: Style.space(8)
    visible: arrange.sel !== null && arrange.host.carry === null
    width: actions.implicitWidth + 2 * border.width
    height: actions.implicitHeight + 2 * border.width
    readonly property real above: r ? r.y - height - barGap : 0
    readonly property real below: r ? r.y + r.height + barGap : 0
    readonly property real floor: arrange.host ? arrange.host.layoutHeight - arrange.host.footHeight : 0
    x: !r ? 0
      : (bar.above >= arrange.host.gapOut || bar.below + height <= bar.floor)
        ? Math.max(arrange.host.gapOut, Math.min(arrange.width - arrange.host.gapOut - width, r.x))
        : r.x + (r.width - width) / 2
    y: !r ? 0
      : bar.above >= arrange.host.gapOut ? bar.above
      : bar.below + height <= bar.floor ? bar.below
      : r.y + Style.space(28)
    color: Upstream.Color.background
    radius: arrange.host ? arrange.host.radiusCard : 0
    border.width: Style.space(2)
    border.color: arrange.host ? arrange.host.accent : "transparent"

    Row {
      id: actions
      x: bar.border.width
      y: bar.border.width

      component Action: Item {
        id: action
        property string label: ""
        property color ink: arrange.host ? arrange.host.textOnSurface : "transparent"
        signal activated()
        width: label.length > 0 ? actionText.implicitWidth + Style.space(24) : 0
        height: Style.space(44)
        visible: action.label.length > 0

        Shared.PressVeil {
          anchors.fill: parent
          ink: action.ink
          on: actionArea.pressed
        }
        Text {
          id: actionText
          anchors.centerIn: parent
          text: action.label
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.weight: arrange.host ? arrange.host.textWeight : Font.Normal
          color: action.ink
        }
        MouseArea {
          id: actionArea
          anchors.fill: parent
          onClicked: action.activated()
        }
      }

      Action {
        label: "edit"
        onActivated: arrange.host.editSelected()
      }
      // A shipped widget is on every moarchy phone: nothing to pass on.
      Action {
        label: arrange.host && !arrange.host.selectedShipped ? "share" : ""
        onActivated: arrange.host.shareSelected()
      }
      Action {
        label: "remove"
        ink: Upstream.Color.urgent
        onActivated: arrange.host.removeSelected()
      }
    }
  }
}
