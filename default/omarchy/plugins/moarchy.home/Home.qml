// Home: pages of tiles, faces left of page 1, the recent strip and the prompt
// bar (docs/home.md). Omalauncher's home screen, on this phone.
//
// Drawn on the surface moarchy.gestures already maps on the Bottom layer
// (HM1), which is the whole of how home appears exactly where a workspace is
// empty and nowhere else: every window is above it. That plugin keeps the
// surface and its drags; this file is what is drawn on it, and it is a kit
// rather than a plugin -- no manifest, imported by relative path -- for the
// reason moarchy.common is one.
//
// It is also the **host** its widgets and faces draw with (widgets.md §C):
// the colour roles, the radii, the metrics and the sheet-drag seam below are
// what a widget reads off `host`, by name.
//
// Touch: every control here, and the empty space under them, hands its press
// to `sheet`, which is the gestures plugin's router (HM14b). The router decides
// once per touch whether it is a page turn, the drawer or the control center,
// and a touch it never claims is a tap the control keeps.
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Upstream
import "../moarchy.common" as Shared
import "../moarchy.common/Theme.js" as Theme
import "../moarchy.common/Toml.js" as Toml
import "../moarchy.common/Apps.js" as Apps
import "../moarchy.common/ShellApps.js" as ShellApps
import "../moarchy.common/Widgets.js" as WidgetList
import "Layout.js" as Layout

Item {
  id: home

  // Set by the surface that draws home.
  property var shell: null
  // The router: sheetPress/sheetMove/sheetRelease/sheetCancel plus
  // sheetDragging and sheetWasDrag (W13).
  property var sheet: null

  // A window over home: set by the surface, which knows. docs/owl.md OW4 --
  // an OWL widget runs only while this is false.
  property bool covered: false

  // OW1. The OWL runtime's host, one for all of home's OWL tiles. Made from
  // its file rather than declared -- a Loader takes only Items, and OwlHost is
  // a QtObject -- so a missing runtime costs those tiles and not home.
  property var owlHost: null
  function makeOwlHost(): void {
    var c = Qt.createComponent("HomeOwlHost.qml")
    if (c.status === Component.Ready) home.owlHost = c.createObject(home, { home: home })
    else console.warn("home: the OWL runtime did not load; OWL tiles stay empty: " + c.errorString())
  }

  // The tap on the prompt bar. The surface owns what that opens (HM22).
  signal promptTapped()

  // --------------------------------------------------------------- settings
  Shared.UiFile { id: ui }

  // ------------------------------------------------------------ host: colour
  //
  // style.md C1, C2. Home has no layer palette of its own -- it is drawn on the
  // wallpaper -- so its roles are Omalauncher's: the theme's background as the
  // tile fill, the theme's foreground on it, and the theme's muted colour as the
  // border (Omalauncher's `Palette.border` is `muted`).
  readonly property color surface: Util.alpha(Upstream.Color.background, ui.homeOpacity)
  readonly property color textOnSurface: Upstream.Color.foreground
  // HM10. A widget that draws its own card draws it invisibly here: the frame
  // is the card on home.
  readonly property color container: "transparent"
  readonly property color containerHigh: Util.alpha(Upstream.Color.foreground, 0.08)
  readonly property color accent: Upstream.Color.accent
  readonly property color textOnAccent: Upstream.Color.background
  // C3. Against the fill as it will actually be seen: the opacity is the
  // user's, so the colour under it is part of the question.
  readonly property color subdued: Theme.readableOn(
    Theme.mix(Qt.rgba(Upstream.Color.background.r, Upstream.Color.background.g, Upstream.Color.background.b, 1),
              Upstream.Color.foreground, 0.08),
    Upstream.Color.foreground, 0.55, 4.5)
  readonly property color frameBorderColor: Upstream.Color.muted

  // ------------------------------------------------------------- host: shape
  readonly property int radiusFrame: ui.radiusFrame
  readonly property int frameBorder: ui.homeBorder
  // A card inside a tile is the tile; a tile inside a tile takes the frame's
  // radius rather than the control center's 20.
  readonly property int radiusTile: ui.radiusFrame
  readonly property int radiusCard: ui.radiusFrame
  function radiusOn(size) { return Math.min(ui.radiusFrame, Math.max(0, size) / 2) }

  // ----------------------------------------------------------- host: metrics
  // The control center's, so a widget moved from there to here keeps its
  // proportions; the cell is home's own.
  readonly property int textWeight: Font.Normal
  readonly property int glyphSlot: Math.round(Style.font.iconLarge * 1.35)
  readonly property int tapSlot: Math.max(Style.space(44), home.glyphSlot)
  readonly property int tileHeight: ui.controlCenterTile
  readonly property int sliderHeight: ui.controlCenterSlider
  readonly property int roundSize: ui.controlCenterRound
  readonly property int holdInterval: 500
  readonly property int dragSlop: Style.space(10)
  readonly property bool dryRun: false

  // ------------------------------------------------------------- host: touch
  readonly property bool sheetDragging: home.sheet ? !!home.sheet.sheetDragging : false
  readonly property bool sheetWasDrag: home.sheet ? !!home.sheet.sheetWasDrag : false

  // HM7. Where a face finds the package's widgets and the frame, wherever the
  // face itself is: a copy in ~/.config/omarchy/faces/ has no package beside it
  // to import from, and home knows where the one it was loaded from is.
  function widgetUrl(id) {
    return String(Qt.resolvedUrl("../moarchy.common/widgets/" + WidgetList.fileFor(id)))
  }
  readonly property string frameUrl: String(Qt.resolvedUrl("HomeFrame.qml"))

  // W5. What a widget's "open this" means on home: the screen comes up and
  // home stays where it is underneath, because home is not a sheet that has to
  // get out of the way.
  function openScreen(id) {
    if (home.shell && typeof home.shell.summon === "function")
      home.shell.summon(id, "{}")
  }

  // ------------------------------------------------------------------ layout
  property var parsed: null          // home.toml's data, or null for none
  property string layoutError: ""    // HM16, "line: why"
  // Bumped by `home reload` and by an edit to a file a tile or face loads.
  property int revision: 0

  // HM51. The file's pages, with the two that wait: the face invite left of
  // them and an empty page of tiles after them.
  readonly property var resolved: Layout.withWaiting(Layout.pages(home.parsed))
  // Page 1, from the pages as drawn rather than as last read, so it is right
  // straight after an arrangement and before the file has read back.
  readonly property int firstTiles: {
    for (var i = 0; i < home.pages.length; i++) if (home.pages[i].kind === "tiles") return i
    return 0
  }
  // What is drawn. Assigned rather than bound, so the same pages arriving twice
  // -- once from an arrangement (HM48), once more when the file it wrote reads
  // back -- rebuild no tile the second time. A Repeater over a new array makes
  // every widget again, and that is a visible blink on this phone.
  property var pages: home.resolved.pages
  function showPages(next) {
    if (JSON.stringify(next) === JSON.stringify(home.pages)) return
    // HM52. Stay on the page on screen while pages move around it: page 1 if
    // that is where home was, else the same page by what it is.
    var was = home.pages[home.page]
    var onFirst = home.page === home.firstTiles
    var key = was ? JSON.stringify(was) : ""
    home.pages = next
    var to = -1
    if (onFirst) {
      for (var i = 0; i < next.length && to < 0; i++) if (next[i].kind === "tiles") to = i
    } else {
      for (var j = 0; j < next.length && to < 0; j++) if (JSON.stringify(next[j]) === key) to = j
    }
    if (to >= 0 && to !== home.page) {
      home.page = to
      home.pagePosition = to
    }
  }
  onResolvedChanged: home.showPages(home.resolved.pages)
  Component.onCompleted: {
    home.pages = home.resolved.pages
    home.makeOwlHost()
  }

  // HM4. Home opens on page 1, the first page of tiles.
  property int page: home.firstTiles
  // The page drawn, as a fraction while a finger is turning it (HM5).
  property real pagePosition: home.page
  property bool paging: false

  Behavior on pagePosition {
    enabled: !home.paging
    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
  }

  function goTo(n) {
    var to = Math.max(0, Math.min(home.pages.length - 1, Math.round(n)))
    home.page = to
    home.pagePosition = to
  }

  // HM6. Already home and going home again: page 1.
  function goHome() { home.goTo(home.firstTiles) }

  // Faces and pages of tiles can be added or removed under the current page;
  // stay on a page that exists.
  onPagesChanged: if (home.page > home.pages.length - 1) home.goTo(home.pages.length - 1)

  // HM5. The router's page drag, in pages. Past either end it moves a third as
  // far as the finger, so the edge is felt rather than hit.
  function dragTo(travelled) {
    var last = home.pages.length - 1
    var p = travelled
    if (p < 0) p = p / 3
    else if (p > last) p = last + (p - last) / 3
    home.pagePosition = p
  }

  function settle(start, travelled, velocity, fling) {
    home.goTo(Layout.settle(start, travelled, velocity, fling, home.pages.length))
  }

  // The bottom of a page of tiles: the recent strip and the prompt bar.
  readonly property int gapIn: ui.homeGapsIn
  readonly property int gapOut: ui.homeGapsOut
  readonly property int barHeight: Style.space(52)
  readonly property int recentHeight: Style.space(60)
  readonly property bool showRecent: ui.homeRecent > 0 && home.recent.length > 0
  readonly property bool showBar: ui.homePromptBar
  readonly property int footHeight:
    (home.showBar ? home.barHeight + home.gapIn : 0)
    // HM21. The strip's room is kept while it is empty: laid out against its
    // presence, the grid lost a row the moment any app opened and its bottom
    // tiles moved or went.
    + (ui.homeRecent > 0 ? home.recentHeight + home.gapIn : 0)

  // The height home lays out against: its own, except while the keyboard is
  // up. The surface it is drawn on is arranged around the keyboard's exclusive
  // zone (that is how moarchy.gestures knows the keyboard is up), so its height
  // drops while the keyboard is up. Laid out against that, the grid would lose
  // rows and drop tiles for as long as the keyboard stayed; held at the height
  // from before, the keyboard covers the bottom of home and nothing moves.
  //
  // Not "the tallest it has been": the surface is taller for a moment at
  // startup, before the bar's and the strip's zones are arranged, and a grid
  // held at that height put the prompt bar under the strip, off the screen.
  property bool keyboardUp: false
  property real layoutHeight: 0
  function relayout() {
    if (!home.keyboardUp || home.layoutHeight <= 0) home.layoutHeight = home.height
  }
  // Later, not now: the height and keyboardUp move together, keyboardUp being
  // worked out from this same surface's height, and the height's handler ran
  // first -- so a keyboard coming up was read as a shorter home, and the foot
  // jumped up over the tiles.
  onHeightChanged: Qt.callLater(home.relayout)
  onKeyboardUpChanged: Qt.callLater(home.relayout)
  // A new width is a rotation, and starts again whatever the keyboard is doing.
  onWidthChanged: home.layoutHeight = home.height

  // The grid every page of tiles shares: the space above the foot.
  readonly property var grid: Layout.grid(home.width, Math.max(0, home.layoutHeight - home.footHeight),
                                          ui.homeColumns, home.gapIn, home.gapOut)

  // -------------------------------------------------------------- the file
  FileView {
    id: layoutFile
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/home.toml"
    watchChanges: true
    printErrors: false
    // HM16. Absent is the shipped layout; unparseable keeps what is on screen
    // and is said in the report. Never written from here (HM19).
    onLoaded: {
      var r = Toml.parse(layoutFile.text())
      if (r.ok) { home.parsed = r.data; home.layoutError = "" }
      else home.layoutError = r.line + ": " + r.error
    }
    onLoadFailed: { home.parsed = null; home.layoutError = "" }
    onFileChanged: Qt.callLater(function () { layoutFile.reload() })
  }

  // --------------------------------------------------------- recent apps (HM21)
  //
  // The apps open now, most recently focused first. Nothing on the phone counts
  // launches, so this is what can honestly be shown; the order is remembered
  // for as long as the shell runs.
  property var appIdIndex: ({})
  function buildIndex(): void { home.appIdIndex = Apps.index(home.shell) }
  onShellChanged: home.buildIndex()
  Connections {
    target: home.shell ? home.shell.appLibrary : null
    function onAppsChanged() { home.buildIndex() }
  }

  property var focusOrder: []
  function noteFocus(tl): void {
    if (!tl) return
    var next = [tl]
    for (var i = 0; i < home.focusOrder.length; i++)
      if (home.focusOrder[i] !== tl) next.push(home.focusOrder[i])
    home.focusOrder = next.slice(0, 32)
  }

  // Each window's own `activated`, not ToplevelManager.activeToplevel: that
  // reads null here with a window plainly focused (moarchy.bar/Bar.qml and
  // moarchy.gestures' focusedToplevel() both record it), and an order built
  // from it would be no order at all.
  Instantiator {
    model: ToplevelManager.toplevels
    delegate: Connections {
      required property var modelData
      target: modelData
      function onActivatedChanged() { if (modelData.activated) home.noteFocus(modelData) }
    }
  }

  readonly property var recent: {
    var open = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    var out = []
    for (var i = 0; i < home.focusOrder.length; i++)
      if (open.indexOf(home.focusOrder[i]) >= 0) out.push(home.focusOrder[i])
    for (var j = 0; j < open.length; j++)
      if (out.indexOf(open[j]) < 0) out.push(open[j])
    return out.slice(0, ui.homeRecent)
  }

  // ------------------------------------------------------------- the agent
  Shared.AgentFile { id: agents }

  // HM20.
  readonly property string placeholder: agents.current === ""
    ? "open an app…" : "open an app or ask " + agents.current + "…"

  // --------------------------------------------------------------- refresh
  // What WidgetColumn does when its surface opens, for the widgets that probe
  // rather than bind (Fetch): once each time home comes back into view.
  function refresh(): void {
    for (var i = 0; i < pageRepeater.count; i++) {
      var p = pageRepeater.itemAt(i)
      if (p && typeof p.refresh === "function") p.refresh()
    }
  }

  // ------------------------------------------------------------------ report
  function report(): string {
    var lines = []
    lines.push("page=" + (home.page - home.firstTiles + 1)
               + " index=" + home.page + "/" + home.pages.length
               + " columns=" + home.grid.columns + " rows=" + home.grid.rows
               + " cell=" + home.grid.cell + " height=" + home.layoutHeight
               + (home.keyboardUp ? " keyboard=up" : ""))
    lines.push("frame radius=" + home.radiusFrame + " border=" + home.frameBorder
               + " opacity=" + ui.homeOpacity + " gaps=" + home.gapIn + "/" + home.gapOut)
    if (home.layoutError !== "") lines.push("layout-error=" + home.layoutError)
    if (home.resolved.skipped.length) lines.push("skipped=" + home.resolved.skipped.join("; "))
    for (var i = 0; i < pageRepeater.count; i++) {
      var p = pageRepeater.itemAt(i)
      if (p) lines.push(p.describe())
    }
    var names = []
    for (var r = 0; r < home.recent.length; r++)
      names.push(String(home.recent[r].appId || "?"))
    lines.push("recent=" + names.join(","))
    lines.push("agent=" + (agents.current || "none"))
    lines.push("menu=" + (home.menuOpen ? "open" : "closed"))
    lines.push("edit=" + (home.editing
      ? (home.editing.page - home.firstTiles + 1) + ":" + (home.editing.i + 1) + " " + home.selectedWidget()
      : "none"))
    if (home.carry)
      lines.push("carry=" + (home.carry.page - home.firstTiles + 1) + ":" + (home.carry.i + 1)
                 + " moved=" + home.carry.moved + " over=" + (home.carry.target - home.firstTiles + 1)
                 + " edge=" + home.carry.edge + " at=" + Math.round(home.carry.fx) + "," + Math.round(home.carry.fy))
    return lines.join("\n")
  }

  // ------------------------------------------------------- arranging (§K)
  //
  // The editor's state. `editing` is the selected tile; `carry` is a tile under
  // a finger, from a long press that went on moving (HM42) or a drag inside the
  // selected one (HM44); `live` is a resize under way (HM45). Tiles are named
  // by page (an index into `pages`) and `i`, their place in that page's list
  // as written, which Layout.place() hands back with each placed tile.
  property var editing: null          // { page, i }
  property var carry: null            // see liftAt()
  property var live: null             // { page, i, cell }
  readonly property bool arranging: home.editing !== null

  readonly property int carryEdge: Style.space(28)
  readonly property int dragSlopPx: Style.space(10)

  function placedOn(pageIndex) {
    var p = home.pages[pageIndex]
    if (!p || p.kind !== "tiles") return { tiles: [], dropped: [] }
    return Layout.place(p.tiles, home.grid.columns, home.grid.rows)
  }

  // How far right of home's own coordinates a page is drawn right now.
  function pageOffset(pageIndex) { return (pageIndex - home.pagePosition) * home.width }

  // The placed cell of tile `i` on a page, or null.
  function cellOf(pageIndex, i) {
    var t = home.placedOn(pageIndex).tiles
    for (var k = 0; k < t.length; k++) if (t[k].i === i) return t[k]
    return null
  }

  // The selected tile's rectangle in home's coordinates, resize included.
  readonly property var selectedRect: {
    if (!home.editing) return null
    var c = (home.live && home.live.page === home.editing.page && home.live.i === home.editing.i)
      ? home.live.cell : home.cellOf(home.editing.page, home.editing.i)
    if (!c) return null
    var r = Layout.rect(home.grid, c)
    r.x += home.pageOffset(home.editing.page)
    return r
  }

  // The tile under a point of home, on the page showing, or null. The foot is
  // no tile, and neither is anything while a page is still turning.
  function tileAt(hx, hy) {
    if (home.pagePosition !== Math.round(home.pagePosition)) return null
    if (hy >= home.layoutHeight - home.footHeight) return null
    var t = home.placedOn(home.page).tiles
    var k = Layout.under(home.grid, t, hx, hy)
    return k < 0 ? null : { page: home.page, i: t[k].i, cell: t[k] }
  }

  function select(pageIndex, i) {
    menu.open = false
    homeMenu.open = false
    home.editing = { page: pageIndex, i: i }
  }
  function endEdit() {
    home.editing = null
    home.carry = null
    home.live = null
    shareCard.open = false
  }

  // HM37, HM42. The router's long press, in scene coordinates: on a tile it
  // selects it and lifts it, so the same finger can carry it; anywhere else it
  // is the home menu.
  function holdAt(sceneX, sceneY) {
    var q = home.mapFromItem(null, sceneX, sceneY)
    var t = home.tileAt(q.x, q.y)
    if (!t) { home.openMenu(); return "menu" }
    home.select(t.page, t.i)
    home.carryStart(t.page, t.i, t.cell, q.x, q.y)
    return "tile"
  }
  function liftMove(sceneX, sceneY) {
    var q = home.mapFromItem(null, sceneX, sceneY)
    home.carryMove(q.x, q.y)
  }
  function liftEnd() { home.carryEnd() }
  function liftCancel() { home.carry = null }

  // HM44. A tile picked up at (hx, hy). It is not carried until the finger
  // passes the slop, so a long press that lifts where it pressed only selects.
  function carryStart(pageIndex, i, cell, hx, hy) {
    var r = Layout.rect(home.grid, cell)
    home.carry = { page: pageIndex, i: i, cell: cell,
                   holdX: hx - (r.x + home.pageOffset(pageIndex)), holdY: hy - r.y,
                   startX: hx, startY: hy, fx: hx, fy: hy, moved: false,
                   target: pageIndex, preview: null, swap: -1, edge: 0 }
  }

  function carryMove(hx, hy) {
    var c = home.carry
    if (!c) return
    var n = Object.assign({}, c)
    n.fx = hx
    n.fy = hy
    if (!n.moved && Math.max(Math.abs(hx - c.startX), Math.abs(hy - c.startY)) > home.dragSlopPx)
      n.moved = true
    if (n.moved) {
      n.target = home.page
      n.preview = null
      n.swap = -1
      var tp = home.pages[n.target]
      if (tp && tp.kind === "tiles") {
        // Left of page 1 only faces go, and a face is no cell to land in.
        var others = home.placedOn(n.target).tiles.filter(function (t) {
          return !(n.target === n.page && t.i === n.i)
        })
        var k = Layout.under(home.grid, others, hx, hy)
        if (k >= 0) n.swap = others[k].i
        else n.preview = Layout.dropCell(home.grid, n.cell, hx - n.holdX, hy - n.holdY, others)
      }
      n.edge = hx < home.carryEdge ? -1 : (hx > home.width - home.carryEdge ? 1 : 0)
    }
    home.carry = n
  }

  // HM44. Held at a side edge, the page turns; then it waits longer, so the
  // page just reached can be looked at before the next one comes.
  Timer {
    id: edgeTurn
    interval: 600
    running: home.carry !== null && home.carry.moved && home.carry.edge !== 0
    repeat: true
    onTriggered: {
      var next = home.page + home.carry.edge
      if (next >= 0 && next < home.pages.length) home.goTo(next)
      edgeTurn.interval = 1200
      Qt.callLater(function () { if (home.carry) home.carryMove(home.carry.fx, home.carry.fy) })
    }
    onRunningChanged: if (!edgeTurn.running) edgeTurn.interval = 600
  }

  // HM44. Lifted where it was pressed: still selected. Dropped: swapped, moved,
  // or back where it came from; and a drag ends edit mode either way.
  function carryEnd() {
    var c = home.carry
    home.carry = null
    if (!c || !c.moved) return
    var tp = home.pages[c.target]
    if (tp && tp.kind === "tiles") {
      if (c.swap >= 0) {
        home.commit(function (next) {
          var a = next[c.page].tiles[c.i]
          var b = next[c.target].tiles[c.swap]
          var ra = { x: a.x, y: a.y, w: a.w, h: a.h }
          var rb = { x: b.x, y: b.y, w: b.w, h: b.h }
          Object.assign(a, rb)
          Object.assign(b, ra)
          // Across pages they trade pages too.
          if (c.page !== c.target) {
            next[c.page].tiles[c.i] = b
            next[c.target].tiles[c.swap] = a
          }
        })
      } else if (c.preview) {
        home.commit(function (next) {
          var t = next[c.page].tiles[c.i]
          Object.assign(t, { x: c.preview.x, y: c.preview.y, w: c.preview.w, h: c.preview.h })
          if (c.page !== c.target) {
            next[c.page].tiles.splice(c.i, 1)
            next[c.target].tiles.push(t)
          }
        })
      }
    }
    home.endEdit()
  }

  // HM45. Lifting after a resize keeps the tile selected.
  function resizeTo(cell) {
    if (!home.editing) return
    home.live = { page: home.editing.page, i: home.editing.i, cell: cell }
  }
  function resizeEnd() {
    var l = home.live
    if (!l) return
    home.commit(function (next) {
      Object.assign(next[l.page].tiles[l.i], { x: l.cell.x, y: l.cell.y, w: l.cell.w, h: l.cell.h })
    })
  }

  // HM48. One write, through the one writer. Every page of tiles goes out at
  // the cells it is drawn at, so the file says what the screen shows; a tile
  // with no room keeps the size it asked for and no position, as written.
  // Layout.written() leaves out what waits and what emptied (HM51, HM52), and
  // what is drawn next is that, read back the way the file will be -- so the
  // read-back finds nothing to change.
  function commit(change) {
    var next = []
    for (var p = 0; p < home.pages.length; p++) {
      var page = home.pages[p]
      if (page.kind !== "tiles") { next.push(page); continue }
      var at = {}
      var placed = home.placedOn(p).tiles
      for (var k = 0; k < placed.length; k++) at[placed[k].i] = placed[k]
      var tiles = []
      for (var j = 0; j < page.tiles.length; j++) {
        var t = page.tiles[j]
        var c = at[j]
        tiles.push(c ? { widget: t.widget, x: c.x, y: c.y, w: c.w, h: c.h }
                     : { widget: t.widget, x: -1, y: -1, w: t.w, h: t.h })
      }
      next.push({ kind: "tiles", tiles: tiles, waiting: page.waiting === true })
    }
    change(next)
    home.live = null
    var out = Layout.written(next)
    home.showPages(Layout.withWaiting(Layout.pages({ page: out })).pages)
    writer.command = ["moarchy-home", "set", JSON.stringify({ page: out })]
    writer.running = true
  }

  Process {
    id: writer
    // A refused write leaves the file as it was; reading it again puts the
    // screen back to what the file says, rather than showing a layout that
    // was never saved.
    onExited: (code, status) => {
      if (code === 0) return
      console.warn("home: moarchy-home set refused the arrangement (exit " + code + ")")
      home.parsed = null
      layoutFile.reload()
    }
  }

  // ------------------------------------------------------ the action bar (HM46)
  function selectedWidget() {
    if (!home.editing) return ""
    var p = home.pages[home.editing.page]
    var t = p && p.tiles ? p.tiles[home.editing.i] : null
    return t ? t.widget : ""
  }
  readonly property bool selectedShipped: WidgetList.entry("home", home.selectedWidget()) !== null

  function removeSelected() {
    var e = home.editing
    if (!e) return
    home.commit(function (next) { next[e.page].tiles.splice(e.i, 1) })
    home.endEdit()
  }

  // HM46. The agent gets the file and the skill; a shipped widget is copied to
  // the user's own first, because the packaged file is not theirs to change.
  function editSelected() {
    var id = home.selectedWidget()
    var e = home.editing
    if (!id || !e) return
    var where = "the tile on home page " + (e.page - home.firstTiles + 1) + ", number " + (e.i + 1)
                + " in its list in ~/.config/omarchy/home.toml"
    var prompt = home.selectedShipped
      ? "Use the moarchy skill. My home tile \"" + id + "\" (" + where + ") is a shipped widget, "
        + "/usr/share/moarchy/plugins/moarchy.common/widgets/" + WidgetList.fileFor(id) + ". "
        + "Copy it to ~/.config/omarchy/widgets/" + id + "-mine.qml, point that tile at \""
        + id + "-mine\" with moarchy-home, then ask me what I want changed."
      : "Use the moarchy skill. My home widget \"" + id + "\" (" + where + ") is "
        + "~/.config/omarchy/widgets/" + id + ".qml. Read it, then ask me what I want changed."
    home.endEdit()
    ShellApps.goToFreeWorkspace(home.shell)
    agents.ask(prompt)
  }

  // HM53. What the agent is called on home, and the two things it is asked to
  // make. Through `moarchy-agent ask`, which opens the agent picker when none
  // is chosen, on a free workspace as the prompt bar's ask is (HM23).
  readonly property string agentName: agents.current || "an agent"

  function askAgent(prompt) {
    homeMenu.open = false
    home.endEdit()
    ShellApps.goToFreeWorkspace(home.shell)
    agents.ask(prompt)
  }

  function createWidget(pageIndex) {
    var n = Math.max(1, pageIndex - home.firstTiles + 1)
    home.askAgent("Use the moarchy skill. Make me a new home widget for page " + n + " of home. "
                  + "Ask me what it should show, then write it to ~/.config/omarchy/widgets/<a fitting id>.qml "
                  + "and put it on that page with `moarchy-home add <id> " + n + "`.")
  }

  function createFace() {
    home.askAgent("Use the moarchy skill. Make me a new face for home, left of my other pages. "
                  + "Ask me what it should be, then write it to ~/.config/omarchy/faces/<a fitting name>.qml "
                  + "and add it with `moarchy-home face <name>`.")
  }

  function shareSelected() {
    var id = home.selectedWidget()
    if (!id || home.selectedShipped) return
    shareCard.widgetId = id
    shareCard.open = true
  }

  // ------------------------------------------------------------- the menu
  // HM37, HM38. What a long press on home opens; the surface's router decides
  // that a press was one, and leaving home or the back swipe closes it.
  readonly property bool menuOpen: homeMenu.open
  function openMenu(): void {
    menu.open = false            // the agent menu, if it was up
    homeMenu.open = true
  }
  function closeMenu(): void { homeMenu.open = false }

  IpcHandler {
    target: "home"

    function report(): string { return home.report() }
    function page(): string { return String(home.page - home.firstTiles + 1) }
    // 1 is the first page of tiles, 0 and below are faces (HM4). Not `goto`,
    // which older JavaScript reserves.
    function go(n: string): string {
      var v = parseInt(n, 10)
      if (!isFinite(v)) return "usage: go <page>"
      home.goTo(home.firstTiles + v - 1)
      return "ok"
    }
    // HM41.
    function menu(action: string): string {
      if (action === "open") home.openMenu()
      else if (action === "close") home.closeMenu()
      else if (action !== "state") return "usage: menu open|close|state"
      return home.menuOpen ? "open" : "closed"
    }
    // owl.md OW11. The page a w x h tile goes on, starting from `page`: that one
    // if it has room, else the next that has, else the spare page after the
    // last -- which a tile there makes a page (HM51). Asked by moarchy-owl,
    // which cannot know the grid's size.
    function room(page: string, w: string, h: string): string {
      var from = home.firstTiles + Math.max(1, parseInt(page, 10) || 1) - 1
      var tw = Math.max(1, parseInt(w, 10) || 1), th = Math.max(1, parseInt(h, 10) || 1)
      for (var p = from; p < home.pages.length; p++) {
        var pg = home.pages[p]
        if (pg.kind !== "tiles") continue
        var before = Layout.place(pg.tiles, home.grid.columns, home.grid.rows)
        var after = Layout.place(pg.tiles.concat([{ widget: "_", x: -1, y: -1, w: tw, h: th }]),
                                 home.grid.columns, home.grid.rows)
        if (after.dropped.length === before.dropped.length) return String(p - home.firstTiles + 1)
      }
      return String(home.pages.length - home.firstTiles + 1)
    }
    // HM49. "1:2" is page 1's second tile as the file lists it; "none" ends.
    function edit(spec: string): string {
      if (spec === "none") { home.endEdit(); return "none" }
      var m = String(spec).match(/^(-?\d+):(\d+)$/)
      if (!m) return "usage: edit <page>:<n> | none"
      var p = home.firstTiles + parseInt(m[1], 10) - 1
      var i = parseInt(m[2], 10) - 1
      var pg = home.pages[p]
      if (!pg || pg.kind !== "tiles" || i < 0 || i >= pg.tiles.length) return "no tile " + spec
      home.goTo(p)
      home.select(p, i)
      return "ok"
    }
    // HM7, HM14a. Recompile every face and user widget from disk.
    function reload(): string {
      home.revision++
      layoutFile.reload()
      return "ok"
    }
  }

  // ================================================================== drawing

  // Empty space is the wallpaper's own drag (gestures.md D1) and, now, the
  // page's and the control center's (HM5, HM26). Under every tile, so a tile's
  // own controls take their touches first and hand them on the same way.
  Shared.SheetDragArea {
    anchors.fill: parent
    sheet: home.sheet
  }

  Item {
    id: track
    width: home.width
    height: home.height
    x: -home.pagePosition * home.width

    Repeater {
      id: pageRepeater
      model: home.pages
      delegate: Item {
        id: pageItem
        required property var modelData
        required property int index
        x: pageItem.index * home.width
        // The page a tile is carried from draws over the others, so the tile
        // is not hidden under the page it is carried onto.
        z: home.carry !== null && home.carry.page === pageItem.index ? 1 : 0
        width: home.width
        height: home.height
        // Only the page on screen and its neighbours are built, so a home of
        // eight pages costs three pages of widgets.
        readonly property bool near: Math.abs(pageItem.index - home.pagePosition) < 1.5

        function describe(): string {
          var head = "page " + (pageItem.index - home.firstTiles + 1) + " "
          if (pageItem.modelData.kind === "invite") return head + "invite"
          if (pageItem.modelData.waiting && pageItem.modelData.tiles.length === 0) return head + "spare"
          if (pageItem.modelData.kind === "face")
            return head + "face=" + pageItem.modelData.face
                   + (faceLoader.item ? "" : " state=" + faceLoader.faceState)
          return head + (tilesLoader.item ? tilesLoader.item.describe() : "tiles (not built)")
        }
        function refresh(): void {
          if (tilesLoader.item) tilesLoader.item.refresh()
        }

        // ----------------------------------------------------------- a face
        // Beside the Loader rather than inside it: a Loader's children are its
        // one item, and a second object declared in it is a fight over that.
        FileView {
          id: faceProbe
          path: faceLoader.name ? faceLoader.userPath : ""
          printErrors: false
          watchChanges: true
          onLoaded: faceLoader.userExists = true
          onLoadFailed: faceLoader.userExists = false
          onFileChanged: Qt.callLater(function () { faceProbe.reload(); home.revision++ })
        }

        Loader {
          id: faceLoader
          anchors.fill: parent
          active: pageItem.modelData.kind === "face" && pageItem.near
          readonly property string name: pageItem.modelData.face || ""
          readonly property string userPath:
            (Quickshell.env("HOME") || "") + "/.config/omarchy/faces/" + faceLoader.name + ".qml"
          property bool userExists: false
          property string faceState: "loading"

          // HM7. The user's face wins by name over the packaged one.
          // The query is only on the user's file, which is the only one that
          // changes while the shell runs; see HomeTile for why it is there.
          readonly property string url: faceLoader.userExists
            ? "file://" + faceLoader.userPath + "?r=" + home.revision
            : String(Qt.resolvedUrl("faces/" + faceLoader.name + ".qml"))

          function load(): void {
            if (!faceLoader.active || faceLoader.name === "") return
            faceLoader.setSource(faceLoader.url, { host: home, shell: home.shell })
          }
          onActiveChanged: faceLoader.load()
          onUrlChanged: faceLoader.load()
          Component.onCompleted: faceLoader.load()
          onStatusChanged: {
            faceLoader.faceState = faceLoader.status === Loader.Ready ? "ok"
                                 : faceLoader.status === Loader.Error ? "error" : "loading"
            if (faceLoader.status === Loader.Error)
              console.warn("home: face " + faceLoader.name + " did not load from " + faceLoader.url)
          }
        }

        // HM7. A face that resolves to nothing says which file it looked for.
        Text {
          anchors.centerIn: parent
          width: parent.width - Style.space(48)
          visible: pageItem.modelData.kind === "face" && faceLoader.faceState === "error"
          text: "face \"" + faceLoader.name + "\" did not load\n" + faceLoader.userPath
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignHCenter
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: home.textWeight
          color: home.subdued
        }

        // ------------------------------------------------- the face invite
        // HM51. Left of the leftmost page: a page waiting for a face of the
        // user's own, which the agent builds (HM53). Omalauncher's FaceInvite.
        HomeFrame {
          visible: pageItem.modelData.kind === "invite"
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(48), Style.space(320))
          height: inviteColumn.implicitHeight + Style.space(40)
          host: home

          Column {
            id: inviteColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(20)
            spacing: Style.space(12)

            Text {
              text: "a face of your own"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: home.textWeight
              color: home.accent
            }
            Text {
              width: parent.width
              text: "This page is yours to fill with a face: a feed, a dashboard, a start page, a game. "
                    + "Say what you want and " + home.agentName + " builds it here, full screen."
              wrapMode: Text.Wrap
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.weight: home.textWeight
              color: home.textOnSurface
            }
            Item {
              width: parent.width
              height: Style.space(44)
              Shared.PressVeil {
                anchors.fill: parent
                ink: home.accent
                on: inviteArea.pressed && !home.sheetDragging
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "[ create with " + home.agentName + " ]"
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.weight: home.textWeight
                color: home.accent
              }
              // Through the router like every control on home, so a swipe that
              // starts on the button still turns the page (HM14b).
              Shared.SheetDragArea {
                id: inviteArea
                anchors.fill: parent
                sheet: home.sheet
                onClicked: if (!home.sheetWasDrag) home.createFace()
              }
            }
          }
        }

        // HM51. An empty page of tiles says how one gets a tile.
        HomeFrame {
          visible: pageItem.modelData.kind === "tiles" && pageItem.modelData.tiles.length === 0
          anchors.horizontalCenter: parent.horizontalCenter
          y: Math.max(0, (home.layoutHeight - home.footHeight - height) / 2)
          width: emptyText.implicitWidth + Style.space(24)
          height: emptyText.implicitHeight + Style.space(12)
          host: home
          Text {
            id: emptyText
            anchors.centerIn: parent
            text: "no widgets on this page \u00b7 long-press for a new one"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: home.textWeight
            color: home.subdued
          }
        }

        // --------------------------------------------------- a page of tiles
        Loader {
          id: tilesLoader
          anchors.fill: parent
          active: pageItem.modelData.kind === "tiles" && pageItem.near
          sourceComponent: Item {
            id: tilesPage

            readonly property var placed: Layout.place(pageItem.modelData.tiles,
                                                       home.grid.columns, home.grid.rows)

            function describe(): string {
              var out = "tiles"
              for (var i = 0; i < tileRepeater.count; i++) {
                var t = tileRepeater.itemAt(i)
                if (!t) continue
                var m = tilesPage.placed.tiles[i]
                out += "\n  " + m.widget + " " + m.x + "," + m.y + " " + m.w + "x" + m.h
                       + " state=" + t.tileState + (t.kind === "owl" ? " owl" : "")
                if (t.error !== "") out += " error=" + t.error
                if (t.tileState === "missing") out += " missing=" + m.widget
                if (t.tileState === "unavailable") out += " available=0"
              }
              if (tilesPage.placed.dropped.length)
                out += "\n  dropped=" + tilesPage.placed.dropped.join(",")
              out += "\n  prompt-bar=" + (home.showBar ? "shown" : "hidden")
              return out
            }
            function refresh(): void {
              for (var i = 0; i < tileRepeater.count; i++) {
                var t = tileRepeater.itemAt(i)
                if (t) t.refresh()
              }
            }

            Repeater {
              id: tileRepeater
              model: tilesPage.placed.tiles
              delegate: HomeTile {
                id: tileItem
                required property var modelData
                // HM44, HM45. A tile being resized is drawn at its live cell; a
                // carried one under the finger, in home's coordinates less where
                // this page is drawn, so it stays put while pages turn under it.
                readonly property bool carried: home.carry !== null && home.carry.moved
                  && home.carry.page === pageItem.index && home.carry.i === tileItem.modelData.i
                readonly property var cellNow: (home.live && home.live.page === pageItem.index
                                                && home.live.i === tileItem.modelData.i)
                  ? home.live.cell : tileItem.modelData
                readonly property var r: Layout.rect(home.grid, tileItem.cellNow)
                x: tileItem.carried ? home.carry.fx - home.carry.holdX - home.pageOffset(pageItem.index)
                                    : tileItem.r.x
                y: tileItem.carried ? home.carry.fy - home.carry.holdY : tileItem.r.y
                z: tileItem.carried ? 10 : 0
                opacity: tileItem.carried ? 0.9 : 1
                width: tileItem.r.width
                height: tileItem.r.height
                host: home
                widgetId: tileItem.modelData.widget
                revision: home.revision
                cols: tileItem.cellNow.w
                rows: tileItem.cellNow.h
                // owl.md OW4: home on screen, and this page the one showing.
                showing: !home.covered && pageItem.index === home.page
              }
            }
          }
        }
      }
    }
  }

  // ----------------------------------------------------------------- the foot
  //
  // HM20, HM21. Under the grid on every page of tiles, sliding with it: a face
  // has the whole page, so the foot goes when a face comes in. Its opacity
  // follows how far the current position is from the nearest page of tiles.
  Column {
    id: foot
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: home.gapOut
    anchors.rightMargin: home.gapOut
    // Placed against layoutHeight, not anchored to the bottom, for the same
    // reason the grid is: the keyboard covers it rather than pushing it up
    // over the tiles.
    y: home.layoutHeight - home.gapOut - foot.height
    spacing: home.gapIn
    opacity: {
      // HM20, HM4. Shown on pages of tiles and not on faces, which can sit
      // either side of page 1 now: between two pages, in proportion.
      var a = Math.floor(home.pagePosition)
      var b = Math.ceil(home.pagePosition)
      var t = home.pagePosition - a
      function on(i) { var p = home.pages[i]; return p && p.kind === "tiles" ? 1 : 0 }
      return Math.max(0, Math.min(1, on(a) * (1 - t) + on(b) * t))
    }
    visible: opacity > 0

    // ------------------------------------------------------------ recent
    HomeFrame {
      id: recentFrame
      host: home
      width: parent.width
      height: home.recentHeight
      visible: home.showRecent

      Row {
        anchors.fill: parent
        anchors.margins: recentFrame.inset + Style.space(4)
        spacing: Style.space(4)

        Repeater {
          model: home.recent
          delegate: Item {
            id: recentItem
            required property var modelData
            width: Math.min(Style.space(48), (recentFrame.width - Style.space(16)) / Math.max(1, ui.homeRecent))
            height: parent.height

            Image {
              anchors.centerIn: parent
              width: Math.min(parent.width, parent.height) - Style.space(6)
              height: width
              sourceSize.width: width
              sourceSize.height: height
              asynchronous: true
              source: Apps.iconFor(home.shell, home.appIdIndex, recentItem.modelData)
            }

            Shared.SheetDragArea {
              anchors.fill: parent
              sheet: home.sheet
              onClicked: if (!home.sheetWasDrag)
                ShellApps.focusToplevel(home.shell, recentItem.modelData)
            }
          }
        }
      }
    }

    // -------------------------------------------------------- prompt bar
    // HM22. A picture of a field: the tap raises the drawer with its field
    // live. Home asks for no keyboard focus, ever.
    HomeFrame {
      id: bar
      host: home
      width: parent.width
      height: home.barHeight
      visible: home.showBar

      Shared.SheetDragArea {
        anchors.fill: parent
        sheet: home.sheet
        onClicked: if (!home.sheetWasDrag) home.promptTapped()
      }

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(14)
        spacing: Style.space(10)

        Shared.AgentChip {
          id: chip
          anchors.verticalCenter: parent.verticalCenter
          agent: agents.current
          accent: home.accent
          subdued: home.subdued
          ink: home.textOnSurface
          radiusTile: home.radiusTile
          textWeight: home.textWeight
          open: menu.open
          onTapped: {
            var p = chip.mapToItem(home, 0, 0)
            var b = bar.mapToItem(home, 0, 0)
            menu.anchorX = p.x
            menu.anchorY = b.y
            menu.anchorBottom = b.y + bar.height
            menu.open = true
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - chip.width - parent.spacing
          text: home.placeholder
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: home.textWeight
          color: home.subdued
        }
      }
    }
  }

  // HM24. Over everything on home while open.
  Shared.AgentMenu {
    id: menu
    anchors.fill: parent
    agents: agents
    shell: home.shell
    surface: Util.alpha(Upstream.Color.background, Math.max(0.94, ui.homeOpacity))
    textOnSurface: home.textOnSurface
    subdued: home.subdued
    accent: home.accent
    borderColor: home.frameBorderColor
    borderWidth: home.frameBorder
    radiusCard: home.radiusFrame
    textWeight: home.textWeight
    onClosed: menu.open = false
  }

  // §K. Over the pages and the foot while a tile is selected or carried.
  HomeArrange {
    anchors.fill: parent
    host: home
  }

  HomeShare {
    id: shareCard
    anchors.fill: parent
    host: home
    onClosed: shareCard.open = false
  }

  HomeMenu {
    id: homeMenu
    anchors.fill: parent
    host: home
    onClosed: homeMenu.open = false
  }
}
