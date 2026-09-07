// The app drawer: what the bottom-edge swipe up opens.
//
// ---------------------------------------------------------------------------
// Why not just keep opening the Omarchy menu
// ---------------------------------------------------------------------------
// The swipe used to run `omarchy-menu toggle apps`, which is the desktop
// command palette opened at its Apps page: a single-column list of names, no
// icons, built to be filtered by typing. That is the right shape for a keyboard
// and the wrong one for a thumb -- on a phone the launcher is the primary way
// in, and it should be an icon grid you recognise rather than a list you read.
//
// The palette is not lost. Everything it could reach lives in
// moarchy.settings, behind the shade's gear -- which is where system
// administration belongs on a phone, rather than one mis-tap from an app icon
// on the launcher. $mod+Alt+Space still opens the menu at its root for anyone
// with a keyboard attached.
//
// So at rest this screen is a search field and a grid, and nothing else. On a
// screen that fits four icons across, a row of controls at the top is a row of
// apps you cannot see.
//
// ---------------------------------------------------------------------------
// Why typing brings settings back
// ---------------------------------------------------------------------------
// At rest, and only at rest. Browsing wants the grid; already knowing the name
// of the thing wants a field, and it is the same field either way. So once
// there is a query, matching Settings rows appear beneath the apps
// (docs/settings.md section O): Screenshot runs, Set a reminder opens its
// screen, Night light opens the page it lives on.
//
// This is not the palette coming back and it is not a second copy of the tree.
// The index is a walk of moarchy.settings' own PAGES, the tap goes through
// moarchy.settings' own activate(), and there is no list of actions here to
// fall out of date. What the drawer owns is the field and the rows it draws.
//
// The two imports below are the price: this plugin will not load without
// moarchy.settings beside it. They ship in one package to one directory, so
// that holds -- but a `~/.config/omarchy/plugins` copy of only *one* of the two
// breaks the path, and the user directory wins. Clear both or neither.
//
// ---------------------------------------------------------------------------
// Why this owns no edge of its own
// ---------------------------------------------------------------------------
// moarchy.gestures already owns the bottom strip, and two exclusive
// layer surfaces cannot share an edge -- the second one is arranged above the
// first rather than on top of it. So the gesture plugin keeps the input and
// toggles this plugin through the shell. The drawer itself is only ever a
// destination.
//
// ---------------------------------------------------------------------------
// Why Top + a zero exclusive zone rather than Overlay
// ---------------------------------------------------------------------------
// The search field needs the on-screen keyboard, and moarchy-keyboard sits on Top
// with an exclusive zone. A surface that reserves nothing is arranged into
// whatever area is left after the exclusive ones are placed -- so on Top with
// zone 0 the drawer is laid out below the bar, above the home pill, and above
// the keyboard when it rises, without a single line of geometry maths here.
// Overlay would put it over all three and leave the grid buried under the
// keyboard, which is the one arrangement that makes search useless.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui
// moarchy.settings', not ours: the Settings tree flattened for search, and the
// batched guard script its pages are read with. See the header note above.
import "../moarchy.settings/Search.js" as Search
import "../moarchy.settings/Guards.js" as Guards
import "../moarchy.common/Theme.js" as Theme
import "../moarchy.common" as Shared

Item {
  id: root

  // Injected by the host in the panel Loader's onLoaded. None of these may be
  // `readonly` or `required`: readonly makes the assignment throw, and required
  // makes the component fail to instantiate at all, because a plugin is created
  // first and configured afterwards. Either way the failure is silent.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
                               || (Quickshell.env("HOME") + "/.local/share/omarchy")
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  // 0 shut .. 1 open, and the drag writes it directly. The gestures plugin owns
  // the bottom edge -- it cannot be shared, so this surface never sees the
  // touch -- and drives this property from its own MultiPointTouchArea while
  // the finger moves. That is what makes the drawer follow the finger rather
  // than appear at a threshold.
  property real progress: 0

  // Set by the gestures plugin for the length of the drag. It turns the
  // animation off (so writes track 1:1) and keeps `opened` honest mid-gesture.
  property bool dragging: false

  // shell.isPluginOpen() reads this by name to decide what toggle() means, so
  // it has to stay honest. Half-dragged is neither open nor shut, and calling
  // it open would let the next swipe try to close something still being
  // pulled out.
  readonly property bool opened: root.progress >= 1 && !root.dragging

  Behavior on progress {
    enabled: !root.dragging
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }

  // The close drag is 1:1 with the finger, and that is not a preference: the
  // handle is *on* the sheet it moves. Any other ratio and the handle races
  // out from under the thumb -- at a third of this it moved about 3.7x finger
  // speed, the touch ended up above the strip it started on, and the gesture
  // came back as a cancel often enough to leave the drawer open on a full
  // drag. Matching the travel to the sheet height keeps the bar exactly where
  // it was grabbed, which is also how a real bottom sheet behaves.
  //
  // The open drag can use a shorter travel because it is driven from the
  // gesture strip, which does not move.
  readonly property real closeTravel: Math.max(1, drawerWindow.height)
  readonly property real closeCommit: 0.7

  // H1. Travel past which a touch on the sheet stops being a tap and starts
  // dragging the sheet shut.
  readonly property int dragSlop: Style.space(10)

  // Where the finger went down, in *scene* coordinates. Local coordinates are
  // useless for this: every input item on the sheet is a child of the sheet,
  // so its frame moves as the sheet does, and a delta measured in it feeds
  // back into itself. Scene coordinates are stationary, so a finger that stops
  // moving produces a delta that stops changing.
  property real sheetPressY: 0
  property bool sheetDragging: false

  // Cleared on the next press, not on release, and that ordering is the whole
  // point. Qt delivers `released` and *then* `clicked`, so a flag cleared in
  // the release handler is already false when the click arrives -- and the
  // delegate launches the app the finger happened to start the drag on. The
  // symptom was a short drag that "closed" the drawer: it had not closed, it
  // had launched something, which dismisses the drawer on its way out.
  property bool sheetWasDrag: false

  // A short, fast flick means the same as a long slow drag. Without this, a
  // drag that begins near the far end of the sheet cannot reach the commit
  // threshold at all -- there is not enough sheet left to travel.
  property real sheetVelocity: 0
  property real sheetLastY: 0
  property real sheetLastT: 0
  readonly property real sheetFling: 0.6

  function sheetPress(item, mouse): void {
    root.sheetPressY = item.mapToItem(null, mouse.x, mouse.y).y
    root.sheetDragging = false
    root.sheetWasDrag = false
    root.sheetVelocity = 0
    root.sheetLastY = root.sheetPressY
    root.sheetLastT = Date.now()
  }

  function sheetMove(item, mouse): void {
    var dy = item.mapToItem(null, mouse.x, mouse.y).y - root.sheetPressY
    if (!root.sheetDragging) {
      // Downward only. An upward drag on the sheet means nothing here, and
      // claiming it would fight the grid the moment it has enough apps to
      // scroll (H5).
      if (dy <= root.dragSlop) return
      root.sheetDragging = true
      root.dragging = true
    }
    var nowY = item.mapToItem(null, mouse.x, mouse.y).y
    var now = Date.now()
    var dt = Math.max(1, now - root.sheetLastT)
    // Positive is downward, which for this sheet is the closing direction.
    root.sheetVelocity = root.sheetVelocity * 0.6 + ((nowY - root.sheetLastY) / dt) * 0.4
    root.sheetLastY = nowY
    root.sheetLastT = now
    root.progress = Math.max(0, Math.min(1, 1 - dy / root.closeTravel))
  }

  function sheetRelease(): void {
    if (!root.sheetDragging) return
    root.sheetWasDrag = true
    root.sheetDragging = false
    root.dragging = false
    if (root.sheetVelocity >= root.sheetFling) root.dismiss()
    else if (root.sheetVelocity <= -root.sheetFling) root.progress = 1
    else if (root.progress <= root.closeCommit) root.dismiss()
    else root.progress = 1
  }

  function sheetCancel(): void {
    if (!root.sheetDragging) return
    root.sheetDragging = false
    root.dragging = false
    root.progress = 1
  }

  // Diagnostic only, and cheap enough to leave in: one integer appended per
  // frame while a drag is in flight, cleared when the next one starts.
  property var dragTrace: []
  onDraggingChanged: if (root.dragging) root.dragTrace = []
  onProgressChanged: {
    if (!root.dragging) return
    var next = root.dragTrace.slice()
    if (next.length < 200) next.push(Math.round(root.progress * 100))
    root.dragTrace = next
  }

  property string query: ""
  readonly property string pluginId: "moarchy.drawer"

  readonly property int columns: 4
  readonly property int iconSize: Style.space(42)

  // Must match moarchy.gestures' own stripHeight. Duplicated rather than
  // read across plugins for the same reason the shade duplicates it: this
  // surface has to know the number even when the gestures plugin failed to
  // load, and a sheet that ran off the bottom of the screen in that case would
  // be worse than one that leaves the band unused.
  //
  // Not 20 pixels. Style.space rounds a *scaled* value and the scale comes from
  // the theme's shell.toml, so this is nearer 23 at the default ~1.15 -- which
  // is why nothing here or in the selftest writes the number down.
  readonly property int gestureStrip: Style.space(20)

  // What the on-screen keyboard reserves at the bottom, duplicated from
  // moarchy.gestures for the reason above. Deliberately *not* through
  // Style.space, and that is not an oversight the way it would be for every
  // other length here: this is moarchy-keyboard's own panel and that client
  // never sees this theme's spacing scale.
  //
  // Only ever used as half of a threshold (I5e), so it does not have to be
  // exact -- it has to be nowhere near either cluster it separates.
  readonly property int keyboardPanelHeight: 200

  // I5e. Is the keyboard up? Asked of the compositor's configure rather than of
  // the search field, because the field answers a different question and I5d is
  // the proof they come apart: the keyboard can be up with nothing here focused
  // at all, and then I5a's inset stays on with the keyboard under it.
  //
  // Measured on this panel: the granted height is 694 or 674 with the keyboard
  // down and 494 or 474 with it up, the pair in each cluster being this
  // surface's own inset on and off. The clusters are 180px apart and the
  // threshold sits between them, so the 20px the inset moves cannot walk the
  // answer across it -- the binding settles in one step in either direction
  // rather than oscillating.
  //
  // False while the surface is down, and that default is the safe one: `height`
  // is whatever the last configure left behind (100 on a surface that has never
  // mapped), so an ungated read would map the first frame with the inset off
  // and flash a band of wallpaper under the pill -- I5c's symptom, from the
  // other end.
  readonly property bool keyboardUp:
    drawerWindow.visible && drawerWindow.screen
    && drawerWindow.height < drawerWindow.screen.height - root.keyboardPanelHeight / 2

  // I5d. Put the keyboard away on the way out.
  //
  // Fire-and-forget over the same bus name moarchy-toggle-keyboard drives, and
  // execDetached rather than a Process for the reason F3 gives: the answer is
  // not needed and the round trip is on the one path that has to feel instant.
  function hideKeyboard(): void {
    Quickshell.execDetached(["busctl", "--user", "call", "sm.puri.OSK0",
                             "/sm/puri/OSK0", "sm.puri.OSK0", "SetVisible",
                             "b", "false"])
  }

  // Set for the length of a dismissal that exists to open something else, and
  // cleared by the close() it guards. Without it the hide above fires on the
  // hand-off paths too and robs the successor of a keyboard it is about to
  // want: tapping a Wi-Fi row in the drawer's own results would open the
  // passphrase screen with the keyboard forced down under it.
  property bool handingOff: false

  // The weight the bar and every other surface runs at (docs/style.md B3).
  // Light text on a dark ground reads thinner than it measures, and one
  // screen left at Regular reads as a different phone.
  readonly property int textWeight: Font.DemiBold

  // The sheet radius, the same one the shade's sheet uses (docs/style.md
  // D1). Named rather than written twice: it is also the height of the
  // rectangle that squares the bottom corners back off, and those two
  // numbers are the same number rather than two that happen to match.
  readonly property int radiusSheet: Style.space(28)

  // An app cell is a grid thing you tap as a unit, which is D1's `tile`. Only
  // the press veil is drawn at it -- the cell itself has no chrome.
  readonly property int radiusTile: Style.space(20)

  // A settings result is a full-width list row, which is D1's `card` -- the
  // same 18 the rows in moarchy.settings are drawn at, because it is the same
  // kind of row read on a different screen. The glyph slot comes from the same
  // place for the same reason (E5): derived from the glyph, not fixed.
  readonly property int radiusCard: Style.space(18)
  readonly property int glyphSlot: Math.round(Style.font.iconLarge * 1.35)

  // Radii are written out rather than taken from Style.cornerRadius, which
  // mirrors Hyprland's `decoration:rounding` and is pinned to 0 here by the
  // hyprctl shim -- right for tiled windows under Sway, wrong for a phone.
  // Colours still come from the theme, so a theme switch restyles all of this.
  readonly property color surface: Color.menu.background
  // NOT `onSurface` / `onAccent`, however much the Material role names want to
  // be spelled that way. QML reserves the `on<Uppercase>` prefix for signal
  // handlers, so a property declared there is never readable: the binding
  // evaluates to undefined, undefined assigned to a `color` is #000000, and
  // nothing is logged. The symptom is every glyph and label painted pure black
  // on a dark tile while the properties either side of them are fine.
  readonly property color textOnSurface: Color.menu.text
  readonly property color container: Util.alpha(Color.menu.text, 0.08)
  readonly property color subduedBase: Theme.mix(
    Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 1), Color.menu.text, 0.08)
  readonly property color subdued: Theme.readableOn(root.subduedBase,
                                                   Color.menu.text, 0.55, 4.5)

  // The veil is shared (docs/refactor.md E2); the default ink is this
  // surface's own, which is the half a shared type cannot know (style.md H2).
  component PressVeil: Shared.PressVeil { ink: root.textOnSurface }


  readonly property var appRows: {
    // Re-read on every appsChanged() as well as on every keystroke: the bump
    // below is what makes a freshly installed app appear without a reopen.
    var bump = root.appsRevision
    if (!root.shell || !root.shell.appLibrary) return []
    return root.shell.appLibrary.sortedEntries(root.query)
  }
  property int appsRevision: 0

  Connections {
    target: root.shell ? root.shell.appLibrary : null
    function onAppsChanged() { root.appsRevision++ }
  }

  // --------------------------------------------------- settings results (O)
  //
  // Five, because the sheet has to stay an app grid with a tail rather than a
  // list with some icons on top. Beyond about five the section is taller than
  // the two rows of apps above it, and a query broad enough to return more than
  // five settings rows is a query that was going to be narrowed anyway.
  readonly property int settingsLimit: 5

  // The whole of the matching. Everything else on this side is about which of
  // these the guards allow on screen.
  readonly property var settingsHits: Search.search(root.query, root.settingsLimit)

  // What the last guard batch answered, keyed by `<pageId>/<rowId>`. A row with
  // no `when:` is never in here and never needs to be.
  property var settingsGuards: ({})
  property int guardGeneration: 0

  // O7. A guarded row is withheld until its guard says yes, rather than shown
  // and then taken away. `when` hides only on an explicit 0 in Settings because
  // there the page is already up and a row appearing late is the lesser fault;
  // in a list that is being retyped every 120ms, a row that flickers in and out
  // under the thumb is the worse one.
  readonly property var settingsRows: {
    var hits = root.settingsHits
    var answers = root.settingsGuards
    var out = []
    for (var i = 0; i < hits.length; i++) {
      var h = hits[i]
      if (h.row.when && answers[h.key] !== true) continue
      out.push(h)
    }
    return out
  }

  // One bash for the whole result set, the same bargain Guards.js strikes for a
  // page: a fork on a 1.15GHz A53 costs far more than the tests inside it, and
  // this runs on a settled keystroke rather than on a screen being opened.
  //
  // Guards.build answers "" when nothing carries a `when:`, and most queries
  // are exactly that -- so most keystrokes cost no process at all (O7).
  function readSettingsGuards() {
    var hits = root.settingsHits
    var rows = []
    for (var i = 0; i < hits.length; i++) {
      if (!hits[i].row.when) continue
      // Guards.js keys its output by `id`, and a row id is unique only within
      // its page. The composite key is what makes a batch that spans pages
      // parseable at all; the parser splits on the first two colons, so the
      // slash in it survives.
      rows.push({ id: hits[i].key, when: hits[i].row.when })
    }

    // Bumped before the early return, not after it. A query with nothing to ask
    // still has to invalidate a batch that is already in flight -- otherwise
    // "record" starts one, "emoji" clears the map without moving the
    // generation, and the first batch lands afterwards and is believed.
    root.guardGeneration += 1

    var script = Guards.build(rows, "")
    if (!script) { root.settingsGuards = ({}); return }

    guardProc.wanted = root.guardGeneration
    if (guardProc.running) guardProc.running = false
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  onSettingsHitsChanged: root.readSettingsGuards()

  Process {
    id: guardProc
    property int wanted: 0
    stdout: StdioCollector {
      onStreamFinished: {
        // A batch for a query that has already been retyped is not a late
        // answer, it is the wrong answer.
        if (guardProc.wanted !== root.guardGeneration) return
        root.settingsGuards = Guards.parse(String(text || "")).when
      }
    }
  }

  // A tap on a settings result. The drawer decides *where* to send it and
  // moarchy.settings decides what that means -- which is the whole reason there
  // is no command line anywhere in this file.
  //
  //   nav                       open the page it points at. Set a reminder is a
  //                             row on Reminders and a screen of its own, and
  //                             the screen is the thing being asked for (O5).
  //   action, link, plugin      fire it, quietly. Settings stands the page up,
  //                             runs the row and never maps (O4).
  //   switch, choice, info      open the page it lives on. A radio flipped from
  //                             a search result is a value changed by something
  //                             that never showed it to you (O6).
  //
  // A row that turns out to be hidden or not ready lands on its page instead of
  // doing nothing, and that decision is Settings' too (O9).
  function activateSetting(hit) {
    if (!hit || !root.shell || typeof root.shell.summon !== "function") return

    var payload
    if (hit.type === "nav")
      payload = { page: String(hit.row.page) }
    else if (hit.type === "action" || hit.type === "link" || hit.type === "plugin")
      payload = { page: hit.pageId, activate: hit.rowId, quiet: true }
    else
      payload = { page: hit.pageId }

    // Settings' own open() hides this surface, the same as the shade's gear
    // does. Dismissing first anyway is the belt to those braces: a quiet open
    // never reaches the branch that hides anything.
    //
    // A hand-off, so the keyboard stays where it is (I5d). Settings is about to
    // stand up a page that may be a passphrase field.
    root.handingOff = true
    root.dismiss()
    root.shell.summon("moarchy.settings", JSON.stringify(payload))
  }

  function open(payloadJson) {
    // Only one of the two overlays is ever up. Asking the host rather than
    // tracking it here means this still holds when the shade was opened by its
    // own drag and this plugin never heard about it.
    if (root.shell && typeof root.shell.isPluginOpen === "function"
        && root.shell.isPluginOpen("moarchy.shade"))
      root.shell.hide("moarchy.shade")

    root.query = ""
    searchField.text = ""
    // A hand-off that never reached an unmap must not silence the next real
    // close (I5d).
    root.handingOff = false
    // Belt to close()'s braces. close() is the path every dismissal takes and
    // is where releasing the field belongs, but the invariant the margin gate
    // rests on is "focused means the keyboard is up" -- so the open path
    // asserts it too rather than trusting that nothing ever opens this surface
    // from a state it did not close from.
    focusSink.forceActiveFocus()
    root.dragging = false
    root.progress = 1

    // Icons are indexed off a directory scan that never re-runs on its own, so
    // an app installed since the shell started has no icon until this. Deferred
    // rather than blocking: a blocking reload inside open() spins a nested
    // event loop and the surface never becomes visible -- the same trap the
    // launcher's back-button patch hit.
    if (root.shell && root.shell.appLibrary)
      Qt.callLater(function() { root.shell.appLibrary.refreshIcons() })
  }

  function close() {
    // Move focus off the search field BEFORE the surface goes away. The keyboard
    // is driven by zwp_text_input_v3 and an unmap is not a deactivate: close the
    // drawer straight from the search field and the keyboard is left standing
    // over whatever is underneath, with nothing focused that could dismiss it.
    // `focus = false` is not enough -- it releases the focus *scope*, not the
    // active focus, so Qt has no reason to disable the text input. Handing
    // active focus to a plain Item is what actually sends the disable.
    focusSink.forceActiveFocus()

    // I5d. Releasing the field is not enough, and this is the half that was
    // missing. The field is only one of the things that can have the keyboard
    // up: this surface holds the seat's keyboard while it is open, so the
    // window underneath is deactivated for that whole time and sway re-activates
    // it on the unmap. Its text input re-enters and the keyboard rises -- a
    // keyboard nobody asked for, standing on whatever is now on screen.
    //
    // Unconditional, for F3's reasons. Asking whether it was up first needs the
    // DBus probe's round trip on a dismissal, and G2 already records what
    // acting on a stale answer costs. The price is that leaving an overlay over
    // an app you were typing in puts the keyboard away; that is the trade F3
    // and G1 both already make.
    if (!root.handingOff) root.hideKeyboard()

    root.query = ""
    root.dragging = false
    root.progress = 0
  }

  // Every dismissal goes through the host rather than setting `opened` directly,
  // so openPanelIds and this plugin cannot drift apart and leave the next swipe
  // toggling the wrong way.
  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  function launch(entry) {
    if (!entry || !root.shell || !root.shell.appLibrary) return
    root.shell.appLibrary.launch(entry.id, root.shell.appLibrary.entryName(entry))
    // A hand-off too (I5d): the app being launched is the one that gets to say
    // whether it wants a keyboard, and a terminal asks for one the moment it
    // maps. Forcing it down here would fight that on a race.
    root.handingOff = true
    root.dismiss()
  }

  // Lets the drawer be driven without a finger, which is how the selftest
  // asserts it: omarchy-shell drawer state
  IpcHandler {
    target: "drawer"

    function state(): string { return root.opened ? "open" : "closed" }
    // How far up the sheet is, so a drag can be measured rather than
    // photographed and guessed at.
    function progress(): string {
      return Math.round(root.progress * 100) + (root.dragging ? " dragging" : "")
    }

    // The samples the last drag actually produced. Polling `progress` over IPC
    // cannot answer whether the sheet tracked the finger -- each call is a
    // process spawn on an A53, so the sampling is slower than the thing being
    // sampled. Recording in-process and reading the trace afterwards can.
    function dragTrace(): string { return root.dragTrace.join(" ") }

    // docs/style.md F1, F3. Neither is answerable by a screenshot: the
    // pill and the field draw the same picture whether or not they are the same
    // rectangle, which is exactly how the dead band survived this long. So the
    // two rects are reported side by side, in surface coordinates -- the panel
    // pixels bin/moarchy-touch takes are these doubled. `focused` closes the
    // loop: tap a corner, read it back.
    //
    // Meaningless while the drawer is closed or mid-slide, the same as
    // geometry(): open it first.
    function searchTarget(): string {
      var box = it => {
        var p = it.mapToItem(null, 0, 0)
        return Math.round(p.x) + "," + Math.round(p.y)
             + " " + Math.round(it.width) + "x" + Math.round(it.height)
      }
      return "pill=" + box(searchPill)
           + " field=" + box(searchField)
           + " focused=" + searchField.activeFocus
    }

    // What the compositor actually granted this surface. Nothing else can
    // answer it: sway's IPC does not list layer surfaces, so `swaymsg -t
    // get_tree` is silent about every one of them.
    //
    // `h` is the configure this window received, so it is the compositor's
    // number rather than ours -- which is what makes it evidence. `margin` is
    // only our own property read back: it proves the assignment was accepted,
    // never that it was honoured. When the two disagree, `h` is the one that
    // is telling the truth (docs/gestures.md I2).
    //
    // `gap` is how far the last content pixel comes to rest above the bottom of
    // the surface. It must never fall below `strip`, or a row settles under the
    // home pill where it cannot be tapped (I4, I5).
    //
    // Meaningless while the surface is closed or mid-slide: open it first.
    function geometry(): string {
      // Measured off whatever is last on the sheet, which stopped being the
      // grid the moment a query could put a settings section under it (O11).
      // Read off the grid regardless, `gap` would report the distance from the
      // bottom of the *apps* to the bottom of the surface -- a number that
      // includes the whole settings section and is comfortably over the strip
      // while the last result sits under the home pill.
      var last = settingsSection.visible ? settingsSection : grid
      var pad = settingsSection.visible ? 0 : grid.bottomMargin
      var gap = Math.round(drawerWindow.height - last.mapToItem(null, 0, last.height).y + pad)
      return "w=" + drawerWindow.width
           + " h=" + drawerWindow.height
           + " margin=" + drawerWindow.margins.bottom
           + " strip=" + root.gestureStrip
           + " gap=" + gap
           + " screen=" + (drawerWindow.screen
               ? drawerWindow.screen.width + "x" + drawerWindow.screen.height : "?")
    }

    // Drives a launch down the same path a tap does: find the entry the grid
    // would have shown, then root.launch(), which starts the app and dismisses
    // the sheet. It exists because docs/windows.md L1-L7 cannot be asserted any
    // other way -- the splash is feedback for a tap, and a check has no finger.
    //
    // It is no longer only a check's finger. moarchy-store's Open button calls
    // this rather than launching the entry itself, so that installing something
    // and opening it puts its icon on the wallpaper like every other launch
    // (L9). That makes this a contract with a consumer outside this repo:
    // renaming it, or moving it off the drawer, breaks Open in the store.
    // Callers pass the bare id -- no .desktop suffix -- or the lookup below
    // misses and the splash falls back to a generic icon.
    //
    // An id with no entry behind it still launches, straight through
    // appLibrary, and says so in the answer. That is not a convenience: L6 is
    // "what happens when nothing ever appears", and an id that resolves to no
    // application is the only way to ask for that without installing a .desktop
    // file that lies.
    function launch(desktopId: string): string {
      var id = String(desktopId || "")
      if (!id) return "no id"
      if (!root.shell || !root.shell.appLibrary) return "no shell"
      // Rows, not entries: sortedEntries returns {entry, score, key, name}
      // wrappers, the same shape the grid delegate below unwraps. Reading
      // `.id` off a row yields undefined and launches nothing, silently.
      var rows = root.shell.appLibrary.sortedEntries("") || []
      for (var i = 0; i < rows.length; i++) {
        var entry = rows[i] && rows[i].entry
        if (entry && String(entry.id) === id) {
          root.launch(entry)
          return "ok"
        }
      }
      root.shell.appLibrary.launch(id, id)
      return "no-entry"
    }

    // Every id the grid would list, so a check can pick a real app instead of
    // guessing at one that happens to be installed.
    function entries(): string {
      if (!root.shell || !root.shell.appLibrary) return ""
      var out = []
      var rows = root.shell.appLibrary.sortedEntries("") || []
      for (var i = 0; i < rows.length; i++)
        if (rows[i] && rows[i].entry) out.push(String(rows[i].entry.id))
      return out.join("\n")
    }

    // ------------------------------------------------- settings results (O)
    //
    // Typing, without a finger. It writes the field rather than `root.query`
    // directly, so what a check drives is the same path a keystroke takes --
    // including the debounce, which is flushed here rather than waited out: a
    // check that slept 120ms would be asserting the timer, not the results.
    function type(text: string): string {
      searchField.text = String(text || "")
      queryDebounce.stop()
      root.query = searchField.text
      return "ok"
    }

    // What the section is showing, after the guards. `visible` is always 1 for
    // a listed row -- a guarded row that has not answered yet is simply not
    // here -- and it is a column rather than a promise so O7 has something to
    // read when that changes.
    function results(): string {
      var rows = root.settingsRows
      var out = []
      for (var i = 0; i < rows.length; i++)
        out.push([rows[i].key, rows[i].type, rows[i].label,
                  rows[i].section, "1"].join("\t"))
      return out.join("\n")
    }

    // Every hit the query matched, guards ignored. `results` is what is on
    // screen; this is what the index found, and O7 is the difference between
    // the two.
    function matches(): string {
      var hits = root.settingsHits
      var out = []
      for (var i = 0; i < hits.length; i++)
        out.push(hits[i].key + "\t" + (hits[i].row.when ? "guarded" : "-"))
      return out.join("\n")
    }

    // A tap on one of them, down the same function the delegate calls. Keyed by
    // `<pageId>/<rowId>`, which is what `results` prints.
    function activateResult(key: string): string {
      var rows = root.settingsRows
      for (var i = 0; i < rows.length; i++)
        if (rows[i].key === key) { root.activateSetting(rows[i]); return "ok" }
      // Told apart on purpose: a key the index knows but the guards withheld is
      // O7 working, and a key nothing matched is a query that was never typed.
      var hits = root.settingsHits
      for (var j = 0; j < hits.length; j++)
        if (hits[j].key === key) return "hidden"
      return "unknown result"
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

    visible: root.progress > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // I5d. The unmap is the event that raises the keyboard, so it is also the
    // event that has to put it away. `handingOff` is consumed here rather than
    // in close(): for the drawer close() runs a whole animation before the
    // surface goes, and a flag cleared at the top of it would be gone by the
    // time this ran.
    onVisibleChanged: {
      if (visible) return
      if (!root.handingOff) keyboardRetreat.restart()
      root.handingOff = false
    }


    WlrLayershell.namespace: "moarchy-drawer"
    WlrLayershell.layer: WlrLayer.Top

    // Reserve nothing, but be arranged into what the exclusive surfaces left.
    // This is the whole reason the keyboard can coexist with the search field.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    // Extend past the bottom of the usable area, under the gesture strip. A
    // zero exclusive zone means sway arranges this *into* what the exclusive
    // surfaces left, so without this the sheet stops at the top of the strip
    // and a band of wallpaper -- or of the app behind -- shows under it with
    // the pill drawn on it (docs/gestures.md I1).
    //
    // The exclusion mode is deliberately untouched. The strip still reserves
    // its band off every window and this surface is still arranged around the
    // on-screen keyboard, because a margin moves only this surface's own bottom
    // edge. Reserving and drawing-under are separate questions.
    //
    // Negative is legal, not a trick: wlroots stores layer-shell margins as
    // int32_t and computes `box.height = bounds.height - (margin.top +
    // margin.bottom)` with no clamping, and sway delegates to it and adds no
    // validation of its own.
    //
    // Gated on the search field, and this is the whole subtlety. A margin does
    // not extend the surface "under the strip" -- it extends it past the bottom
    // of the *usable area*, and what sits there depends on what else is
    // reserving. With the keyboard down that is the strip, which is on Overlay
    // and draws over us: exactly what is wanted. With the keyboard up it is the
    // keyboard, which is on Top like this surface and mapped earlier, so the
    // drawer wins the overlap and paints over it.
    //
    // Measured, not reasoned about: unconditional, with the keyboard up, the
    // drawer's last 20px covered the whole top key row -- `qwertyuiop` reduced
    // to a sliver under the app labels. Content compensation does not help,
    // because the grid's bottomMargin moves the last *row* and not the surface.
    //
    // Two signals, and the field is the *second* of them now (I5e).
    //
    // activeFocus leads: the field holding focus is what causes the keyboard to
    // come up, so it flips before the keyboard has finished rising and the
    // inset is already off when it arrives. What it cannot do is answer for a
    // keyboard this surface did not raise, and I5d is the proof that happens --
    // so on its own it left the inset on with the keyboard under it, and the
    // sheet's last row painted over the top key row.
    //
    // `keyboardUp` covers exactly that gap. It reads the compositor's own
    // configure, which lags the raise by a frame but cannot be wrong about it.
    //
    // OR rather than a replacement, deliberately. Either term alone drops the
    // inset, so this can only turn it off in more cases than before and never
    // in fewer -- which is what keeps I5a and I5c saying what they said.
    //
    // Safe against the drag, which was the reason to want it constant. Focus
    // does not change mid-drag: a close moves it to focusSink only once the
    // sheet is already on its way out, and while typing the height is constant
    // for the whole gesture. closeTravel and the sheet's `y` both read
    // drawerWindow.height and neither sees it move.
    margins.bottom: (searchField.activeFocus || root.keyboardUp)
                    ? 0 : -root.gestureStrip

    // Plain Exclusive rather than the prime-then-OnDemand dance in
    // Ui/KeyboardPanel.qml: that exists so clicks can still reach the bar
    // underneath, and this drawer deliberately owns the whole screen while it
    // is up. Every other full-screen overlay in the shell -- menu, emojis,
    // clipboard, image picker -- does exactly this.
    //
    // Gated on `progress`, NOT on `opened`. `opened` goes false on the first
    // frame of the close drag, which drops keyboard_interactivity to None
    // mid-gesture; sway then hands focus back to a window, and that focus
    // change cancels the touch this surface is holding. The symptom was a
    // close drag that died after one frame -- and only when a window was open
    // for focus to return to, which is why it passed by hand on an empty
    // workspace and failed every time under the selftest. Holding Exclusive
    // until the sheet is all the way down keeps the gesture intact.
    WlrLayershell.keyboardFocus: root.progress > 0 ? WlrKeyboardFocus.Exclusive
                                                   : WlrKeyboardFocus.None

    // The scrim is what makes a half-open drawer read as half-open rather than
    // as a window that has not finished drawing. One blended quad, its alpha
    // bound straight to the drag -- no opacity on a subtree, which would make
    // the renderer composite the whole sheet off-screen first on a GPU that
    // has nothing spare.
    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.6 * root.progress)
    }

    Rectangle {
      id: sheet
      width: parent.width
      height: parent.height
      // Rides up from below the bottom edge. Translation only: this is a
      // Mali-400 at GLES 2.0, so there are no shaders to spend, and a `scale`
      // on a full-screen item costs a re-raster where a `y` costs nothing.
      y: parent.height * (1 - root.progress)
      color: root.surface

      // Rounded at the top only -- the edge it comes in from. The bottom
      // corners sit against the home pill and are never seen.
      radius: root.radiusSheet

      Keys.onEscapePressed: root.dismiss()

      // The radius rounds all four corners, so square the bottom two back off
      // rather than leave two notches over the gesture strip.
      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: root.radiusSheet
        color: root.surface
      }

      // H1, for a drag that starts on empty sheet rather than on an icon.
      // Declared before the handle and the column so it sits *under* them:
      // later siblings take input first, so this only ever sees touches
      // nothing else claimed.
      MouseArea {
        // no press state (style.md H7): a drag catcher under the content, not
        // a control.
        anchors.fill: parent
        onPressed: mouse => root.sheetPress(this, mouse)
        onPositionChanged: mouse => root.sheetMove(this, mouse)
        onReleased: root.sheetRelease()
        onCanceled: root.sheetCancel()
      }

      // Pull the sheet down to close it, by the handle across its top.
      //
      // This started as a DragHandler covering the whole sheet, so a downward
      // drag anywhere would close it the way Android does. Measured, that
      // delivers **one** translation event for an entire gesture here: the app
      // delegates' MouseAreas hold the exclusive grab and the handler only
      // ever gets a passive one, so the sheet jumped rather than followed.
      // (It also has to be `onTranslationChanged`, not
      // `onActiveTranslationChanged` -- DragHandler's activeTranslation and
      // persistentTranslation share one NOTIFY signal, and the handler is
      // named after the signal. Spelled the other way it silently never runs.)
      //
      // The grid cannot supply the gesture either: with the apps this phone
      // has, contentHeight measures 516 against a 598 view, so the Flickable
      // never drags and never overscrolls.
      //
      // A MultiPointTouchArea on a strip of its own has neither problem, and
      // it is what the gestures plugin and the shade already use: the surface
      // it covers *is* its input region, Wayland's implicit grab keeps the
      // whole gesture on it however far the finger travels, and it cannot
      // compete with a tap on an app icon because it does not overlap one.
      // The visible bar is the affordance a Material bottom sheet uses.
      Item {
        id: handleStrip
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(26)

        property real dragStartY: 0

        Rectangle {
          anchors.centerIn: parent
          width: Style.space(36)
          height: Math.max(2, Style.space(4))
          radius: height / 2
          color: Util.alpha(root.textOnSurface, root.dragging ? 0.8 : 0.3)
          Behavior on color { ColorAnimation { duration: 140 } }
        }

        MultiPointTouchArea {
          anchors.fill: parent
          maximumTouchPoints: 1

          onPressed: pts => {
            if (pts.length === 0) return
            handleStrip.dragStartY = pts[0].sceneY
            root.dragging = true
          }

          onUpdated: pts => {
            if (pts.length === 0 || !root.dragging) return
            var dy = pts[0].sceneY - handleStrip.dragStartY
            root.progress = Math.max(0, Math.min(1, 1 - dy / root.closeTravel))
          }

          onReleased: pts => {
            if (!root.dragging) return
            root.dragging = false
            if (root.progress <= root.closeCommit) root.dismiss()
            else root.progress = 1
          }

          // A stranded touch must not leave the drawer parked half-open. The
          // -1 marks the trace so a failed drag says *which* way it ended:
          // a cancel and a short drag both leave the drawer open, and they
          // want opposite fixes.
          onCanceled: pts => {
            if (!root.dragging) return
            var marked = root.dragTrace.slice()
            marked.push(-1)
            root.dragTrace = marked
            root.dragging = false
            root.progress = 1
          }
        }
      }


      Column {
        anchors.top: handleStrip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        anchors.bottomMargin: Style.space(10)
        spacing: Style.space(10)

        // -------------------------------------------------------- search
        // A pill, because that is what a phone search field looks like and
        // because a fully rounded target is easier to hit than a rectangle of
        // the same area. The desktop Ui.TextField underneath keeps its focus
        // and IME behaviour -- only its chrome is replaced, by turning its own
        // background off and drawing this one behind it.
        Rectangle {
          id: searchPill
          width: parent.width
          height: Style.space(46)
          radius: height / 2
          color: root.container

          Text {
            id: searchGlyph
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍉"
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
            color: root.subdued
          }

          // Fills the pill, and the insets are padding rather than anchor
          // margins (docs/style.md F1-F3). Both halves of that matter.
          //
          // A Ui.TextField with verticalPadding 0 and no background is exactly
          // one line of Style.font.body tall -- 16-22px of a 46px pill -- and
          // anchoring it by verticalCenter left that as its whole height. The
          // anchor margins then put the rest of the pill outside the control
          // too, so the magnifier and both lead-ins were chrome with nothing
          // under them. Roughly a third of what is drawn here answered a tap.
          //
          // Padding draws identically to the margins it replaces and is
          // *inside* the hit area, so nothing moves on screen (F2).
          //
          // Pinned rather than left to `horizontalPadding`, which the base type
          // adds to `Border.left(spec)` -- and that spec is `focus` or `normal`,
          // so on a theme whose two border widths differ the text used to jump
          // sideways the instant the field was tapped (F5). Vertical is safe as
          // it stands: top and bottom move together, so the centre holds.
          Ui.TextField {
            id: searchField
            anchors.fill: parent
            leftPadding: searchGlyph.x + searchGlyph.width + Style.space(10)
            rightPadding: Style.space(16)
            // The control is taller than its line now, so it has to be told
            // where that line goes. Left at the default the text renders
            // against the top of the pill.
            verticalAlignment: TextInput.AlignVCenter
            placeholderText: "Search apps and settings"
            background: null
            verticalPadding: 0
            onTextChanged: queryDebounce.restart()
          }
        }

        // --------------------------------------------------------- grid
        GridView {
          id: grid
          width: parent.width
          // Only as tall as it needs to be. Stretched to fill, the view covers
          // the empty sheet below the last row and swallows a drag that starts
          // there -- a Flickable takes the press whether or not it has anything
          // to show at that point. Capped, the sheet's own drag area (H1) gets
          // those touches, and when there are more apps than fit this is the
          // full height again and it scrolls exactly as before.
          // + bottomMargin, or the cap defeats it: with the margin
          // outside the cap a grid whose apps fit becomes scrollable by exactly
          // the margin, which makes it interactive where it was not and lets it
          // swallow the close-drag (H1) the cap exists to protect.
          //
          // Minus whatever the settings section below is taking. Without that
          // term the grid still measures itself against the whole sheet and the
          // section is drawn off the bottom of it -- and it is the section, not
          // the grid, that is under the thumb when a query is showing.
          // Gated on `visible`, both terms. A Column leaves an invisible child
          // out of its layout but the child still reports a height -- the
          // caption and its padding, here -- so reading it unguarded would take
          // ~30px off the grid on every screen that has no query at all.
          height: Math.min(parent.height - y
                           - (settingsSection.visible
                              ? settingsSection.height + parent.spacing : 0),
                           contentHeight + bottomMargin)
          // Scroll padding, so the last row comes to rest a strip clear of the
          // home pill now that the sheet runs under it (I4). Rows may pass
          // beneath the pill mid-scroll; none may stop there.
          //
          // It belongs to whatever is last, and with a query up that is the
          // settings section. Kept on both and the gap is paid twice: the grid
          // would reserve a strip in the middle of the sheet, above rows that
          // are not near the pill at all.
          bottomMargin: settingsSection.visible ? 0 : root.gestureStrip
          clip: true
          cellWidth: Math.floor(width / root.columns)
          cellHeight: Style.space(86)
          model: root.appRows
          boundsBehavior: Flickable.StopAtBounds
          // A Flickable whose content fits its view does not drag at all, and
          // with the apps this phone has it does fit -- measured at
          // contentHeight 516 against a 598 view. Leaving it "interactive"
          // there means it silently swallows vertical drags that could have
          // meant something. Say so explicitly instead, and let the close
          // gesture below have them.
          interactive: contentHeight > height
          // Virtualised on purpose. With every entry instantiated, 50-odd
          // delegates each holding a decoded icon is real memory on a phone
          // that has 900MB to play with.
          cacheBuffer: cellHeight * 2

          delegate: Item {
            required property var modelData
            // sortedEntries returns wrappers -- {entry, score, key, name} --
            // not entries. Reading `.icon` straight off the row yields
            // undefined and a grid of blank squares with no error anywhere.
            readonly property var entry: modelData.entry

            width: grid.cellWidth
            height: grid.cellHeight

            // The cell has never had chrome -- it is an icon and a label on
            // the bare sheet -- so the veil is the chrome (docs/style.md H8),
            // drawn at the size a cell looks rather than at the 90x86 the
            // delegate spans. The 3px inset keeps two neighbours from touching.
            PressVeil {
              anchors.fill: parent
              anchors.margins: Style.space(3)
              radius: root.radiusTile
              on: cellArea.pressed && !root.sheetDragging
            }

            Column {
              anchors.centerIn: parent
              width: parent.width - Style.space(6)
              spacing: Style.space(4)

              Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.iconSize
                height: root.iconSize
                // Without sourceSize an SVG rasterises at its natural size --
                // 512px squares held for every visible app.
                sourceSize: Qt.size(root.iconSize, root.iconSize)
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectFit
                source: root.shell && root.shell.appLibrary
                  ? root.shell.appLibrary.iconSource(entry ? entry.icon : "")
                  : ""
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.shell && root.shell.appLibrary
                  ? root.shell.appLibrary.entryName(entry) : ""
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: root.textOnSurface
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
              }
            }

            // H1, H4. The drag has to live here rather than on a area behind
            // the grid, because this MouseArea holds the exclusive grab for
            // the whole gesture -- the same reason a sheet-wide DragHandler
            // got exactly one event. So it does both jobs: a touch that never
            // travels is a launch, one that goes down past the slop drags the
            // sheet.
            MouseArea {
              id: cellArea
              anchors.fill: parent
              onPressed: mouse => root.sheetPress(this, mouse)
              onPositionChanged: mouse => root.sheetMove(this, mouse)
              onReleased: root.sheetRelease()
              onCanceled: root.sheetCancel()
              onClicked: if (!root.sheetWasDrag) root.launch(entry)
            }
          }
        }

        // ---------------------------------------------- settings results (O)
        //
        // A list and not more grid cells, for two reasons that both come down
        // to what a cell can hold. A settings row needs to say where it lives
        // -- "Wi-Fi" under System is a different thing from "Wi-Fi networks"
        // under Network & internet, and the section name is the only thing that
        // tells them apart -- and a 90px cell has no room for a second line
        // under a label that already wraps to two. The other reason is that a
        // glyph in a grid of app icons reads as an app.
        //
        // Not in `appRows` either, and that is not a layout decision: that
        // property feeds `drawer entries` and `drawer launch`, which
        // moarchy-store calls and the selftest asserts (L9). A settings row in
        // there would be an id the store could be handed and would try to
        // gtk-launch.
        Column {
          id: settingsSection
          width: parent.width
          spacing: Style.space(4)
          visible: root.settingsRows.length > 0
          // Belongs to whatever is last on the sheet (I4); see the grid above.
          bottomPadding: root.gestureStrip

          Text {
            leftPadding: Style.space(6)
            topPadding: Style.space(6)
            bottomPadding: Style.space(2)
            text: "SETTINGS"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: root.textWeight
            // Wide enough to read as a divider rather than as a row with a very
            // short label. Through Style.space like every other length, so it
            // tracks the theme's scale (docs/style.md A2).
            font.letterSpacing: Style.space(1)
            color: root.subdued
          }

          Repeater {
            model: root.settingsRows

            delegate: Item {
              id: resultRow
              required property var modelData

              width: settingsSection.width
              // The height a Settings row is (docs/style.md I), because this is
              // one -- read here, tapped there, and a person should not be able
              // to tell which list they are looking at by its rhythm.
              height: Style.space(58)

              // Like the app cells above: the row has no chrome of its own, so
              // the veil is the chrome (H8). Guarded on `sheetDragging`, because
              // this MouseArea is also the sheet's drag handle and `pressed`
              // stays true for the whole gesture -- unguarded, a thumb dragging
              // the sheet shut lights every row it passes over (H6).
              PressVeil {
                anchors.fill: parent
                radius: root.radiusCard
                on: resultArea.pressed && !root.sheetDragging
              }

              // Through Ui.OpticalGlyph and in a slot, exactly as the same row
              // is drawn in moarchy.settings: a glyph centred in a box is
              // centred on its *painted* bounds, not on the em square, and a
              // plain Text sits visibly high in a slot (docs/style.md B5, E5).
              // The slot is derived from the glyph, never fixed.
              Ui.OpticalGlyph {
                id: resultGlyph
                // Drawn only when there is one, but the slot is kept either
                // way: five heterogeneous rows with a ragged left edge read as
                // five lists, and an invisible Item still holds its anchors.
                visible: text !== ""
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                width: root.glyphSlot
                height: root.glyphSlot
                text: resultRow.modelData.glyph
                fontFamily: Style.font.family
                fontSize: Style.font.iconLarge
                color: root.textOnSurface
              }

              Text {
                id: resultSection
                anchors.right: parent.right
                anchors.rightMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                text: resultRow.modelData.section
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: root.subdued
                elide: Text.ElideRight
                // Never more than its share: the label is what was searched
                // for and the section is where it happens to live.
                width: Math.min(implicitWidth, parent.width * 0.35)
                horizontalAlignment: Text.AlignRight
              }

              Text {
                anchors.left: resultGlyph.right
                anchors.leftMargin: Style.space(14)
                anchors.right: resultSection.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: resultRow.modelData.label
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: root.textWeight
                color: root.textOnSurface
                elide: Text.ElideRight
              }

              // The same four handlers the app cells carry, for the same
              // reason: this MouseArea holds the exclusive grab for the whole
              // gesture, so a downward drag that starts on a settings row can
              // only close the sheet (H1) if it is this area that drags it.
              MouseArea {
                id: resultArea
                anchors.fill: parent
                onPressed: mouse => root.sheetPress(this, mouse)
                onPositionChanged: mouse => root.sheetMove(this, mouse)
                onReleased: root.sheetRelease()
                onCanceled: root.sheetCancel()
                onClicked: if (!root.sheetWasDrag) root.activateSetting(resultRow.modelData)
              }
            }
          }
        }
      }
    }

    // Somewhere for active focus to go when the drawer closes (I5c). It has to
    // be a real item *inside this window*, and for a long time it was not: it
    // sat out at plugin root, a child of an Item that belongs to no window at
    // all. An item with no window cannot be given active focus, so
    // `focusSink.forceActiveFocus()` in close() set a flag on an orphan and
    // took nothing away from the search field, which kept its `focus` across
    // the unmap and had it handed straight back the moment sway re-activated
    // the surface on the next open.
    //
    // Two symptoms, one fault. The one that was noticed first is that the
    // keyboard stops rising: a tap on a field Qt already considers focused
    // changes no focus and so re-enables no text input. The one that is worse
    // is the margin above -- gated on `searchField.activeFocus`, it dropped the
    // bottom inset on every open, so the drawer drew its first frame under the
    // strip and then shrank off it, leaving wallpaper in the band under the
    // pill for as long as it was up.
    //
    // Zero-sized and declared last, which costs nothing: it takes no input and
    // draws nothing, and the sheet's own drag areas are unaffected by a sibling
    // with no area.
    Item { id: focusSink }
  }


  // I5d, second half. The keyboard is raised *by* the unmap -- sway re-activates
  // the window this surface was covering and its text input re-enters -- so a
  // SetVisible sent from close() is answering a question that has not been
  // asked yet, and the handback undoes it.
  //
  // Measured with the close()-time call alone: the theme picker passed 0 of 6
  // and the drawer and Settings failed 6 of 6, on identical code. The variable
  // is how much runs between the call and the surface actually going away --
  // the drawer animates its progress to 0 over 200ms and the busctl lands well
  // inside that window.
  //
  // So it is repeated once the surface is down. Both are kept and they do
  // different jobs: the early one takes the keyboard away as the sheet leaves,
  // which is what stops it flashing, and this one is the only one guaranteed to
  // be after the handback.
  Timer {
    id: keyboardRetreat
    interval: 250
    onTriggered: root.hideKeyboard()
  }

  // Typing on a phone keyboard is slow enough that per-keystroke re-sorting of
  // every desktop entry is affordable, but the icon churn behind it is not.
  Timer {
    id: queryDebounce
    interval: 120
    onTriggered: root.query = searchField.text
  }
}
