// The launch splash: the app's own icon on the wallpaper, from the tap until
// its window appears. Specified in docs/windows.md L1-L8.
//
// ---------------------------------------------------------------------------
// What this replaces
// ---------------------------------------------------------------------------
// Upstream's AppLibrary shows a launch OSD -- a rounded panel reading
// "Launching Files..." with a rocket glyph -- two seconds after the tap, and
// takes it down when a toplevel appears. Two things were wrong with that here.
//
// Two seconds is most of a PinePhone app launch, so the feedback arrived after
// the moment it was for: you tapped, nothing happened, you tapped again, and
// the panel appeared to tell you about the launch you had already given up on.
// And a panel of chrome with a generic glyph is not what a phone shows while an
// app opens; every phone shows the app.
//
// So install/port-4x.sh rewires that path rather than duplicating it: the delay
// drops to zero, the two `omarchy-shell osd` calls go, and `launchIcon` is
// added. All the state still lives on AppLibrary -- which app, whether a
// toplevel arrived, the 15s giving-up timer -- and this plugin is the surface
// that draws it. Nothing here decides when a launch is over.
//
// ---------------------------------------------------------------------------
// Why the surface is the size of the icon
// ---------------------------------------------------------------------------
// The obvious shape is a full-screen transparent sheet with the icon centred in
// it, which is what every other overlay in this repo is. It is the wrong shape
// for this one. A splash must never eat a touch: the phone's only navigation is
// the home pill and the back edge, and both are live while an app is opening.
// A surface sized to its own content cannot swallow anything outside it -- the
// same argument mobileomarchy.gestures makes for its strip -- so L3 holds by
// construction rather than by getting a mask right. The mask is set as well,
// and belt and braces is deliberate here: an app that never opens leaves this
// on screen for fifteen seconds.
//
// A layer surface with no anchor on an axis is centred on that axis by the
// compositor, which is what puts a 108px square in the middle of the screen.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  // Injected by the host in the panel Loader's onLoaded. None of these may be
  // `readonly` or `required`: a plugin is created first and configured
  // afterwards, and either keyword turns that into a silent failure.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
                               || (Quickshell.env("HOME") + "/.local/share/omarchy")
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "mobileomarchy.splash"

  // ------------------------------------------------------------- launch state
  //
  // All of it read off AppLibrary, none of it duplicated. `launchOsdOpen` keeps
  // its upstream name through the port patch on purpose: renaming it would make
  // the patch in install/port-4x.sh bigger than the behaviour it changes, and
  // bigger patches are what break on the next vendored bump.
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property bool launching: root.appLibrary ? root.appLibrary.launchOsdOpen === true : false

  readonly property string iconSource: {
    if (!root.appLibrary) return ""
    var src = root.appLibrary.launchIcon
    if (src === undefined || String(src).length === 0) {
      // Reached when the port patch that fills launchIcon did not apply. A
      // generic icon is a worse splash than the right one and a much better
      // one than an empty square, so L7 still holds.
      try { return String(root.appLibrary.iconSource("")) } catch (e) { return "" }
    }
    return String(src)
  }

  // The fallback outline's colour, off the theme so it recolours with
  // everything else, with a literal only for a shell whose Color singleton
  // failed to load.
  readonly property color placeholder: (typeof Color !== "undefined" && Color.foreground)
                                       ? Color.foreground : "#c0caf5"

  // ------------------------------------------------------------------ sizing
  //
  // Rather more than twice the drawer's grid icon: 96 of a 360px-wide screen,
  // about the fraction a phone splash usually gives its icon. Measured against
  // a capture at 80, which read as a small icon that happened to be centred
  // rather than as a launch. Still leaves the surface (130) well under half the
  // screen -- see the header for why that matters.
  readonly property int iconSize: Style.space(96)
  readonly property int surfaceSize: Math.round(root.iconSize * 1.35)

  // ------------------------------------------------------------------- fade
  //
  // Set on the way in, animated on the way out. The whole complaint about the
  // OSD was that its feedback arrived after the moment it was for; a fade-in
  // would put a slower version of that straight back. Going out is animated so
  // the app that just mapped is not revealed by a jump cut.
  property real fade: 0
  onLaunchingChanged: {
    if (root.launching) {
      fadeOut.stop()
      root.fade = 1
    } else if (root.fade > 0) {
      fadeOut.restart()
    }
  }

  NumberAnimation {
    id: fadeOut
    target: root
    property: "fade"
    to: 0
    duration: 160
    easing.type: Easing.OutCubic
  }

  // --------------------------------------------------------- early finishing
  //
  // A .desktop entry can summon a shell plugin instead of starting a process --
  // mobileomarchy.device is one, and its Exec is `omarchy-shell shell toggle`.
  // No toplevel ever appears for those, so the completion AppLibrary watches
  // for never arrives and this would sit over the screen it was announcing
  // until the 15s timeout. A plugin surface opening is the same event for our
  // purposes: what was asked for is on screen. See L5.
  function finish() {
    if (!root.appLibrary) return
    root.appLibrary.closeLaunchFeedback(root.appLibrary.launchSerial)
  }

  Connections {
    target: root.shell
    ignoreUnknownSignals: true
    function onOpenPanelIdsChanged() {
      if (!root.launching) return
      var open = (root.shell && root.shell.openPanelIds) || ({})
      for (var id in open) {
        if (id !== root.pluginId && open[id] === true) {
          root.finish()
          return
        }
      }
    }
  }

  // Lets the splash be asserted without a camera, which is how
  // `mobileomarchy-selftest --launch` proves L1-L7.
  IpcHandler {
    target: "splash"

    function state(): string { return root.launching ? "open" : "closed" }
    function icon(): string { return root.iconSource }

    // What is actually on the surface, which is not the same question as what
    // the icon source is: a source that resolves to a file Qt cannot load
    // draws nothing at all. L7 is about the pixels, so it asks about those.
    function drawn(): string {
      // The surface first. Image.status stays Ready after the splash comes
      // down -- the component is not destroyed, only hidden -- so without this
      // `drawn` answers about the last launch instead of about the screen, and
      // reported an icon over a capture that plainly had none.
      if (!splashWindow.visible) return "down"
      if (appIcon.status === Image.Ready) return "icon " + root.iconSource
      if (fallbackIcon.visible) return "fallback"
      return "nothing"
    }

    // Reported from the properties the surface is built from rather than from
    // the window, which has no size at all while it is unmapped -- a geometry
    // that reads 0 when the splash is down would make the L2 check pass for
    // the wrong reason.
    function geometry(): string {
      // The layer is read back off the window rather than restated as a
      // literal, so a regression to Top fails a check instead of waiting for
      // someone to take a screenshot over a fullscreen app (L2a).
      var layer = "?"
      try {
        layer = splashWindow.WlrLayershell.layer === WlrLayer.Overlay ? "overlay"
              : splashWindow.WlrLayershell.layer === WlrLayer.Top ? "top"
              : String(splashWindow.WlrLayershell.layer)
      } catch (e) { layer = "?" }
      return "w=" + root.surfaceSize + " h=" + root.surfaceSize
           + " icon=" + root.iconSize + " layer=" + layer
    }
  }

  PanelWindow {
    id: splashWindow

    visible: root.fade > 0

    // Deliberately unanchored: see the header. implicitWidth/Height are what
    // the compositor is given, and with no anchor on either axis it centres
    // the result on the output.
    implicitWidth: root.surfaceSize
    implicitHeight: root.surfaceSize
    color: "transparent"

    WlrLayershell.namespace: "mobileomarchy-splash"

    // Overlay, not Top, and that was measured rather than chosen. Sway renders
    // a fullscreen view ABOVE the top layer -- only Overlay stays in front of
    // one -- so on Top this vanished behind the first fullscreen window it met.
    // A capture taken with `splash state` reporting `open` on both sides of it
    // showed the app underneath and no icon at all. On a phone whose own
    // pinephone.conf fullscreens every TUI, a splash that any fullscreen app
    // can hide is not a splash.
    //
    // The usual reason to prefer Top -- staying under the gesture strip and the
    // shade -- costs nothing here. Ordering within Overlay is map order and
    // this maps last, so it draws over both; but it is a 130px square in the
    // middle of the screen, the pill is at the bottom edge, and the shade
    // cannot be open during a launch because launches come from the drawer.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Reserve nothing. An exclusive zone here would reflow every tiled window
    // twice per launch, which is the opposite of what a splash is for.
    exclusionMode: ExclusionMode.Ignore

    // One pixel, not an empty region, and the difference is the whole point.
    // An empty mask reads as "no input" and means the opposite: Qt treats an
    // empty mask as *unset*, and an unset input region is the entire surface.
    // moarchy-keyboard hit this in src/panel.cpp and carries the same
    // one-pixel workaround. So the square passes touch through everywhere
    // except its own top-left pixel -- the second of the two guarantees
    // behind L3, and the reason the first one (sizing the surface to the
    // icon) is not allowed to be the only one.
    mask: Region { x: 0; y: 0; width: 1; height: 1 }

    Image {
      id: appIcon

      anchors.centerIn: parent
      width: root.iconSize
      height: root.iconSize
      // Without sourceSize an SVG rasterises at its natural size. The drawer
      // learned this holding 512px squares for every visible app.
      sourceSize: Qt.size(root.iconSize, root.iconSize)
      fillMode: Image.PreserveAspectFit
      // Synchronous on purpose: this image exists to be on screen in the frame
      // the tap produced, and an async load hands back an empty square first.
      asynchronous: false
      cache: true
      source: root.iconSource
      opacity: root.fade
    }

    // The fallback, for an entry whose icon resolves to nothing. Drawn rather
    // than shipped as a file, because there is no generic icon to ship to:
    // application-x-executable, applications-other and system-run all exist on
    // this image only inside AdwaitaLegacy's mimetypes/ and legacy/
    // directories, which the active theme does not inherit -- so Qt's themed
    // lookup comes back empty and upstream's iconSource("") fallback resolves
    // to "". An outline in the theme's own foreground is never missing, never
    // the wrong colour, and costs no asset.
    Rectangle {
      id: fallbackIcon

      anchors.centerIn: parent
      width: root.iconSize
      height: root.iconSize
      // Not Ready covers both halves of the problem: no source at all, and a
      // source pointing at something Qt could not decode.
      visible: appIcon.status !== Image.Ready
      radius: Math.round(root.iconSize / 5)
      color: "transparent"
      border.width: Math.max(2, Math.round(root.iconSize / 24))
      border.color: root.placeholder
      opacity: root.fade * 0.7
      scale: appIcon.scale
    }

    // L8. Slow, small, and on the transform only -- one textured quad being
    // scaled is what a Mali-400 can afford, and it is what says the launch is
    // still running rather than stuck.
    SequentialAnimation {
      running: splashWindow.visible
      loops: Animation.Infinite
      NumberAnimation {
        target: appIcon; property: "scale"
        from: 1.0; to: 1.06; duration: 900; easing.type: Easing.InOutSine
      }
      NumberAnimation {
        target: appIcon; property: "scale"
        to: 1.0; duration: 900; easing.type: Easing.InOutSine
      }
    }
  }
}
