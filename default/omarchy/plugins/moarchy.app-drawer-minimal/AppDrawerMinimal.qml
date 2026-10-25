// The minimal app drawer: one row per app, alphabetical, in one ink.
// docs/app-drawer-minimal.md.
//
// ---------------------------------------------------------------------------
// Why a second plugin rather than a mode on the first
// ---------------------------------------------------------------------------
// The two drawers disagree about what a launcher is. `moarchy.app-drawer` is a
// grid you recognise by artwork before you have read anything; this is a list
// you read down by name. That disagreement is not a layout flag -- it reaches
// the model (rows against cells), the scroll axis, the delegate, the icon, and
// whether an A-Z rail means anything at all. `AppDrawer.qml` also carries a
// settings search index and an uninstall card; a branch through all of that for
// a second layout is how one file comes to serve neither (M-preamble).
//
// What the two genuinely share is the sheet: the drag, the band, the edge
// arithmetic, the keyboard inset. All of that is `moarchy.common` already, and
// this file instantiates it rather than restating it. Where a comment here
// would only repeat one there, it says which one instead -- the reasoning has
// not changed by being used twice, and two copies of it would drift.
//
// ---------------------------------------------------------------------------
// Why the icons are glyphs
// ---------------------------------------------------------------------------
// M8. One ink, from the theme, for every row. `Glyphs.js` carries the table and
// the argument for it, including why a symbolic SVG is not used.
//
// ---------------------------------------------------------------------------
// What it deliberately has not got
// ---------------------------------------------------------------------------
// M17, M18. No uninstall card, no long press, no settings results. Removing an
// app stays on the screen with the artwork you can be sure you recognised, and
// the settings index stays on the screen that owns it. Both are one import
// away and neither is taken: a second copy of either is a second thing to keep
// true.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Upstream
import qs.Ui as Ui
import "../moarchy.common/Apps.js" as Apps
import "../moarchy.common/Theme.js" as Theme
import "../moarchy.common/ShellApps.js" as ShellApps
import "../moarchy.common/Sheet.js" as Sheet
import "../moarchy.common/Edge.js" as Edge
import "../moarchy.common" as Shared
import "Glyphs.js" as Glyphs

Item {
  id: root

  // Injected by the host in the panel Loader's onLoaded, by name and after
  // construction. Neither `readonly` nor `required`: readonly makes the
  // assignment throw and required makes the component fail to instantiate,
  // because a plugin is created first and configured afterwards. Either way
  // the failure is silent. AppDrawer.qml carries the long version.
  property var shell: null

  readonly property string pluginId: "moarchy.app-drawer-minimal"

  // ------------------------------------------------- the sheet contract (M2)
  //
  // The six properties moarchy.gestures writes on whatever an edge raises:
  // `entryEdge`, `progress`, `dragging`, `warming`, `homeHint`, and
  // `closeTravel` read back. A sheet missing one of them is not refused -- the
  // gestures plugin tests each with `typeof` -- it simply stops following the
  // finger in that one respect, which is invisible until somebody drags it.
  property string entryEdge: Edge.BOTTOM
  readonly property bool sideways: Edge.horizontal(root.entryEdge)

  property real progress: 0
  property bool dragging: false
  property real homeHint: 0

  readonly property bool opened: root.progress >= 1 && !root.dragging

  Behavior on progress {
    enabled: !root.dragging
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }

  Behavior on homeHint {
    enabled: !root.dragging
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }

  // gestures.md D2a/D2b, and the trap is the one AppDrawer.qml records at
  // length: shut, this window is a one-pixel band, and a drag divided by the
  // band moves the sheet hundreds of times finger speed until the surface
  // grows. So: the screen until this window has been up once, its own size
  // ever after, on whichever axis the finger is travelling.
  property real sheetHeight: 0
  property real sheetWidth: 0

  readonly property real closeTravel: Math.max(1, root.sideways
    ? (root.sheetWidth > 0 ? root.sheetWidth
                           : (drawerWindow.screen ? drawerWindow.screen.width : 360))
    : (root.sheetHeight > 0 ? root.sheetHeight
                            : (drawerWindow.screen ? drawerWindow.screen.height : 720)))
  readonly property real closeCommit: 0.7
  readonly property int dragSlop: Style.space(10)
  readonly property real sheetFling: 0.3

  // gestures.md N3. Written by moarchy.gestures when an upward drag latches, so
  // the grow happens during the slop of a real open rather than on every strip
  // press -- most of which are a workspace swipe.
  property bool warming: false
  readonly property bool surfaceUp: root.progress > 0 || root.warming
  readonly property var bandAnchors: Edge.anchors(root.entryEdge, root.surfaceUp)

  // H1, on the shared tracker. Travelling back toward the entry edge is what
  // closes a sheet that is already up; scene coordinates throughout, because
  // every input item here is a child of the sheet and a delta measured in a
  // frame that moves feeds back into itself.
  Shared.DragTracker {
    id: sheetDrag
    axis: Edge.axis(root.entryEdge)
    travel: root.closeTravel
    openDirection: Edge.openDirection(root.entryEdge)
    latchSign: Edge.closeLatchSign(root.entryEdge)
    // P6. On a sideways edge the close drag crosses the list's own scroll
    // axis, and a list that shut the sheet whenever a thumb's arc wandered
    // would be a list nobody could scroll. On the bottom edge the two share an
    // axis and H5 settles it, so this stays off there.
    axisDominant: root.sideways
    slop: root.dragSlop
    startFrom: root.progress

    onBegan: root.dragging = true
    onMoved: p => root.progress = p

    onFinished: (p, v) => {
      root.dragging = false
      if (v <= -root.sheetFling) root.dismiss()
      else if (v >= root.sheetFling) root.progress = 1
      else if (p <= root.closeCommit) root.dismiss()
      else root.progress = 1
    }

    onStranded: root.markTrace(-2)
    onCanceled: from => {
      root.markTrace(-1)
      root.dragging = false
      root.progress = from
    }
  }

  // The names Shared.SheetDragArea forwards to. `sheetWasDrag` is what a click
  // handler tests before launching: Qt delivers `released` and then `clicked`,
  // so a thumb that dragged the sheet shut must not also open the app it
  // started on.
  readonly property bool sheetDragging: sheetDrag.latched
  readonly property bool sheetWasDrag: sheetDrag.wasDrag

  function sheetPress(item, mouse): void {
    var p = item.mapToItem(null, mouse.x, mouse.y)
    sheetDrag.press(p.x, p.y)
  }

  function sheetMove(item, mouse): void {
    var p = item.mapToItem(null, mouse.x, mouse.y)
    sheetDrag.move(p.x, p.y)
  }

  function sheetRelease(): void { sheetDrag.release() }
  function sheetCancel(): void { sheetDrag.cancel() }

  // Diagnostic only. One integer per frame while a drag is in flight, cleared
  // when the next one starts -- because polling `progress` over IPC cannot
  // answer whether the sheet tracked the finger: each call is a process spawn
  // on this hardware, so the sampling is slower than the thing sampled.
  property var dragTrace: []
  property var retireTrace: []

  function noteRetire(): void {
    if (root.dragging) return
    if (root.progress <= 0 && root.homeHint <= 0) return
    var next = root.retireTrace.slice()
    if (next.length < 200)
      next.push(Math.round(root.progress * 100) + ":" + Math.round(root.homeHint * 100))
    root.retireTrace = next
  }

  function markTrace(marker): void {
    var next = root.dragTrace.slice()
    next.push(marker)
    root.dragTrace = next
  }

  onHomeHintChanged: root.noteRetire()

  onDraggingChanged: {
    if (root.dragging) {
      root.dragTrace = []
      root.retireTrace = []
    }
  }

  onProgressChanged: {
    root.noteRetire()
    if (!root.dragging) return
    var next = root.dragTrace.slice()
    if (next.length < 200) next.push(Math.round(root.progress * 100))
    root.dragTrace = next
  }

  // ------------------------------------------------------------- the model
  //
  // M5. The same question the app drawer asks, so two launchers cannot list
  // the same phone in two different orders. `sortedEntries("")` is already
  // alphabetical by the name the grid draws -- it sorts on `entrySortKey`,
  // which is that name lowercased -- so the rail below needs no second sort.
  //
  // The rows are wrappers, `{entry, score, key, name}`, and not entries.
  // Reading `.icon` or `.id` straight off a row yields undefined and draws
  // nothing, with no error anywhere.
  property string query: ""
  property int appsRevision: 0

  readonly property var appRows: {
    // Re-read on every appsChanged() as well as on every keystroke: the bump
    // is what makes a freshly installed app appear without a reopen.
    var bump = root.appsRevision
    if (!root.shell || !root.shell.appLibrary) return []
    return root.shell.appLibrary.sortedEntries(root.query)
  }

  Connections {
    target: root.shell ? root.shell.appLibrary : null
    function onAppsChanged() { root.appsRevision++; root.buildIndex() }
  }

  onShellChanged: root.buildIndex()
  Component.onCompleted: root.buildIndex()

  function entryName(entry) {
    return root.shell && root.shell.appLibrary
      ? String(root.shell.appLibrary.entryName(entry) || "") : ""
  }

  // ------------------------------------------ is this app already running?
  //
  // The one question this sheet asks about *windows* rather than about desktop
  // entries, and it is asked on the launch path: an app already running maps
  // no new window, so the hop to a free workspace has nothing to arrive on
  // (windows.md L10).
  //
  // Answered through moarchy.common/Apps.js, which is the same appId index the
  // grid and the workspace overview resolve through. One index, because two
  // implementations of "which app is this window" is how every moarchy plugin
  // came to be drawn as `org.quickshell` with no artwork at all.
  //
  // Held here rather than there because the *timing* is this sheet's: rebuilt
  // on `appsChanged`, and separate from `appRows` on purpose -- that one is
  // the query's answer and re-sorts on every keystroke, and what is running
  // must not depend on what is in the search field.
  property var appIdIndex: ({})

  function buildIndex(): void { root.appIdIndex = Apps.index(root.shell) }

  // Read straight off zwlr-foreign-toplevel-management-v1: no fork, no tree
  // walk, no polling, and an appId per window, which is all this needs.
  function entryIsRunning(entry): bool {
    if (!entry) return false
    var open = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    for (var i = 0; i < open.length; i++) {
      var e = open[i] ? Apps.entryForAppId(root.appIdIndex, open[i].appId) : null
      if (e && String(e.id) === String(entry.id)) return true
    }
    return false
  }

  // ---------------------------------------------------------- the rail (D)
  //
  // M12. One entry per letter the list actually has an app under, with the
  // index of that letter's first row. A letter with no app is not drawn: a
  // rail offering Q, X and Z on a phone with thirty-four apps is three dead
  // targets, and a target that does nothing is worse than an absent one.
  //
  // M16. Empty while a query is showing. Eleven letters down the side of four
  // results is a rail that cannot take the thumb anywhere it is not already.
  // Deduplicated across the whole list rather than run by run, and `#` is why.
  // The sort is a plain string comparison on `key`, so a name starting with a
  // digit sorts before `a` and one starting with an accent sorts after `z` --
  // two disjoint runs that `letterFor` gives the same label. Run-by-run
  // dedup draws `#` at both ends of the rail, which reads as a bug rather
  // than as the two things it is. First occurrence wins, so `#` takes the
  // thumb to the digits; the handful of names past `z` are still there to
  // scroll to.
  readonly property var railLetters: {
    if (root.query !== "") return []
    var rows = root.appRows
    var out = []
    var seen = ({})
    for (var i = 0; i < rows.length; i++) {
      // `key` and not the drawn name, because it is the field the sort was
      // done on. Letter-from-one-string and order-from-another is how a rail
      // comes to jump backwards.
      var letter = Glyphs.letterFor(rows[i].key)
      if (seen[letter]) continue
      seen[letter] = true
      out.push({ letter: letter, index: i })
    }
    return out
  }

  // M13. Which rail entry a point on the rail is over, `y` measured in the
  // rail's own coordinates. The rail is a scrubber and not eleven buttons: the
  // finger lands anywhere on it and keeps choosing as it slides, so this is
  // arithmetic over the column rather than a hit test on a child -- a letter
  // per MouseArea would hand the grab to whichever one the finger landed on
  // and then stop hearing about it the moment it slid onto the next.
  //
  // Clamped, because an implicit grab keeps delivering positions well past
  // both ends of the item, and a thumb that has run off the bottom of the rail
  // plainly still means Z.
  function railIndexAt(y): int {
    var letters = root.railLetters
    if (letters.length === 0) return -1
    if (railColumn.step <= 0) return -1
    var i = Math.floor((y - railColumn.inset) / railColumn.step)
    return Math.max(0, Math.min(letters.length - 1, i))
  }

  // Which letter the finger is on, or -1. Drawn as the rail's own press state
  // (H1) and read by `railTarget` so a check can ask the same question a thumb
  // does.
  property int railActive: -1

  function scrubTo(y): void {
    var i = root.railIndexAt(y)
    if (i < 0) return
    root.railActive = i
    // Beginning, not Contain: a scrub means "take me to M", and Contain leaves
    // M wherever it already was whenever it happens to be on screen -- so the
    // list stands still for the first third of the rail and then jumps.
    list.positionViewAtIndex(root.railLetters[i].index, ListView.Beginning)
  }

  // --------------------------------------------------------------- launch
  //
  // M7. Straight through the app drawer's own launch path, by calling the same
  // library and making the same two decisions it makes -- and those two are
  // the whole of it, so they are stated here rather than reached for across a
  // plugin boundary:
  //
  //   the workspace hop   windows.md L10. Stand on the workspace the window
  //                       will land on before starting it, so the splash is
  //                       drawn over the wallpaper being arrived at rather
  //                       than over the app being left. Not for an entry that
  //                       summons a plugin (a layer surface is visible from
  //                       every workspace) and not for an app already running
  //                       (a single-instance app maps no new window, so there
  //                       would be nothing to arrive on).
  //
  //   the Android route   android.md AC 11. Waydroid's generated Exec line
  //                       writes policy_control at or before the window's
  //                       first layout, which removes the status bar inset the
  //                       app pads against. Nothing repairs a window already
  //                       laid out, so the launch goes through
  //                       moarchy-android-launch instead.
  function launch(entry) {
    if (!entry || !root.shell || !root.shell.appLibrary) return

    if (!Apps.pluginSummonedBy(entry) && !root.entryIsRunning(entry))
      ShellApps.goToFreeWorkspace(root.shell)

    var id = String(entry.id || "")
    if (id.indexOf("waydroid.") === 0 && id.indexOf(".", 9) > 0)
      Quickshell.execDetached(["/usr/lib/moarchy/bin/moarchy-android-launch",
                               id.substring(9)])
    else
      root.shell.appLibrary.launch(entry.id, root.shell.appLibrary.entryName(entry))
    root.dismiss()
  }

  // ---------------------------------------------------------------- colour
  //
  // style.md C2's roles, read off the theme so a theme switch restyles the
  // screen. NOT spelled `onSurface`: QML reserves the `on<Uppercase>` prefix
  // for signal handlers, so a property declared there is never readable -- the
  // binding evaluates to undefined, undefined assigned to a `color` is
  // #000000, and nothing is logged. The symptom is every glyph and label on a
  // dark sheet painted pure black.
  readonly property color surface: Upstream.Color.menu.background
  readonly property color textOnSurface: Upstream.Color.menu.text
  readonly property color container: Util.alpha(Upstream.Color.menu.text, 0.08)
  readonly property color subduedBase: Theme.mix(
    Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 1), Upstream.Color.menu.text, 0.08)
  readonly property color subdued: Theme.readableOn(root.subduedBase,
                                                    Upstream.Color.menu.text, 0.55, 4.5)

  // style.md B3. Light text on a dark ground reads thinner than it measures,
  // and one screen left at Regular reads as a different phone.
  readonly property int textWeight: Font.DemiBold

  Shared.UiFile { id: ui }
  readonly property int radiusSheet: ui.radiusSheet
  readonly property int radiusCard: ui.radiusCard

  // The veil is shared (refactor.md E2); the default ink is this surface's own,
  // which is the half a shared type cannot know (style.md H2).
  component PressVeil: Shared.PressVeil { ink: root.textOnSurface }

  // H3. A control on a sheet that also drags it, bound to the sheet once
  // rather than forwarding four handlers apiece. Declaring any of the four on
  // an instance replaces the shared handler rather than adding to it;
  // scripts/style-check.sh fails the day one does.
  component SheetArea: Shared.SheetDragArea { sheet: root }

  // M6. A row is a glyph, a name and nothing else. 46 rather than the app
  // drawer's 86-tall cell: there is no wrapped two-line label to make room
  // for, and a taller row buys nothing but fewer apps per screenful.
  readonly property int rowHeight: Style.space(46)

  // E5. Derived from the glyph, never a fixed 44: on a theme with a larger
  // base font the glyph is already over the floor, and a fixed slot would
  // shrink the target back down to meet it.
  readonly property int glyphSlot: Math.round(Style.font.iconLarge * 1.35)
  readonly property int clearSlot:
    Math.min(Style.space(46), Math.max(Style.space(44), root.glyphSlot))

  // Must match moarchy.gestures' own stripHeight. Duplicated rather than read
  // across plugins for the reason the other two sheets duplicate it: this
  // surface has to know the number even when the gestures plugin failed to
  // load, and a sheet running off the bottom of the screen in that case would
  // be worse than one that leaves the band unused.
  readonly property int gestureStrip: Style.space(20)

  // I5e. Is the keyboard up? Asked of the compositor's configure rather than
  // of the search field, because the field answers a different question: the
  // keyboard can be up with nothing here focused at all. False while the
  // surface is down, and that default is the safe one -- shut, this window is
  // a one-pixel band, which `reserving()` would read as a keyboard.
  readonly property bool keyboardUp:
    root.surfaceUp && drawerWindow.height > 200 && osk.reserving(drawerWindow)

  // G14a. The keyboard, asked to show when a finger taps the search field.
  // Hide is not this surface's: G2 is the one way down, and a drawer that put
  // the keyboard away on close is what made it flap when launching an app.
  Shared.Osk { id: osk }

  // G14a. The search pill slides under the opening finger as the sheet comes
  // up, and a press there must not read as a request. Armed off `opened`, not
  // off the end of a drag: a drag released part-way hands the last stretch to
  // the animation, and a summon never drags at all.
  property bool keyboardRaiseArmed: false

  Timer {
    id: keyboardRaiseArm
    interval: 120
    onTriggered: root.keyboardRaiseArmed = root.opened
  }

  onOpenedChanged: {
    root.keyboardRaiseArmed = false
    if (root.opened) keyboardRaiseArm.restart()
    else keyboardRaiseArm.stop()
  }

  // ------------------------------------------------------------ open, close
  function open(payloadJson) {
    // B6. A sheet opening puts away every sheet on its own layer or above it,
    // and none below. This one is Top, so that is the control center above it
    // and the other drawer and the theme picker beside it. Which sheets those
    // are is Sheet.js' single list, read from the rank rather than named here.
    //
    // Q3a. A summon carries no direction, so it uses this sheet's own edge --
    // but only from rest: a commit runs through this function with the sheet
    // part-way in, and resetting there would teleport it on the frame it was
    // let go.
    if (root.progress <= 0 && !root.dragging) root.entryEdge = Edge.BOTTOM

    Sheet.cover(root.shell, root.pluginId, Sheet.TOP)

    root.query = ""
    searchField.text = ""
    root.railActive = -1
    list.positionViewAtBeginning()
    root.homeHint = 0
    // Belt to close()'s braces: the invariant the keyboard gate rests on is
    // "focused means the keyboard is up", so the open path asserts it too
    // rather than trusting that nothing opens this surface from a state it did
    // not close from.
    focusSink.forceActiveFocus()
    root.dragging = false
    root.progress = 1
  }

  function close() {
    // F8. A row tap that launches can take this surface away under a finger
    // that is still down, and an unmapped MouseArea reports no release. A
    // tracker left active is a watchdog that puts `progress` back four seconds
    // later, over whatever is on screen by then.
    sheetDrag.cancel()
    handleDrag.cancel()

    // Move focus off the search field BEFORE the surface goes away. An unmap
    // is not a text-input-v3 deactivate, so a field that still holds active
    // focus keeps receiving commits after the drawer is gone -- and
    // `focus = false` is not enough, because it releases the focus scope
    // rather than the active focus.
    focusSink.forceActiveFocus()

    root.query = ""
    root.railActive = -1
    root.dragging = false
    root.progress = 0
    root.homeHint = 0
  }

  // Every dismissal goes through the host rather than setting `progress`
  // directly, so openPanelIds and this plugin cannot drift apart and leave the
  // next swipe toggling the wrong way.
  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  // ------------------------------------------------------------------- IPC
  //
  // Driven without a finger, which is how the ACs in
  // docs/app-drawer-minimal.md are decided. The verbs that dump the model are
  // not a convenience: a collapsed row and a missing row are the same
  // screenshot, and a list showing the wrong data looks like a list whose
  // rendering is broken.
  IpcHandler {
    target: "app-drawer-minimal"

    function state(): string { return root.opened ? "open" : "closed" }

    function progress(): string {
      return Math.round(root.progress * 100) + (root.dragging ? " dragging" : "")
    }

    function homeHint(): string {
      return Math.round(root.homeHint * 100) + (root.dragging ? " dragging" : "")
    }

    // The samples the last drag actually produced, and what the release left
    // behind as `progress:homeHint` per frame. Read afterwards rather than
    // watched, because one IPC round trip is slower than the thing sampled.
    function dragTrace(): string { return root.dragTrace.join(" ") }
    function retireTrace(): string { return root.retireTrace.join(" ") }

    // M5, M6, M10. The list as it is drawn, in draw order: the id a launch
    // takes, the glyph the row shows, and the name it reads. Tab-separated, so
    // a name with spaces stays one field.
    function rows(): string {
      var out = []
      var model = root.appRows
      for (var i = 0; i < model.length; i++) {
        var entry = model[i] && model[i].entry
        if (!entry) continue
        out.push([String(entry.id), Glyphs.forEntry(entry),
                  root.entryName(entry).replace(/\t/g, " ")].join("\t"))
      }
      return out.join("\n")
    }

    // M12. The letters the rail offers, with the row each one lands on.
    function rail(): string {
      var letters = root.railLetters
      var out = []
      for (var i = 0; i < letters.length; i++)
        out.push(letters[i].letter + "\t" + letters[i].index)
      return out.join("\n")
    }

    // M13. Where a letter takes the list, down the same arithmetic a finger
    // gets. An unknown letter is told apart from one the rail is not offering:
    // the second is M12 working and the first is a typo.
    function railTarget(letter: string): string {
      var want = String(letter || "").toUpperCase()
      if (!want) return "no letter"
      var letters = root.railLetters
      for (var i = 0; i < letters.length; i++)
        if (letters[i].letter === want) {
          root.scrubTo(railColumn.inset + (i + 0.5) * railColumn.step)
          return String(letters[i].index)
        }
      return "no row under " + want
    }

    // M15. Typing, without a finger. It writes the field rather than
    // `root.query`, so what a check drives is the path a keystroke takes --
    // including the debounce, flushed here rather than waited out: a check that
    // slept 120ms would be asserting the timer.
    function type(text: string): string {
      searchField.text = text
      queryDebounce.stop()
      root.query = searchField.text
      return "ok"
    }

    // M7. A launch down the same function a tap calls. Callers pass the bare
    // id -- no .desktop suffix -- or the lookup misses.
    function launch(desktopId: string): string {
      var id = String(desktopId || "")
      if (!id) return "no id"
      if (!root.shell || !root.shell.appLibrary) return "no shell"
      var model = root.appRows
      for (var i = 0; i < model.length; i++) {
        var entry = model[i] && model[i].entry
        if (entry && String(entry.id) === id) {
          root.launch(entry)
          return "ok"
        }
      }
      return "no entry"
    }

    // style.md F1, F3. Neither is answerable by a screenshot: the pill and the
    // field draw the same picture whether or not they are the same rectangle,
    // which is how a dead band survives. Surface coordinates -- the panel
    // pixels bin/moarchy-touch takes are these doubled.
    function searchTarget(): string {
      var box = it => {
        var p = it.mapToItem(null, 0, 0)
        return Math.round(p.x) + "," + Math.round(p.y)
             + " " + Math.round(it.width) + "x" + Math.round(it.height)
      }
      return "pill=" + box(searchPill)
           + " field=" + box(searchField)
           + " focused=" + searchField.activeFocus
           + " clear=" + (clearButton.visible ? box(clearButton) : "none")
           + " text=" + JSON.stringify(searchField.text)
    }

    // Where a row is, so a tap can be aimed rather than guessed at: the row
    // pitch is 46 *scaled* px and a coordinate computed from Style.space in a
    // shell script is wrong the moment the theme's scale moves. Both frames,
    // because they differ by the bar and a check has to say which it used.
    function rowTarget(index: string): string {
      var i = parseInt(String(index || "0"))
      if (typeof list.itemAtIndex !== "function") return "no list"
      var item = list.itemAtIndex(i)
      if (!item) return "no row"
      var p = item.mapToItem(null, 0, 0)
      var g = item.mapToGlobal(0, 0)
      return "id=" + (item.entry ? String(item.entry.id) : "")
           + " rect=" + Math.round(p.x) + "," + Math.round(p.y)
           + " size=" + Math.round(item.width) + "x" + Math.round(item.height)
           + " global=" + Math.round(g.x) + "," + Math.round(g.y)
    }

    // What the compositor actually granted this surface. Nothing else can
    // answer it: sway's IPC does not list layer surfaces at all. `h` is the
    // configure this window received, so it is the compositor's number rather
    // than ours; `margin` is only our own property read back. Meaningless
    // while the sheet is closed or mid-slide -- open it first.
    function geometry(): string {
      var gap = Math.round(drawerWindow.height
                           - list.mapToItem(null, 0, list.height).y + list.bottomMargin)
      return "w=" + drawerWindow.width
           + " h=" + drawerWindow.height
           + " travel=" + Math.round(root.closeTravel)
           + " margin=" + drawerWindow.margins.bottom
           + " strip=" + root.gestureStrip
           + " gap=" + gap
           + " rowHeight=" + root.rowHeight
           + " rail=" + root.railLetters.length
           // Where the list is standing. A screenshot cannot tell a list that
           // opened scrolled from one whose first rows are missing, and those
           // want opposite fixes.
           + " contentY=" + Math.round(list.contentY)
           + " originY=" + Math.round(list.originY)
           + " contentH=" + Math.round(list.contentHeight)
           + " firstRow=" + list.indexAt(1, list.contentY + 1)
           + " screen=" + (drawerWindow.screen
               ? drawerWindow.screen.width + "x" + drawerWindow.screen.height : "?")
           // refactor.md F8. Whether a touch is still open on either tracker.
           // It must read `idle` whenever no finger is down, and a control that
           // presses without ending is the only way it does not -- invisible
           // from every other instrument, because the sheet is exactly where
           // the finger left it either way.
           + " drag=" + (sheetDrag.latched || handleDrag.latched ? "latched"
                       : sheetDrag.active || handleDrag.active ? "active" : "idle")
    }

    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
  }

  PanelWindow {
    id: drawerWindow

    // The one place the sheet's own size is written. Guarded on a number that
    // could only be the band: no phone this runs on has a 200px sheet.
    onHeightChanged: if (drawerWindow.height > 200) root.sheetHeight = drawerWindow.height
    onWidthChanged: if (drawerWindow.width > 200) root.sheetWidth = drawerWindow.width

    // gestures.md N3. Never unmapped: shut, a one-pixel band along the entry
    // edge; grown to the sheet when an upward drag latches, not on press.
    // Quickshell deletes a layer-shell window that goes invisible, so a
    // drawer mapped per open builds a whole QQuickWindow on the frame the
    // finger is moving -- measured at ~200ms against ~30 for a resize.
    visible: true
    anchors {
      top: root.bandAnchors.top
      bottom: root.bandAnchors.bottom
      left: root.bandAnchors.left
      right: root.bandAnchors.right
    }
    implicitHeight: 1
    implicitWidth: 1
    color: "transparent"

    // N3. Grown is not live: while warming this surface is full-screen and on
    // Top, so its input region is cut down until the sheet is actually drawn.
    //
    // One pixel and not none: Qt treats an empty mask as unset, and an unset
    // input region is the *whole surface*. The pixel is outside the surface,
    // where the compositor clips it to nothing -- inside the band it would be
    // a dead spot at the edge of whatever it sits over.
    Region { id: warmRegion; x: -1; y: -1; width: 1; height: 1 }
    mask: root.progress > 0 ? null : warmRegion

    WlrLayershell.namespace: "moarchy-app-drawer-minimal"
    WlrLayershell.layer: WlrLayer.Top

    // Reserve nothing, but be arranged into what the exclusive surfaces left.
    // This is the whole reason the keyboard can coexist with the search field:
    // on Top with zone 0 the sheet is laid out below the bar and above the
    // keyboard with no geometry maths here. Overlay would bury the list under
    // the keyboard, which is the one arrangement that makes search useless.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    // gestures.md I1, I5a. Extend past the bottom of the usable area, under
    // the gesture strip, or a band of wallpaper shows under the sheet with the
    // home pill drawn on it. Gated on the keyboard: with it down the band
    // below is the strip, which is on Overlay and draws over us; with it up
    // the band is the keyboard, which is on Top like this surface and mapped
    // earlier, so unconditional we would paint over its top key row.
    //
    // One signal, and it is the compositor's own configure -- it lags the
    // raise by a frame and cannot be wrong about it.
    margins.bottom: root.keyboardUp ? 0 : -root.gestureStrip

    // Gated on `progress`, NOT on `opened`. `opened` goes false on the first
    // frame of the close drag, which would drop keyboard_interactivity
    // mid-gesture; the compositor then hands focus back to a window, and that
    // focus change cancels the touch this surface is holding.
    WlrLayershell.keyboardFocus: root.progress > 0 ? WlrKeyboardFocus.Exclusive
                                                   : WlrKeyboardFocus.None

    // One blended quad, its alpha bound straight to the drag. Not an `opacity`
    // on the subtree, which makes the renderer composite the whole sheet
    // off-screen first.
    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Upstream.Color.background, 0.6 * root.progress)
    }

    Rectangle {
      id: sheet

      // On the entry axis, the last sheet size rather than the window's: on
      // the band the window is one pixel across there, and a sheet that
      // followed it would lay the list out again at one pixel on every close.
      // The cross axis takes the parent, because the cross axis never
      // collapses.
      width: root.sideways
           ? (root.sheetWidth > 0 ? root.sheetWidth
              : (drawerWindow.screen ? drawerWindow.screen.width : parent.width))
           : parent.width
      height: root.sideways ? parent.height
            : (root.sheetHeight > 0 ? root.sheetHeight
               : (drawerWindow.screen ? drawerWindow.screen.height : parent.height))

      // Q2. Rides in from whichever edge raised it, and keeps going by up to
      // 80px as the finger approaches the home stop (A4). Translation only: a
      // `scale` on a full-screen item costs a re-raster where an `x` or a `y`
      // costs nothing.
      readonly property var at: Edge.offset(root.entryEdge, root.progress,
                                            parent.width, parent.height,
                                            sheet.width, sheet.height)
      readonly property real lift:
        Edge.openDirection(root.entryEdge) * Style.space(80) * root.homeHint

      x: sheet.at.x + (root.sideways ? sheet.lift : 0)
      y: sheet.at.y + (root.sideways ? 0 : sheet.lift)
      color: root.surface
      radius: root.radiusSheet

      // Escape closes the sheet. There is no page stack here to walk -- the
      // card and the settings section that gave the other drawer one are M17
      // and M18 -- so this is the whole of the ladder.
      Keys.onEscapePressed: root.dismiss()

      // The radius rounds all four corners, so square the trailing two back
      // off rather than leave two notches over whatever is behind.
      Shared.TrailingSquare {
        edge: root.entryEdge
        depth: root.radiusSheet
        color: root.surface
      }

      // H1, for a drag that starts on empty sheet rather than on a row.
      // Declared before the handle and the column so it sits *under* them:
      // later siblings take input first, so this only sees what nothing else
      // claimed.
      SheetArea {
        // no press state (style.md H7): a drag catcher under the content, not
        // a control.
        anchors.fill: parent
      }

      // Pull the sheet down by the handle across its top. A MultiPointTouchArea
      // on a strip of its own, and not a DragHandler over the content: a
      // handler over content gets one translation event for an entire gesture,
      // because the delegates' MouseAreas hold the exclusive grab. The strip
      // cannot compete with a tap on a row because it does not overlap one.
      Item {
        id: handleStrip
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(26)

        Rectangle {
          anchors.centerIn: parent
          width: Style.space(36)
          height: Math.max(2, Style.space(4))
          radius: height / 2
          color: Util.alpha(root.textOnSurface, root.dragging ? 0.8 : 0.3)
          Behavior on color { ColorAnimation { duration: 140 } }
        }

        // Its own tracker instance, not the sheet's. A finger starts on one or
        // the other and never both, and their release rules differ: this one
        // commits on distance alone where the sheet also takes a fling.
        // `latchOnPress`, because the whole strip is a handle -- there is
        // nothing else a touch here could mean.
        Shared.DragTracker {
          id: handleDrag
          travel: root.closeTravel
          openDirection: -1
          latchSign: 0
          latchOnPress: true
          startFrom: root.progress

          onBegan: root.dragging = true
          onMoved: p => root.progress = p

          onFinished: (p, v) => {
            root.dragging = false
            if (p <= root.closeCommit) root.dismiss()
            else root.progress = 1
          }

          onStranded: root.markTrace(-2)
          onCanceled: from => {
            root.markTrace(-1)
            root.dragging = false
            root.progress = from
          }
        }

        MultiPointTouchArea {
          anchors.fill: parent
          maximumTouchPoints: 1

          onPressed: pts => {
            if (pts.length === 0) return
            handleDrag.press(pts[0].sceneX, pts[0].sceneY)
          }
          onUpdated: pts => { if (pts.length > 0) handleDrag.move(pts[0].sceneX, pts[0].sceneY) }
          onReleased: pts => handleDrag.release()
          onCanceled: pts => handleDrag.cancel()
        }
      }

      Column {
        id: sheetColumn
        anchors.top: handleStrip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        anchors.bottomMargin: Style.space(10)
        spacing: Style.space(10)

        // --------------------------------------------------------- the title
        //
        // The one thing this screen has that the grid does not, and it earns
        // its line: a list of names with a search field over it and nothing
        // else looks like a result set, and a result set implies a query
        // somebody has forgotten typing. "All apps" says the list is the whole
        // list.
        Text {
          id: header
          leftPadding: Style.space(6)
          topPadding: Style.space(6)
          text: "All apps"
          font.family: Style.font.family
          font.pixelSize: Style.font.display
          font.weight: root.textWeight
          color: root.textOnSurface
        }

        // -------------------------------------------------------- the search
        //
        // The app drawer's pill, on the same terms and for the same reasons
        // (style.md F1-F6): a fully rounded target is easier to hit than a
        // rectangle of the same area, the field's insets are PADDING rather
        // than anchor margins so that every drawn pixel of the pill focuses
        // it, and the clear button keeps a target of its own.
        Rectangle {
          id: searchPill
          width: parent.width
          height: Style.space(46)
          radius: ui.radiusOn(height)
          color: root.container

          Text {
            id: searchGlyph
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍉"   // U+F0349  md-magnify
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
            color: root.subdued
          }

          Ui.TextField {
            id: searchField
            anchors.left: parent.left
            anchors.right: clearButton.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            leftPadding: searchGlyph.x + searchGlyph.width + Style.space(10)
            rightPadding: clearButton.visible ? Style.space(4) : Style.space(16)
            // The control is taller than its line, so it has to be told where
            // that line goes; left at the default the text renders against the
            // top of the pill.
            verticalAlignment: TextInput.AlignVCenter
            placeholderText: "Search apps"
            background: null
            verticalPadding: 0
            onTextChanged: queryDebounce.restart()

            // G14a. A press that *starts* on this field, and only once the
            // sheet is sitting still. ClickFocus keeps Exclusive from parking
            // here on map; onPressed rather than a TapHandler, because the pill
            // slides under the opening finger and onTapped fires on that
            // release.
            focusPolicy: Qt.ClickFocus
            activeFocusOnTab: false
            MouseArea {
              anchors.fill: parent
              enabled: root.keyboardRaiseArmed
              propagateComposedEvents: true
              onPressed: mouse => {
                if (root.keyboardRaiseArmed) osk.show()
                mouse.accepted = false
              }
            }
          }

          // F6. Only when there is something to clear, and zero-wide rather
          // than merely invisible: an invisible Item still holds its anchors,
          // so a fixed width would take 44px off the field's hit area on every
          // screenful where nothing has been typed.
          Item {
            id: clearButton
            visible: searchField.text.length > 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? root.clearSlot : 0
            height: root.clearSlot

            PressVeil {
              anchors.fill: parent
              radius: ui.radiusOn(width)
              on: clearArea.pressed && !root.sheetDragging
            }

            Ui.OpticalGlyph {
              anchors.fill: parent
              text: "󰅙"   // U+F0159  md-close_circle
              fontFamily: Style.font.family
              fontSize: Style.font.iconLarge
              color: root.subdued
            }

            MouseArea {
              id: clearArea
              anchors.fill: parent
              // Straight to the query as well as to the field: through
              // onTextChanged alone this goes via the 120ms debounce, and the
              // list then holds the results of a query that is visibly no
              // longer there.
              onClicked: {
                searchField.text = ""
                queryDebounce.stop()
                root.query = ""
              }
            }
          }
        }

        // ------------------------------------------------- the list and rail
        //
        // An Item holding both, rather than two Column children, because they
        // are side by side rather than stacked and the rail is as tall as the
        // list.
        //
        // No binding loop in the height: this reads sheetColumn's height and
        // its own `y`, and `y` is fixed by the title and the pill above it
        // rather than by the height this goes on to decide.
        Item {
          id: listArea
          width: parent.width
          height: Math.max(0, sheetColumn.height - y)

          ListView {
            id: list
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: railColumn.left
            anchors.rightMargin: root.railLetters.length > 0 ? Style.space(4) : 0
            clip: true
            model: root.appRows
            boundsBehavior: Flickable.StopAtBounds
            // Scroll padding, so the last row comes to rest a strip clear of
            // the home pill now that the sheet runs under it (I4). Rows may
            // pass beneath the pill mid-scroll; none may stop there.
            bottomMargin: root.gestureStrip
            // A Flickable whose content fits its view does not drag at all,
            // and leaving it "interactive" there means it silently swallows
            // vertical drags that could have closed the sheet (H1).
            interactive: contentHeight > height
            // Virtualised on purpose: a delegate per entry is real memory on a
            // phone with 900MB. Four screenfuls of buffer, expressed in rows
            // rather than in the view's own width -- a delegate sized from the
            // view is zero wide at construction, and a cacheBuffer derived
            // from that builds the whole model before the first layout.
            cacheBuffer: root.rowHeight * 4

            delegate: Item {
              id: row
              required property var modelData
              readonly property var entry: modelData.entry

              width: list.width
              // A constant, never read off the view: the fill loop advances on
              // this number, and a delegate that measures zero walks the whole
              // model synchronously before the event loop runs again.
              height: root.rowHeight

              // The row has no chrome of its own, so the veil is the chrome
              // (style.md H8), inset so two neighbours never touch.
              PressVeil {
                anchors.fill: parent
                anchors.topMargin: Style.space(2)
                anchors.bottomMargin: Style.space(2)
                radius: root.radiusCard
                on: rowArea.pressed && !root.sheetDragging
              }

              // M8. The icon, and it is a glyph. Through Ui.OpticalGlyph and
              // in a slot, because a glyph centred in a box is centred on its
              // *painted* bounds rather than on the em square, and a plain
              // Text sits visibly high in a slot (style.md B5, E5).
              Ui.OpticalGlyph {
                id: rowGlyph
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                width: root.glyphSlot
                height: root.glyphSlot
                text: Glyphs.forEntry(row.entry)
                fontFamily: Style.font.family
                fontSize: Style.font.iconLarge
                color: root.textOnSurface
              }

              Text {
                anchors.left: rowGlyph.right
                anchors.leftMargin: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: root.entryName(row.entry)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: root.textWeight
                color: root.textOnSurface
                elide: Text.ElideRight
              }

              // H1, H4. The drag has to live here rather than on an area
              // behind the list, because this MouseArea holds the exclusive
              // grab for the whole gesture. So it does both jobs: a touch that
              // never travels is a launch, one that travels drags the sheet.
              SheetArea {
                id: rowArea
                anchors.fill: parent
                onClicked: if (!root.sheetWasDrag) root.launch(row.entry)
              }
            }
          }

          // --------------------------------------------------------- the rail
          //
          // M12, M13. A column of letters and one touch area over the lot. Not
          // a letter per MouseArea: the gesture is a scrub, and eleven areas
          // would hand the grab to whichever one the finger happened to land
          // on and then stop hearing about it the moment it slid onto the next.
          //
          // Zero-wide when there is nothing to offer, so the list takes the
          // whole sheet while a query is showing (M16). Zero rather than
          // invisible, for the reason the clear button is: an invisible Item
          // still holds its anchors.
          Item {
            id: railColumn
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.gestureStrip
            width: root.railLetters.length > 0 ? Style.space(22) : 0
            visible: width > 0

            readonly property int count: root.railLetters.length

            // The pitch, and the cap is the whole of it. Twenty-odd letters on
            // this rail is the division; five would be five letters stranded a
            // hundred pixels apart, which is not an index of anything. So:
            // share the rail out, but never further apart than a line.
            readonly property real step: railColumn.count > 0
              ? Math.min(railColumn.height / railColumn.count, Style.space(18)) : 0

            // From the top, and NOT centred. Centring looked tidier and put the
            // last two letters under moarchy-keyboard's show button, which
            // floats over the bottom right of any surface with a text field on
            // it -- measured on sargo: the toggle covers logical y 592..620 and
            // the full width of this rail. A control another package owns is
            // not one to fight for pixels, and running from the top is also
            // what the design this screen copies does.
            readonly property real inset: 0

            Column {
              y: railColumn.inset
              width: parent.width

              Repeater {
                model: root.railLetters

                delegate: Text {
                  required property var modelData
                  required property int index

                  width: railColumn.width
                  height: railColumn.step
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  text: modelData.letter
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: root.textWeight
                  color: railArea.pressed && root.railActive === index
                  // drag guard (style.md H6): M14. This area never drags the
                  // sheet, so `pressed` cannot be a drag in progress -- but the
                  // rule on this surface is that no press lights during one,
                  // and a control exempt by accident of behaviour is one that
                  // stops being exempt the day the behaviour moves.
                           ? root.textOnSurface : root.subdued
                  Behavior on color { ColorAnimation { duration: 120 } }
                }
              }
            }

            // M14. A plain MouseArea and NOT a SheetArea, which is the one
            // exemption from H3 on this screen. Its whole gesture is a
            // vertical drag: forwarded to the sheet, every scrub past the
            // slop would close the drawer, and the rail would be a control
            // nobody could use. Named in the specification so the exemption is
            // a decision rather than an omission.
            MouseArea {
              id: railArea
              anchors.fill: parent
              // `mouse.y` is already in the rail's coordinates: this area
              // fills it, which is the whole reason railIndexAt() takes them.
              onPressed: mouse => root.scrubTo(mouse.y)
              onPositionChanged: mouse => root.scrubTo(mouse.y)
              onReleased: root.railActive = -1
              onCanceled: root.railActive = -1
            }
          }
        }
      }
    }

    // Somewhere for active focus to go when the drawer closes (N4). It has to
    // be a real item *inside this window*: an item with no window cannot be
    // given active focus, so a sink at plugin root sets a flag on an orphan
    // and takes nothing away from the search field -- which then keeps its
    // `focus` across the unmap and has it handed straight back on the next
    // open, reopening the drawer with last time's query still in it.
    Item { id: focusSink; focus: true }
  }

  // Typing on a phone keyboard is slow enough that per-keystroke re-sorting of
  // every desktop entry is affordable; the churn behind it is not.
  Timer {
    id: queryDebounce
    interval: 120
    onTriggered: root.query = searchField.text
  }
}
