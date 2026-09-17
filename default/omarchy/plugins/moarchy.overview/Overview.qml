// The overview: every workspace as a card, and a window you can pick up.
//
// Implements docs/gestures.md §P. AC ids in comments below refer to that file,
// which is the contract; this file is one way of meeting it.
//
// ---------------------------------------------------------------------------
// What this is for
// ---------------------------------------------------------------------------
// The sideways swipe steps one workspace at a time (B1) and the drawer lists
// every window in one flat shelf (M). Neither answers "where is everything",
// and on a phone where a workspace *is* an app that question is the map. So:
// one card per workspace, in number order, each holding the windows on it --
// which is also the only surface on this phone that can say a workspace holds
// two.
//
// ---------------------------------------------------------------------------
// Why it owns no edge
// ---------------------------------------------------------------------------
// moarchy.gestures owns the right edge, the same way it owns the bottom strip
// and the left edge: two exclusive layer surfaces cannot share an edge, and
// every gesture on this phone is read by the one plugin that holds the seat.
// This sheet is only ever a destination, driven through `progress` frame by
// frame while the finger moves (P2).
//
// ---------------------------------------------------------------------------
// Why Top and not Overlay
// ---------------------------------------------------------------------------
// The drawer's reason, minus the keyboard. A sheet on Top with a zero exclusive
// zone is arranged into what the exclusive surfaces left -- below the bar,
// above the home pill -- with no geometry maths here. Overlay would put it over
// the bar, which is the one piece of chrome that should stay readable while you
// are looking at a map of the phone.
//
// It takes no keyboard focus at all, which the drawer cannot afford to do: this
// screen has no field to type in, and Exclusive focus deactivates the window
// underneath. That window is precisely what the focused card is drawn from
// (P4), so taking focus would blank the one marker the map exists to carry.
import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui
import "Tree.js" as Tree
import "../moarchy.common/Apps.js" as Apps
import "../moarchy.common/ShellApps.js" as ShellApps
import "../moarchy.common/Theme.js" as Theme
import "../moarchy.common/Sheet.js" as Sheet
import "../moarchy.common" as Shared

Item {
  id: root

  // Injected by the host in the panel Loader's onLoaded, by name and after
  // construction. It may not be `readonly` or `required`: readonly makes the
  // assignment throw, and required makes the component fail to instantiate at
  // all, because a plugin is created first and configured afterwards. Either
  // way the failure is silent.
  property var shell: null

  readonly property string pluginId: "moarchy.overview"

  // ---------------------------------------------------------------- the sheet
  //
  // P2. 0 shut .. 1 open, and the right-edge drag writes it directly, the way
  // the strip writes the drawer's. That is what makes this follow the finger
  // rather than appear at a threshold.
  property real progress: 0

  // Set by the gestures plugin for the length of the drag. It turns the
  // animation off (so writes track 1:1) and keeps `opened` honest mid-gesture.
  property bool dragging: false

  // shell.isPluginOpen() reads this by name to decide what toggle() means, so
  // it has to stay honest. Half-dragged is neither open nor shut.
  readonly property bool opened: root.progress >= 1 && !root.dragging

  Behavior on progress {
    enabled: !root.dragging
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }

  // P9. Mapped once the edge drag has latched, not on press. The gestures
  // plugin sets it, the same way it warms the drawer -- most presses on an edge
  // are not the gesture that opens the sheet, and a surface warmed for one that
  // never happened is a full-screen composite nobody asked for.
  property bool warming: false
  readonly property bool surfaceUp: root.progress > 0 || root.warming

  // The one place `sheetWidth` is written. Guarded on a number that could only
  // be the shut band (P8), and no phone this runs on has a 100px-wide screen.
  //
  // Not `overviewWindow.width`: shut, this window is a one-pixel column, and
  // the drag that *opens* the sheet necessarily starts while it is. Dividing a
  // drag by the band moves the sheet hundreds of times finger speed until the
  // surface grows -- the drawer records the same trap on the other axis.
  property real sheetWidth: 0

  readonly property real closeTravel: Math.max(1,
    root.sheetWidth > 0 ? root.sheetWidth
                        : (overviewWindow.screen ? overviewWindow.screen.width : 360))

  // P2. Seven tenths across, which is the drawer's own commit fraction: the two
  // sheets are dragged the same way on different axes, and a phone with one
  // threshold for "far enough" is a phone you only have to learn once.
  readonly property real closeCommit: 0.7
  readonly property int dragSlop: Style.space(10)
  readonly property real sheetFling: 0.3

  // P2, on the shared tracker (docs/refactor.md F1). This sheet is open and
  // rightward is the way out of it, so `latchSign` is +1 -- and leftward is
  // what would raise progress, so `openDirection` is -1.
  Shared.DragTracker {
    id: sheetDrag
    axis: "x"
    travel: root.closeTravel
    openDirection: -1
    latchSign: 1
    // P6. A vertical drag on this sheet scrolls the list of cards, and a card
    // list that shut the sheet whenever a thumb's arc wandered sideways would
    // be a list nobody could scroll.
    axisDominant: true
    slop: root.dragSlop
    startFrom: root.progress

    onBegan: root.dragging = true
    onMoved: p => root.progress = p

    // The numbers stay here (F3). `v` is signed toward open, so a fling shut is
    // the negative one.
    onFinished: (p, v) => {
      root.dragging = false
      if (v <= -root.sheetFling) root.dismiss()
      else if (v >= root.sheetFling) root.progress = 1
      else if (p <= root.closeCommit) root.dismiss()
      else root.progress = 1
    }

    onStranded: root.markTrace(-2)

    // Guarded on `dragging`, which no other sheet here needs to be. Every lift
    // (P6) cancels this tracker on the frame the hold fires, and an unguarded
    // handler would write a -1 into the trace and re-assert `progress` for a
    // gesture that was never a sheet drag -- so a drag trace would end in -1
    // every time somebody moved a window, and G12's evidence sentence would
    // stop meaning what it says.
    onCanceled: from => {
      if (!root.dragging) return
      root.markTrace(-1)
      root.dragging = false
      root.progress = from
    }
  }

  readonly property bool sheetDragging: sheetDrag.latched
  readonly property bool sheetWasDrag: sheetDrag.wasDrag
  readonly property real sheetPressX: sheetDrag.startX
  readonly property real sheetPressY: sheetDrag.startY

  // P6. While a window is in the air the sheet is not being dragged, and the
  // two gestures share one finger -- so the forwarding stops rather than the
  // tracker being asked to arbitrate. The lift itself cancels the tracker on
  // the frame it fires; these keep it cancelled for the rest of the touch.
  function sheetPress(item, mouse): void {
    if (root.lifted) return
    // P6. Cleared here rather than where the lift is armed, and that is not
    // tidiness: only a tile arms a lift, so clearing it there leaves the flag
    // standing after a drop -- and the next tap on a *card* reads it and does
    // nothing. Every control on this sheet presses through this function, which
    // is what makes it the one place the flag can be retired from. Same
    // ordering, and the same reason, as `wasDrag`: cleared on the next press,
    // never on release, because Qt delivers `clicked` after `released`.
    root.liftFired = false
    var p = item.mapToItem(null, mouse.x, mouse.y)
    sheetDrag.press(p.x, p.y)
  }

  function sheetMove(item, mouse): void {
    if (root.lifted) return
    var p = item.mapToItem(null, mouse.x, mouse.y)
    sheetDrag.move(p.x, p.y)
  }

  function sheetRelease(): void { sheetDrag.release() }
  function sheetCancel(): void { sheetDrag.cancel() }

  // Diagnostic only, and cheap enough to leave in: one integer per frame while
  // a drag is in flight, cleared when the next one starts. The drawer's
  // `dragTrace` and the back edge's `backTrace` are the same instrument, and
  // for the same reason -- polling `progress` over IPC is slower than the thing
  // being sampled, so an animation and a finger look identical from outside.
  property var dragTrace: []

  function markTrace(marker): void {
    var next = root.dragTrace.slice()
    next.push(marker)
    root.dragTrace = next
  }

  onDraggingChanged: if (root.dragging) root.dragTrace = []

  onProgressChanged: {
    if (!root.dragging) return
    var next = root.dragTrace.slice()
    if (next.length < 200) next.push(Math.round(root.progress * 100))
    root.dragTrace = next
  }

  // ---------------------------------------------------------------- the board
  //
  // P3. What sway is holding, read through moarchy.overview/Tree.js. Kept from
  // the last good answer rather than emptied on a parse failure: a card list
  // that blinks out and back is worse than one that waits a beat.
  property var board: []

  readonly property int freeNumber: Tree.freeNumber(root.board)

  // The cards, which are the board plus the one that is not a workspace yet.
  //
  // P7. A trailing card for the next free number, so "somewhere else" is a
  // place on screen you can drop onto rather than a gesture you have to know.
  // It is the same number the strip's home swipe would take you to and the same
  // one bin/moarchy-one-app-per-workspace would pick for a new window (F1) --
  // one rule, read here off the board so the card and the drop agree.
  readonly property var cards: {
    var out = []
    var live = root.board || []
    for (var i = 0; i < live.length; i++) out.push(live[i])
    out.push({
      number: root.freeNumber, name: "", focused: false,
      layout: "", windows: [], fresh: true
    })
    return out
  }

  // P3. One `swaymsg` per refresh, and refreshes only while the sheet is up.
  //
  // A Process and not I3: Quickshell's I3 object publishes workspaces and
  // dispatches commands and has no window list at all (Tree.js says why). This
  // is the same way the rest of this shell reads anything the QML APIs do not
  // expose -- rfkill, brightnessctl, mmcli -- and it is one fork per change
  // rather than a subscription this plugin would have to hold while shut.
  Shared.Probe {
    id: treeProbe
    command: ["swaymsg", "-r", "-t", "get_tree"]
    // Named rather than taken from scope: `text` is a property on half the
    // types in QtQuick, and qmllint calls the bare form ambiguous for exactly
    // that reason.
    onAnswered: json => root.receiveTree(json)
  }

  function receiveTree(json: string): void {
    var next = Tree.workspaces(json)
    if (next) root.board = next
  }

  // P9. The whole of keepLoaded's bargain: shut, this plugin runs nothing. A
  // plugin that polled the compositor in its unopened window would cost the
  // shell a fork per tick for a surface nobody is looking at.
  function refresh(): void {
    if (!root.surfaceUp) return
    // Never under a window that is in the air. `board` is rebuilt rather than
    // mutated, so a refresh mid-lift hands the ghost a stale object and the
    // tile it came from stops recognising itself -- the drop still lands,
    // because a con_id outlives the array it was read from, but the card it
    // left goes back to full strength with the window apparently still on it.
    if (root.lifted) return
    if (!treeProbe.running) treeProbe.running = true
  }

  // A move is not a workspace event and often not a window event either --
  // moving a window between two workspaces that both already exist changes
  // neither list -- so nothing below would fire and the card the window left
  // would keep drawing it.
  //
  // Four reads over about two thirds of a second, and the later ones are why.
  // The first is soon enough to read as part of the drop; but P7's
  // reconciliation is a *second* actor on the same sway event, and a `layout`
  // command moves neither the workspace list nor the toplevel list -- so a
  // board read that wins that race leaves the card saying SPLIT over a pair
  // that is already tabs, with nothing left to fire and correct it. Bounded
  // rather than left running: a timer that polls the compositor for as long as
  // the sheet is up is the thing P9 exists to refuse.
  Timer {
    id: settle
    interval: 160
    repeat: true
    property int ticks: 0
    onTriggered: {
      root.refresh()
      settle.ticks++
      if (settle.ticks >= 4) settle.stop()
    }

    function begin(): void { settle.ticks = 0; settle.restart() }
  }

  // Sway's own events, through the two the shell already watches. A workspace
  // appearing or emptying moves `I3.workspaces`; a window mapping or closing
  // moves the toplevel list. Between them they cover everything that changes
  // the board without this sheet having asked for it.
  Connections {
    target: I3.workspaces
    enabled: root.surfaceUp
    function onValuesChanged() { root.refresh() }
  }

  Connections {
    target: ToplevelManager.toplevels
    enabled: root.surfaceUp
    function onValuesChanged() { root.refresh() }
  }

  onSurfaceUpChanged: if (root.surfaceUp) root.refresh()

  // ------------------------------------------- what to draw for a window (P5)
  //
  // The index is the drawer's, through the same moarchy.common/Apps.js: a tile
  // here is the shelf's tile, and resolving "which icon is this window" twice
  // is what left every moarchy-apps plugin on the shelf as `org.quickshell`
  // with no artwork (K5).
  property var appIdIndex: ({})

  function buildIndex(): void { root.appIdIndex = Apps.index(root.shell) }

  onShellChanged: root.buildIndex()
  Component.onCompleted: root.buildIndex()

  Connections {
    target: root.shell ? root.shell.appLibrary : null
    function onAppsChanged() { root.buildIndex() }
  }

  // The foreign-toplevel handle for a window in the tree, or null.
  //
  // Matched on app id *and* title, and both halves are load-bearing. The app id
  // alone is ambiguous the moment two terminals are open, and for this shell's
  // own screens it is not even distinguishing: Settings, Wi-Fi, Bluetooth and
  // SIM all carry the shell process's `org.quickshell` (K9), and their titles
  // are what tell them apart.
  //
  // A handle is what Apps.js needs -- it asks each plugin whether the window is
  // its own (M4) -- and the tree carries no handle. This is the join, and it is
  // the one place in this file that knows the two lists describe the same
  // windows.
  function toplevelFor(win) {
    if (!win) return null
    var list = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    var loose = null
    for (var i = 0; i < list.length; i++) {
      var tl = list[i]
      if (!tl || String(tl.appId || "") !== win.appId) continue
      if (String(tl.title || "") === win.title) return tl
      // An app that retitles itself between the tree read and this lookup still
      // gets its icon, which is the visible half. Kept as a fallback rather
      // than returned first, so two windows of one app resolve by title when
      // they can.
      if (!loose) loose = tl
    }
    return loose
  }

  // A window the compositor has and the toplevel list does not is an ordinary
  // case, not a defect: an XWayland client has no foreign-toplevel handle at
  // all, and one mapped since the tree was read has not reached the list yet.
  // So every resolver below falls back to the app id the *tree* gave us, which
  // is the same key the drawer's index is built on.
  //
  // The exception is a shell app, and it cannot be one: its app id is the shell
  // process's own (K9), so there is nothing to look up -- and it always has a
  // handle, because resolving one is how its window found itself.
  function iconFor(win) {
    var tl = root.toplevelFor(win)
    if (tl) return Apps.iconFor(root.shell, root.appIdIndex, tl)
    if (!win || !root.shell || !root.shell.appLibrary) return ""
    var entry = Apps.entryForAppId(root.appIdIndex, win.appId)
    return entry ? root.shell.appLibrary.iconSource(entry.icon) : ""
  }

  function glyphFor(win) {
    return Apps.glyphFor(root.shell, root.toplevelFor(win))
  }

  function nameFor(win) {
    var tl = root.toplevelFor(win)
    if (tl) return Apps.nameFor(root.shell, root.appIdIndex, tl)
    if (!win) return ""
    var entry = Apps.entryForAppId(root.appIdIndex, win.appId)
    if (entry && root.shell && root.shell.appLibrary)
      return root.shell.appLibrary.entryName(entry)
    // Its own app id is a worse label than a desktop entry's name and a better
    // one than nothing.
    return win.appId || win.title || "Window"
  }

  // ------------------------------------------------------------- the lift (P6)
  //
  // A window is picked up by a press and hold, and that is not a taste
  // decision: three gestures want a drag that begins on a tile. The list under
  // it scrolls vertically, the sheet itself closes rightward, and the tile has
  // to be able to travel in *both* of those directions to reach a card above or
  // below it. There is no axis left to claim, so the lift is claimed by time
  // instead -- which is what Android's own overview does with the cards it lets
  // you drag.
  //
  // The delay is the drawer's (L1). One number for "hold" on this phone.
  readonly property int holdDelay: 500

  // The window under the finger while the timer runs, and the window in the air
  // after it fires. Two properties rather than one flag and a payload, for the
  // drawer's reason: a Timer has no argument, and a second finger on a second
  // tile must not be able to lift the first one's window.
  property var holdWindow: null
  property int holdFrom: 0
  property var lifted: null
  property int liftedFrom: 0

  // Where the finger is, in scene coordinates, so the ghost rides under it and
  // the drop target is read from the same number.
  property real liftX: 0
  property real liftY: 0

  // The workspace number the release would move to, or 0 for none. Read every
  // frame from `liftY`, because a drop target that only updated when a card was
  // entered would keep its highlight over a finger that had left the sheet.
  property int dropTarget: 0

  // P6. True from the moment a lift fires until the next press, so the click Qt
  // delivers after the finger lifts does not also focus the window that was
  // just carried somewhere else -- or, on the card it was dropped on, go to that
  // workspace. Retired by `sheetPress`, which says why it is there and not here.
  property bool liftFired: false

  function armLift(win, fromNumber): void {
    root.holdWindow = win || null
    root.holdFrom = fromNumber
    if (root.holdWindow) holdTimer.restart()
  }

  function cancelHold(): void {
    holdTimer.stop()
    root.holdWindow = null
  }

  // Travel cancels the hold, on either axis. The sheet's own tracker cannot do
  // this job: it latches on rightward travel past the slop and deliberately
  // ignores everything else, so a finger dragging a tile *upward* would leave
  // the timer running under a gesture that had plainly become a scroll.
  function holdMove(item, mouse): void {
    var p = item.mapToItem(null, mouse.x, mouse.y)
    if (root.lifted) {
      root.liftX = p.x
      root.liftY = p.y
      root.dropTarget = root.cardNumberAt(p.y)
      return
    }
    if (!holdTimer.running) return
    if (Math.abs(p.y - root.sheetPressY) > root.dragSlop
        || Math.abs(p.x - root.sheetPressX) > root.dragSlop)
      root.cancelHold()
  }

  Timer {
    id: holdTimer
    interval: root.holdDelay
    onTriggered: {
      if (!root.holdWindow) return
      root.liftFired = true
      root.lifted = root.holdWindow
      root.liftedFrom = root.holdFrom
      root.holdWindow = null
      root.liftX = root.sheetPressX
      root.liftY = root.sheetPressY
      root.dropTarget = root.cardNumberAt(root.liftY)
      // The sheet's drag and the lift are one finger, and from here it is the
      // lift's. Cancelled rather than merely ignored, so the watchdog that
      // would otherwise fire four seconds later cannot put `progress` back over
      // whatever is on screen by then (F2, F8).
      sheetDrag.cancel()
    }
  }

  // Which card a scene y falls on, as a workspace number, or 0 for none.
  //
  // Arithmetic and not an item lookup, and that is what fixes the card height:
  // while a lift is in flight the tile's own MouseArea holds the exclusive
  // grab, so no card underneath ever sees an enter or a press to answer with.
  // Cards are all one height for exactly this reason (P7).
  function cardNumberAt(sceneY: real): int {
    if (!root.surfaceUp) return 0
    var p = cardColumn.mapFromItem(null, 0, sceneY)
    if (p.y < 0) return 0
    var pitch = root.cardHeight + root.cardGap
    var i = Math.floor(p.y / pitch)
    var list = root.cards
    if (i < 0 || i >= list.length) return 0
    // The gap between two cards belongs to neither, so a drop aimed between
    // them is refused rather than guessed at.
    if (p.y - i * pitch > root.cardHeight) return 0
    return list[i].number
  }

  // P6. Move the window in the air to the workspace under the finger.
  //
  // Nothing happens for a drop on the card it came from, and nothing happens
  // for a drop in a gap: both are the same answer, which is that this gesture
  // did not ask for anything.
  function drop(): bool {
    var win = root.lifted
    var to = root.dropTarget
    root.lifted = null
    root.dropTarget = 0
    if (!win || to <= 0 || to === root.liftedFrom) return false
    return root.move(win.conId, to)
  }

  // P6, P7. One window, one workspace, by con_id.
  //
  // Criteria and not focus, and the order matters: `move container` leaves
  // focus where it was, so the phone stays on the workspace you are looking at
  // and this sheet stays up to be dragged from again. Focusing the window to
  // move it -- which is what a `layout` command would need -- would carry the
  // screen underneath to a workspace nobody asked to visit.
  //
  // What makes two windows on one workspace usable is not here. A window joins
  // the container already on the workspace and keeps its direction, so an
  // inherited `splith` puts the pair side by side at 180px each -- a width
  // nothing on this phone can use. bin/moarchy-one-app-per-workspace sees the
  // move on sway's own event stream and splits the holding container
  // vertically, which is 370px each and what `default_orientation auto` would
  // have picked for a container this shape anyway (P7). That rule lives with
  // the daemon that already owns "what happens when a workspace would hold two"
  // rather than being half-owned here -- a keyboard user's `$mod+Shift+2` gets
  // the same treatment as this drag, which it would not if the sheet did it.
  function move(conId: int, to: int): bool {
    if (!(conId > 0) || !(to > 0)) return false
    var sent = ShellApps.dispatch(root.shell,
      "[con_id=" + conId + "] move container to workspace number " + to)
    if (sent) settle.begin()
    return sent
  }

  // ------------------------------------------------------------ what taps do
  //
  // P4. A tap on a tile goes to that window; a tap on the card goes to that
  // workspace. Both are the same journey at two resolutions, and both leave.
  function focusWindow(win): void {
    if (!win) return
    if (ShellApps.dispatch(root.shell, "[con_id=" + win.conId + "] focus"))
      root.dismiss()
  }

  function goToWorkspace(number: int): void {
    if (!(number > 0)) return
    if (ShellApps.dispatch(root.shell, "workspace number " + number))
      root.dismiss()
  }

  // --------------------------------------------------------------- lifecycle
  function open(payloadJson) {
    // A sheet opening puts away every sheet on its own layer or above it, and
    // none of the ones below it (docs/refactor.md B6). This one is Top, so that
    // is the shade above it and the drawer and the theme picker beside it --
    // read from the rank rather than named here (I2), because five screens that
    // named their own pair gave three different answers.
    Sheet.cover(root.shell, root.pluginId, Sheet.TOP)

    root.cancelHold()
    root.lifted = null
    root.dropTarget = 0
    root.dragging = false
    root.progress = 1
    // The board is read on the way in rather than trusted from last time: the
    // phone has been used since, and a map that opens showing where things were
    // is worse than one that opens a frame late.
    root.refresh()
  }

  function close() {
    // F8's reason, on this sheet: a tap that focuses a window takes the surface
    // away under a finger that is still down, and an unmapped MouseArea reports
    // no release. A tracker left active is a watchdog that puts `progress` back
    // four seconds later, over whatever is on screen by then.
    sheetDrag.cancel()
    root.cancelHold()
    root.lifted = null
    root.dropTarget = 0
    root.dragging = false
    root.progress = 0
  }

  // Every dismissal goes through the host rather than setting `opened`
  // directly, so openPanelIds and this plugin cannot drift apart and leave the
  // next swipe toggling the wrong way.
  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  // ------------------------------------------------------------------ the IPC
  //
  // P10. Reachable without a finger, which is how the selftest asserts it:
  //   omarchy-shell overview state
  //   omarchy-shell overview grid
  //   omarchy-shell overview move 1234 3
  IpcHandler {
    target: "overview"

    function state(): string { return root.opened ? "open" : "closed" }

    function progress(): string {
      return Math.round(root.progress * 100) + (root.dragging ? " dragging" : "")
    }

    // The samples the last drag produced. Polling `progress` over IPC cannot
    // answer whether the sheet tracked the finger -- each call is a process
    // spawn on an A53, so the sampling is slower than the thing being sampled.
    function dragTrace(): string { return root.dragTrace.join(" ") }

    // P3. The board this sheet is drawing, one line per card.
    //
    // The apps are app ids and not display names: an id is what sway reports
    // and what a check can predict, where a name comes from a desktop entry
    // that is not installed on every phone.
    //
    // `ids` is the same windows as con_ids, in the same order, and it is what
    // makes `move` usable from a terminal: a con_id is the only thing that
    // names one window out of two of the same app (Tree.js says why), and
    // without it a check would have to go and parse the tree itself -- a second
    // reader of the thing being tested.
    function grid(): string {
      var live = root.board || []
      var out = []
      for (var i = 0; i < live.length; i++) {
        var ws = live[i]
        var apps = []
        var ids = []
        for (var j = 0; j < ws.windows.length; j++) {
          apps.push(ws.windows[j].appId || "?")
          ids.push(ws.windows[j].conId)
        }
        out.push("ws=" + ws.number
                 + " focus=" + (ws.focused ? 1 : 0)
                 + " layout=" + (ws.layout || "?")
                 + " n=" + ws.windows.length
                 + " apps=" + (apps.length ? apps.join(",") : "-")
                 + " ids=" + (ids.length ? ids.join(",") : "-"))
      }
      out.push("free=" + root.freeNumber)
      return out.join("\n")
    }

    // P6 without a finger, and it is the same call the drop makes rather than a
    // second path to the same place: a check that exercised its own
    // reimplementation of the move would be a check of the check.
    //
    // Two arguments, because an IpcHandler function takes strings and a phone
    // has no other way to name one window out of several.
    function move(conId: string, to: string): string {
      var id = Number(conId)
      var dest = Number(to)
      if (!(id > 0) || !(dest > 0)) return "usage: move <con_id> <workspace>"
      if (!root.move(id, dest)) return "error: nothing to dispatch through"
      return "ok: " + id + " -> " + dest
    }

    // P6. The lift, without the 500ms. `index` is the position in `grid`'s
    // output -- workspace, then window within it -- so a check can pick a
    // window up, read where the cue says it would land, and put it down.
    function lift(ws: string, index: string): string {
      var live = root.board || []
      for (var i = 0; i < live.length; i++) {
        if (live[i].number !== Number(ws)) continue
        var win = live[i].windows[Number(index)]
        if (!win) break
        root.liftFired = true
        root.lifted = win
        root.liftedFrom = live[i].number
        root.dropTarget = live[i].number
        return "ok: " + (win.appId || "?") + " from " + live[i].number
      }
      return "error: no such window"
    }

    // The other half of `lift`: aim it at a card and let go. Named for what it
    // does to the window rather than for the finger, because there is none.
    function dropOn(ws: string): string {
      if (!root.lifted) return "error: nothing lifted"
      root.dropTarget = Number(ws)
      var from = root.liftedFrom
      // What the drop actually did, not what it was asked to do. A drop onto
      // the card a window came from is a real answer and so is a shell with no
      // gestures plugin to dispatch through, and an `ok` for either is a check
      // that passes over a phone where nothing moved.
      if (!root.drop())
        return from === Number(ws) ? "ok: " + from + " -> " + ws + " (unchanged)"
                                   : "error: nothing to dispatch through"
      return "ok: " + from + " -> " + ws
    }

    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok: open"
    }

    function close(): string {
      root.dismiss()
      return "ok: closed"
    }

    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
  }

  // ------------------------------------------------------------- the surface
  readonly property int textWeight: Font.DemiBold

  Shared.UiFile { id: ui }
  readonly property int radiusSheet: ui.radiusSheet
  readonly property int radiusTile: ui.radiusTile
  readonly property int radiusCard: ui.radiusCard

  // Must match moarchy.gestures' own stripHeight, duplicated for the drawer's
  // reason: this surface has to know the number even when the gestures plugin
  // failed to load, and a sheet that stopped short of the bottom in that case
  // would leave a band of wallpaper with the pill drawn on it.
  readonly property int gestureStrip: Style.space(20)

  // P8. Is the keyboard reserving space right now? Asked of the compositor's
  // own configure for this surface, which is the only answer that cannot be
  // wrong about it -- `sm.puri.OSK0`'s `Visible` reports the keyboard's intent
  // and has been seen true with nothing drawn (I5e).
  //
  // This screen never raises or lowers it. The keyboard stays up across a sheet
  // opening and closing (G14), so it can perfectly well be up behind this one,
  // and the margin below is what has to know.
  //
  // False while the surface is down, and that default is the safe one: shut,
  // the window is a one-pixel column, which `reserving()` would read as a
  // keyboard -- and the grow would then take two configures, one with the inset
  // and one without, which is a band of wallpaper for a frame.
  Shared.Osk { id: osk }
  readonly property bool keyboardUp:
    root.surfaceUp && overviewWindow.width > 100 && osk.reserving(overviewWindow)

  readonly property color surface: Color.menu.background
  // NOT `onSurface`: QML reserves the `on<Uppercase>` prefix for signal
  // handlers, so a property declared there is never readable -- the binding
  // evaluates to undefined, undefined assigned to a `color` is #000000, and
  // nothing is logged.
  readonly property color textOnSurface: Color.menu.text
  readonly property color container: Util.alpha(Color.menu.text, 0.08)
  readonly property color subduedBase: Theme.mix(
    Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 1), Color.menu.text, 0.08)
  readonly property color cardFill: root.subduedBase
  readonly property color subdued: Theme.readableOn(root.subduedBase,
                                                    Color.menu.text, 0.55, 4.5)

  // The veil is shared (docs/refactor.md E2); the default ink is this surface's
  // own, which is the half a shared type cannot know (style.md H2).
  component PressVeil: Shared.PressVeil { ink: root.textOnSurface }

  // H3. The controls on this sheet also drag it, bound to the sheet once rather
  // than forwarding four handlers apiece.
  component SheetArea: Shared.SheetDragArea { sheet: root }

  component SheetHeader: Shared.SheetHeader {
    ink: root.textOnSurface
    fill: root.container
    titleWeight: root.textWeight
    radiusTile: root.radiusTile
    onBack: root.dismiss()
  }

  // P7. One height for every card, which is what lets a drop be arithmetic
  // rather than a hit test (cardNumberAt says why). A workspace holding more
  // windows than fit gets a count rather than a taller card.
  readonly property int columns: 4
  readonly property int iconSize: Style.space(36)
  readonly property int tileHeight: Style.space(62)
  readonly property int cardPad: Style.space(8)
  readonly property int cardCaption: Style.space(18)
  readonly property int cardHeight:
    root.cardPad * 2 + root.cardCaption + root.tileHeight
  readonly property int cardGap: Style.space(8)
  readonly property int sheetMargin: Style.space(12)

  // The windows a card draws, and how many it could not. The last slot becomes
  // a count once there are more than `columns`, so a phone that somehow has six
  // windows on one workspace still gets a card the same height as the rest.
  function shownWindows(list) {
    var all = list || []
    if (all.length <= root.columns) return all
    return all.slice(0, root.columns - 1)
  }

  function hiddenCount(list): int {
    var all = list || []
    if (all.length <= root.columns) return 0
    return all.length - (root.columns - 1)
  }

  // One tile: the window's artwork and its name. Drawn twice -- in a card, and
  // under the finger while it is in the air -- from one declaration, so the
  // thing you picked up is visibly the thing you are carrying.
  component AppTile: Item {
    id: appTile

    property var win: null
    property bool dimmed: false

    // P7a. Greater than zero draws a count in place of the artwork -- the
    // windows this card had no slot for. The same component rather than a
    // rectangle with a number in it, so the count lands exactly where the icons
    // beside it do: a marker that is not in line with what it is counting reads
    // as a fourth app whose name did not load.
    property int overflow: 0

    readonly property string glyph:
      appTile.overflow > 0 ? "" : root.glyphFor(appTile.win)

    opacity: appTile.dimmed ? 0.35 : 1
    Behavior on opacity { NumberAnimation { duration: 140 } }

    Column {
      anchors.centerIn: parent
      width: parent.width - Style.space(6)
      spacing: Style.space(4)

      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.iconSize
        height: root.iconSize

        Image {
          anchors.fill: parent
          visible: appTile.overflow === 0 && appTile.glyph === ""
          // Without sourceSize an SVG rasterises at its natural size -- 512px
          // squares, held per tile.
          sourceSize: Qt.size(root.iconSize, root.iconSize)
          asynchronous: true
          cache: true
          fillMode: Image.PreserveAspectFit
          source: appTile.overflow === 0 && appTile.glyph === ""
                ? root.iconFor(appTile.win) : ""
        }

        Text {
          anchors.centerIn: parent
          visible: appTile.overflow > 0
          text: "+" + appTile.overflow
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: root.textWeight
          color: root.subdued
        }

        // K5, M4. A shell app has no desktop entry to take an icon from -- its
        // app id is the shell process's own -- so it wears the glyph its own
        // card wears, centred on its ink rather than on the box the font
        // reserves (style.md B5).
        Ui.OpticalGlyph {
          anchors.fill: parent
          visible: appTile.glyph !== ""
          text: appTile.glyph
          fontFamily: Style.font.family
          fontSize: root.iconSize
          color: root.textOnSurface
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        // A space for the count, and a space rather than nothing: an empty
        // Text lays out to zero height, and the column would then centre the
        // count on the whole slot instead of where the icons are. One line of
        // nothing is what keeps the two in the same row.
        text: appTile.overflow > 0 ? " " : root.nameFor(appTile.win)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.weight: root.textWeight
        color: root.textOnSurface
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }
  }

  PanelWindow {
    id: overviewWindow

    // P8. Never unmapped: shut, a one-pixel column along the right edge; grown
    // to the sheet when the edge drag latches, not on press.
    //
    // The drawer's measurement, on the other axis and for the same reason.
    // Quickshell deletes a layer-shell window that goes invisible, so each open
    // would build a new QQuickWindow -- a render thread, a GL context, a
    // swapchain, the whole scene graph and a first layout -- while the finger
    // went on moving. Kept alive, an open is a resize.
    //
    // A column and not a full-screen transparent surface: that is a full-screen
    // blend in every frame on a Mali-400, where a one-pixel column blends one.
    visible: true
    anchors { top: true; bottom: true; right: true; left: root.surfaceUp }
    implicitWidth: 1
    color: "transparent"

    onWidthChanged: if (overviewWindow.width > 100) root.sheetWidth = overviewWindow.width

    // P8. Grown is not live. While warming, this surface is full-screen, on Top
    // and over everything -- so its input region is cut down until the sheet is
    // actually being drawn.
    //
    // One pixel and not none: Qt treats an empty mask as unset, and an unset
    // input region is the *whole surface* -- the opposite of what is being
    // asked for. The pixel is outside the surface, where the compositor clips
    // it to nothing.
    Region { id: warmRegion; x: -1; y: -1; width: 1; height: 1 }
    mask: root.progress > 0 ? null : warmRegion

    WlrLayershell.namespace: "moarchy-overview"
    WlrLayershell.layer: WlrLayer.Top

    // Reserve nothing, but be arranged into what the exclusive surfaces left:
    // below the bar and above the home pill, with no geometry maths here.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    // Extend past the bottom of the usable area, under the gesture strip, so
    // the sheet's own background runs to the bottom edge rather than leaving a
    // band of the app behind it with the pill drawn on it (I1).
    //
    // Gated on the keyboard, which is the drawer's subtlety and not a different
    // one. A margin does not extend a surface "under the strip" -- it extends it
    // past the bottom of the *usable area*, and what sits there depends on what
    // else is reserving. With the keyboard down that is the strip, which is
    // Overlay and draws over us: exactly what is wanted. With it up that is the
    // keyboard, which is on Top like this surface and mapped earlier, so this
    // sheet wins the overlap and paints over its top key row.
    //
    // Nothing here raises the keyboard -- this screen owns no field and takes no
    // focus -- but nothing puts it away either (G14), so it can be up behind
    // this sheet whenever the app underneath left it up.
    margins.bottom: root.keyboardUp ? 0 : -root.gestureStrip

    // No keyboard focus at all, ever. The header note says why: this screen has
    // nothing to type into, and Exclusive focus would deactivate the very
    // window the focused card is drawn from.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // The scrim is what makes a half-open sheet read as half-open rather than
    // as a window that has not finished drawing. One blended quad, its alpha
    // bound straight to the drag -- no opacity on a subtree, which would make
    // the renderer composite the whole sheet off-screen first on a GPU that has
    // nothing spare.
    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.6 * root.progress)
    }

    Rectangle {
      id: sheet

      // The last sheet width, not the window's: on the band the window is one
      // pixel wide, and a sheet that followed it would lay every card out again
      // at one pixel on each close.
      width: root.sheetWidth > 0 ? root.sheetWidth
           : (overviewWindow.screen ? overviewWindow.screen.width : parent.width)
      height: parent.height

      // Rides in from beyond the right edge. Translation only: this is a
      // Mali-400 at GLES 2.0, so an `x` costs nothing where a `scale` costs a
      // re-raster of everything on the sheet.
      x: parent.width - sheet.width * root.progress
      color: root.surface
      radius: root.radiusSheet

      // The radius belongs on the leading edge only -- the trailing one is off
      // the side of the screen. One rectangle squaring the far corners back
      // off, its width the radius, which is the same number rather than two
      // that have to agree.
      Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.radiusSheet
        color: parent.color
      }

      Column {
        anchors.fill: parent
        anchors.leftMargin: root.sheetMargin
        anchors.rightMargin: root.sheetMargin
        anchors.topMargin: Style.space(4)
        spacing: Style.space(4)

        SheetHeader {
          title: "Overview"
        }

        Flickable {
          id: list
          width: parent.width
          height: sheet.height - Style.space(4) - Style.space(44)
                - Style.space(4) - root.gestureStrip
          contentHeight: cardColumn.height
          boundsBehavior: Flickable.StopAtBounds
          clip: true
          // A vertical list on a sheet that closes sideways: the two axes never
          // contend, so neither has to steal from the other.
          flickableDirection: Flickable.VerticalFlick
          // P6. A lift owns the finger outright. Without this the list goes on
          // flicking under a window being carried, and the card the drop lands
          // on is not the card the finger was over.
          interactive: !root.lifted

          Column {
            id: cardColumn
            width: list.width
            spacing: root.cardGap

            Repeater {
              model: root.cards

              delegate: Rectangle {
                id: card
                required property var modelData

                readonly property bool fresh: !!card.modelData.fresh
                readonly property bool isTarget:
                  !!root.lifted && root.dropTarget === card.modelData.number
                readonly property var wins: card.modelData.windows || []

                width: cardColumn.width
                height: root.cardHeight
                radius: root.radiusCard
                color: root.cardFill

                // P4, P6. Two things a card can be saying, and they are drawn
                // the same way on purpose: the accent is already this shell's
                // word for "this is where you would end up" -- the shelf's
                // running dot, the strip's armed pill, the back edge's
                // committed arc.
                border.width: card.isTarget || card.modelData.focused ? 2 : 1
                border.color: card.isTarget ? Color.accent
                            : card.modelData.focused ? Util.alpha(Color.accent, 0.6)
                            : Util.alpha(root.textOnSurface, 0.1)

                PressVeil {
                  anchors.fill: parent
                  radius: parent.radius
                  // Off while the sheet is being dragged from this card and
                  // while a window is in the air over it: in both cases the
                  // movement is the feedback, and a lit card underneath is
                  // noise (style.md H6).
                  on: cardArea.pressed && !root.sheetDragging && !root.lifted
                }

                Column {
                  anchors.fill: parent
                  anchors.margins: root.cardPad
                  spacing: 0

                  Item {
                    width: parent.width
                    height: root.cardCaption

                    Text {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: card.fresh ? "NEW" : String(card.modelData.number)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.weight: root.textWeight
                      font.letterSpacing: Style.space(1)
                      color: card.modelData.focused ? Color.accent : root.subdued
                    }

                    // P7. Said only when the windows are hidden behind each
                    // other.
                    //
                    // Two windows on a card are tiled, one above the other, and
                    // a label saying so on every such card is a word that never
                    // varies. `tabbed` and `stacked` are the cases worth a
                    // word: the tiles say there are two apps here and only one
                    // of them is on screen, which is the one thing about a card
                    // a glance at the phone cannot tell you.
                    Text {
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      visible: card.modelData.layout === "tabbed"
                            || card.modelData.layout === "stacked"
                      text: card.modelData.layout === "tabbed" ? "TABS" : "STACKED"
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.weight: root.textWeight
                      font.letterSpacing: Style.space(1)
                      color: root.subdued
                    }
                  }

                  Item {
                    width: parent.width
                    height: root.tileHeight

                    // The empty card, and the one that is not a workspace yet.
                    // A workspace with nothing on it is a home screen, which is
                    // a thing you can go to -- so it says so rather than
                    // drawing an empty rectangle nobody would tap.
                    Text {
                      anchors.centerIn: parent
                      visible: card.wins.length === 0
                      text: card.fresh ? "New workspace" : "Home screen"
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.weight: root.textWeight
                      color: root.subdued
                    }

                    Row {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 0

                      Repeater {
                        model: root.shownWindows(card.wins)

                        delegate: Item {
                          id: tileSlot
                          required property var modelData

                          width: cardColumn.width / root.columns
                          height: root.tileHeight

                          AppTile {
                            anchors.fill: parent
                            win: tileSlot.modelData
                            // The window that is in the air is drawn under the
                            // finger instead. Dimmed rather than hidden, so the
                            // card it came from keeps its shape while a drop is
                            // still being aimed -- and so a drop that goes
                            // nowhere puts it back where it visibly was.
                            //
                            // Compared on the con_id and not on the object. A
                            // Repeater over a plain JS array hands the delegate
                            // a wrapper, not the array's own object, so `===`
                            // against what the lift captured is false for the
                            // tile it was captured from -- which drew a window
                            // in the air and left it lit on its old card as
                            // well. The id is what sway calls the window, and
                            // it is what the move is dispatched by.
                            dimmed: !!root.lifted && !!tileSlot.modelData
                                    && root.lifted.conId === tileSlot.modelData.conId
                          }

                          PressVeil {
                            anchors.fill: parent
                            anchors.margins: Style.space(3)
                            radius: root.radiusTile
                            on: tileArea.pressed && !root.sheetDragging
                                && !root.lifted
                          }

                          SheetArea {
                            id: tileArea
                            anchors.fill: parent

                            onGrabbed: (area, mouse) =>
                              root.armLift(tileSlot.modelData, card.modelData.number)
                            onDragged: (area, mouse) => root.holdMove(area, mouse)
                            onUngrabbed: {
                              if (root.lifted) root.drop()
                              root.cancelHold()
                            }

                            // P4. A tap is a tap only if it was not a drag, not
                            // a lift, and not the tail of the sheet being
                            // pulled shut from this very tile.
                            onClicked: {
                              if (root.sheetWasDrag || root.liftFired) return
                              root.focusWindow(tileSlot.modelData)
                            }
                          }
                        }
                      }

                      // The windows this card has no slot for. A count and not
                      // a smaller tile: a tile narrower than a slot stops being
                      // one (M4), and a card that grew would break the
                      // arithmetic every drop is aimed by.
                      //
                      // Drawn where the icons are and not in the middle of the
                      // slot: the tiles beside it carry an icon over a label, so
                      // a count centred on the whole slot sits a line above
                      // everything it is counting.
                      AppTile {
                        visible: root.hiddenCount(card.wins) > 0
                        width: cardColumn.width / root.columns
                        height: root.tileHeight
                        overflow: root.hiddenCount(card.wins)
                      }
                    }
                  }
                }

                // Under the tiles in stacking order, so a press on a tile is
                // the tile's. The card answers everywhere the tiles do not.
                SheetArea {
                  id: cardArea
                  anchors.fill: parent
                  z: -1

                  onClicked: {
                    if (root.sheetWasDrag || root.liftFired) return
                    root.goToWorkspace(card.modelData.number)
                  }
                }
              }
            }
          }
        }
      }

      // P6. The window in the air, drawn over everything and answering nothing:
      // the tile's own MouseArea still holds the grab, and an input region here
      // would take the release that ends the drag.
      Item {
        id: ghost
        visible: !!root.lifted
        width: cardColumn.width / root.columns
        height: root.tileHeight

        // Scene coordinates in, sheet coordinates out. The sheet moves under
        // the finger while it is being dragged and the ghost must not, so this
        // maps every frame rather than caching an offset.
        x: sheet.mapFromItem(null, root.liftX, root.liftY).x - width / 2
        y: sheet.mapFromItem(null, root.liftX, root.liftY).y - height / 2

        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(3)
          radius: root.radiusTile
          color: root.container
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.8)
        }

        AppTile {
          anchors.fill: parent
          win: root.lifted
        }
      }
    }
  }
}
