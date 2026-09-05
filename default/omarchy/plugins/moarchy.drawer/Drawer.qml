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
// So this screen is a search field and a grid, and nothing else. On a screen
// that fits four icons across, a row of controls at the top is a row of apps
// you cannot see.
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
  readonly property color subduedBase: root.mix(
    Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 1), Color.menu.text, 0.08)
  readonly property color subdued: root.readableOn(root.subduedBase,
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

  function open(payloadJson) {
    // Only one of the two overlays is ever up. Asking the host rather than
    // tracking it here means this still holds when the shade was opened by its
    // own drag and this plugin never heard about it.
    if (root.shell && typeof root.shell.isPluginOpen === "function"
        && root.shell.isPluginOpen("moarchy.shade"))
      root.shell.hide("moarchy.shade")

    root.query = ""
    searchField.text = ""
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
      var gap = Math.round(drawerWindow.height - grid.mapToItem(null, 0, grid.height).y + grid.bottomMargin)
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
    // activeFocus rather than the keyboard's actual visibility: the real signal
    // lives on sm.puri.OSK0 over DBus and cannot be read synchronously (the
    // back gesture probes it asynchronously for the same reason). The field
    // holding focus is what causes the keyboard to be up, so it leads the state
    // it stands in for rather than lagging it.
    //
    // Safe against the drag, which was the reason to want it constant. The flip
    // is driven by focus, and focus does not change mid-drag: a close moves it
    // to focusSink only once the sheet is already on its way out, and while
    // typing the height is constant for the whole gesture. closeTravel and the
    // sheet's `y` both read drawerWindow.height and neither sees it move.
    margins.bottom: searchField.activeFocus ? 0 : -root.gestureStrip

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
      radius: Style.space(28)

      Keys.onEscapePressed: root.dismiss()

      // The radius rounds all four corners, so square the bottom two back off
      // rather than leave two notches over the gesture strip.
      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Style.space(28)
        color: root.surface
      }

      // H1, for a drag that starts on empty sheet rather than on an icon.
      // Declared before the handle and the column so it sits *under* them:
      // later siblings take input first, so this only ever sees touches
      // nothing else claimed.
      MouseArea {
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

          Ui.TextField {
            id: searchField
            anchors.left: searchGlyph.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(16)
            placeholderText: "Search apps"
            background: null
            horizontalPadding: 0
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
          height: Math.min(parent.height - y, contentHeight + bottomMargin)
          // Scroll padding, so the last row comes to rest a strip clear of the
          // home pill now that the sheet runs under it (I4). Rows may pass
          // beneath the pill mid-scroll; none may stop there.
          bottomMargin: root.gestureStrip
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
              anchors.fill: parent
              onPressed: mouse => root.sheetPress(this, mouse)
              onPositionChanged: mouse => root.sheetMove(this, mouse)
              onReleased: root.sheetRelease()
              onCanceled: root.sheetCancel()
              onClicked: if (!root.sheetWasDrag) root.launch(entry)
            }
          }
        }
      }
    }
  }

  // Somewhere for active focus to go when the drawer closes. It has to be a
  // real item inside the window -- focus handed to nothing at all leaves Qt
  // believing the text field still has it.
  Item { id: focusSink }

  // Typing on a phone keyboard is slow enough that per-keystroke re-sorting of
  // every desktop entry is affordable, but the icon churn behind it is not.
  Timer {
    id: queryDebounce
    interval: 120
    onTriggered: root.query = searchField.text
  }
}
