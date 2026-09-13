// The recents carousel: what a swipe up from the bottom strip opens while an
// app is on screen.
//
// ---------------------------------------------------------------------------
// Where this sits in the bottom gesture
// ---------------------------------------------------------------------------
// One upward drag from the home pill passes through two stops. moarchy
// gestures owns the strip and writes this plugin's `progress` as the finger
// moves, exactly the way it already drives the drawer:
//
//   0 ---- 40% -------- 75% ---- 100%   of a 0.45 * screen-height travel
//   app    RECENTS       HOME
//
// Release under 15% and the carousel springs back; release in the recents band
// and it stays up; release past 75% and the gesture plugin switches to a blank
// workspace instead and puts this away. Which of the two overlays the drag
// drives is decided once, on press: an occupied workspace gets recents, a blank
// one gets the drawer. So the drawer is reachable only from the home screen,
// which is the arrangement Android has and the reason a blank workspace is
// worth landing on at all.
//
// ---------------------------------------------------------------------------
// Why the cards are icons and not thumbnails
// ---------------------------------------------------------------------------
// Two independent reasons, either of which is enough.
//
// Quickshell 0.3.1's ScreencopyView takes a ShellScreen -- through
// wlr-screencopy, which is what grim uses -- or a Toplevel. The toplevel path
// is wired only to `hyprland-toplevel-export-v1`, and Sway does not implement
// it. There is no per-window capture to be had here at all.
//
// And even given the protocol there would be nothing to capture: Sway does not
// render a workspace that is not visible, so the one frame a recents card wants
// is the one frame nobody is drawing. Android gets around that by snapshotting
// each app as it is backgrounded, which on this phone would mean keeping N
// 720x1440 textures resident inside a 361MB budget on a Mali-400 -- the same
// cost that stopped the theme picker using each theme's preview.png.
//
// So a card is the app's icon, its name, and the window title. On a 360px-wide
// screen that is also simply more legible than a 62%-scale screenshot.
//
// ---------------------------------------------------------------------------
// Why ToplevelManager rather than swaymsg
// ---------------------------------------------------------------------------
// zwlr-foreign-toplevel-management-v1, which Sway implements, gives the appId,
// the title, which window is active, a closed() signal, and the only two verbs
// a card needs: activate() and close(). No fork, no get_tree walk, no polling.
// Everything else in this repo that wants compositor state shells out to
// swaymsg; this is the first thing that does not have to.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui
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

  readonly property string pluginId: "moarchy.recents"

  // ------------------------------------------------------------ drag contract
  //
  // Deliberately the same three names the drawer uses, so the gestures plugin
  // drives both overlays through one writer. 0 shut, 1 open; `dragging` turns
  // the animation off while the finger owns the value so writes track 1:1.
  property real progress: 0
  property bool dragging: false

  // What shell.isPluginOpen() reads back. Honest mid-gesture: a half-pulled
  // carousel is not open, so the next swipe still means "open" rather than
  // toggling it shut.
  readonly property bool opened: root.progress >= 1 && !root.dragging

  Behavior on progress {
    enabled: !root.dragging
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }

  // How close the finger is to the home band, 0..1, written by the gestures
  // plugin once the carousel is fully up. The cards fade and slide with it so
  // the second stop announces itself before you let go.
  property real homeHint: 0

  // Retires on the same terms as `progress`, and for the same reason. Three
  // things read this -- the scrim's alpha, the cards' opacity and the sheet's
  // y -- and every one of them is at its *thinnest* in the home band, which is
  // the cue that letting go returns to the wallpaper. Zeroed instantly while
  // `progress` was still animating out, all three snapped back to their
  // fully-open values and stayed there for the 200ms the carousel took to
  // leave: the scrim went 0.4 -> 1.0, the cards 0.45 -> 1.0 and the sheet
  // jumped down a space(80). The carousel flashed to full strength on its way
  // out, which reads as a glitch because nothing about going home should look
  // like the switcher arriving.
  //
  // Gated on `!dragging` exactly like progress, so the finger still drives
  // this directly and only the release is animated.
  Behavior on homeHint {
    enabled: !root.dragging
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }

  // ------------------------------------------------------------- the preview
  //
  // J. A still of the app you are leaving, shrinking onto the leading card, so
  // that an up-swipe reads as "put away". Without it A4 (hide) and E3 (close)
  // look identical from the outside: the app vanishes behind a rising sheet
  // either way.
  //
  // Armed when the drag latches rather than when the finger lands. The capture
  // needs a mapped window to build its buffers against and this surface is
  // `visible: progress > 0`, so there is nothing to capture into until the
  // drag has started regardless.
  property bool previewArmed: false

  // Set the moment the gesture ends, and separate from `previewArmed`, which
  // stays true long enough afterwards for the fade to play against a surface
  // that is still mapped.
  property bool previewReleasing: false

  // 0 at full screen, 1 landed on the card. Follows `progress` directly for
  // the whole drag -- the preview has to track the finger, not lag it -- so
  // the Behavior below is gated off except across the two moments that are
  // genuinely animations: the capture arriving, and a cancelled gesture
  // putting the app back.
  property real previewTrack: 0
  property bool previewEasing: false

  Behavior on previewTrack {
    enabled: root.previewEasing
    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
  }

  function armPreview(): void {
    if (root.previewArmed && !root.previewReleasing) return
    previewDisarm.stop()
    previewEase.stop()
    root.previewReleasing = false
    root.previewEasing = false
    root.previewTrack = 0
    root.previewArmed = true
  }

  // Content is ~145ms behind the arm (measured; docs/gestures.md J). It
  // arrives at full size, pixel-aligned with the app already on screen, and
  // eases from there to wherever the finger has got to -- so what appears
  // mid-drag is a fade between two pictures of the same thing at the same
  // size, never a jump to a smaller one. J4.
  function beginPreviewCatchUp(): void {
    if (!root.previewArmed || root.previewReleasing) return
    root.previewEasing = true
    root.previewTrack = root.progress
    previewEase.restart()
  }

  // `restore` is the difference between J5 and J6. A gesture that changed
  // nothing puts the app back at full size; one that hid it leaves the
  // preview where the finger left it and fades. Always called, including for
  // gestures that never got a frame: a capture that cannot complete -- a
  // blanked screen delivers no frame and reports no error (J7) -- has to be
  // dropped at the end of the gesture rather than waited on.
  function disarmPreview(restore): void {
    if (!root.previewArmed) return
    root.previewReleasing = true
    if (restore) {
      root.previewEasing = true
      root.previewTrack = 0
      previewEase.restart()
    }
    previewDisarm.restart()
  }

  Timer { id: previewEase; interval: 200; onTriggered: root.previewEasing = false }

  // Outlives the fade, so the surface is still mapped while it plays.
  Timer {
    id: previewDisarm
    interval: 260
    onTriggered: {
      root.previewArmed = false
      root.previewReleasing = false
      root.previewEasing = false
      root.previewTrack = 0
    }
  }

  // One sample per frame while a drag is in flight, read back over IPC by the
  // selftest. A drag that jumped straight to open leaves two or three samples;
  // one that followed the finger leaves a ramp. Nothing in a screenshot can
  // tell those apart on this hardware.
  property var dragTrace: []
  // F4. What the *release* left behind, as `progress:homeHint` pairs. The
  // retire is 200ms and one IPC round trip is ~300ms, so the decay cannot be
  // watched from outside -- the same wall dragTrace exists to get around, one
  // gesture later. A homeHint that snapped would leave a step here (57 then 0
  // while progress is still 100); one that retires leaves a ramp.
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
    // J1. The preview follows the same number the sheet does.
    if (root.previewArmed && !root.previewReleasing) root.previewTrack = root.progress
    root.noteRetire()
    if (!root.dragging) return
    var next = root.dragTrace.slice()
    if (next.length < 200) next.push(Math.round(root.progress * 100))
    root.dragTrace = next
  }

  // A carousel card is something in a row you tap as a unit, which is the
  // tile radius rather than the card one (docs/style.md D1).
  readonly property int radiusTile: Style.space(20)

  // The weight the bar and every other surface runs at (docs/style.md B3).
  // Light text on a dark ground reads thinner than it measures, and one
  // screen left at Regular reads as a different phone.
  readonly property int textWeight: Font.DemiBold

  // ------------------------------------------------------------------ palette
  //
  // NOT named `onSurface`/`onAccent` the Material way. QML reserves the
  // `on<Uppercase>` prefix for signal handlers, so a property spelled that way
  // is never readable: the binding evaluates to undefined, undefined assigned
  // to a color is #000000, and nothing is logged.
  readonly property color surface: Color.menu.background
  readonly property color textOnSurface: Color.menu.text

  // A card is a raised surface, and it has to be built as one rather than
  // borrowed from the menu palette.
  //
  // Forced opaque first: themes may set `menu.background-alpha` below 1,
  // because a desktop menu over a wallpaper looks better slightly translucent,
  // and a card you can see the app through is not a card.
  //
  // Then lifted off the scrim. Painted flat at menu.background the cards were
  // *correct* and invisible: the scrim is that same background colour over a
  // dark app, so an unfocused card matched its surroundings to the byte --
  // sampled at (660,700) the neighbour read #111c18 and so did the empty space
  // beside it. The carousel looked like it held one app when it held three,
  // which is the kind of bug a screenshot shows and a state dump does not.
  readonly property color cardSurface: Qt.tint(
    Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 1),
    Util.alpha(root.textOnSurface, 0.06))
  readonly property color container: Util.alpha(Color.menu.text, 0.08)
  // Measured against the card, which is the most lifted surface a card's
  // title sits on -- readable there means readable on the scrim too.
  readonly property color subdued: Theme.readableOn(root.cardSurface,
                                                   Color.menu.text, 0.55, 4.5)

  // The veil is shared (docs/refactor.md E2); the default ink is this
  // surface's own, which is the half a shared type cannot know (style.md H2).
  component PressVeil: Shared.PressVeil { ink: root.textOnSurface }


  readonly property int iconSize: Style.space(56)

  // Travel that a card has to be dragged up before releasing closes it. Short
  // enough to flick, long enough that a sloppy tap cannot reach it.
  readonly property int dismissTravel: Style.space(90)

  // ----------------------------------------------------------- K. shell apps
  //
  // Settings, Wi-Fi and Bluetooth are windows (docs/gestures.md K1), so they
  // arrive here through ToplevelManager like `foot` does and every branch that
  // used to exist for them is gone: the model, the MRU, the accent border,
  // focusing, closing and the empty-carousel check are one code path again.
  //
  // What is left is decoration. Their app id is "org.quickshell" -- the shell
  // process's own, and Qt has no per-window override (K9) -- so there is no
  // desktop entry to look an icon or a name up in. The plugin that draws the
  // window is asked instead, and it is asked by *handle*: ShellApps.forToplevel
  // compares the toplevel object against each plugin's appWindow.toplevel,
  // which the window itself resolved once when it mapped.
  //
  // This used to be three QtObjects standing in for the three screens, plus a
  // polling Timer to find the plugins, plus a hide-them-all function, plus a
  // `shellAppsRunning` the gestures plugin asked before raising the carousel.
  // All of it existed to answer questions the compositor now answers.
  function shellAppFor(app) {
    return ShellApps.forToplevel(root.shell, app)
  }

  // --------------------------------------------------------------- the model
  //
  // Most-recently-used first, which is the order Android shows and the order a
  // thumb expects: the app you just left is under your finger. ToplevelManager
  // hands them over in creation order, so the ordering is kept here.
  //
  // First is *drawn* rightmost -- the view is laid out right-to-left (E1) --
  // so nothing that reads this list has to know which end of the screen index
  // 0 lands on.
  property var mru: []

  function indexOfToplevel(list, tl) {
    for (var i = 0; i < list.length; i++) if (list[i] === tl) return i
    return -1
  }

  // Everything the carousel can show: the compositor's windows, which since
  // K1 includes this shell's own three screens. One list, and no longer two
  // concatenated.
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

    // And the active one leads, so the card under the thumb is the app the
    // swipe just came out of (E1). activeToplevel reads null here even with a
    // window focused -- the same reason the back gesture had to stop trusting
    // it -- so fall back to the per-toplevel `activated` flag, which is what
    // marks the card below and does track focus.
    //
    // The shell-app branch that used to come first is gone with the stand-ins:
    // a focused Settings is a focused toplevel and answers both of these.
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

  Component.onCompleted: root.rebuildMru()

  // ------------------------------------------------- appId -> desktop entry
  //
  // appLibrary can sort entries and turn an icon name into a source, but it
  // has no lookup by id. Build the index once and rebuild it when the app
  // list changes -- scanning sortedEntries() inside a delegate would be
  // O(apps) per card per frame.
  property var appIdIndex: ({})
  property int appsRevision: 0

  function buildIndex(): void {
    var bump = root.appsRevision
    var map = ({})
    if (!root.shell || !root.shell.appLibrary) { root.appIdIndex = map; return }
    var rows = root.shell.appLibrary.sortedEntries("")
    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i].entry
      if (!entry) continue
      var id = String(entry.id || "").toLowerCase().replace(/\.desktop$/, "")
      if (!id) continue
      if (map[id] === undefined) map[id] = entry
      // Sway reports the app_id an app sets for itself, which is often the
      // last segment of a reverse-DNS desktop id -- org.gnome.Papers maps to
      // an app_id of "papers". Index both, first writer wins so an exact
      // match is never displaced by a suffix collision.
      var tail = id.split(".").pop()
      if (tail && map[tail] === undefined) map[tail] = entry
    }
    root.appIdIndex = map
  }

  Connections {
    target: root.shell ? root.shell.appLibrary : null
    function onAppsChanged() { root.appsRevision++; root.buildIndex() }
  }

  onShellChanged: root.buildIndex()

  function entryFor(appId) {
    if (!appId) return null
    var e = root.appIdIndex[String(appId).toLowerCase()]
    return e === undefined ? null : e
  }

  function iconFor(appId) {
    var entry = root.entryFor(appId)
    if (!entry || !root.shell || !root.shell.appLibrary) return ""
    return root.shell.appLibrary.iconSource(entry.icon)
  }

  function nameFor(app) {
    if (!app) return ""
    // K5. A shell app names itself: there is no desktop entry to look it up
    // in, because its app id is the shell process's own (K9).
    var own = root.shellAppFor(app)
    if (own) return String(own.appWindow.appName || "")
    var entry = root.entryFor(app.appId)
    if (entry && root.shell && root.shell.appLibrary)
      return root.shell.appLibrary.entryName(entry)
    return app.appId || app.title || "Window"
  }

  // K5. The third line: the page a shell app is on, which its own window
  // already carries, and the window title for anything else. A shell app's
  // title is "<name> — <page>", so reading it off the window rather than off
  // the toplevel is what keeps the card from repeating its own name.
  function titleFor(app) {
    if (!app) return ""
    var own = root.shellAppFor(app)
    if (own) return String(own.appWindow.pageTitle || "")
    return String(app.title || "")
  }

  // K5. The glyph a shell app's card wears in place of an icon, or "" for a
  // window, which has a desktop entry to take one from.
  function glyphFor(app) {
    var own = root.shellAppFor(app)
    return own ? String(own.appWindow.glyph || "") : ""
  }

  // ------------------------------------------------------------------ actions
  //
  // activate() is the foreign-toplevel request, which Sway answers by focusing
  // the window and switching to whatever workspace holds it. There is no
  // con_id to dispatch against here and no need for one.
  // One line, for every card. A shell app is a toplevel, so focusing it is
  // whatever focusing any other card is -- which is a sway dispatch and not the
  // foreign-toplevel activate() this used to send. That request does nothing on
  // this compositor, for `foot` as much as for one of this shell's own windows,
  // and had been doing nothing for as long as the carousel has existed; the
  // measurement and the reasoning are in moarchy.gestures' focusToplevel().
  //
  // Nothing is hidden on the way. That used to be an ordering this comment
  // spent a paragraph on -- hide the shell app *before* activating, because
  // dropping an exclusive-focus layer surface made sway re-pick a focus and
  // take the keyboard back off the window just raised. There is no layer
  // surface to drop and no focus to re-pick: switching workspace is all of it.
  function focusApp(app): void {
    if (!app) return
    ShellApps.focusToplevel(root.shell, app)
    root.dismiss()
  }

  // close() is xdg_toplevel.close -- a close *request*, so an editor with
  // unsaved work prompts rather than dies. That is what makes firing it from a
  // flick acceptable, and a shell app takes it like any other window: Qt hides
  // the window and the plugin's own onUnmapped resets its state (K6).
  function closeApp(app): void {
    if (!app) return
    app.close()

    // Drop it from the order immediately rather than waiting for closed(): an
    // app that refuses to quit would otherwise leave a card that has already
    // animated away.
    var next = []
    for (var i = 0; i < root.mru.length; i++)
      if (root.mru[i] !== app) next.push(root.mru[i])
    root.mru = next
    if (next.length === 0) root.goHomeAndDismiss()
  }

  // E6. An empty carousel is not a screen worth standing on -- and with A9
  // (an up-swipe with nothing open does nothing) this is the only way it could
  // ever have no cards, so going home here means the empty state is
  // unreachable and is not built at all. There is deliberately no "clear all"
  // either (E7): one control that closes every open app is one mis-tap from
  // losing all of them, with no undo.
  //
  // Hand the home switch back to the gestures plugin, which owns the
  // workspace logic.
  function goHomeAndDismiss(): void {
    if (root.shell && root.shell.panelLoaders) {
      var loader = root.shell.panelLoaders["moarchy.gestures"]
      if (loader && loader.item && typeof loader.item.run === "function")
        loader.item.run("home")
    }
    root.dismiss()
  }

  // ------------------------------------------------------------ open / close
  function open(payloadJson) {
    // Only one overlay is ever up. Asking the host rather than tracking it
    // here means this still holds when the shade was opened by its own drag
    // and this plugin never heard about it.
    if (root.shell && typeof root.shell.isPluginOpen === "function") {
      if (root.shell.isPluginOpen("moarchy.shade"))
        root.shell.hide("moarchy.shade")
      if (root.shell.isPluginOpen("moarchy.drawer"))
        root.shell.hide("moarchy.drawer")
    }
    root.rebuildMru()
    // An app installed since the shell started has no icon until this. Same
    // deferral the drawer uses: a blocking reload inside open() spins a nested
    // event loop and the surface never becomes visible.
    if (root.shell && root.shell.appLibrary)
      Qt.callLater(function() {
        root.shell.appLibrary.refreshIcons()
        root.buildIndex()
      })
    root.dragging = false
    root.homeHint = 0
    root.progress = 1
    cards.positionViewAtBeginning()
  }

  function close() {
    root.dragging = false
    root.homeHint = 0
    root.progress = 0
  }

  // Every dismissal goes through the host rather than setting `opened`
  // directly, so openPanelIds and this plugin cannot drift apart and leave the
  // next swipe toggling the wrong way.
  function dismiss(): void {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  // Lets the carousel be driven without a finger, which is how the selftest
  // asserts it: omarchy-shell recents state
  IpcHandler {
    target: "recents"

    function state(): string { return root.opened ? "open" : "closed" }

    function progress(): string {
      return Math.round(root.progress * 100) + (root.dragging ? " dragging" : "")
    }

    function retireTrace(): string { return root.retireTrace.join(" ") }

    // F4. Read separately from `progress` because the glitch this exists to
    // catch is the two disagreeing: the carousel flashed to full strength on
    // its way home when this snapped to 0 while progress was still animating
    // out. A single number cannot show that.
    function homeHint(): string {
      return Math.round(root.homeHint * 100) + (root.dragging ? " dragging" : "")
    }

    // The samples the last drag actually produced. Polling progress over IPC
    // cannot see a 300ms gesture; this is the record it left behind.
    function dragTrace(): string { return root.dragTrace.join(" ") }

    // One line per card, so a dismissal is assertable by counting.
    //
    // A shell app prints its plugin id rather than its app id, and that is
    // deliberate: all three carry "org.quickshell" (K9), so the app id names
    // the shell process and not the screen. The plugin id is what every check
    // in the suite greps for and what a person reading the list expects.
    function list(): string {
      var out = []
      for (var i = 0; i < root.mru.length; i++) {
        var app = root.mru[i]
        if (!app) continue
        var own = root.shellAppFor(app)
        out.push((own ? own.pluginId : (app.appId || "?"))
                 + " " + (own ? root.titleFor(app) : (app.title || "")))
      }
      return out.join("\n")
    }

    // E1. Which end of the screen the row starts from, which `list` cannot
    // say: that one is model order and reads the same whether the mirroring
    // happened or not, so on its own it would go green on a layoutDirection
    // that silently did nothing. The centres of the first two cards, in view
    // coordinates. Card 0 is centred either way -- the highlight range sees
    // to that -- so the discriminating number is card 1: left of card 0 when
    // the row is drawn from the right, and right of it when it is not.
    function cardX(): string {
      var out = []
      for (var i = 0; i < 2; i++) {
        var it = cards.itemAtIndex(i)
        out.push(it ? Math.round(it.mapToItem(cards, it.width / 2, 0).x) : "none")
      }
      return out.join(" ")
    }

    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      else root.open("{}")
      return "ok"
    }

    // J1-J4. The shrink is over in a few hundred milliseconds, so like
    // dragTrace this is the record it leaves rather than something a poll
    // could catch mid-gesture.
    function preview(): string {
      return "progress=" + Math.round(root.progress * 100)
           + " armed=" + root.previewArmed
           + " releasing=" + root.previewReleasing
           + " content=" + shot.hasContent
           + " track=" + Math.round(root.previewTrack * 100)
           + " scale=" + Math.round(appPreview.currentScale * 100)
           + " landed=" + Math.round(appPreview.landedScale * 100)
           + " opacity=" + Math.round(appPreview.opacity * 100)
    }

    function close(): string { root.dismiss(); return "ok" }

    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
  }

  PanelWindow {
    id: recentsWindow

    visible: root.progress > 0 || root.previewArmed
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "moarchy-recents"
    WlrLayershell.layer: WlrLayer.Top

    // Ignore, not the drawer's zero-zone Normal, and the difference is the
    // on-screen keyboard.
    //
    // A zero-zone surface is *arranged into* whatever the exclusive surfaces
    // left, which is exactly right for the drawer: its search field needs
    // the keyboard, so the grid reflowing above it is the feature.
    // A switcher has no text field and gets no benefit -- what it got instead
    // was the carousel squashed into the top two thirds of the screen
    // whenever the app behind it happened to have a text field focused.
    // Nothing is wrong in that arrangement; it is the arrangement being
    // applied to the wrong kind of surface.
    //
    // Ignore takes the whole output, the way the shade does, and the keyboard
    // is simply behind it. There is no need to mask the home pill's band back
    // out the way the shade has to: the gesture strip is on Overlay and every
    // Overlay surface sits above every Top one, so the pill stays live over
    // this with no geometry at all. That is what lets one drag carry on past
    // the recents stop into the home band.
    exclusionMode: ExclusionMode.Ignore

    // None, permanently, and that is a decision rather than an oversight. The
    // drawer needs Exclusive for its search field and pays for it: gating
    // keyboardFocus on `opened` there dropped interactivity on the first frame
    // of a close drag, Sway handed focus back to a window, and the focus
    // change cancelled the touch the surface was still holding. A carousel has
    // no text input, so it can sidestep that whole class of bug by never
    // taking focus at all. Touch reaches a layer surface either way.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // One blended quad, its alpha bound straight to the drag -- no opacity on
    // a subtree, which would make the renderer composite the whole sheet
    // off-screen first on a GPU that has nothing spare.
    Rectangle {
      anchors.fill: parent
      // Opaque once it is all the way up, translucent for the whole drag.
      // Half-open, seeing the app through it is what says the sheet is still
      // moving; fully open it is a switcher, and anything showing through is
      // noise -- with a text field focused behind, that noise is a whole
      // on-screen keyboard ghosting under the cards. The home band fades it
      // back out, which is the cue that letting go returns to the wallpaper.
      //
      // J9. Once the preview is carrying the app, this goes opaque ahead of
      // the drag. Otherwise the app is on screen twice -- shrinking in the
      // preview and still full-size behind it -- and the live copy shows
      // around the edges of its own snapshot. Measured on tokyo-night at
      // progress 0.7: the app's list and the whole on-screen keyboard were
      // legible around a preview of themselves.
      color: Util.alpha(Color.background,
                        Math.max(root.progress, appPreview.fadeIn)
                          * (1 - 0.6 * root.homeHint))
    }

    // Tapping the empty space around the cards puts the carousel away and
    // leaves the app you came from focused, the way tapping outside any sheet
    // does.
    MouseArea {
      // no press state (style.md H7): a dismiss scrim. Lighting the whole
      // screen is not feedback, and the carousel leaving is what answers.
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: sheet
      anchors.fill: parent
      // Rides up from below. Translation only: this is a Mali-400 at GLES 2.0,
      // so a `scale` on *this* item costs a re-raster where a `y` costs
      // nothing -- it is a subtree of glyphs and icons, and scaling it
      // re-rasters every one. The home band is signalled the same cheap way --
      // the row keeps travelling upward and the scrim thins -- rather than by
      // scaling the cards down the way Android does.
      //
      // The app preview (J) scales and that is not a contradiction: it is a
      // single textured quad with nothing to re-raster. Measured here, 2026-09-05:
      // a full-screen capture at a fixed scale costs 60fps -> 43-47fps, and
      // animating its scale on top of that costs nothing measurable (44-46fps).
      // The cost is the blit, not the scale, and a shrinking quad blits less.
      y: parent.height * (1 - root.progress) - Style.space(80) * root.homeHint

      ListView {
        id: cards

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -Style.space(14)
        height: Math.round(recentsWindow.height * 0.56)

        orientation: ListView.Horizontal
        model: root.mru
        clip: false
        opacity: 1 - 0.55 * root.homeHint

        // The row is drawn from the right: index 0 -- the app you just left --
        // sits at the right-hand end and older apps run away to the left,
        // which is where Android's overview puts them and where the thumb
        // that raised the carousel already is. Only the painting is mirrored.
        // The model stays most-recent-first, so `recents list`, the accent
        // border and the preview's hand-off to card 0 all read unchanged, and
        // the highlight range below is symmetric about the centre, so the
        // mirroring leaves the centred card centred.
        layoutDirection: Qt.RightToLeft

        // A pager, not a free scroll: one card is always centred, so a flick
        // lands somewhere definite instead of between two apps.
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds

        readonly property int cardWidth: Math.round(recentsWindow.width * 0.62)
        readonly property int gap: Style.space(12)
        // The delegate is one *pitch* wide -- card plus its gap -- and the
        // card is centred inside it. The obvious spelling instead gives the
        // view leftMargin/rightMargin to centre the first and last cards, and
        // that fights StrictlyEnforceRange: the highlight range and the
        // margins each want to decide contentX, and the view settles with one
        // card filling the screen and its neighbours pushed out of sight. A
        // pitch-wide delegate and a pitch-wide range agree on exactly one
        // position per card, which is what makes the next app peek in at the
        // edge -- the affordance that says the row can be paged at all.
        readonly property int pitch: cardWidth + gap

        preferredHighlightBegin: (width - pitch) / 2
        preferredHighlightEnd: (width + pitch) / 2
        spacing: 0

        delegate: Item {
          id: cardSlot
          required property var modelData

          // K5. A card is a window either way; what differs is where its icon
          // and name come from. Non-empty exactly for this shell's own three
          // screens, which have no desktop entry to look one up in (K9).
          readonly property string glyph: root.glyphFor(cardSlot.modelData)
          readonly property bool shellApp: cardSlot.glyph !== ""

          width: cards.pitch
          height: cards.height

          Rectangle {
            id: card
            width: cards.cardWidth
            anchors.horizontalCenter: parent.horizontalCenter
            height: parent.height
            radius: root.radiusTile
            color: root.cardSurface

            // Every card needs an edge, for the same reason it needs a raised
            // fill: this is the only thing separating the one at the screen
            // edge from the space next to it. The app you just left is the one
            // you are most likely to want back, so that one gets the accent
            // and a heavier line.
            border.width: modelData && modelData.activated ? Math.max(2, Style.space(2))
                                                           : Math.max(1, Style.space(1))
            border.color: modelData && modelData.activated
              ? Color.accent : Util.alpha(root.textOnSurface, 0.22)

            // A child of the card and not of the slot, so it takes the card's
            // width rather than the row pitch (docs/style.md H8, E2). Guarded
            // on the drag: once the card is following the finger, the movement
            // is the feedback and a lit card on its way off screen is noise.
            PressVeil {
              anchors.fill: parent
              radius: parent.radius
              on: dismissArea.pressed && !dismissArea.drag.active
            }

            Column {
              anchors.centerIn: parent
              width: parent.width - Style.space(28)
              spacing: Style.space(12)

              Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.iconSize
                height: root.iconSize

                // A window's icon comes from its desktop entry. A shell app
                // has none to come from -- its app id is the shell process's
                // own (K9) -- so it carries its own glyph, and K5 makes it the
                // same one the control that opens it wears. Two items rather
                // than one Image with a fallback: an Image source that resolves
                // to nothing and a glyph are different kinds of thing, and
                // `visible` on each keeps the one that is wrong from painting
                // at all.
                Image {
                  anchors.fill: parent
                  visible: !cardSlot.shellApp
                  // Without sourceSize an SVG rasterises at its natural size
                  // -- 512px squares held for every card.
                  sourceSize: Qt.size(root.iconSize, root.iconSize)
                  asynchronous: true
                  cache: true
                  fillMode: Image.PreserveAspectFit
                  source: cardSlot.shellApp
                    ? "" : root.iconFor(cardSlot.modelData ? cardSlot.modelData.appId : "")
                }

                // Centred on its ink and not on the box the font reserves,
                // for the reason Settings' own header records: a Nerd Font
                // glyph is rarely centred inside its advance, and next to a
                // column of app icons that are centred exactly, an offset one
                // is what the eye picks out.
                Ui.OpticalGlyph {
                  anchors.fill: parent
                  visible: cardSlot.shellApp
                  text: cardSlot.glyph
                  fontFamily: Style.font.family
                  // The slot, not a font step. It sits beside 56px app icons
                  // and has to read as one of them; a glyph's ink fills less
                  // of its em box than an icon fills its square, so matching
                  // the numbers lands it slightly smaller, which is right.
                  fontSize: root.iconSize
                  color: root.textOnSurface
                }
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.nameFor(modelData)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: root.textWeight
                color: root.textOnSurface
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.titleFor(modelData)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.textWeight
                color: root.subdued
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                visible: text.length > 0 && text !== root.nameFor(cardSlot.modelData)
              }
            }

            Behavior on y {
              enabled: !dismissArea.drag.active
              SpringAnimation { spring: 4; damping: 0.4 }
            }
            Behavior on opacity { NumberAnimation { duration: 140 } }
          }

          // Dismiss is vertical, paging is horizontal, so the two axes never
          // have to arbitrate for meaning -- which is exactly what stopped the
          // shade giving its notification cards a swipe-away, where both
          // gestures wanted the same axis as the scroll.
          //
          // `preventStealing` stays false on purpose: that is what lets the
          // enclosing ListView take a horizontal drag off this MouseArea once
          // it passes its own threshold, while a vertical one stays here. A
          // DragHandler cannot do this job -- over a sheet of delegates it
          // gets one translation event for a whole gesture, because the
          // delegates' MouseAreas hold the exclusive grab.
          MouseArea {
            id: dismissArea
            anchors.fill: parent
            preventStealing: false
            drag.target: card
            drag.axis: Drag.YAxis
            // Up only. A downward drag on a card means nothing, and allowing
            // it would let a card be parked below the row.
            drag.minimumY: -cardSlot.height
            drag.maximumY: 0

            onClicked: root.focusApp(cardSlot.modelData)

            onReleased: {
              if (card.y <= -root.dismissTravel) {
                dismissOut.start()
              } else {
                card.y = 0
              }
            }

            onCanceled: card.y = 0
          }

          // Let the card leave before the model drops it, so the row closing
          // the gap reads as a consequence rather than a glitch.
          SequentialAnimation {
            id: dismissOut
            ParallelAnimation {
              NumberAnimation { target: card; property: "y"; to: -cardSlot.height
                                duration: 140; easing.type: Easing.OutCubic }
              NumberAnimation { target: card; property: "opacity"; to: 0; duration: 140 }
            }
            ScriptAction {
              script: {
                root.closeApp(cardSlot.modelData)
                card.y = 0
                card.opacity = 1
              }
            }
          }
        }
      }
    }

    // ------------------------------------------------------------ J. preview
    //
    // Above the sheet, so handing off to card 0 is this fading out to reveal
    // the card already drawn underneath rather than two things swapping.
    // Above the scrim too, so the preview keeps its brightness while the
    // workspace behind it dims (J9) -- the other order makes the preview look
    // like it brightens the screen when it arrives mid-drag.
    //
    // A ScreencopyView handles no input, so sitting on top costs the cards and
    // the dismiss-tap nothing.
    Item {
      id: appPreview
      anchors.fill: parent
      visible: root.previewArmed

      readonly property bool shown:
        root.previewArmed && !root.previewReleasing && shot.hasContent

      // Two opacities, deliberately. `fadeIn` hides the capture's arrival and
      // is animated; `fadeOut` is the hand-off to card 0 and is a straight
      // function of the drag. Folding them into one property with a Behavior
      // would put that animation on every frame of the drag, and the preview
      // would trail the finger instead of following it.
      property real fadeIn: appPreview.shown ? 1 : 0
      Behavior on fadeIn { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

      readonly property real fadeOut:
        Math.max(0, Math.min(1, 1 - (root.progress - 0.82) / 0.18))

      opacity: appPreview.fadeIn * appPreview.fadeOut

      // Where it lands: inside card 0's slot, uniform, fitted to whichever of
      // the card's dimensions runs out first. On this 1:2 panel that is the
      // height, so it settles a little narrower than the card.
      readonly property real landedScale: Math.min(
        cards.cardWidth / Math.max(1, recentsWindow.width),
        cards.height / Math.max(1, recentsWindow.height))

      readonly property real currentScale:
        1 - (1 - appPreview.landedScale) * root.previewTrack

      ScreencopyView {
        id: shot
        anchors.fill: parent
        live: false
        paintCursor: false

        // The whole output, uncropped and unscaled: at track 0 it is
        // pixel-aligned with what is already on screen, which is the entire
        // reason its arrival can be invisible (J4). Cropping the bar and the
        // strip out would cost that alignment for a band the snapshot shares
        // with the screen anyway.
        captureSource: root.previewArmed ? recentsWindow.screen : null

        onHasContentChanged: if (hasContent) root.beginPreviewCatchUp()
      }

      transform: [
        Scale {
          origin.x: appPreview.width / 2
          origin.y: appPreview.height / 2
          xScale: appPreview.currentScale
          yScale: appPreview.currentScale
        },
        // Card 0's centre sits one verticalCenterOffset above the middle of
        // the sheet, so the preview has to arrive there and not at the centre.
        Translate { y: -Style.space(14) * root.previewTrack }
      ]
    }
  }
}
