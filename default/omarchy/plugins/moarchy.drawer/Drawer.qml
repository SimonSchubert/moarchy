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
import "../moarchy.common/ShellApps.js" as ShellApps
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

  // A4. How close the finger is to the home stop, 0..1, written by the
  // gestures plugin once the sheet is fully up -- and only for a drag from the
  // strip, because a drag on the home screen has no home to go to.
  //
  // The sheet keeps travelling with it. That is the carousel's cue, inherited
  // along with the gesture it was attached to: past the first stop the rest of
  // the drag has to mean something, and a sheet that stands still for the last
  // third of it says the finger is doing nothing. A translation and not an
  // `opacity`, for the reason the sheet's own note gives -- a subtree alpha
  // makes this GPU composite the whole thing off-screen first, and this
  // subtree is the screen.
  //
  // Retired on the same terms as `progress`, and for the same reason the
  // carousel's was: zeroed instantly while the sheet is still animating out,
  // it drops 80px on the way down, which reads as the drawer flinching.
  property real homeHint: 0

  Behavior on homeHint {
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
  // Not `drawerWindow.height`, and that is the whole of this note: a
  // layer-shell window that is not mapped reports Qt's default 100x100.
  // Measured on the device -- `drawer geometry` answers `w=100 h=100` with the
  // drawer down and `w=360 h=694` with it up -- and the drag that *opens* this
  // sheet necessarily starts while it is down. Dividing a drag by 100 moves the
  // sheet seven times finger speed until the surface maps, which is a jump on
  // the first frames and then a visible retreat as the divisor corrects.
  //
  // So: the screen until this window has been up once, its own height ever
  // after. The two differ by the bar's exclusive zone -- 26px of 720 here -- so
  // the first drag of a session is 3.6% off 1:1 and every one after it is
  // exact. The alternative, hard-coding the screen, is wrong by that much
  // forever and silently wrong on a device with a different bar.
  property real sheetHeight: 0

  readonly property real closeTravel: Math.max(1,
    root.sheetHeight > 0 ? root.sheetHeight
                         : (drawerWindow.screen ? drawerWindow.screen.height : 720))
  readonly property real closeCommit: 0.7

  // H1. Travel past which a touch on the sheet stops being a tap and starts
  // dragging the sheet shut.
  readonly property int dragSlop: Style.space(10)

  readonly property real sheetFling: 0.6

  // H1, on the shared tracker (docs/refactor.md F1). Downward closes, so
  // `openDirection` is -1: travelling up is what would raise progress, and
  // this sheet is already up.
  //
  // Scene coordinates are the tracker's whole input convention, and the reason
  // is this surface's: every input item here is a child of the sheet, so its
  // frame moves as the sheet does and a delta measured in it feeds back into
  // itself.
  Shared.DragTracker {
    id: sheetDrag
    travel: root.closeTravel
    openDirection: -1
    latchAxis: "down"
    slop: root.dragSlop
    startFrom: root.progress

    onBegan: root.dragging = true
    onMoved: p => root.progress = p

    // H3, and the numbers stay here (F3). A short, fast flick means the same
    // as a long slow drag: a drag beginning near the far end of the sheet
    // cannot reach the commit threshold at all, because there is not enough
    // sheet left to travel.
    onFinished: (p, v) => {
      root.dragging = false
      if (v >= root.sheetFling) root.dismiss()
      else if (v <= -root.sheetFling) root.progress = 1
      else if (p <= root.closeCommit) root.dismiss()
      else root.progress = 1
    }

    onStranded: root.markTrace(-2)
    onCanceled: from => {
      root.dragging = false
      root.progress = from
    }
  }

  // The names the controls on this sheet already read. `sheetPressX` and
  // `sheetPressY` are the hold's (L3) and the shelf tile's: a long press has
  // to be cancelled by travel in *any* direction, because a finger that has
  // gone 40px sideways has plainly stopped meaning "tell me about this one",
  // and the sheet's own gesture is one axis and has never needed x.
  readonly property bool sheetDragging: sheetDrag.latched
  readonly property bool sheetWasDrag: sheetDrag.wasDrag
  readonly property real sheetPressX: sheetDrag.startX
  readonly property real sheetPressY: sheetDrag.startY

  function sheetPress(item, mouse): void {
    var p = item.mapToItem(null, mouse.x, mouse.y)
    // L2. Cleared here rather than on release, for the reason `wasDrag` is:
    // Qt delivers `released` and then `clicked`, so a flag cleared in the
    // release handler is already false when the click arrives -- and the app
    // whose card is on screen is the app that launches behind it.
    root.holdFired = false
    sheetDrag.press(p.x, p.y)
  }

  function sheetMove(item, mouse): void {
    var p = item.mapToItem(null, mouse.x, mouse.y)
    sheetDrag.move(p.x, p.y)
  }

  function sheetRelease(): void { sheetDrag.release() }
  function sheetCancel(): void { sheetDrag.cancel() }

  // ------------------------------------------------------- the hold (L1-L4)
  //
  // The same MouseArea that launches an app and drags the sheet also has to
  // answer a long press, and it has to do that without taking anything from
  // either. It cannot be a TapHandler alongside: that handler would only ever
  // get a passive grab -- the delegate's MouseArea holds the exclusive one, the
  // same fact the sheet-wide DragHandler note above is about -- so the press it
  // saw would end wherever the MouseArea decided the gesture was over.
  //
  // A timer armed on `pressed` and cancelled by everything that means "this was
  // not a hold" has no grab of its own to lose.
  readonly property int holdDelay: 500

  // The cell under the finger, or null. Held rather than passed to the timer,
  // because a Timer has no payload and a second finger on a second cell must
  // not be able to open the first one's card.
  property var holdEntry: null

  // L2. True from the moment the card opens until the next press, so the click
  // Qt delivers after the finger lifts does not also launch the app.
  property bool holdFired: false

  function armHold(entry): void {
    root.holdEntry = entry || null
    if (root.holdEntry) holdTimer.restart()
  }

  function cancelHold(): void {
    holdTimer.stop()
    root.holdEntry = null
  }

  // L3, L4. Travel cancels the hold, in either direction and on either axis.
  //
  // sheetMove cannot do this job: it latches only on *downward* travel past the
  // slop, deliberately (H5), so an upward drag on a grid that fits its view --
  // which is what this phone's app count gives -- moves nothing, latches
  // nothing, and would leave the timer running under a finger that has already
  // travelled half the sheet. A scroll on a grid that does not fit cancels
  // through onCanceled instead, when the Flickable steals the grab.
  function holdMove(item, mouse): void {
    if (!holdTimer.running) return
    var p = item.mapToItem(null, mouse.x, mouse.y)
    if (Math.abs(p.y - root.sheetPressY) > root.dragSlop
        || Math.abs(p.x - root.sheetPressX) > root.dragSlop)
      root.cancelHold()
  }

  Timer {
    id: holdTimer
    interval: root.holdDelay
    onTriggered: {
      if (!root.holdEntry) return
      root.holdFired = true
      root.openDetail(root.holdEntry)
      root.holdEntry = null
    }
  }

  // Diagnostic only, and cheap enough to leave in: one integer appended per
  // frame while a drag is in flight, cleared when the next one starts.
  property var dragTrace: []

  // F4. What the *release* left behind, as `progress:homeHint` pairs. The
  // retire is 200ms and one IPC round trip is ~300ms, so the decay cannot be
  // watched from outside -- the same wall dragTrace exists to get around, one
  // gesture later. A homeHint that snapped leaves a step here (57 then 0 while
  // progress is still 100); one that retires leaves a ramp.
  //
  // Inherited from the carousel along with `homeHint` itself, and it is the
  // reason both came over together: the bug F4 records is not about carousels,
  // it is about two numbers that drive one animation retiring on different
  // terms, and this sheet now has exactly that pair.
  property var retireTrace: []

  function noteRetire(): void {
    if (root.dragging) return
    if (root.progress <= 0 && root.homeHint <= 0) return
    var next = root.retireTrace.slice()
    if (next.length < 200)
      next.push(Math.round(root.progress * 100) + ":" + Math.round(root.homeHint * 100))
    root.retireTrace = next
  }

  onHomeHintChanged: root.noteRetire()

  onDraggingChanged: if (root.dragging) { root.dragTrace = []; root.retireTrace = [] }
  onProgressChanged: {
    root.noteRetire()
    if (!root.dragging) return
    var next = root.dragTrace.slice()
    if (next.length < 200) next.push(Math.round(root.progress * 100))
    root.dragTrace = next
  }

  // A failed drag says *which* way it ended: a cancel and a stranded touch both
  // leave the drawer where the finger did, and they want opposite fixes.
  function markTrace(marker): void {
    var next = root.dragTrace.slice()
    next.push(marker)
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

  // The search field's clear button. Derived, never a flat 44 (E5): on a theme
  // with a larger base font the glyph is already over the floor, and a fixed 44
  // would shrink its target back down to meet the glyph instead of clearing it.
  // Capped at the pill, because a slot taller than the 46 it sits in would
  // stick out of both ends of the chrome it has none of.
  readonly property int clearSlot:
    Math.min(Style.space(46), Math.max(Style.space(44), root.glyphSlot))

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
  // The fifth of C2's six roles, and the drawer had never needed one: at rest
  // this screen is a search pill and bare icons, and a second tone with nothing
  // to distinguish from would be a colour nobody chose. The detail card is what
  // gave it something -- the card is `container`, and Remove has to read as a
  // control sitting on it rather than as more card (style.md C2, and the
  // Bluetooth sheet's Forget for the precedent that a destructive button here is
  // a tone up, not a red).
  readonly property color containerHigh: Util.alpha(Color.menu.text, 0.14)
  readonly property color subduedBase: Theme.mix(
    Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 1), Color.menu.text, 0.08)

  // The detail card's fill, and it has to be this rather than `container`.
  //
  // `container` is an 8% wash, which is 8% of whatever is behind it -- and
  // behind this card is a grid of saturated app icons rather than a page of
  // text. Measured on glass: Foliate's and Geary's labels read straight through
  // the Uninstall button, over the word Uninstall.
  //
  // This is the colour `container` resolves TO over a solid surface, with the
  // transparency taken out, which is the same number subduedBase already had to
  // compute for the contrast maths (C3). One computation named twice, rather
  // than two that have to agree -- and it is what makes H2's press arithmetic
  // true here, since a 12% veil over a 14% fill assumes the 14% is over
  // something solid.
  readonly property color cardFill: root.subduedBase
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

  // Whether this shell has paid for one icon rescan yet -- see open().
  property bool iconsRefreshed: false

  Connections {
    target: root.shell ? root.shell.appLibrary : null
    function onAppsChanged() { root.appsRevision++; root.buildIndex() }
  }

  onShellChanged: { root.buildIndex(); root.rebuildMru() }
  Component.onCompleted: { root.buildIndex(); root.rebuildMru() }

  // ----------------------------------------------------- M. open apps (M1-M11)
  //
  // The shelf at the top of the sheet, and the one thing on this surface that
  // does not come out of `appLibrary`: a window is not an entry.
  //
  // It used to be asked of moarchy.recents, which owned the only
  // ToplevelManager walk in the shell. The carousel is gone (M0) and its model
  // came here rather than to a shared component, because there is exactly one
  // consumer left: a component shared by one plugin is indirection with a
  // manifest. What it kept from the carousel is every line of reasoning below
  // -- the MRU rule, the appId index and its suffix fallback, the shell-app
  // branch -- because none of that was about being a carousel.
  //
  // zwlr-foreign-toplevel-management-v1, which Sway implements, gives the
  // appId, the title, which window is active, a closed() signal, and the only
  // two verbs a tile needs: close(), and enough identity to focus by. No fork,
  // no `swaymsg -t get_tree` walk, no polling.

  // Most-recently-used first, which is the order a thumb expects: the app you
  // just left is the leftmost tile. ToplevelManager hands windows over in
  // creation order, so the ordering is kept here.
  property var mru: []

  function indexOfToplevel(list, tl) {
    for (var i = 0; i < list.length; i++) if (list[i] === tl) return i
    return -1
  }

  // Everything the shelf can show: the compositor's windows, which since K1
  // includes this shell's own screens -- Settings, Wi-Fi and Bluetooth are
  // windows and arrive here like `foot` does, with no branch of their own.
  function liveApps() {
    var windows = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    var out = []
    for (var i = 0; i < windows.length; i++) out.push(windows[i])
    return out
  }

  // Rebuilt rather than mutated, because a `var` holding an array only
  // notifies on assignment -- pushing into it in place updates nothing.
  function rebuildMru(): void {
    var live = root.liveApps()
    var next = []

    // Anything already ranked keeps its rank, as long as it still exists.
    for (var i = 0; i < root.mru.length; i++)
      if (root.indexOfToplevel(live, root.mru[i]) >= 0) next.push(root.mru[i])

    // New windows go to the front: a window that just mapped is the most
    // recent thing there is.
    for (var j = 0; j < live.length; j++)
      if (root.indexOfToplevel(next, live[j]) < 0) next.unshift(live[j])

    // And the active one leads, so the first tile is the app the swipe came
    // out of. activeToplevel reads null here even with a window focused -- the
    // same reason the back gesture had to stop trusting it -- so fall back to
    // the per-toplevel `activated` flag, which does track focus.
    var active = ToplevelManager.activeToplevel
    if (!active)
      for (var k = 0; k < live.length; k++)
        if (live[k] && live[k].activated) { active = live[k]; break }
    if (active) {
      var at = root.indexOfToplevel(next, active)
      if (at > 0) { next.splice(at, 1); next.unshift(active) }
    }
    root.mru = next
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.rebuildMru() }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.rebuildMru() }
  }

  // M10. Windows this opening of the drawer has asked to close. `close()` is a
  // request and not a kill -- an editor with unsaved work answers it with a
  // dialog and keeps its window -- so a tile that waited for the toplevel to
  // actually go would hang in the air for as long as the app took to decide,
  // or spring back under a finger that had already thrown it away. It goes at
  // once, and this is what keeps it gone. Cleared by open(), so an app that
  // refused to quit is running and has its tile back.
  property var closingApps: []

  readonly property var openApps: {
    var live = root.mru || []
    var out = []
    for (var i = 0; i < live.length; i++)
      if (root.closingApps.indexOf(live[i]) < 0) out.push(live[i])
    return out
  }

  // ---------------------------------------------- appId -> desktop entry
  //
  // `appLibrary` can sort entries and turn an icon name into a source, but it
  // has no lookup by id. Build the index once and rebuild it when the app list
  // moves -- scanning sortedEntries() inside a delegate would be O(apps) per
  // tile per frame.
  //
  // Separate from `appRows` on purpose: that one is the *query's* answer and
  // re-sorts on every keystroke, and a tile's icon must not depend on what is
  // in the search field.
  property var appIdIndex: ({})

  function buildIndex(): void {
    var map = ({})
    if (!root.shell || !root.shell.appLibrary) { root.appIdIndex = map; return }
    var rows = root.shell.appLibrary.sortedEntries("")
    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i].entry
      if (!entry) continue
      var id = String(entry.id || "").toLowerCase().replace(/\.desktop$/, "")
      if (!id) continue
      if (map[id] === undefined) map[id] = entry
      // Sway reports the app_id an app sets for itself, which is often the last
      // segment of a reverse-DNS desktop id -- org.gnome.Papers maps to an
      // app_id of "papers". Index both; first writer wins, so an exact match is
      // never displaced by a suffix collision.
      var tail = id.split(".").pop()
      if (tail && map[tail] === undefined) map[tail] = entry

      // A shell app's window carries the shell process's own app id (K9), so
      // nothing above can ever find its entry. The entry names the plugin in
      // its Exec line -- `omarchy-shell shell toggle <id>` -- and that is the
      // only place the two are joined: Quickshell's DesktopEntry exposes name,
      // icon, categories and exec, and no way to read an X- key, so the
      // X-Moarchy-Plugin these entries also carry is unreachable from here.
      //
      // Kept under a prefix so a plugin id can never be returned for an app_id
      // that happens to spell the same thing.
      var toggled = root.pluginSummonedBy(entry)
      if (toggled) {
        var key = "plugin:" + toggled[1].toLowerCase()
        if (map[key] === undefined) map[key] = entry
      }
    }
    root.appIdIndex = map
  }

  // The plugin id an entry summons, as a one-element match, or null for an
  // entry that starts a process. Written once: buildIndex keys the shelf's
  // icons off it (K5) and launch() asks it whether a window is coming (L10).
  function pluginSummonedBy(entry) {
    if (!entry) return null
    return /(?:^|\s)shell\s+toggle\s+(\S+)/.exec(String(entry.execString || ""))
  }

  function entryForAppId(appId) {
    if (!appId) return null
    var e = root.appIdIndex[String(appId).toLowerCase()]
    return e === undefined ? null : e
  }

  function entryForPluginId(pluginId) {
    if (!pluginId) return null
    var e = root.appIdIndex["plugin:" + String(pluginId).toLowerCase()]
    return e === undefined ? null : e
  }

  // K5, M4. A shell app names and draws itself: its app id is the shell
  // process's own (K9), so there is no desktop entry to look either up in. The
  // plugin that draws the window is asked instead, and asked by *handle* --
  // ShellApps.forToplevel compares the toplevel against each plugin's
  // appWindow.toplevel, which the window itself resolved once when it mapped.
  function shellAppFor(app) {
    return ShellApps.forToplevel(root.shell, app)
  }

  // K5, M4 again, for the icon. openNameFor has asked the plugin since K5 and
  // this did not, so a shell app resolved a name and never an artwork -- and
  // the app id it falls back on is `org.quickshell` for every one of them. It
  // went unseen while the only shell apps were Settings, Wi-Fi and Bluetooth,
  // which open from the shade and never take a tile on the shelf.
  function openIconFor(app) {
    if (!app || !root.shell || !root.shell.appLibrary) return ""
    var own = root.shellAppFor(app)
    var entry = own ? root.entryForPluginId(own.pluginId) : root.entryForAppId(app.appId)
    if (!entry) return ""
    return root.shell.appLibrary.iconSource(entry.icon)
  }

  function openNameFor(app) {
    if (!app) return ""
    var own = root.shellAppFor(app)
    if (own) return String(own.appWindow.appName || "")
    var entry = root.entryForAppId(app.appId)
    if (entry && root.shell && root.shell.appLibrary)
      return root.shell.appLibrary.entryName(entry)
    return app.appId || app.title || "Window"
  }

  // The page a shell app is on, which its own window already carries, and the
  // window title for anything else. A shell app's title is "<name> — <page>",
  // so reading it off the window rather than off the toplevel is what keeps a
  // line from repeating its own name. Only the IPC prints it: a tile is too
  // narrow for a second line (M4).
  function openTitleFor(app) {
    if (!app) return ""
    var own = root.shellAppFor(app)
    if (own) return String(own.appWindow.pageTitle || "")
    return String(app.title || "")
  }

  function openGlyphFor(app) {
    var own = root.shellAppFor(app)
    return own ? String(own.appWindow.glyph || "") : ""
  }

  // The tiles are a grid row: same icon, same column pitch, same label, one
  // dot (M4). The height is the grid's cell plus the dot and its gap, because
  // a tile carries one thing a cell does not and shortening the label to pay
  // for it would make the shelf's type smaller than the grid's -- which is the
  // second visual language M4 exists to avoid.
  readonly property int openDot: Math.max(4, Style.space(5))
  readonly property int openCellHeight: Style.space(86)

  // M6. Travel that a tile has to be flicked up before releasing closes its
  // app.
  readonly property int openDismissTravel: Style.space(40)

  // M5. A sway focus dispatch and not `activate()`: the foreign-toplevel
  // request does nothing on this compositor, for `foot` as much as for one of
  // this shell's own windows. The call is handed to moarchy.gestures, which is
  // where every other compositor call in this shell already lives.
  function focusOpen(app): void {
    if (!app) return
    ShellApps.focusToplevel(root.shell, app)
    root.dismiss()
  }

  // M6, M9. `close()` is xdg_toplevel.close -- a close *request*, so an editor
  // with unsaved work prompts rather than dies. That is what makes firing it
  // from a flick acceptable, and a shell app takes it like any other window:
  // Qt hides the window and the plugin's own onUnmapped resets its state (K6).
  //
  // Closing the last one leaves the drawer standing (M9). There is nowhere to
  // send it: this surface is not a switcher that empties, it is the launcher.
  function closeOpen(app): void {
    if (!app) return
    app.close()
    var next = root.closingApps.slice()
    next.push(app)
    root.closingApps = next
  }

  // --------------------------------------------------- settings results (O)
  //
  // Five, because the sheet has to stay an app grid with a tail rather than a
  // list with some icons on top. Beyond about five the section is taller than
  // the two rows of apps above it, and a query broad enough to return more than
  // five settings rows is a query that was going to be narrowed anyway.
  readonly property int settingsLimit: 5

  // The height a settings result is drawn at, named here because the fit
  // below has to do arithmetic with it and a number in two places is a number
  // that drifts.
  readonly property int settingsRowHeight: Style.space(58)

  // How many of them there is actually room for. `settingsLimit` is the
  // editorial answer and the comment above is still the reason for it; this is
  // the physical one, and with the on-screen keyboard up the two are very
  // different numbers.
  //
  // Without this the section took its natural height first and the grid was
  // left the remainder -- so typing one letter with the keyboard raised
  // collapsed the apps to a 12px strip of icons clipped through their tops,
  // with five timezone rows laid out in the space underneath. That is the
  // "list with some icons on top" the limit above exists to prevent; it just
  // could not see the keyboard coming.
  //
  // No binding loop: this reads sheetColumn.height and grid.y, and grid.y is
  // fixed by the search pill above the grid rather than by the height this
  // goes on to decide.
  readonly property int settingsFit: {
    if (!sheetColumn || !grid || !settingsCaption) return root.settingsLimit
    var below = sheetColumn.height - grid.y
    if (below <= 0) return root.settingsLimit
    // One full row of apps survives whenever the query matched any, so the
    // sheet cannot become a settings list wearing a search field.
    var keep = root.appRows.length > 0 ? grid.cellHeight : 0
    var room = below - keep - sheetColumn.spacing
               - settingsCaption.height - root.gestureStrip
    var per = root.settingsRowHeight + Style.space(4)
    return Math.max(0, Math.min(root.settingsLimit, Math.floor(room / per)))
  }

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
    var fit = root.settingsFit
    var out = []
    for (var i = 0; i < hits.length && out.length < fit; i++) {
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

  // -------------------------------------------------- the app detail card (L)
  //
  // Everything the card knows comes from `moarchy-app-remove`, which is where
  // the pacman reasoning lives (L11, L12). Nothing here decides what may be
  // removed; this file decides what the card looks like while the script is
  // deciding, and that separation is the point -- a rule about dependencies
  // written in QML is a rule nothing can run from a terminal to check.
  //
  // The entry itself, or null. One property rather than a bool and a payload:
  // "card up with no entry" is not a state this screen has, and two properties
  // that must agree are two properties that can stop agreeing.
  property var detailEntry: null

  //   info      what the app is
  //   plan      what removing it would take -- L7, never skipped
  //   working   the removal is running
  property string detailStage: "info"

  property var detailInfo: ({})
  property var detailPlan: ({})

  // True while a script is in flight. The card draws a line of its own rather
  // than an empty one: on an A53 the `info` fork lands in well under a second
  // and the `plan` fork is a pacman transaction, which does not.
  property bool detailBusy: false

  // An answer for a card that has since been closed, or opened on something
  // else, is not a late answer -- it is the wrong one. Same bargain the
  // settings guards strike above, for the same reason.
  //
  // Moved by openDetail and closeDetail ONLY. Arming a plan is not a new card
  // and must not invalidate one: `info` and `plan` are two forks about the same
  // entry, and a generation bumped on the tap would throw away an `info` still
  // in flight -- which on a busy phone is the card losing the line that says
  // what the app is, at the moment it is being asked about removing it.
  property int detailGeneration: 0

  function parseKv(text) {
    var out = ({})
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var t = lines[i].indexOf("\t")
      if (t <= 0) continue
      out[lines[i].slice(0, t)] = lines[i].slice(t + 1)
    }
    return out
  }

  // argv and not `bash -c`, so nothing here has to quote a desktop id. They
  // contain spaces on this phone -- "Disk Usage.desktop" is upstream's own --
  // and a quoting bug in a command whose verb is `remove` is not a bug worth
  // being one shell metacharacter away from.
  //
  // Non-login, deliberately: /usr/lib/moarchy/bin is already on the shell's
  // PATH (it comes from /etc/profile.d, through the session), and a login shell
  // sources profiles that touch ~/.local/share -- the directory the desktop
  // entry watcher is on. AppLibrary's own scans carry the same note.
  function detailRun(proc, verb, extra) {
    if (!root.detailEntry) return
    var argv = ["moarchy-app-remove", verb, String(root.detailEntry.id)]
    if (extra) argv.push(extra)
    root.detailBusy = true
    proc.wanted = root.detailGeneration
    if (proc.running) proc.running = false
    proc.command = argv
    proc.running = true
  }

  function openDetail(entry): void {
    if (!entry) return
    root.detailGeneration += 1
    root.detailEntry = entry
    root.detailStage = "info"
    root.detailInfo = ({})
    root.detailPlan = ({})
    root.detailRun(infoProc, "info", "")
  }

  // L7. Uninstall does not remove; it asks the question and shows the answer.
  function planRemoval(): void {
    root.detailStage = "plan"
    root.detailPlan = ({})
    root.detailRun(planProc, "plan", "")
  }

  function removeApp(): void {
    if (!root.detailEntry) return
    root.detailStage = "working"
    root.detailRun(removeProc, "remove",
                   root.shell && root.shell.appLibrary
                     ? String(root.shell.appLibrary.entryName(root.detailEntry)) : "")
  }

  function closeDetail(): void {
    root.detailGeneration += 1
    root.detailEntry = null
    root.detailStage = "info"
    root.detailInfo = ({})
    root.detailPlan = ({})
    root.detailBusy = false
  }

  // L8. What the plan settled: a package with a blocker has no Remove button at
  // all, rather than one that fails when pressed.
  readonly property string detailBlocked: String(root.detailPlan.blocked || "")

  // L8, from the other end: an answer that says nothing is not permission.
  //
  // The empty plan is a real state and not a hypothetical -- a phone whose
  // moarchy package predates bin/moarchy-app-remove runs a shell that has this
  // card and no script behind it, so the Process exits immediately, the
  // collector hands back "", and `blocked` is empty because nothing said
  // anything. Read as "not blocked" that draws a Remove button over a command
  // that does not exist, which is a control that silently does nothing -- the
  // exact failure docs/style.md E exists to prevent, arrived at from the
  // opposite direction.
  //
  // Every kind the script can report emits `count`, including the ones with no
  // package to count, so its absence means the script did not answer.
  readonly property bool detailPlanReady: String(root.detailPlan["count"] || "") !== ""

  // L6. Where the app came from, in one line. "No package" is an answer and a
  // blank line is not, so every kind the script can report has a phrase here --
  // including the one that means the script could not tell.
  //
  // Bracketed reads throughout: `package` is a future reserved word, and the
  // dotted form is legal in ES5 but not worth depending on in a file that is
  // parsed by whatever qmllint the next Qt ships.
  readonly property string detailOrigin: {
    var kind = String(root.detailInfo["kind"] || "")
    if (kind === "package") {
      var name = String(root.detailInfo["package"] || "")
      var version = String(root.detailInfo["version"] || "")
      return version ? name + " " + version : name
    }
    if (kind === "user") return "Personal entry"
    if (kind === "webapp") return "Web app"
    if (kind === "tui") return "Terminal app"
    if (kind === "flatpak") return "Flatpak"
    if (kind === "") return ""
    return "Unknown origin"
  }

  // L7. The count and the weight, in the card's words rather than pacman's.
  // A launcher that belongs to no package has no packages to count, so it says
  // what it does take instead -- the script's own `note`.
  readonly property string detailPlanSummary: {
    if (String(root.detailPlan["kind"] || "") !== "package")
      return String(root.detailPlan["note"] || "")
    var count = parseInt(String(root.detailPlan["count"] || "0"))
    if (!count) return ""
    var head = count === 1 ? "Removes 1 package" : "Removes " + count + " packages"
    var size = String(root.detailPlan["size"] || "")
    return size ? head + ", " + size : head
  }
  // Bracketed, not dotted: `protected` is a future reserved word, and a dotted
  // read of it is legal in ES5 but not in every parser this file passes through.
  readonly property bool detailProtected: String(root.detailInfo["protected"] || "") === "1"

  // G3. The card is a screen inside this surface, so back leaves it before it
  // leaves the drawer -- and from the plan it steps back to the detail rather
  // than out, because that is the step that was taken to get there. Returning
  // false is what tells the gestures plugin to close the whole overlay.
  function goBack(): bool {
    if (!root.detailEntry) return false
    // Mid-removal there is nothing to go back to and the pacman transaction
    // does not stop for a gesture. Consumed rather than obeyed.
    if (root.detailStage === "working") return true
    if (root.detailStage === "plan") { root.detailStage = "info"; return true }
    root.closeDetail()
    return true
  }

  Process {
    id: infoProc
    property int wanted: 0
    stdout: StdioCollector {
      onStreamFinished: {
        if (infoProc.wanted !== root.detailGeneration) return
        root.detailInfo = root.parseKv(String(text || ""))
        root.detailBusy = false
      }
    }
  }

  Process {
    id: planProc
    property int wanted: 0
    stdout: StdioCollector {
      onStreamFinished: {
        if (planProc.wanted !== root.detailGeneration) return
        root.detailPlan = root.parseKv(String(text || ""))
        root.detailBusy = false
      }
    }
  }

  Process {
    id: removeProc
    property int wanted: 0
    // L9. The outcome is a notification, sent by the script, so nothing here
    // has to stay on screen to report it -- which is what lets the card close
    // on exit rather than turning into a result screen nobody asked for. The
    // grid drops the app on its own (L10): removing a package takes its
    // .desktop file with it, DesktopEntries notices, and appsChanged() is
    // already wired to appRows.
    onExited: {
      if (removeProc.wanted !== root.detailGeneration) return
      root.closeDetail()
    }
  }

  function open(payloadJson) {
    // A sheet opening puts away every sheet on its own layer or above it, and
    // none of the ones below it (docs/refactor.md B6). This one is Top, so
    // that is the shade above it and the theme picker beside it -- not a
    // preference for one sheet at a time, which is why the shade keeps this
    // one standing (shade.md S28) while this keeps hiding the shade.
    //
    // Themes was missing and the omission was invisible: it is Top and
    // Exclusive like this surface, so which of the two drew on top was decided
    // by map order rather than by anything the specification says -- the same
    // fault G10b records for two Overlay surfaces contesting the corner.
    //
    // Asking the host rather than tracking it here means this still holds when
    // a sheet was raised by its own drag and this plugin never heard about it.
    if (root.shell && typeof root.shell.isPluginOpen === "function") {
      if (root.shell.isPluginOpen("moarchy.shade")) root.shell.hide("moarchy.shade")
      if (root.shell.isPluginOpen("moarchy.themes")) root.shell.hide("moarchy.themes")
    }

    root.query = ""
    searchField.text = ""

    // M10. A window that refused to close is still running, and this is where
    // it gets its tile back.
    //
    // Guarded, and the guard is not a micro-optimisation. `openApps` is a
    // binding over this, so an assignment notifies whether or not the value
    // changed; it re-evaluates to a fresh JS array, and the shelf's ListView
    // discards and rebuilds every delegate -- each one re-resolving an icon, a
    // glyph and a name. That landed on the frame the sheet arrives, which is
    // the frame the drawer looked slow on. Nothing was ever closed on most
    // opens, so most of those rebuilds produced the list that was already
    // there.
    if (root.closingApps.length > 0) root.closingApps = []

    // L5. The drawer opens on the grid, never on somebody's half-read card.
    root.closeDetail()
    // A hand-off that never reached an unmap must not silence the next real
    // close (I5d).
    root.handingOff = false
    // A4. A drag that armed home and was then abandoned must not leave the
    // next opening sitting 80px high.
    root.homeHint = 0
    // Belt to close()'s braces. close() is the path every dismissal takes and
    // is where releasing the field belongs, but the invariant the margin gate
    // rests on is "focused means the keyboard is up" -- so the open path
    // asserts it too rather than trusting that nothing ever opens this surface
    // from a state it did not close from.
    focusSink.forceActiveFocus()
    root.dragging = false
    root.progress = 1

    // Once per shell, not once per open.
    //
    // The scan behind refreshIcons() is two `find` passes over ~/.icons,
    // ~/.local/share/icons, every $XDG_DATA_DIRS/icons and /usr/share/pixmaps,
    // finishing by swapping `iconIndex` -- which by design re-evaluates every
    // `iconSource()` binding on screen. On every open, both of those landed on
    // the frame the sheet was settling onto, on a Mali-400.
    //
    // It was there because "a directory scan that never re-runs on its own",
    // and that stopped being true: AppLibrary watches DesktopEntries and
    // restarts a 750ms `iconIndexDebounce` on every change -- the same event
    // appsChanged arrives on. So an app installed while the shell is running
    // already gets its icon, and calling this from here only ran the scan a
    // second time.
    //
    // What upstream's own comment says the call is for is narrower and real:
    // the shell can start before a first-install package has finished placing
    // its icons, and nothing touches a .desktop file afterwards to notice it.
    // One scan on the first open covers that; every open after it was paying
    // again for an answer that had not moved.
    if (!root.iconsRefreshed && root.shell && root.shell.appLibrary) {
      root.iconsRefreshed = true
      Qt.callLater(function() { root.shell.appLibrary.refreshIcons() })
    }
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
    // The card goes with the surface. Left standing it would be the first thing
    // on screen the next time the drawer came up, about an app that may not be
    // installed any more.
    root.closeDetail()
    root.cancelHold()
    root.dragging = false
    root.progress = 0
    root.homeHint = 0
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

    // windows.md L10. Stand on the workspace the window will land on, before
    // starting it rather than after it maps.
    //
    // Focus already followed a new window: it lands on the focused workspace,
    // which has the app you launched from on it, so bin/moarchy-one-app-per-
    // workspace moves it to a free one and follows it there. What it cannot do
    // is act before the window exists, and on this hardware that is seconds of
    // gtk-launch spent looking at the app you were leaving with the splash
    // drawn over it.
    //
    // Before appLibrary.launch(), so the splash it starts is drawn over the
    // wallpaper of the workspace being arrived at. No race with the daemon
    // either: the window then maps alone on that workspace and on_new_window()
    // returns at its `if not others` guard without moving anything.
    //
    // Not for an entry that summons a plugin. Some of those draw a window and
    // some draw a layer surface (windows.md L5, and moarchy.device is one), and
    // a layer surface is visible from every workspace -- so moving would leave
    // you standing on an empty one when it was dismissed, having gone nowhere
    // and come back somewhere else.
    if (!root.pluginSummonedBy(entry)) ShellApps.goToFreeWorkspace(root.shell)

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

    // F4. The release, as `progress:homeHint` per frame. Read rather than
    // watched, for the reason dragTrace is.
    function retireTrace(): string { return root.retireTrace.join(" ") }

    // A4. Where the home stop stands right now, so a drag can be measured
    // mid-gesture as well as after it.
    function homeHint(): string {
      return Math.round(root.homeHint * 100) + (root.dragging ? " dragging" : "")
    }

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
           // The clear button, or where it would be. Reported as `none` rather
           // than as a zero-width rect at the pill's right edge, because a
           // check that taps a rect it was handed must not be handed one it
           // cannot tell from a real target (F6).
           + " clear=" + (clearButton.visible ? box(clearButton) : "none")
           // What is actually in the field, so a check can say the tap emptied
           // it rather than that something is no longer drawn.
           + " text=" + JSON.stringify(searchField.text)
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
           // What a drag on this sheet divides by (D2a). Unlike `h` it is
           // meaningful while the drawer is closed -- which is the state it
           // has to be right in, because that is where an opening drag starts.
           + " travel=" + Math.round(root.closeTravel)
           + " margin=" + drawerWindow.margins.bottom
           + " strip=" + root.gestureStrip
           + " gap=" + gap
           + " screen=" + (drawerWindow.screen
               ? drawerWindow.screen.width + "x" + drawerWindow.screen.height : "?")
           // refactor.md F8. Whether a touch is still open on either tracker.
           // It must read `idle` whenever no finger is down, and a control that
           // presses without ending is the only way it does not -- which is
           // invisible from every other instrument, because the sheet is
           // exactly where the finger left it either way. Published as one
           // word rather than two flags: what a check wants to know is whether
           // anything is outstanding.
           + " drag=" + (sheetDrag.latched || handleDrag.latched ? "latched"
                       : sheetDrag.active || handleDrag.active ? "active" : "idle")
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

    // ------------------------------------------------------ app detail (L)
    //
    // The card, without a finger. A hold can be driven for real --
    // `sudo moarchy-touch hold` over a cell is what L1 is checked with -- but
    // everything the card then says is text inside a QML item, and nothing
    // outside this process can read it. A `grim` capture cannot either: it can
    // show that *a* card is up and not which entry it is about, which is the
    // half that matters.
    //
    // One function for the whole state rather than one per field, because the
    // interesting assertions are about two things agreeing -- the stage and
    // what is in it.
    function detail(): string {
      if (!root.detailEntry) return ""
      var out = ["id\t" + String(root.detailEntry.id),
                 "stage\t" + root.detailStage,
                 "busy\t" + (root.detailBusy ? "1" : "0")]
      var k
      for (k in root.detailInfo) out.push("info." + k + "\t" + root.detailInfo[k])
      for (k in root.detailPlan) out.push("plan." + k + "\t" + root.detailPlan[k])
      return out.join("\n")
    }

    // Where a cell is, so L1's hold can be aimed rather than guessed at. Same
    // reason searchTarget exists: a coordinate computed from Style.space in a
    // shell script is a coordinate that is wrong the moment the theme's
    // spacing scale moves, and the grid's rows are 86 *scaled* px apart.
    //
    // Both frames are reported. `rect` is surface space, which is what
    // searchTarget answers in and what every other geometry function here
    // means; `global` is what mapToGlobal makes of it, which is what
    // moarchy-touch wants once doubled for the panel scale. They differ by the
    // bar, and reporting the pair is what lets a check say which one it used.
    function cellTarget(index: string): string {
      var i = parseInt(String(index || "0"))
      if (!grid || typeof grid.itemAtIndex !== "function") return "no grid"
      var item = grid.itemAtIndex(i)
      if (!item) return "no cell"
      var p = item.mapToItem(null, 0, 0)
      var g = item.mapToGlobal(0, 0)
      return "id=" + (item.entry ? String(item.entry.id) : "")
           + " rect=" + Math.round(p.x) + "," + Math.round(p.y)
           + " size=" + Math.round(item.width) + "x" + Math.round(item.height)
           + " global=" + Math.round(g.x) + "," + Math.round(g.y)
    }


    // ---------------------------------------------------- M. open apps
    //
    // One line per tile, in the format `recents list` prints -- same order,
    // same fields, a shell app named by its plugin id for the reason recorded
    // there (K9). M1 is then a diff of the two rather than two lists read side
    // by side, which is the only way to assert that this row *is* the
    // carousel's model and not a second one that happens to agree today.
    function openApps(): string {
      var out = []
      var live = root.openApps
      for (var i = 0; i < live.length; i++) {
        var app = live[i]
        if (!app) continue
        var own = ShellApps.forToplevel(root.shell, app)
        out.push((own ? own.pluginId : (app.appId || "?"))
                 + " " + root.openTitleFor(app))
      }
      return out.join("\n")
    }

    // Where a tile is, so the flick (M6) and the tap (M5) can be aimed rather
    // than guessed at -- the same two coordinate frames cellTarget reports,
    // and for the same reason.
    //
    // `no row` is what it answers while the shelf is not drawn, which is what
    // M2 and M9 are checked with. A word and not a coordinate, deliberately: a
    // check handed a rect it cannot tell from a real one is a check that taps
    // the search field and passes (style.md F6).
    function openTarget(index: string): string {
      // Through `headerItem` and its alias, because the shelf is the grid's
      // header now and an id declared inside a Component cannot be named from
      // out here. A collapsed header answers `no row` the same way a missing
      // one does: both mean there is nothing on screen to aim at.
      var section = grid ? grid.headerItem : null
      if (!section || !section.shown) return "no row"
      var openRow = section.row
      if (!openRow || typeof openRow.itemAtIndex !== "function") return "no row"
      var item = openRow.itemAtIndex(parseInt(String(index || "0")))
      if (!item) return "no tile"
      var app = item.modelData
      var own = app ? ShellApps.forToplevel(root.shell, app) : null
      var p = item.mapToItem(null, 0, 0)
      var g = item.mapToGlobal(0, 0)
      return "id=" + (own ? own.pluginId : (app && app.appId ? String(app.appId) : ""))
           + " rect=" + Math.round(p.x) + "," + Math.round(p.y)
           + " size=" + Math.round(item.width) + "x" + Math.round(item.height)
           + " global=" + Math.round(g.x) + "," + Math.round(g.y)
    }

    // Opens the card on an id, down the same function the hold timer calls.
    // Keyed the way `launch` is, and it misses for the same reason: callers
    // pass the bare id with no .desktop suffix.
    function hold(desktopId: string): string {
      var id = String(desktopId || "")
      if (!id) return "no id"
      if (!root.shell || !root.shell.appLibrary) return "no shell"
      var rows = root.shell.appLibrary.sortedEntries("") || []
      for (var i = 0; i < rows.length; i++) {
        var entry = rows[i] && rows[i].entry
        if (entry && String(entry.id) === id) { root.openDetail(entry); return "ok" }
      }
      return "no entry"
    }

    // Arms the plan, which is what Uninstall does. Asynchronous on purpose --
    // it is a pacman transaction on an A53 -- so a caller reads `detail` back
    // until `busy` is 0 rather than being handed an answer that was guessed at.
    function uninstall(): string {
      if (!root.detailEntry) return "no card"
      if (root.detailProtected) return "protected"
      root.planRemoval()
      return "ok"
    }

    // L8, as a yes/no. `pending` is not `no`: a check that treated "the plan
    // has not landed yet" as "cannot remove" would pass against a shell that
    // never answers, which is the one failure this is worth asserting against.
    function canRemove(): string {
      if (!root.detailEntry) return "no card"
      if (root.detailProtected) return "no"
      if (root.detailStage !== "plan") return "unasked"
      if (root.detailBusy) return "pending"
      if (!root.detailPlanReady) return "no"
      return root.detailBlocked === "" ? "yes" : "no"
    }

    // The Remove button. Named for what it does rather than `remove`, because
    // this one uninstalls a package and the noise of the name is the point --
    // the default selftest suite never calls it, and nothing should reach it by
    // completing a shorter word.
    function removeConfirm(): string {
      if (!root.detailEntry) return "no card"
      if (root.detailStage !== "plan") return "unasked"
      if (root.detailBlocked !== "") return "blocked"
      if (!root.detailPlanReady) return "no plan"
      root.removeApp()
      return "ok"
    }

    function detailClose(): string { root.closeDetail(); return "ok" }

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

    // The one place `sheetHeight` is written. Guarded on a number that could
    // only be the placeholder: 100 is what an unmapped layer surface reports,
    // and no phone this runs on has a 200px-tall sheet.
    onHeightChanged: if (drawerWindow.height > 200) root.sheetHeight = drawerWindow.height

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
      //
      // And keeps going, by up to 80px, as the finger approaches the home stop
      // (A4) -- the same cheap cue, on the same drag, that the carousel gave.
      y: parent.height * (1 - root.progress) - Style.space(80) * root.homeHint
      color: root.surface

      // Rounded at the top only -- the edge it comes in from. The bottom
      // corners sit against the home pill and are never seen.
      radius: root.radiusSheet

      // Through goBack() rather than straight to dismiss, so a keyboard walks
      // the same ladder the back gesture does (L5): the plan, then the card,
      // then the drawer. Escape closing the whole sheet from an open card would
      // be the one way out of this screen that skips a level.
      Keys.onEscapePressed: if (!root.goBack()) root.dismiss()

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
        // commits on distance alone where the sheet also takes a fling (A3).
        // One instance would have to pick, and picking is a behaviour change
        // this refactor may not make (refactor.md G4).
        //
        // `latchOnPress`, because the whole strip is a handle: there is
        // nothing else a touch here could mean, and `dragging` from the press
        // is what lights the bar under a thumb that has not moved yet.
        Shared.DragTracker {
          id: handleDrag
          travel: root.closeTravel
          openDirection: -1
          latchAxis: "either"
          latchOnPress: true
          startFrom: root.progress

          onBegan: root.dragging = true
          onMoved: p => root.progress = p

          onFinished: (p, v) => {
            root.dragging = false
            if (p <= root.closeCommit) root.dismiss()
            else root.progress = 1
          }

          // A stranded touch must not leave the drawer parked half-open, and
          // until F2 nothing here stopped it: this area handled cancel and not
          // the touch that never ends. The watchdog arrives with the tracker.
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

          // Fills the pill up to the clear button, and the insets are padding
          // rather than anchor margins (docs/style.md F1-F3). Both halves of
          // that matter.
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
          //
          // Left/right rather than fill, so the clear button below keeps a
          // target of its own (docs/style.md F4, F6) -- the same shape as the
          // Wi-Fi passphrase and its reveal eye. With nothing typed the button
          // is 0 wide and `clearButton.left` is the pill's right edge, so the
          // field is back to filling the pill and F1 still holds: every pixel
          // of the drawn pill focuses it.
          Ui.TextField {
            id: searchField
            anchors.left: parent.left
            anchors.right: clearButton.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            leftPadding: searchGlyph.x + searchGlyph.width + Style.space(10)
            // 16 against the pill's own edge, 4 against the button: the
            // button's slot already carries the gap on that side, and a second
            // one would leave the caret stranded well short of the glyph.
            rightPadding: clearButton.visible ? Style.space(4) : Style.space(16)
            // The control is taller than its line now, so it has to be told
            // where that line goes. Left at the default the text renders
            // against the top of the pill.
            verticalAlignment: TextInput.AlignVCenter
            placeholderText: "Search apps and settings"
            background: null
            verticalPadding: 0
            onTextChanged: queryDebounce.restart()
          }

          // Clear (F6). A field a thumb can fill is a field a thumb has to be
          // able to empty: backspacing a wrong query out is 20 taps on a phone
          // keyboard, and the alternative people actually use -- close the
          // drawer and swipe it up again -- throws away the scroll position and
          // the keyboard with it.
          //
          // Only when there is something to clear. Drawn unconditionally it is
          // a control that does nothing for as long as the field is empty,
          // which is most of the time this surface is on screen, and it would
          // sit exactly where a thumb reaching for the right-hand column of
          // apps comes to rest.
          Item {
            id: clearButton
            visible: searchField.text.length > 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            // Zero, not merely invisible: an invisible Item still holds its
            // anchors, so a fixed width would take 44px off the field's hit
            // area on every screenful where nothing has been typed.
            width: visible ? root.clearSlot : 0
            height: root.clearSlot

            // No chrome of its own, so the veil is the chrome (docs/style.md
            // H8), exactly as the reveal eye does it. Guarded on
            // `sheetDragging` like every other control on this sheet (H6):
            // this one holds its own grab and never becomes the drag, so the
            // guard cannot fire today -- but "which of these MouseAreas is
            // also a drag handle" is exactly the question the rule exists so
            // that nobody has to answer per control.
            PressVeil {
              anchors.fill: parent
              radius: width / 2
              on: clearArea.pressed && !root.sheetDragging
            }

            Ui.OpticalGlyph {
              anchors.fill: parent
              text: "󰅙"
              fontFamily: Style.font.family
              fontSize: Style.font.iconLarge
              color: root.subdued
            }

            MouseArea {
              id: clearArea
              anchors.fill: parent
              // Straight to the query as well as to the field. Through
              // onTextChanged alone this goes via the 120ms debounce, and the
              // grid then holds the results of a query that is visibly no
              // longer there -- which reads as a tap that did not take.
              onClicked: {
                searchField.text = ""
                queryDebounce.stop()
                root.query = ""
              }
            }
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

          // A header changes where the content *starts*, not only how tall it
          // is: `originY` moves up by the header's height and `contentY` does
          // not follow, so a shelf that appears after the view was built
          // leaves the grid scrolled to exactly where its first row used to
          // be -- the apps look right and the row above them is cut in half,
          // which is precisely how it landed on the phone the first time.
          //
          // Corrected by the same delta rather than by snapping to the top,
          // because the two cases want the same answer: at the top, moving
          // `contentY` by the change keeps the shelf fully visible; scrolled
          // into the apps -- where a closing app can collapse the header under
          // you -- it keeps what is on screen exactly where it is. Neither is
          // a scroll anybody asked for.
          property real lastOriginY: 0
          onOriginYChanged: {
            var shift = grid.originY - grid.lastOriginY
            grid.lastOriginY = grid.originY
            if (shift !== 0) grid.contentY += shift
          }

          // ----------------------------------------- M. open apps
          //
          // The shelf is the grid's *header*, not a sibling above it, so it
          // scrolls with the apps instead of standing over them: dragging the
          // grid up carries the row off the top the way it carries the first
          // row of icons, and there is one scrolling thing on this sheet
          // rather than one that moves and one that does not.
          //
          // That is also why the flick (M6) has to claim its axis explicitly
          // in the tile below. Pinned, the row had no competitor for an
          // upward drag; inside the scroll it has the grid, and an
          // arbitration that is left to whichever threshold fires first is
          // one that resolves differently on a slow finger than on a fast one.
          header: Column {
            id: openSection

            // How the IPC reaches the tiles: an id inside a Component is
            // scoped to that Component, so `grid.headerItem` is the only
            // handle there is from outside it.
            property alias row: openRow

            readonly property bool shown:
              root.openApps.length > 0 && root.query === ""

            width: grid.width
            // Collapsed to nothing rather than merely hidden (M2, M3). A
            // header keeps its height in `contentHeight` whether it is
            // visible or not, so an invisible one leaves its own height as a
            // hole at the top of the grid -- a screenful of apps pushed down
            // by a row that is not there.
            height: openSection.shown ? openSection.implicitHeight : 0
            visible: openSection.shown
            spacing: Style.space(2)
            // The gap to the first row of apps. It was the sheet column's
            // spacing while this was a sibling; inside the view there is no
            // spacing to inherit and the shelf has to carry its own.
            bottomPadding: Style.space(10)

            Text {
              id: openCaption
              leftPadding: Style.space(6)
              topPadding: Style.space(2)
              bottomPadding: Style.space(2)
              text: "OPEN"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: root.textWeight
              // The settings caption's letter spacing, because this is the same
              // kind of thing: a divider that happens to be a word (O).
              font.letterSpacing: Style.space(1)
              color: root.subdued
            }

            ListView {
              id: openRow
              width: parent.width
              height: root.openCellHeight
              orientation: ListView.Horizontal
              model: root.openApps
              spacing: 0
              boundsBehavior: Flickable.StopAtBounds
              // Four fit, and four is what this phone has room for. A fifth
              // window makes the row scroll rather than making the tiles
              // smaller: a tile narrower than a grid cell stops being one (M4).
              //
              // Horizontal only, which is what keeps the flick (M6) and the
              // sheet's close drag (M7) reachable through it: a Flickable
              // steals the grab on the axis it flicks, and this one does not
              // flick vertically.
              interactive: contentWidth > width
              // Clipped, unlike the carousel's row. That one is the whole
              // surface and has nothing to spill onto; this one is a 86px band
              // in the middle of a sheet, so an unclipped tile scrolled off its
              // left edge would paint over the search field. A flicked tile
              // therefore leaves under the caption rather than over it, which
              // is the same direction and reads the same way.
              clip: true
              cacheBuffer: root.openCellHeight * 2

              delegate: Item {
                id: tileSlot
                required property var modelData

                // K5, M4. A shell app has no desktop entry to take an icon from
                // -- its app id is the shell process's own -- so it wears the
                // glyph its card wears. Non-empty for exactly those.
                readonly property string glyph: root.openGlyphFor(tileSlot.modelData)

                width: grid.cellWidth
                height: openRow.height

                // M6. The flick is hand-rolled rather than a MouseArea `drag`,
                // for the reason every gesture on this sheet is: this handler is
                // also the sheet's close-drag handle (H1), and Qt's own drag
                // would latch on the downward travel that belongs to the sheet.
                // Clamped to `maximumY: 0` it would move nothing while doing it,
                // so the symptom would be a downward drag that quietly stopped
                // closing the drawer -- and stopped delivering the click too.
                //
                // Read the way sheetMove reads travel, in scene coordinates and
                // in the same frame, so exactly one of the two ever latches.
                property bool flicking: false
                // Cleared on the next press and not on release, for the reason
                // `sheetWasDrag` is: `clicked` arrives after `released`, and a
                // flag cleared too early focuses the app that was just thrown
                // away.
                property bool wasFlick: false

                Item {
                  id: tile
                  // Width and height rather than `anchors.fill`: the flick moves
                  // `y`, and an item anchored to its parent has no y of its own
                  // to move.
                  width: parent.width
                  height: parent.height

                  PressVeil {
                    anchors.fill: parent
                    anchors.margins: Style.space(3)
                    radius: root.radiusTile
                    // Off once the tile is following the finger: the movement is
                    // the feedback, and a lit tile on its way out is noise (H6).
                    on: tileArea.pressed && !root.sheetDragging && !tileSlot.flicking
                  }

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
                        visible: tileSlot.glyph === ""
                        // Without sourceSize an SVG rasterises at its natural
                        // size -- 512px squares, held per tile.
                        sourceSize: Qt.size(root.iconSize, root.iconSize)
                        asynchronous: true
                        cache: true
                        fillMode: Image.PreserveAspectFit
                        source: tileSlot.glyph === ""
                          ? root.openIconFor(tileSlot.modelData) : ""
                      }

                      // Centred on its ink rather than on the box the font
                      // reserves, next to icons that are centred exactly
                      // (style.md B5, E5).
                      Ui.OpticalGlyph {
                        anchors.fill: parent
                        visible: tileSlot.glyph !== ""
                        text: tileSlot.glyph
                        fontFamily: Style.font.family
                        fontSize: root.iconSize
                        color: root.textOnSurface
                      }
                    }

                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      text: root.openNameFor(tileSlot.modelData)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.weight: root.textWeight
                      color: root.textOnSurface
                      elide: Text.ElideRight
                      // One line, where the grid's cell takes two. A second line
                      // here would move the dot down a row on some tiles and not
                      // others, and a marker that is not in the same place on
                      // every tile is not a marker.
                      maximumLineCount: 1
                    }

                    // M4. The whole of what says "running". It is the accent
                    // because the accent is what this shell already uses for
                    // "the window you would go back to" -- it is the carousel's
                    // border on the active card, at the size a tile can carry.
                    Rectangle {
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: root.openDot
                      height: root.openDot
                      radius: width / 2
                      color: Color.accent
                    }
                  }

                  // The spring is for the gesture that did *not* commit: a tile
                  // let go short of the travel comes back rather than sliding,
                  // which is the same answer a carousel card gives. Off while
                  // the finger owns `y`, so the tile tracks it 1:1.
                  Behavior on y {
                    enabled: !tileSlot.flicking
                    SpringAnimation { spring: 4; damping: 0.4 }
                  }
                  Behavior on opacity { NumberAnimation { duration: 140 } }
                }

                MouseArea {
                  id: tileArea
                  anchors.fill: parent

                  // Axis arbitration, and the whole of it. Three things want
                  // a drag that starts on a tile: the row beside it pages
                  // (horizontal), the grid underneath scrolls (vertical,
                  // because the shelf is inside it), and the tile itself
                  // flicks away (vertical). So the axis is claimed on the
                  // first real movement and nothing is left to threshold
                  // order: vertical-dominant and this handler keeps the
                  // gesture, horizontal-dominant and the row is free to take
                  // it -- exactly the split the carousel's cards get for free
                  // from a horizontal view and a `drag.axis: YAxis`.
                  //
                  // The cost is stated rather than hidden: the grid cannot be
                  // scrolled by a finger that starts on a tile. It is one 86px
                  // row at the top of a sheet that is scrollable everywhere
                  // else, and the alternative -- letting the grid win -- is a
                  // flick that closes an app only when the grid happens to be
                  // at its top.
                  preventStealing: false

                  onPressed: mouse => {
                    tileSlot.flicking = false
                    tileSlot.wasFlick = false
                    tileArea.preventStealing = false
                    flickOut.stop()
                    tile.y = 0
                    tile.opacity = 1
                    // The sheet's press, unchanged: a downward drag from a tile
                    // is still a drag on the sheet (M7).
                    root.sheetPress(this, mouse)
                    // M8. Deliberately no armHold(): the detail card is about a
                    // desktop entry and a tile is a window.
                  }

                  onPositionChanged: mouse => {
                    var p = this.mapToItem(null, mouse.x, mouse.y)
                    var dy = p.y - root.sheetPressY
                    var dx = p.x - root.sheetPressX
                    // Claimed once, on the first movement past a few pixels,
                    // and well under either flick or scroll threshold -- the
                    // point is to have decided before anything else asks.
                    if (!tileArea.preventStealing
                        && (Math.abs(dx) > 3 || Math.abs(dy) > 3))
                      tileArea.preventStealing = Math.abs(dy) > Math.abs(dx)
                    // Upward past the slop is a flick, and stays one for the
                    // rest of the gesture -- a finger that comes back down does
                    // not hand the sheet a drag it never started.
                    if (!root.sheetDragging
                        && (tileSlot.flicking || dy < -root.dragSlop)) {
                      tileSlot.flicking = true
                      // The slop comes out of the travel, so the tile starts
                      // moving from where the finger was when it latched rather
                      // than jumping by one slop.
                      tile.y = Math.max(-tileSlot.height,
                                        Math.min(0, dy + root.dragSlop))
                      return
                    }
                    root.sheetMove(this, mouse)
                  }

                  onReleased: {
                    if (tileSlot.flicking) {
                      tileSlot.flicking = false
                      tileSlot.wasFlick = true
                      if (tile.y <= -root.openDismissTravel) flickOut.start()
                      else tile.y = 0
                      // The sheet's touch still has to be ended. It never
                      // latched -- a flick is upward and this sheet latches
                      // downward -- so before F2 leaving it unfinished cost
                      // nothing. It now strands a live watchdog that fires
                      // four seconds later and puts `progress` back: measured
                      // on the device, M5 read the drawer as open because M6's
                      // flick had reopened it from behind.
                      root.sheetCancel()
                      return
                    }
                    root.sheetRelease()
                  }

                  onCanceled: {
                    tileSlot.flicking = false
                    tile.y = 0
                    root.sheetCancel()
                  }

                  onClicked: {
                    if (root.sheetWasDrag || tileSlot.wasFlick) return
                    root.focusOpen(tileSlot.modelData)
                  }
                }

                // Let the tile leave before the model drops it, so the row
                // closing the gap reads as a consequence rather than a glitch --
                // the carousel's dismissOut, at a tile's scale.
                SequentialAnimation {
                  id: flickOut
                  ParallelAnimation {
                    NumberAnimation { target: tile; property: "y"
                                      to: -tileSlot.height
                                      duration: 140; easing.type: Easing.OutCubic }
                    NumberAnimation { target: tile; property: "opacity"; to: 0
                                      duration: 140 }
                  }
                  ScriptAction {
                    script: {
                      root.closeOpen(tileSlot.modelData)
                      tile.y = 0
                      tile.opacity = 1
                    }
                  }
                }
              }
            }
          }

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
            //
            // L1-L4 ride on the same handler for the same reason: it holds the
            // grab, so a hold is a timer this one arms and everything that ends
            // the gesture disarms. `onCanceled` covers the scroll case (L4) --
            // QQuickMouseArea::ungrabMouse() clears `pressed` and emits it when
            // the Flickable steals the grab.
            MouseArea {
              id: cellArea
              anchors.fill: parent
              onPressed: mouse => { root.sheetPress(this, mouse); root.armHold(entry) }
              onPositionChanged: mouse => {
                root.sheetMove(this, mouse)
                root.holdMove(this, mouse)
              }
              onReleased: { root.cancelHold(); root.sheetRelease() }
              onCanceled: { root.cancelHold(); root.sheetCancel() }
              onClicked: if (!root.sheetWasDrag && !root.holdFired) root.launch(entry)
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
            id: settingsCaption
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
              height: root.settingsRowHeight

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

      // ------------------------------------------------ the app detail (L)
      //
      // A card over the sheet and not a surface of its own (L5). The drawer
      // keeps its keyboard focus, its scroll position and its progress, so
      // closing this leaves the grid exactly where the hold found it -- and a
      // second layer-shell surface for a card would have to be arranged,
      // focused and dismissed against the keyboard and the strip, which is
      // three problems this screen has already solved once.
      //
      // Declared after sheetColumn, so it takes input ahead of the grid (E6).
      Rectangle {
        id: detailScrim
        anchors.fill: parent
        visible: root.detailEntry !== null
        color: Util.alpha(root.surface, 0.92)

        MouseArea {
          // no press state (style.md H7): a scrim that dismisses. A tap
          // outside the card is the way out that needs no control of its own,
          // and it is also the swallower that keeps the tap off the icon
          // underneath -- which would otherwise launch the app whose card is
          // being closed.
          anchors.fill: parent
          onClicked: if (root.detailStage !== "working") root.closeDetail()
        }

        Rectangle {
          anchors.centerIn: parent
          width: parent.width - Style.space(48)
          height: detailCol.implicitHeight + Style.space(32)
          radius: root.radiusCard
          color: root.cardFill

          MouseArea {
            // no press state (style.md H7): a tap swallower behind a modal.
            // Declared before the content so the content still takes its own
            // taps (E6); without it every gap between the controls is a hole
            // through to the scrim, and the card closes when you meant to read
            // it.
            anchors.fill: parent
          }

          Column {
            id: detailCol
            anchors.centerIn: parent
            width: parent.width - Style.space(32)
            spacing: Style.space(14)

            // --- what it is ------------------------------------------------
            //
            // An Item with anchors rather than a Row: a Row refuses horizontal
            // anchors on its children, and the label block has to be "whatever
            // is left after the icon" rather than a width computed here.
            Item {
              width: parent.width
              height: Math.max(root.iconSize, detailHeadText.height)

              Image {
                id: detailIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.iconSize
                height: root.iconSize
                // Same reason as the grid's: without this an SVG rasterises at
                // its natural 512.
                sourceSize: Qt.size(root.iconSize, root.iconSize)
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectFit
                source: root.shell && root.shell.appLibrary && root.detailEntry
                  ? root.shell.appLibrary.iconSource(root.detailEntry.icon)
                  : ""
              }

              Column {
                id: detailHeadText
                anchors.left: detailIcon.right
                anchors.leftMargin: Style.space(12)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: root.shell && root.shell.appLibrary && root.detailEntry
                    ? root.shell.appLibrary.entryName(root.detailEntry) : ""
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.weight: root.textWeight
                  color: root.textOnSurface
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: text.length > 0
                  text: String(root.detailInfo.comment || "")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: root.textWeight
                  color: root.subdued
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }
              }
            }

            // --- where it came from (L6) -----------------------------------
            Column {
              width: parent.width
              spacing: Style.space(2)
              visible: root.detailStage === "info"

              Text {
                width: parent.width
                text: root.detailBusy && root.detailOrigin === ""
                        ? "Looking it up" : root.detailOrigin
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: root.textWeight
                color: root.textOnSurface
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: text.length > 0
                text: String(root.detailInfo.size || "")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: root.subdued
              }

              Text {
                width: parent.width
                visible: text.length > 0
                text: String(root.detailInfo.id || "")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: root.subdued
                elide: Text.ElideMiddle
              }
            }

            // --- the plan (L7, L8) -----------------------------------------
            Column {
              width: parent.width
              spacing: Style.space(4)
              visible: root.detailStage === "plan"

              Text {
                width: parent.width
                text: root.detailBusy ? "Working out what that takes"
                    : root.detailBlocked !== "" ? "This one cannot be removed"
                    : root.detailPlanReady ? root.detailPlanSummary
                    : "Nothing answered for this one"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: root.textWeight
                color: root.textOnSurface
                wrapMode: Text.Wrap
              }

              // L8's reason, in pacman's own words. Three lines of a dependency
              // message is a lot of card, so it elides -- what matters is that
              // it names something, and "required by gtk4" is in the first
              // line of every one of these.
              Text {
                width: parent.width
                visible: text.length > 0 && !root.detailBusy
                text: root.detailBlocked
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: root.subdued
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
              }

              // Every package the removal takes, named. The count above is the
              // number; this is the answer to "which ones".
              Text {
                width: parent.width
                visible: text.length > 0 && !root.detailBusy && root.detailPlanReady
                text: String(root.detailPlan.names || "").split(" ").join(", ")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: root.subdued
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
              }

              // L13. The one thing pacman's own plan cannot say: this package
              // is in moarchy-meta's depends, so the next upgrade of that
              // package resolves its dependencies and puts this back. Said
              // here rather than discovered on the next `pacman -Syu`.
              Text {
                width: parent.width
                visible: String(root.detailPlan.set || "") === "1"
                         && !root.detailBusy && root.detailBlocked === ""
                text: "In the moarchy package set: a later update reinstalls it."
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: root.subdued
                wrapMode: Text.Wrap
              }
            }

            // --- the removal running ---------------------------------------
            Text {
              width: parent.width
              visible: root.detailStage === "working"
              text: "Removing"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: root.textWeight
              color: root.textOnSurface
            }

            // --- L11, said rather than left as a missing button -------------
            Text {
              width: parent.width
              visible: root.detailStage === "info" && root.detailProtected
              text: "Part of moarchy. The shell will not uninstall itself."
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: root.textWeight
              color: root.subdued
              wrapMode: Text.Wrap
            }

            // --- Uninstall (L7) --------------------------------------------
            //
            // Full width, because it is the only control on this stage and a
            // 110px button centred under a 312px card reads as an afterthought.
            Rectangle {
              width: parent.width
              height: Style.space(44)
              radius: height / 2
              color: root.containerHigh
              visible: root.detailStage === "info" && !root.detailProtected
                       && !root.detailBusy
              // Guarded like every other press on this sheet (style.md H6),
              // and the guard is a surface-wide invariant rather than a
              // condition this control can actually meet: the scrim above
              // covers the grid and the handle, so nothing can be dragging the
              // sheet while this button exists. Spelled anyway, because "on
              // the drawer, no press lights during a sheet drag" is the rule,
              // and a control exempt by accident of layout is one that stops
              // being exempt the day the layout moves.
              PressVeil {
                anchors.fill: parent
                radius: parent.radius
                on: uninstallArea.pressed && !root.sheetDragging
              }
              Text {
                anchors.centerIn: parent
                text: "Uninstall"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: root.textWeight
                color: root.textOnSurface
              }
              MouseArea {
                id: uninstallArea
                anchors.fill: parent
                onClicked: root.planRemoval()
              }
            }

            // --- Cancel / Remove (L7, L8) -----------------------------------
            Item {
              id: detailActions
              width: parent.width
              height: Style.space(44)
              visible: root.detailStage === "plan" && !root.detailBusy

              // Two halves of the card's width with one gap between them, so
              // both clear E1 by a wide margin and neither has to grow into the
              // other (E3).
              readonly property int gap: Style.space(12)
              readonly property int half: Math.floor((width - gap) / 2)
              // Alone when there is nothing to confirm: a blocked plan has one
              // way out and it is not called Cancel.
              readonly property bool paired: root.detailBlocked === "" && root.detailPlanReady

              Rectangle {
                id: detailBack
                anchors.left: parent.left
                width: detailActions.paired ? detailActions.half : detailActions.width
                height: parent.height
                radius: height / 2
                color: Util.alpha(root.textOnSurface, 0.10)
                PressVeil {
                  anchors.fill: parent
                  radius: parent.radius
                  on: detailBackArea.pressed && !root.sheetDragging
                }
                Text {
                  anchors.centerIn: parent
                  text: detailActions.paired ? "Cancel" : "Back"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.weight: root.textWeight
                  color: root.textOnSurface
                }
                MouseArea {
                  id: detailBackArea
                  anchors.fill: parent
                  onClicked: root.detailStage = "info"
                }
              }

              Rectangle {
                anchors.right: parent.right
                width: detailActions.half
                height: parent.height
                radius: height / 2
                color: root.containerHigh
                // L8. Not disabled -- absent. A button that is drawn and
                // refuses is a button that has to explain itself twice.
                visible: detailActions.paired
                PressVeil {
                  anchors.fill: parent
                  radius: parent.radius
                  on: detailRemoveArea.pressed && !root.sheetDragging
                }
                Text {
                  anchors.centerIn: parent
                  text: "Remove"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.weight: root.textWeight
                  color: root.textOnSurface
                }
                MouseArea {
                  id: detailRemoveArea
                  anchors.fill: parent
                  onClicked: root.removeApp()
                }
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
