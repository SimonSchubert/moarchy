// The recents carousel: what a swipe up from the bottom strip opens while an
// app is on screen.
//
// ---------------------------------------------------------------------------
// Where this sits in the bottom gesture
// ---------------------------------------------------------------------------
// One upward drag from the home pill passes through two stops. mobileomarchy
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

  readonly property string pluginId: "mobileomarchy.recents"

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
  readonly property color subdued: root.readableOn(root.cardSurface,
                                                   Color.menu.text, 0.55, 4.5)

  // WCAG 2.1 relative luminance and contrast, and a linear composite, so the
  // secondary text colour can be computed per theme instead of guessed.
  //
  // A constant alpha cannot do this job. Measured across all 22 themes'
  // colors.toml, foreground at 0.7 over a lifted card falls below AA in six of
  // them and reaches 3.14:1 on rose-pine; the alpha that clears AA everywhere
  // is 0.9, and at 0.9 a subtitle is within ten percent of its label and the
  // hierarchy the alpha existed to create is gone. Calibrating on Catppuccin --
  // which passes at 5.44 -- is exactly how a single number looks correct and
  // is not. (Method and measurements from the settings work, 4ff1e7f.)
  //
  // `container` is painted with alpha over the surface, so the background the
  // text actually lands on is the blend of the two: measuring against the
  // surface alone overstates the contrast by the width of that lift.
  function luminance(c) {
    function chan(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b)
  }

  function contrastRatio(a, b) {
    var la = root.luminance(a), lb = root.luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  function mix(bg, fg, a) {
    return Qt.rgba(bg.r + a * (fg.r - bg.r),
                   bg.g + a * (fg.g - bg.g),
                   bg.b + a * (fg.b - bg.b), 1)
  }

  // Start quiet and walk toward the foreground only until the pair clears the
  // ratio, so every theme ends up as quiet as it can afford.
  function readableOn(bg, fg, from, minRatio) {
    for (var a = from; a < 1.0; a += 0.01) {
      var c = root.mix(bg, fg, a)
      if (root.contrastRatio(c, bg) >= minRatio) return c
    }
    return fg
  }


  readonly property int iconSize: Style.space(56)

  // Travel that a card has to be dragged up before releasing closes it. Short
  // enough to flick, long enough that a sloppy tap cannot reach it.
  readonly property int dismissTravel: Style.space(90)

  // ----------------------------------------------------------- K. shell apps
  //
  // Settings is a screen you spend time in rather than a sheet you summon and
  // dismiss in one motion, so it gets a card (docs/gestures.md K). It is not a
  // Wayland toplevel and cannot be made into one -- it is a layer surface this
  // same process draws -- so it enters the model as a stand-in that answers
  // the questions a card asks of a window: appId, title, activated, and now
  // whether it is a window at all.
  //
  // A QtObject and not a plain JS record, deliberately. `title` and
  // `activated` are read straight out of delegate bindings, and a plain
  // object's fields do not notify: the card would show whichever page
  // Settings was on when the row was last rebuilt, and would keep its accent
  // border after the screen had gone.
  //
  // One of these, not a registry, and K11 says so out loud: a mechanism with a
  // single user reads as an oversight otherwise, and adding a second shell app
  // should be a decision rather than a discovery that the machinery allows it.
  property var settingsItem: null

  function resolveSettings(): void {
    var loader = root.shell && root.shell.panelLoaders
      ? root.shell.panelLoaders["mobileomarchy.settings"] : null
    root.settingsItem = loader && loader.item ? loader.item : null
  }

  // Polled, not bound, and not resolved once at startup either. `panelLoaders`
  // is a plain map, so indexing it inside a binding takes a dependency on the
  // map and none at all on a key that appears later -- and Settings does
  // appear later: plugins are constructed in shell.json order and it is listed
  // after this one. The `running` binding stops the timer the moment it
  // resolves, and starts it again if the plugin is ever unloaded.
  Timer {
    id: settingsProbe
    interval: 250
    repeat: true
    triggeredOnStart: true
    running: root.settingsItem === null
    onTriggered: root.resolveSettings()
  }

  QtObject {
    id: settingsApp

    readonly property bool shellApp: true
    readonly property string appId: "mobileomarchy.settings"
    readonly property string name: "Settings"

    // K2. The same gear the shade's button that opens it wears. One character
    // of a Nerd Font, invisible in an editor that has no such font: U+E615,
    // nf-seti-config.
    readonly property string glyph: ""

    // K1. Summoned and not yet closed, which outlives any number of hides.
    readonly property bool running: !!(root.settingsItem && root.settingsItem.running)

    // What puts the accent border on this card, and what makes it lead.
    // Settings takes exclusive keyboard focus while it is up, so sway
    // deactivates the window underneath and nothing competes for the mark.
    readonly property bool activated: !!(root.settingsItem && root.settingsItem.opened)

    // K2, K5. The page it will come back to. At the root this is "Settings",
    // which the delegate already suppresses for being the card's own name.
    readonly property string title:
      root.settingsItem ? String(root.settingsItem.pageTitle || "") : ""

    onRunningChanged: root.rebuildMru()
    onActivatedChanged: root.rebuildMru()
  }

  // A9/K1, asked by the gestures plugin when it needs to know whether the
  // strip has a carousel worth raising. Answered here so that "what counts as
  // an app" is decided in exactly one place.
  readonly property bool shellAppsRunning: settingsApp.running

  // --------------------------------------------------------------- the model
  //
  // Most-recently-used first, which is the order Android shows and the order a
  // thumb expects: the app you just left is under your finger. ToplevelManager
  // hands them over in creation order, so the ordering is kept here.
  property var mru: []

  function indexOfToplevel(list, tl) {
    for (var i = 0; i < list.length; i++) if (list[i] === tl) return i
    return -1
  }

  // Everything the carousel can show: the compositor's windows, and any shell
  // app that is running (K1). One list, so nothing below needs to know which
  // kind of thing it is ranking.
  function liveApps() {
    var windows = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    var out = []
    for (var i = 0; i < windows.length; i++) out.push(windows[i])
    if (settingsApp.running) out.push(settingsApp)
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
    // A shell app on screen leads, and is asked before the singleton rather
    // than after it: sway deactivates the window under an exclusive-focus
    // layer surface, but activeToplevel has been seen to answer with one
    // anyway, and that stale answer would put the accent on the app Settings
    // is covering rather than on Settings.
    var active = settingsApp.activated ? settingsApp : ToplevelManager.activeToplevel
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

  onShellChanged: {
    root.buildIndex()
    root.resolveSettings()
  }

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
    // K2. A shell app names itself: there is no desktop entry to look it up
    // in, because there is no .desktop file -- it is a surface we draw.
    if (app.shellApp) return String(app.name || "")
    var entry = root.entryFor(app.appId)
    if (entry && root.shell && root.shell.appLibrary)
      return root.shell.appLibrary.entryName(entry)
    return app.appId || app.title || "Window"
  }

  // ------------------------------------------------------------------ actions
  //
  // activate() is the foreign-toplevel request, which Sway answers by focusing
  // the window and switching to whatever workspace holds it. There is no
  // con_id to dispatch against here and no need for one.
  function focusApp(app): void {
    if (!app) return

    if (app.shellApp) {
      // K5. Resume rather than reopen: the page it was hidden on is the page
      // it comes back to. A plain summon would rebuild the stack at the root.
      if (root.shell && typeof root.shell.summon === "function")
        root.shell.summon(app.appId, JSON.stringify({ resume: true }))
      root.dismiss()
      return
    }

    // K9, and in this order. A card that focuses a window must not hand it
    // over with a full-screen sheet still drawn on top -- and hiding *after*
    // the activate() would take keyboard focus back off the window we had
    // just raised, because dropping an exclusive-focus layer surface makes
    // sway re-pick a target.
    root.hideShellApps()
    app.activate()
    root.dismiss()
  }

  // K4, K9. Off screen, still running: the card stays and the page stack below
  // it is left standing. shell.hide() is the whole implementation -- it lands
  // on the plugin's close(), which is deliberately the hiding one, while
  // quit() is the closing one.
  function hideShellApps(): void {
    if (!settingsApp.running || !settingsApp.activated) return
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(settingsApp.appId)
  }

  // close() is xdg_toplevel.close -- a close *request*, so an editor with
  // unsaved work prompts rather than dies. That is what makes firing it from a
  // flick acceptable.
  function closeApp(app): void {
    if (!app) return

    if (app.shellApp) {
      // K6. quit(), not the hide() above: the card goes and the page stack
      // resets, so the next opening is a fresh one at the root. There is no
      // close *request* to make of our own surface and nothing it could
      // prompt about, so unlike a window this can never be refused -- which is
      // why the removal below is unconditionally right for it.
      if (root.settingsItem && typeof root.settingsItem.quit === "function")
        root.settingsItem.quit()
    } else {
      app.close()
    }

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
      var loader = root.shell.panelLoaders["mobileomarchy.gestures"]
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
      if (root.shell.isPluginOpen("mobileomarchy.shade"))
        root.shell.hide("mobileomarchy.shade")
      if (root.shell.isPluginOpen("mobileomarchy.drawer"))
        root.shell.hide("mobileomarchy.drawer")
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

    // One line per card, so a dismissal is assertable by counting. A shell
    // app prints its plugin id and the page it is on (K1, K2), which is what
    // makes "the card is still there after going home" checkable without a
    // finger.
    function list(): string {
      var out = []
      for (var i = 0; i < root.mru.length; i++) {
        var app = root.mru[i]
        if (app) out.push((app.appId || "?") + " " + (app.title || ""))
      }
      return out.join("\n")
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

    WlrLayershell.namespace: "mobileomarchy-recents"
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

          // K. A card is either a compositor window or one of this shell's own
          // screens. Read once here rather than tested in each binding below.
          readonly property bool shellApp:
            !!(cardSlot.modelData && cardSlot.modelData.shellApp)

          width: cards.pitch
          height: cards.height

          Rectangle {
            id: card
            width: cards.cardWidth
            anchors.horizontalCenter: parent.horizontalCenter
            height: parent.height
            radius: Style.space(20)
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

            Column {
              anchors.centerIn: parent
              width: parent.width - Style.space(28)
              spacing: Style.space(12)

              Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.iconSize
                height: root.iconSize

                // A window's icon comes from its desktop entry. A shell app
                // has none to come from -- there is no .desktop file for a
                // surface this process draws -- so it carries its own glyph,
                // and K2 makes it the same one the control that opens it
                // wears. Two items rather than one Image with a fallback: an
                // Image source that resolves to nothing and a glyph are
                // different kinds of thing, and `visible` on each keeps the
                // one that is wrong from painting at all.
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
                  text: cardSlot.shellApp && cardSlot.modelData
                    ? String(cardSlot.modelData.glyph || "") : ""
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
                color: root.textOnSurface
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: modelData ? (modelData.title || "") : ""
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
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
