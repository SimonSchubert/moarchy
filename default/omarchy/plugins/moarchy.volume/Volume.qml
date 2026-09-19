// The volume panel: the vertical track the hardware rocker raises, with mute
// under it. Specified in docs/volume.md V1-V15.
//
// ---------------------------------------------------------------------------
// Why this watches the sink instead of being told
// ---------------------------------------------------------------------------
// Upstream's OSD (omarchy.osd) is a card at the bottom of the screen and it is
// told: `omarchy-osd -i volume -p 40` sends it a number over IPC, and every
// caller that moves the volume has to remember to send one. That is a second
// thing to keep in step with the first, and on this phone it was never wired at
// all -- the rocker went straight to `wpctl` and nothing was drawn.
//
// So the wiring here is the other way round (V3). `moarchy-volume` moves the
// sink and stops; this plugin binds the sink and raises itself when what it is
// bound to changes. Three things follow that are not extra code:
//
//   - The rocker works with the shell down or too busy to answer an IPC call.
//     A missed call costs the feedback, never the control.
//   - Every other way the volume moves raises the same panel: an Android app
//     under Waydroid, `wpctl` over ssh, a Bluetooth headset's own buttons.
//   - The number on screen is the sink's, not a copy of it that arrived
//     separately and can be stale.
//
// The cost is one latch. A sink that has just appeared writes its volume as it
// binds, and a panel raised by that would greet the phone at login -- so
// changes are ignored for 800ms after the audio object changes identity.
//
// ---------------------------------------------------------------------------
// Why it is a panel and not a sheet
// ---------------------------------------------------------------------------
// It puts nothing away and nothing puts it away (V15). Sheet.js is read here
// for exactly one question -- is the control center open, in which case the control center's own
// slider is already showing the change (V12) -- and never to cover anything.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui as Ui
import "../moarchy.common/Sheet.js" as Sheet
import "../moarchy.common" as Shared

Item {
  id: root

  // Injected by the host after construction, and not `readonly` or `required` --
  // see the app drawer, which also says why this is the only one declared (J8).
  property var shell: null

  readonly property string pluginId: "moarchy.volume"

  // ------------------------------------------------------------- the sink
  //
  // The same two lines the control center carries. `audio` is pulled out as its own
  // property because it is what the Connections below attach to: the node
  // survives a default-sink change and the audio object does not.
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var audio: (root.sink && root.sink.audio) ? root.sink.audio : null
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }

  readonly property bool hasSink: root.audio !== null
  readonly property real level: root.audio
    ? Math.max(0, Math.min(1, root.audio.volume)) : 0
  readonly property bool muted: root.audio ? root.audio.muted === true : false

  // What is drawn: the finger while it is down, the sink the rest of the time.
  // A round trip through PipeWire is fast and it is not free, and a track that
  // lags the thumb by a frame reads as a track that is fighting it.
  readonly property real shown: root.dragging ? root.dragValue : root.level

  // V6. Named rather than picked as a glyph inline, because `volume level`
  // reports the name -- a check can then assert the state without knowing
  // which codepoint this font draws it with.
  readonly property string glyphName: (!root.hasSink || root.muted || root.shown <= 0)
    ? "mute"
    : root.shown <= 0.33 ? "low"
    : root.shown <= 0.66 ? "medium" : "high"
  // What each one draws, measured out of the font rather than taken from the
  // codepoint's name -- the four are not adjacent and the two either side of
  // them are a knot and a walking man:
  //
  //   F075F  speaker with a cross     mute   (upstream's audio panel uses it)
  //   F057F  speaker, no waves        low
  //   F0580  speaker, one wave        medium
  //   F057E  speaker, two waves       high   (the control center's volume slider)
  //
  // Which is Android's own ladder, including the bare cone at the quiet end.
  readonly property string glyph: root.glyphName === "mute" ? "󰝟"
    : root.glyphName === "low" ? "󰕿"
    : root.glyphName === "medium" ? "󰖀" : "󰕾"

  // ------------------------------------------------------------- geometry
  //
  // Right edge, vertically centred: the thumb of the hand already holding the
  // phone is at that edge, which is the whole of Android's reasoning and it
  // holds here.
  readonly property int glyphSlot: Math.round(Style.font.iconLarge * 1.35)
  readonly property int tapSlot: Math.max(Style.space(44), root.glyphSlot)

  readonly property int trackWidth: root.tapSlot
  readonly property int trackHeight: Style.space(180)
  readonly property int pad: Style.space(6)
  readonly property int gap: Style.space(8)

  // The circle is the control center's round button, so the density preference reshapes
  // this panel with the rest of the phone. What it *answers* in is a slot of
  // its own (style.md E4, E5) rather than a target grown into the gap: the gap
  // is 8, so growing reaches 44 on the roomy preset and stops at 40 on the
  // compact one, and a control that meets the floor at one density and misses
  // it at the other is the failure E1 exists to prevent.
  readonly property int muteSize: ui.controlCenterRound
  readonly property int muteSlot: Math.max(root.tapSlot, root.muteSize)

  readonly property int cardWidth: root.trackWidth + root.pad * 2
  readonly property int cardHeight:
    root.pad * 2 + root.trackHeight + root.gap + root.muteSlot

  // The surface is the card plus the margin it holds off the edge, and it is
  // named here rather than read back off the window: `panel.width` is 0 until
  // the window has mapped, and both the slide and the geometry report are
  // computed from it in states where the window has not (V4).
  readonly property int surfaceWidth: root.cardWidth + root.edgeMargin

  // V10. moarchy.gestures' own edge band, duplicated rather than read across
  // plugins for the reason the control center duplicates it: this surface has to clear
  // the edge even in a session where the gestures plugin failed to load. A card
  // sitting on the band would take the workspace overview swipe for the three seconds it
  // is up, and a gesture that works except just after a volume press is worse
  // than one that never worked.
  readonly property int edgeMargin: Style.space(16)

  // ---------------------------------------------------------------- shape
  Shared.UiFile { id: ui }
  readonly property int radiusCard: ui.radiusCard

  // -------------------------------------------------------------- colours
  //
  // The popup roles, like the control center: this is a transient surface over an app,
  // not a screen. C2's six, and `surface` is drawn nearly opaque -- the card
  // sits over whatever was playing, and a translucent one over video is a
  // control you cannot read at exactly the moment you reach for it.
  readonly property color surface: Color.popups.background
  readonly property color textOnSurface: Color.popups.text
  readonly property color container: Util.alpha(Color.popups.text, 0.08)
  readonly property color containerHigh: Util.alpha(Color.popups.text, 0.14)
  readonly property color accent: Color.accent
  readonly property color textOnAccent: Color.background

  // The veil is shared (docs/refactor.md E2); the default ink is this
  // surface's own, which is the half a shared type cannot know (style.md H2).
  component PressVeil: Shared.PressVeil { ink: root.textOnSurface }

  // ----------------------------------------------------------- open state
  property bool opened: false

  // V7. Android's interval. Restarted by every key press and every touch,
  // because both arrive here as a change to the thing this is bound to.
  Timer {
    id: hideTimer
    interval: 3000
    onTriggered: root.opened = false
  }

  // V13. The unmap is a timer and not the end of the slide. With the panel
  // blanked the render loop stops, animations stop with it, and a window kept
  // mapped until an animation finished would still be there when the screen
  // came back. A QTimer runs on the event loop and does not care.
  Timer {
    id: closeHold
    interval: 220
  }

  function raise(): void {
    if (!root.hasSink) return          // V14
    if (root.controlCenterOpen()) return       // V12
    root.opened = true
    hideTimer.restart()
  }

  function dismiss(): void {
    hideTimer.stop()
    root.opened = false
  }

  onOpenedChanged: if (!root.opened) closeHold.restart()

  // B1/I2: the id lives in Sheet.js and this asks it a question. Nothing is
  // covered here -- see the header.
  function controlCenterOpen(): bool {
    return !!(root.shell && typeof root.shell.isPluginOpen === "function"
              && root.shell.isPluginOpen(Sheet.CONTROL_CENTER))
  }

  // --------------------------------------------------------- the latch
  //
  // Disarmed whenever the audio object changes identity -- at startup, and on a
  // default-sink switch -- so the volume it publishes as it binds is read and
  // not announced.
  property bool armed: false

  onAudioChanged: {
    root.armed = false
    if (root.audio) armTimer.restart()
  }

  Timer {
    id: armTimer
    interval: 800
    onTriggered: root.armed = true
  }

  Connections {
    target: root.audio
    ignoreUnknownSignals: true
    function onVolumeChanged() { root.sinkMoved() }
    function onMutedChanged() { root.sinkMoved() }
  }

  function sinkMoved(): void {
    if (!root.armed) return
    root.raise()
  }

  // ------------------------------------------------------- the key stamp
  //
  // V1a. The sink is not the whole story, and the gap is the case this surface
  // was built for: at 100% a press of the up key sets the volume to 100%,
  // PipeWire publishes nothing because nothing changed, and a panel that only
  // watches the sink stays down -- the rocker reading as broken, again, this
  // time with a surface installed to say otherwise. The same at 0 going down.
  //
  // So `moarchy-volume` writes a timestamp and this watches the path. It is
  // still not being *told* in the sense V3 rules out: nothing is sent, nothing
  // is waited on, and a shell that is not running leaves an unread file rather
  // than a command that failed.
  //
  // `keyStampSeen` is the same latch as `armed`, one trigger along: FileView
  // loads the file once when the shell starts, and a panel that greeted every
  // login would be the bug the sink's latch already exists to prevent.
  property bool keyStampSeen: false

  FileView {
    id: keyStamp

    path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
          + "/moarchy/volume-key"
    watchChanges: true
    printErrors: false

    onLoaded: {
      if (!root.keyStampSeen) { root.keyStampSeen = true; return }
      root.raise()
    }
    // Absent is the normal state until the first press ever. Latch anyway, so
    // the press that creates it is a press and not a first sighting.
    onLoadFailed: root.keyStampSeen = true
    onFileChanged: Qt.callLater(function () { keyStamp.reload() })
  }

  // ------------------------------------------------------------ the drag
  //
  // V8. Live, like the control center's volume slider and unlike its brightness one:
  // the sink is set in-process and is free to follow a finger, where
  // brightness forks a process per write.
  property bool dragging: false
  property real dragValue: 0
  property int dragCommits: 0
  property real dragFrom: 0

  function setLevel(v: real): void {
    root.dragValue = Math.max(0, Math.min(1, v))
    root.dragCommits += 1
    if (root.audio) root.audio.volume = root.dragValue
    // Deliberately not an unmute. A drag while muted sets what unmuting will
    // return to, and the mute button is one tap below the thumb (V9).
    root.raise()
  }

  function toggleMute(): void {
    if (!root.audio) return
    root.audio.muted = !root.audio.muted
  }

  // ---------------------------------------------------------------- IPC
  IpcHandler {
    target: "volume"

    function state(): string { return root.opened ? "open" : "closed" }

    // Raising by hand, for a check that wants the surface without moving
    // anybody's volume. `suppressed` and not `closed`: the two reasons it
    // refuses (no sink, control center open) are states, and a caller that cannot tell
    // them from a panel that opened and closed again learns nothing.
    function show(): string { root.raise(); return root.opened ? "open" : "suppressed" }
    function hide(): string { root.dismiss(); return "closed" }

    function level(): string {
      return "level=" + Math.round(root.shown * 100)
           + " muted=" + (root.muted ? "yes" : "no")
           + " glyph=" + root.glyphName
           // V5. What the track would draw, which at zero is nothing. Read off
           // the level and NOT off `fill.visible`: `visible` is inherited, so
           // with the panel down that reads false and the report would say the
           // track is empty at every volume -- a check run from a closed panel
           // would then pass on a fill that was never bound to anything.
           + " fill=" + (root.shown > 0 ? Math.round(fill.height) : 0)
           + " sink=" + (root.hasSink ? "yes" : "none")
    }

    // Logical px, and the card's position on the *screen* rather than in its
    // own surface -- a plugin's surface coordinates are not screen coordinates,
    // and every tap this file has ever been checked with was aimed at a rect
    // that came out of here (style.md J).
    function geometry(): string {
      // The screen off the window if it has one, off the shell if the window
      // has never mapped: this is read with the panel *down* -- that is the
      // only state a check can measure from and then watch it arrive -- and a
      // report of 0x0 would make every aimed touch land in the corner.
      var scr = panel.screen
        || ((Quickshell.screens && Quickshell.screens.length > 0) ? Quickshell.screens[0] : null)
      var sw = scr ? scr.width : 0
      var sh = scr ? scr.height : 0
      // Where the card sits when it is in, not where it is this frame. Parked
      // off the right edge with the panel down, `card.x` is the surface's own
      // width and the report would say the card is off screen -- true, and
      // useless to anything aiming a finger at it.
      var cx = sw - root.surfaceWidth
      var cy = Math.round((sh - root.cardHeight) / 2)
      var layer = "?"
      try {
        layer = panel.WlrLayershell.layer === WlrLayer.Overlay ? "overlay"
              : panel.WlrLayershell.layer === WlrLayer.Top ? "top"
              : String(panel.WlrLayershell.layer)
      } catch (e) { layer = "?" }
      return "card=" + cx + "," + cy + " " + root.cardWidth + "x" + root.cardHeight
           + " track=" + (cx + root.pad) + "," + (cy + root.pad)
           + " " + root.trackWidth + "x" + root.trackHeight
           // The slot and not the circle: this is the rect a tap has to land
           // in, and the circle inside it is 4px smaller on every side.
           + " mute=" + (cx + root.pad + Math.round((root.trackWidth - root.muteSlot) / 2))
           + "," + (cy + root.pad + root.trackHeight + root.gap)
           + " " + root.muteSlot + "x" + root.muteSlot
           + " margin=" + root.edgeMargin
           + " screen=" + sw + "x" + sh
           // How far in the card actually is, 0..100, so a check can tell a
           // card at rest from one mid-slide without watching the pixels.
           + " shown=" + Math.round(card.slide * 100)
           + " layer=" + layer
    }

    function drag(): string {
      return "commits=" + root.dragCommits
           + " from=" + Math.round(root.dragFrom * 100)
           + " to=" + Math.round(root.dragValue * 100)
           + " dragging=" + (root.dragging ? "yes" : "no")
    }

    // The mute button without a finger, so V9's two halves can be told apart:
    // a tap that misses and a toggle that does nothing look identical from the
    // outside.
    function muteTap(): string { root.toggleMute(); return root.muted ? "muted" : "unmuted" }

    function ping(): string { return "ok" }
  }

  // -------------------------------------------------------------- surface
  PanelWindow {
    id: panel

    visible: root.opened || closeHold.running

    // Anchored on one edge only: with no anchor on the other axis the
    // compositor centres the surface on it, which is what puts the card
    // halfway down the screen without this file knowing the screen's height.
    anchors.right: true
    implicitWidth: root.surfaceWidth
    implicitHeight: root.cardHeight
    color: "transparent"

    WlrLayershell.namespace: "moarchy-volume"

    // Overlay, for the splash's reason: sway renders a fullscreen view above
    // the Top layer, so a volume press over a fullscreen video would otherwise
    // move the volume and show nothing.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // V11. An exclusive zone here would reflow every tiled window twice per
    // key press.
    exclusionMode: ExclusionMode.Ignore

    // V10. The card and nothing else, and it follows the card as it slides in:
    // an input region that stayed where the card will be would eat touches
    // through a surface that is not there yet. Never empty while the window is
    // mapped -- Qt reads an empty mask as *unset*, and an unset input region is
    // the whole surface (the splash carries the same note).
    mask: Region {
      x: Math.round(card.x)
      y: 0
      width: root.cardWidth
      height: root.cardHeight
    }

    // G4. One translation, no opacity: the renderer would composite the whole
    // subtree off-screen to fade it, and this is a Mali-400.
    Rectangle {
      id: card

      width: root.cardWidth
      height: root.cardHeight
      x: Math.round((1 - card.slide) * root.surfaceWidth)
      radius: root.radiusCard
      color: Util.alpha(root.surface, 0.97)

      property real slide: root.opened ? 1 : 0
      Behavior on slide {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
      }

      // ------------------------------------------------------- the track
      Rectangle {
        id: track

        x: root.pad
        y: root.pad
        width: root.trackWidth
        height: root.trackHeight
        // D1: the tile radius, capped at half the short side, so Large is a
        // pill and Square is a rectangle.
        radius: ui.radiusOn(width)
        color: root.container

        Rectangle {
          id: fill

          anchors.bottom: parent.bottom
          width: parent.width
          // V5. Not drawn at all at zero -- an empty track is what silence
          // looks like -- and never shorter than the corner diameter once it
          // is. A rounded fill shorter than its own radius cannot keep the
          // track's corners: its square bottom edge paints outside the
          // rounded outline it sits in, which reads as a rendering fault. The
          // control center's slider carries the same floor on its own axis, and
          // Android's own track has it too: its smallest visible fill is
          // about a third of the bar for exactly this reason.
          visible: root.shown > 0
          height: Math.max(parent.radius * 2, parent.height * root.shown)
          radius: parent.radius
          // V9. Muted keeps the height and loses the colour, so what unmuting
          // returns to stays on screen.
          color: root.muted ? root.containerHigh : root.accent

          // G5. Off while the finger is driving it, or the animation and the
          // thumb fight and the thumb loses by one frame, every frame.
          Behavior on height {
            enabled: !root.dragging
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }
        }

        PressVeil {
          anchors.fill: parent
          radius: parent.radius
          on: trackArea.pressed
        }

        // Tap-to-set as well as drag, which is the same control: the value is
        // written on the press, so a tap is a drag of zero length.
        MouseArea {
          id: trackArea

          anchors.fill: parent

          function valueAt(y) {
            return Math.max(0, Math.min(1, 1 - y / Math.max(1, height)))
          }

          onPressed: mouse => {
            root.dragFrom = root.level
            root.dragCommits = 0
            root.dragging = true
            root.setLevel(valueAt(mouse.y))
          }
          onPositionChanged: mouse => {
            if (root.dragging) root.setLevel(valueAt(mouse.y))
          }
          onReleased: root.dragging = false
          onCanceled: root.dragging = false
        }
      }

      // -------------------------------------------------------- the mute
      //
      // A circle centred in a square that answers for it. Nothing here is
      // grown, so nothing can overlap the track above (E3) and the target is
      // the same 44 on both densities.
      Item {
        id: mute

        x: root.pad + Math.round((root.trackWidth - root.muteSlot) / 2)
        y: root.pad + root.trackHeight + root.gap
        width: root.muteSlot
        height: root.muteSlot

        Rectangle {
          anchors.centerIn: parent
          width: root.muteSize
          height: width
          radius: ui.radiusOn(width)
          color: root.muted ? root.accent : root.container

          // H8: the veil takes the drawn circle, never the slot. H4: the ink is
          // this control's own, which flips with the fill under it.
          PressVeil {
            anchors.fill: parent
            radius: parent.radius
            ink: root.muted ? root.textOnAccent : root.textOnSurface
            on: muteArea.pressed
          }

          Ui.OpticalGlyph {
            anchors.fill: parent
            text: root.glyph
            fontFamily: Style.font.family
            fontSize: Style.font.icon
            color: root.muted ? root.textOnAccent : root.textOnSurface
          }
        }

        MouseArea {
          id: muteArea

          anchors.fill: parent
          onClicked: root.toggleMute()
        }
      }
    }
  }
}
