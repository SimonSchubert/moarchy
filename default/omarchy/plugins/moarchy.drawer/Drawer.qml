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
import "../moarchy.common/Apps.js" as Apps
import "../moarchy.common/Theme.js" as Theme
import "../moarchy.common/ShellApps.js" as ShellApps
import "../moarchy.common/Sheet.js" as Sheet
import "../moarchy.common/Edge.js" as Edge
import "../moarchy.common" as Shared

Item {
  id: root

  // Injected by the host in the panel Loader's onLoaded, by name and after
  // construction. It may not be `readonly` or `required`: readonly makes the
  // assignment throw, and required makes the component fail to instantiate at
  // all, because a plugin is created first and configured afterwards. Either way
  // the failure is silent.
  //
  // One, where every plugin here declared six (refactor.md J8). The host also
  // offers `omarchyPath`, `manifest`, `barWidgetRegistry`, `pluginRegistry` and
  // `service`, each behind an `if ("x" in target)` -- so a plugin that does not
  // declare one is simply skipped, and not one of the eleven read any of them.
  // A service is reached through `shell.serviceFor()`, which is the supported
  // way in and the way the bar and the shade have always done it.
  property var shell: null

  // 0 shut .. 1 open, and the drag writes it directly. The gestures plugin owns
  // the bottom edge -- it cannot be shared, so this surface never sees the
  // touch -- and drives this property from its own MultiPointTouchArea while
  // the finger moves. That is what makes the drawer follow the finger rather
  // than appear at a threshold.
  // gestures.md Q2. Which screen edge raised this sheet. Written by
  // moarchy.gestures on a press, and only while the sheet is at rest shut
  // (Q3) -- so it never changes under a finger. Bottom is where this sheet
  // has always come from and is what it falls back to.
  property string entryEdge: Edge.BOTTOM
  readonly property bool sideways: Edge.horizontal(root.entryEdge)

  property real progress: 0

  // Set by the gestures plugin for the length of the drag. It turns the
  // animation off (so writes track 1:1) and keeps `opened` honest mid-gesture.
  property bool dragging: false

  // G14a. The search pill slides under the opening finger as the sheet comes
  // up, and a press there must not read as a request. Armed only once the
  // drawer is sitting still, so the swipe that opened it cannot raise the
  // keyboard.
  //
  // Armed off `opened`, not off the end of a drag. A drag released part-way
  // hands the last stretch to the progress animation, and `drawer open` never
  // drags at all -- so arming when `dragging` fell with the sheet already at 1
  // armed only a finger dragged the whole way up, and the field was dead after
  // every flick.
  property bool keyboardRaiseArmed: false
  Timer {
    id: keyboardRaiseArm
    interval: 120
    onTriggered: root.keyboardRaiseArmed = root.opened
  }

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
  // Not `drawerWindow.height`, and that is the whole of this note: shut, this
  // window is a one-pixel band (N3). `drawer geometry` answers `w=360 h=1` with
  // the drawer down and `w=360 h=694` with it up -- and the drag that *opens*
  // this sheet necessarily starts while it is down. Dividing a drag by the band
  // moves the sheet hundreds of times finger speed until the surface grows,
  // which is a jump on the first frames and then a visible retreat as the
  // divisor corrects. (It was Qt's unmapped 100x100 when this was written, and
  // seven times finger speed.)
  //
  // So: the screen until this window has been up once, its own height ever
  // after. The two differ by the bar's exclusive zone -- 26px of 720 here -- so
  // the first drag of a session is 3.6% off 1:1 and every one after it is
  // exact. The alternative, hard-coding the screen, is wrong by that much
  // forever and silently wrong on a device with a different bar.
  property real sheetHeight: 0

  // The same trap on the other axis, for the same reason: on a right edge
  // the shut surface is a one-pixel *column*, and a drag divided by it moves
  // the sheet hundreds of times finger speed until it grows.
  property real sheetWidth: 0

  // D2a, Q2. The sheet's own extent along the axis the finger travels on.
  // Reading the height for a sheet that arrives sideways is D2b's defect
  // with the axes swapped -- a first drag of the session at half speed,
  // which only ever shows on a cold shell.
  readonly property real closeTravel: Math.max(1, root.sideways
    ? (root.sheetWidth > 0 ? root.sheetWidth
                           : (drawerWindow.screen ? drawerWindow.screen.width : 360))
    : (root.sheetHeight > 0 ? root.sheetHeight
                            : (drawerWindow.screen ? drawerWindow.screen.height : 720)))
  readonly property real closeCommit: 0.7

  // H1. Travel past which a touch on the sheet stops being a tap and starts
  // dragging the sheet shut.
  readonly property int dragSlop: Style.space(10)

  // The strip's `fling`, and for the reason given there: 0.6 was a number
  // matched to a speed reading that swung by 5x between identical gestures.
  readonly property real sheetFling: 0.3

  // H1, on the shared tracker (docs/refactor.md F1). The way out is the way
  // back in, reversed: travelling *away* from the entry edge is what raises
  // progress, and this sheet is already up (Q2). From the bottom that reads
  // `openDirection` -1 and `latchSign` +1, which is what it always was.
  //
  // Scene coordinates are the tracker's whole input convention, and the reason
  // is this surface's: every input item here is a child of the sheet, so its
  // frame moves as the sheet does and a delta measured in it feeds back into
  // itself.
  Shared.DragTracker {
    id: sheetDrag
    axis: Edge.axis(root.entryEdge)
    travel: root.closeTravel
    openDirection: Edge.openDirection(root.entryEdge)
    // Back toward the entry edge only -- this sheet is open, and that is the
    // way out of it.
    latchSign: Edge.closeLatchSign(root.entryEdge)
    // P6's rule, reached here by the same route: on a sideways edge the
    // close drag crosses the grid's own scroll axis, and a grid that shut
    // the sheet whenever a thumb's arc wandered would be a grid nobody could
    // scroll. On the bottom edge the two share an axis and H5 settles it, so
    // this stays off there rather than changing a gesture that works.
    axisDominant: root.sideways
    slop: root.dragSlop
    startFrom: root.progress

    onBegan: root.dragging = true
    onMoved: p => root.progress = p

    // H3, and the numbers stay here (F3). A short, fast flick means the same
    // as a long slow drag: a drag beginning near the far end of the sheet
    // cannot reach the commit threshold at all, because there is not enough
    // sheet left to travel.
    // `v` is signed toward open, so a fling *shut* is the negative one. This
    // sheet opens upward, which is why the two read the other way round from
    // the shade's.
    onFinished: (p, v) => {
      root.dragging = false
      if (v <= -root.sheetFling) root.dismiss()
      else if (v >= root.sheetFling) root.progress = 1
      else if (p <= root.closeCommit) root.dismiss()
      else root.progress = 1
    }

    onStranded: root.markTrace(-2)
    onCanceled: from => {
      // -1, so F2's evidence sentence is true of this tracker too (H5). The
      // handle below marked it and the sheet did not, which left the same check
      // passing for a surface that could not fail it.
      root.markTrace(-1)
      root.dragging = false
      root.progress = from
    }
  }

  // The names the controls on this sheet already read. `sheetPressX` and
  // `sheetPressY` are the hold's (L3): a long press has to be cancelled by
  // travel in *any* direction, because a finger that has gone 40px sideways has
  // plainly stopped meaning "tell me about this one", and the sheet's own
  // gesture is one axis and has never needed x.
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

  onDraggingChanged: {
    if (root.dragging) {
      root.dragTrace = []
      root.retireTrace = []
    }
  }
  onOpenedChanged: {
    root.keyboardRaiseArmed = false
    if (root.opened) keyboardRaiseArm.restart()
    else keyboardRaiseArm.stop()
  }
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

  // I5e. Is the keyboard up? Asked of the compositor's configure rather than of
  // the search field, because the field answers a different question and I5d is
  // the proof they come apart: the keyboard can be up with nothing here focused
  // at all, and then I5a's inset stays on with the keyboard under it.
  //
  // The threshold is Osk.qml's, shared with the home strip's fill. This
  // surface's own inset moves its height by 20px, and the clusters either side
  // of the threshold are 180px apart, so the binding settles in one step in
  // either direction rather than oscillating.
  //
  // False while the surface is down, and that default is the safe one: shut,
  // the window is a one-pixel band (N3), which `reserving()` would read as a
  // keyboard. That answer would drop the inset, and the grow would then take two
  // configures -- one without the inset, one with it -- and flash a band of
  // wallpaper under the pill (I1). Gated on a height only a real sheet has, the
  // same guard `sheetHeight` is written under, so the grow is one configure.
  readonly property bool keyboardUp:
    root.surfaceUp && drawerWindow.height > 200 && osk.reserving(drawerWindow)


  // The weight the bar and every other surface runs at (docs/style.md B3).
  // Light text on a dark ground reads thinner than it measures, and one
  // screen left at Regular reads as a different phone.
  readonly property int textWeight: Font.DemiBold

  // The sheet radius, the same one the shade's sheet uses (docs/style.md
  // D1). Named rather than written twice: it is also the height of the
  // rectangle that squares the bottom corners back off, and those two
  // numbers are the same number rather than two that happen to match.
  Shared.UiFile { id: ui }
  readonly property int radiusSheet: ui.radiusSheet

  // An app cell is a grid thing you tap as a unit, which is D1's `tile`. Only
  // the press veil is drawn at it -- the cell itself has no chrome.
  readonly property int radiusTile: ui.radiusTile

  // A settings result is a full-width list row, which is D1's `card` -- the
  // same card the rows in moarchy.settings are drawn at, because it is the same
  // kind of row read on a different screen. The glyph slot comes from the same
  // place for the same reason (E5): derived from the glyph, not fixed.
  readonly property int radiusCard: ui.radiusCard
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

  // H3. The three controls on this sheet that also drag it, bound to the
  // sheet once rather than forwarding four handlers apiece.
  component SheetArea: Shared.SheetDragArea { sheet: root }

  // G14a. The keyboard, asked to show when a finger taps the search field.
  // Hide is not this surface's: G2 is the one way down, and a drawer that put
  // the keyboard away on close is what made it flap when launching an app.
  Shared.Osk { id: osk }


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

  // N3. Written by moarchy.gestures when an upward drag latches, so the grow
  // happens during the slop of a real open rather than on every strip press.
  // A press is usually a workspace swipe, and growing this grid for that is
  // what made the switch hitch.
  property bool warming: false

  // N3. Whether the window is sheet-sized rather than the band. Warming grows
  // it; it goes back to the band once the sheet is all the way down.
  readonly property bool surfaceUp: root.progress > 0 || root.warming

  // N3, Q2. The four booleans the surface binds: shut, every side but the one
  // opposite the entry edge, which is what makes the band a band.
  readonly property var bandAnchors: Edge.anchors(root.entryEdge, root.surfaceUp)

  Connections {
    target: root.shell ? root.shell.appLibrary : null
    function onAppsChanged() { root.appsRevision++; root.buildIndex() }
  }

  onShellChanged: root.buildIndex()
  Component.onCompleted: root.buildIndex()

  // ------------------------------------------ is this app already running?
  //
  // The one question this sheet asks about *windows* rather than about desktop
  // entries, and it is asked on the launch path: an app that is already running
  // maps no new window, so the hop to a free workspace has nothing to arrive on
  // (windows.md L10).
  //
  // Answered through moarchy.common/Apps.js, which is the same appId index the
  // overview resolves its tiles through (gestures.md P5). One index, because
  // two implementations of "which app is this window" is how every moarchy-apps
  // plugin came to be drawn as `org.quickshell` with no artwork at all (K5).
  //
  // The index is held here rather than there because the *timing* is this
  // sheet's: rebuilt on `appsChanged` below, where the overview rebuilds when
  // its own sheet comes up. Separate from `appRows` on purpose -- that one is
  // the query's answer and re-sorts on every keystroke, and what is running
  // must not depend on what is in the search field.
  property var appIdIndex: ({})

  function buildIndex(): void { root.appIdIndex = Apps.index(root.shell) }

  // Read straight off zwlr-foreign-toplevel-management-v1, which sway
  // implements: no fork, no `swaymsg -t get_tree` walk, no polling, and an
  // appId per window, which is all this question needs. Since K1 that list
  // includes this shell's own screens -- Settings, Wi-Fi, Bluetooth and SIM are
  // windows and arrive here like `foot` does, with no branch of their own.
  function entryIsRunning(entry): bool {
    if (!entry) return false
    var open = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    for (var i = 0; i < open.length; i++) {
      var e = open[i] ? Apps.entryForAppId(root.appIdIndex, open[i].appId) : null
      if (e && String(e.id) === String(entry.id)) return true
    }
    return false
  }

  // L10. Whether an entry summons a plugin rather than starting a process.
  function pluginSummonedBy(entry) { return Apps.pluginSummonedBy(entry) }

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

  Shared.Probe {
    id: guardProc
    property int wanted: 0
    onAnswered: {
      // A batch for a query that has already been retyped is not a late
      // answer, it is the wrong answer.
      if (guardProc.wanted !== root.guardGeneration) return
      root.settingsGuards = Guards.parse(text).when
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
    var lines = text.split("\n")
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

  Shared.Probe {
    id: infoProc
    property int wanted: 0
    onAnswered: {
      if (infoProc.wanted !== root.detailGeneration) return
      root.detailInfo = root.parseKv(text)
      root.detailBusy = false
    }
  }

  Shared.Probe {
    id: planProc
    property int wanted: 0
    onAnswered: {
      if (planProc.wanted !== root.detailGeneration) return
      root.detailPlan = root.parseKv(text)
      root.detailBusy = false
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
    //
    // Which sheets those are is Sheet.js' single list, read from the rank rather
    // than named here (I2): five screens named their own pair and gave three
    // different answers.
    // Q3a. A summon carries no direction, so it uses this sheet's own edge --
    // but only from rest. `releaseTarget()` commits an edge drag *through*
    // this function with the sheet part-way in, and resetting there would
    // teleport it across the screen on the frame it was let go.
    if (root.progress <= 0 && !root.dragging) root.entryEdge = Edge.BOTTOM

    Sheet.cover(root.shell, root.pluginId, Sheet.TOP)

    root.query = ""
    searchField.text = ""

    // L5. The drawer opens on the grid, never on somebody's half-read card.
    root.closeDetail()
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
    // F8, and the shade's reason applies here too: a tile tap that launches,
    // or a hold that opens a card, can take this surface away under a finger
    // that is still down, and an unmapped MouseArea reports no release. A
    // tracker left active is a watchdog that puts `progress` back four seconds
    // later, over whatever is on screen by then. No-ops on every ordinary
    // path, where release() has already ended it.
    sheetDrag.cancel()
    handleDrag.cancel()

    // Move focus off the search field BEFORE the surface goes away. An unmap
    // is not a text-input-v3 deactivate, so a field that still holds active
    // focus keeps receiving commits after the drawer is gone. `focus = false`
    // is not enough -- it releases the focus *scope*, not the active focus.
    // Handing active focus to a plain Item is what actually sends the disable.
    // The keyboard itself stays up (G14); this only stops typing into a field
    // that is no longer on screen.
    focusSink.forceActiveFocus()

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
    //
    // Nor for an app that is already running. `gtk-launch` on a single-instance
    // app maps no new window -- it asks the running one to present itself -- so
    // there would be nothing to arrive on, and the hop would strand you on an
    // empty workspace. Measured: with Clocks already open on 6, a launch left
    // the phone sitting on 4 with nothing there.
    if (!root.pluginSummonedBy(entry) && !root.entryIsRunning(entry))
      ShellApps.goToFreeWorkspace(root.shell)

    root.shell.appLibrary.launch(entry.id, root.shell.appLibrary.entryName(entry))
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

    // The same list with the name beside the id, for a caller that has to draw
    // it rather than launch from it -- `moarchy-trigger rows`, which offers
    // every app as something a hold or the power button can open
    // (gestures.md Q10).
    //
    // A second verb rather than a wider `entries`: that one's output is a bare
    // id per line and two documents asserting against it say so (apps.md T5,
    // T9), so widening it would be a format change to a published answer for
    // the sake of a caller that can have its own.
    //
    // The name comes from appLibrary rather than from the entry, because the
    // library is what resolves a blank or duplicated Name= the way the grid
    // draws it -- two lists that disagree about what an app is called is how a
    // trigger comes to name something the drawer does not.
    function entryRows(): string {
      if (!root.shell || !root.shell.appLibrary) return ""
      var out = []
      var rows = root.shell.appLibrary.sortedEntries("") || []
      for (var i = 0; i < rows.length; i++) {
        var entry = rows[i] && rows[i].entry
        if (!entry) continue
        var name = String(root.shell.appLibrary.entryName(entry) || entry.id)
        // Tab-separated, so a name with spaces in it stays one field. A tab in
        // a Name= would break it; nothing on this phone has one, and a desktop
        // entry that did would be a desktop entry to fix.
        out.push(String(entry.id) + "\t" + name.replace(/\t/g, " "))
      }
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
      searchField.text = text
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
    // only be the band (N3), and no phone this runs on has a 200px-tall sheet.
    onHeightChanged: if (drawerWindow.height > 200) root.sheetHeight = drawerWindow.height
    onWidthChanged: if (drawerWindow.width > 200) root.sheetWidth = drawerWindow.width

    // gestures.md N3. Never unmapped: shut, a one-pixel band along the bottom
    // edge; grown to the sheet when an upward drag latches, not on press.
    //
    // It used to be `visible` only while drawn, and that cost ~200ms on every
    // open, measured on the Pixel 3a (omarchy-test,
    // docs/drawer-open-stall-results.md). Quickshell deletes a layer-shell
    // window that goes invisible, so each open built a new QQuickWindow -- a
    // render thread, a GL context, a swapchain, the whole scene graph and a
    // first layout -- and the first frame took polish 75-114ms, sync 38-51,
    // render 26-43 and swap 85-93 (with scene graph logging on) while the
    // finger went on moving. Kept alive, an open is a resize: one configure and
    // two frames that allocate buffers, measured at 27-35ms for the longest
    // frame against ~225.
    //
    // The shade is the model: shut, it is a bar-height band across the top, so
    // a pull-down costs a resize. Not left full-screen and transparent, which
    // is a full-screen blend in every frame on a Mali-400 (build-log 6b); a
    // band blends one row. It is not free: it still redraws when what is on the
    // sheet changes, which is a one-pixel frame here (+25ms of sway GPU time
    // per switch on the 3a when it lands on a workspace change).
    //
    // Warming used to start on the press, which paid the grow on a sideways
    // workspace swipe as well -- the hitch that went away when this plugin
    // failed to load. Latch is 8px up, still inside the slop of a real open,
    // and a press that never latches never grows.
    visible: true
    // N3, Q2. Shut, a one-pixel band along the entry edge; grown, all four.
    // Both implicit sizes are declared because only the unanchored axis
    // reads one, and which axis that is is now a setting.
    anchors {
      top: root.bandAnchors.top
      bottom: root.bandAnchors.bottom
      left: root.bandAnchors.left
      right: root.bandAnchors.right
    }
    implicitHeight: 1
    implicitWidth: 1
    color: "transparent"

    // N3. Grown is not live. While warming this surface is full-screen, on Top,
    // and over everything -- so its input region is cut down until the sheet is
    // actually being drawn, and stays cut on the band.
    //
    // One pixel and not none: Qt treats an empty mask as unset, and an unset
    // input region is the *whole surface* -- the opposite of what is being
    // asked for. moarchy.splash carries the same workaround for the same
    // reason (windows.md L3). The pixel is outside the surface, where the
    // compositor clips it to nothing: the band is mapped for the whole session,
    // and a pixel inside it would be a dead spot at the edge of whatever it
    // sits over.
    Region { id: warmRegion; x: -1; y: -1; width: 1; height: 1 }
    mask: root.progress > 0 ? null : warmRegion


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
    // Gated on the keyboard, and this is the whole subtlety. A margin does not
    // extend the surface "under the strip" -- it extends it past the bottom of
    // the *usable area*, and what sits there depends on what else is
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
    // One signal, and it is the compositor's own configure (I5a, I5e). It lags
    // the raise by a frame and cannot be wrong about it.
    //
    // `searchField.activeFocus` used to lead it, as a stand-in for "the
    // keyboard is up" on the reasoning that focusing the field is what raised
    // it. Focusing a field raises nothing now (gestures.md G14), so the
    // stand-in stopped standing for anything: left in, it dropped the inset on
    // every tap in the search box with no keyboard underneath, and a band of
    // the app showed through with the home pill drawn on it -- which is I1's
    // failure, arriving from the fix for a different one.
    margins.bottom: root.keyboardUp ? 0 : -root.gestureStrip

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
      // On the entry axis, the last sheet size rather than the window's: on
      // the band the window is one pixel across there, and a sheet that
      // followed it would lay the grid out again at one pixel on every close
      // and at full size on every open. The screen until the window has been
      // up once (`sheetHeight`/`sheetWidth` above).
      //
      // The cross axis takes the parent, because the cross axis never
      // collapses -- a band is one pixel on one axis and full on the other,
      // which is the whole reason the latch exists.
      width: root.sideways
           ? (root.sheetWidth > 0 ? root.sheetWidth
              : (drawerWindow.screen ? drawerWindow.screen.width : parent.width))
           : parent.width
      height: root.sideways ? parent.height
            : (root.sheetHeight > 0 ? root.sheetHeight
               : (drawerWindow.screen ? drawerWindow.screen.height : parent.height))

      // Q2. Rides in from whichever edge raised it. Translation only: this is
      // a Mali-400 at GLES 2.0, so there are no shaders to spend, and a
      // `scale` on a full-screen item costs a re-raster where an `x` or a `y`
      // costs nothing.
      readonly property var at: Edge.offset(root.entryEdge, root.progress,
                                            parent.width, parent.height,
                                            sheet.width, sheet.height)

      // And keeps going, by up to 80px, as the finger approaches the home stop
      // (A4) -- the same cheap cue, on the same drag, that the carousel gave.
      // Signed toward open, so it lifts away from the entry edge whichever one
      // that is; only the strip ever sets `homeHint` (Q4).
      readonly property real lift:
        Edge.openDirection(root.entryEdge) * Style.space(80) * root.homeHint

      x: sheet.at.x + (root.sideways ? sheet.lift : 0)
      y: sheet.at.y + (root.sideways ? 0 : sheet.lift)
      color: root.surface

      // Rounded on the leading edge only -- the one that comes in first. The
      // two corners against the screen edge it arrived from are never seen,
      // and TrailingSquare below squares them back off.
      radius: root.radiusSheet

      // Through goBack() rather than straight to dismiss, so a keyboard walks
      // the same ladder the back gesture does (L5): the plan, then the card,
      // then the drawer. Escape closing the whole sheet from an open card would
      // be the one way out of this screen that skips a level.
      Keys.onEscapePressed: if (!root.goBack()) root.dismiss()

      // The radius rounds all four corners, so square the trailing two back
      // off rather than leave two notches over whatever is behind.
      Shared.TrailingSquare {
        edge: root.entryEdge
        depth: root.radiusSheet
        color: root.surface
      }

      // H1, for a drag that starts on empty sheet rather than on an icon.
      // Declared before the handle and the column so it sits *under* them:
      // later siblings take input first, so this only ever sees touches
      // nothing else claimed.
      SheetArea {
        // no press state (style.md H7): a drag catcher under the content, not
        // a control.
        anchors.fill: parent
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
          radius: ui.radiusOn(height)
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

            // G14a. A press that *starts* on this field, and only once the
            // drawer is sitting still. ClickFocus keeps Exclusive from parking
            // here on map. onPressed rather than a TapHandler: the pill slides
            // under the opening finger, and onTapped fires on that release.
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

          // Clear (F6). A field a thumb can fill is a field a thumb has to be
          // able to empty: backspacing a wrong query out is 20 taps on a phone
          // keyboard, and the alternative people actually use -- close the
          // drawer and swipe it up again -- throws away the scroll position.
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
              radius: ui.radiusOn(width)
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
            SheetArea {
              id: cellArea
              anchors.fill: parent
              onGrabbed: (area, mouse) => root.armHold(entry)
              onDragged: (area, mouse) => root.holdMove(area, mouse)
              onUngrabbed: root.cancelHold()
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
              SheetArea {
                id: resultArea
                anchors.fill: parent
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

    // Somewhere for active focus to go when the drawer closes (N4). It has to
    // be a real item *inside this window*, and for a long time it was not: it
    // sat out at plugin root, a child of an Item that belongs to no window at
    // all. An item with no window cannot be given active focus, so
    // `focusSink.forceActiveFocus()` in close() set a flag on an orphan and
    // took nothing away from the search field, which kept its `focus` across
    // the unmap and had it handed straight back the moment sway re-activated
    // the surface on the next open.
    //
    // The symptom was the drawer re-opening with its query and its focus from
    // last time: the field kept its `focus` across the unmap and took
    // activeFocus straight back on the next map (N4).
    //
    // Zero-sized and declared last, which costs nothing: it takes no input and
    // draws nothing, and the sheet's own drag areas are unaffected by a sibling
    // with no area.
    Item { id: focusSink; focus: true }
  }


  // Typing on a phone keyboard is slow enough that per-keystroke re-sorting of
  // every desktop entry is affordable, but the icon churn behind it is not.
  Timer {
    id: queryDebounce
    interval: 120
    onTriggered: root.query = searchField.text
  }
}
