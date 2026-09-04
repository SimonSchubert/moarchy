// Touchscreen gestures, as a shell surface rather than a daemon.
//
// The manifest declares kind "panel", not "service", even though this behaves
// like a background service. A plugin declared as a service gets mounted twice
// and drew two stacked pills; as a panel it is mounted once. First-party
// plugins follow the same split -- osd is a panel because it owns a layer
// surface, while idle and battery are services because they own none. The rule
// is what the plugin owns, not what it does.
//
// ---------------------------------------------------------------------------
// Why this is not a Sway binding
// ---------------------------------------------------------------------------
// Sway's `bindgesture` only ever fires for touchpads. libinput synthesises
// swipe/pinch gestures from touchpad events and never from a touchscreen, so
// under bare Sway a swipe is invisible however it is bound. lisgd worked round
// that by reading the evdev node directly, but it can only run a command on
// release -- nothing can follow the finger, because lisgd draws nothing.
//
// So do it the way phosh does: a layer-shell surface that owns the bottom edge
// and receives the touch itself. Owning the surface is what makes continuous
// feedback possible at all.
//
// ---------------------------------------------------------------------------
// Why the strip does not have to grow while you drag
// ---------------------------------------------------------------------------
// Wayland sends wl_touch.down to the surface under the finger and then holds an
// *implicit grab*: motion and up for that touch point keep arriving at the same
// surface however far the finger travels, even outside its bounds. So a 20px
// strip can track a full-height swipe. Widening the surface mid-gesture would
// only steal new touches from the app underneath, so we never do it -- which
// also means a bug here can never leave the phone with an unusable touchscreen.
//
// ---------------------------------------------------------------------------
// Why only the bottom edge
// ---------------------------------------------------------------------------
// libadwaita's AdwSwipeTracker and Kirigami both implement back-swipe *inside*
// the app, on touch, so every GNOME and Plasma Mobile app on this phone already
// has swipe-to-go-back. Claiming the left or right edge here would break it.
// The top edge belongs to the bar. That leaves the bottom, which is where a
// phone's home affordance lives anyway.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  // Height of the strip that accepts touch. Deep enough to hit without looking,
  // shallow enough that it rarely lands on an app's own bottom controls.
  readonly property int stripHeight: Style.space(20)

  // Travel that commits a gesture. Below this the pill springs back and nothing
  // happens, so resting a thumb on the edge is not a workspace switch.
  readonly property int commitDistance: Style.space(56)

  // The pill moves a fraction of the finger's travel. Full 1:1 tracking on a
  // 360px screen runs the pill off the edge long before the commit threshold.
  readonly property real damping: 0.32

  // Hold the pill still for this long and the next release closes the focused
  // window. Closing is the one destructive thing here, so it is deliberately
  // not a swipe: a swipe is easy to do by accident on an edge you rest a thumb
  // on, and there would be no way to take it back.
  readonly property int holdMs: 500

  // Movement past this cancels the hold, so a swipe that starts slowly is still
  // a swipe and never a close.
  readonly property int holdSlop: Style.space(8)

  property bool tracking: false
  property bool armed: false
  property real startX: 0
  property real startY: 0
  property real dx: 0
  property real dy: 0

  // How far the pill may slide from centre before it stops following. Past the
  // commit distance the gesture is already decided, so more travel says nothing.
  readonly property int pillTravel: Style.space(80)

  readonly property real pillOffset: root.tracking
    ? Math.max(-root.pillTravel, Math.min(root.pillTravel, root.dx * root.damping))
    : 0

  // Horizontal wins ties: a sideways swipe that drifts upward is still a
  // workspace change, which is the gesture people actually aim for.
  function commit(): void {
    if (Math.abs(root.dx) >= Math.abs(root.dy)) {
      if (root.dx <= -root.commitDistance) root.run("next")
      else if (root.dx >= root.commitDistance) root.run("prev")
    } else if (root.dy <= -root.commitDistance) {
      root.run("menu")
    }
  }

  // omarchy-menu is called by absolute path, the way the emojis plugin calls
  // omarchy-menu-emoji-insert. Relying on PATH is a silent failure mode: a shell
  // started without the session environment gets only
  // /usr/local/sbin:/usr/local/bin:/usr/bin, and then the swipe reports success
  // while nothing happens. swaymsg is left on PATH because it lives in /usr/bin.
  //
  // NOT `readonly`, and that matters. The shell hands plugins their own path --
  // `if ("omarchyPath" in item) item.omarchyPath = shell.omarchyPath` -- so a
  // read-only declaration makes that assignment throw and the whole plugin
  // fails to load, silently, on the next reload. Every first-party plugin
  // declares it exactly like this: writable, with the env var as the fallback
  // for when the shell has not got round to assigning it yet.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
                               || (Quickshell.env("HOME") + "/.local/share/omarchy")

  // Swipe up opens the menu already inside Apps rather than at the root. On a
  // phone the menu is the app launcher first and a command palette second, and
  // the root menu costs a tap before every launch. The back chevron still goes
  // root-ward, so Style/Setup/System are one tap away instead of zero.
  readonly property string launcherRoute: "apps"

  // Every gesture ends here, including the IPC ones, so the compositor calls
  // live in exactly one place.
  //
  //   next/prev  `*_on_output` keeps the switch on this screen, and matches what
  //              bin/mobileomarchy-gestures bound under lisgd, so muscle memory
  //              carries over: dragging content rightwards goes back a workspace.
  //   menu       `toggle`, not `summon`, so a second swipe closes it again.
  //   close      `kill` is a close *request* -- Sway sends xdg_toplevel.close and
  //              the app decides, so an editor with unsaved work prompts rather
  //              than dies. That is what makes firing it from a hold acceptable.
  function run(action: string): void {
    if (action === "next") Quickshell.execDetached(["swaymsg", "workspace", "next_on_output"])
    else if (action === "prev") Quickshell.execDetached(["swaymsg", "workspace", "prev_on_output"])
    else if (action === "menu") Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-menu",
                                                        "toggle", root.launcherRoute])
    else if (action === "close") Quickshell.execDetached(["swaymsg", "kill"])
  }

  // Back to rest. Every path out of a gesture goes through this -- release,
  // cancel, and the watchdog -- so none of them can forget to clear `armed` and
  // leave the pill sitting there lit red.
  function reset(): void {
    hold.stop()
    watchdog.stop()
    root.tracking = false
    root.armed = false
    root.dx = 0
    root.dy = 0
  }

  // Arms on hold, fires on release. Arming and firing are split so the hold can
  // still be taken back: slide off the pill and `armed` clears before you lift.
  Timer {
    id: hold
    interval: root.holdMs
    onTriggered: root.armed = true
  }

  // A touch sequence normally ends in released or canceled, but a compositor
  // restart or a lost seat can strand one mid-gesture. Nothing dangerous
  // happens if it does -- the strip never grows, so input is never trapped --
  // but the pill would stay lit and stop springing back.
  Timer {
    id: watchdog
    interval: 4000
    onTriggered: root.reset()
  }

  // Lets the wiring be tested without a finger:
  //   omarchy-shell gestures swipe left
  //   omarchy-shell gestures close
  IpcHandler {
    target: "gestures"

    function swipe(direction: string): string {
      if (direction === "left") { root.run("next"); return "ok: next workspace" }
      if (direction === "right") { root.run("prev"); return "ok: previous workspace" }
      if (direction === "up") { root.run("menu"); return "ok: menu" }
      return "usage: swipe left|right|up"
    }

    // The same close the hold fires, reachable from a keybind or a menu row for
    // anyone who would rather not hold.
    function close(): string {
      root.run("close")
      return "ok: close requested"
    }

    function status(): string {
      if (root.armed) return "armed: release closes the focused window"
      return root.tracking ? "tracking dx=" + Math.round(root.dx) + " dy=" + Math.round(root.dy)
                           : "idle"
    }
  }

  PanelWindow {
    id: strip

    // Anchoring left+right+bottom without `top` gives a full-width strip whose
    // height we set. Sizing the surface to the strip means the surface *is* the
    // input region, so touch outside it reaches the app with no `mask` needed.
    anchors { bottom: true; left: true; right: true }
    implicitHeight: root.stripHeight
    color: "transparent"

    WlrLayershell.namespace: "mobileomarchy-gestures"

    // Overlay, and the layer is load-bearing rather than cosmetic.
    //
    // Sway arranges exclusive layer surfaces from the TOP layer down --
    // overlay, top, bottom, background -- so the *highest* layer claims the
    // screen edge and everything below it is arranged into what is left. The
    // on-screen keyboard (squeekboard, and wvkbd) sits on Top, so the drawer
    // has to be on Overlay to keep the bottom edge and push the keyboard up
    // above it. That is the Android arrangement.
    //
    // Measured, not assumed: on Bottom the keyboard took the edge and stranded
    // the drawer above it, and restarting either one in either order changed
    // nothing -- it is layer order, not map order.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Reserve the strip instead of floating over the app, the way Android's
    // navigation bar does. The exclusive zone is what keeps the drawer usable
    // at all times: layer-shell surfaces are arranged against the remaining
    // area, so the on-screen keyboard is placed *above* the strip rather than
    // on top of it, and the home pill stays reachable while typing.
    //
    // The cost is stripHeight off every window, permanently. That is the trade
    // Android makes too, and it beats the alternative -- an overlaid strip means
    // either the keyboard buries the drawer, or the drawer eats the keyboard's
    // bottom row.
    exclusionMode: ExclusionMode.Auto

    Rectangle {
      id: pill

      width: Style.space(96)
      height: Math.max(2, Style.space(4))
      radius: height / 2
      anchors.verticalCenter: parent.verticalCenter
      x: (parent.width - width) / 2 + root.pillOffset

      // Brightens while tracking, and stretches as an upward swipe approaches
      // the menu threshold, so the gesture confirms itself before you let go.
      // Armed for close it goes urgent -- the only warning you get that lifting
      // your finger will shut the window, and the reason arming is visible at
      // all rather than firing silently on the timer.
      color: root.armed ? Color.urgent
                        : Util.alpha(Color.foreground, root.tracking ? 0.9 : 0.3)
      scale: root.armed ? 1.5
                        : 1 + Math.min(0.4, Math.max(0, -root.dy) / (root.commitDistance * 4))

      Behavior on x {
        enabled: !root.tracking
        SpringAnimation { spring: 4; damping: 0.35 }
      }
      // Arming happens mid-touch, so this one animation has to run while
      // tracking -- otherwise the urgent state snaps in with no cue.
      Behavior on scale {
        enabled: !root.tracking || root.armed
        SpringAnimation { spring: 4; damping: 0.35 }
      }
      Behavior on color { ColorAnimation { duration: 140 } }
    }

    MultiPointTouchArea {
      anchors.fill: parent
      maximumTouchPoints: 1

      onPressed: pts => {
        if (pts.length === 0) return
        root.startX = pts[0].sceneX
        root.startY = pts[0].sceneY
        root.dx = 0
        root.dy = 0
        root.tracking = true
        root.armed = false
        hold.restart()
        watchdog.restart()
      }

      onUpdated: pts => {
        if (pts.length === 0 || !root.tracking) return
        root.dx = pts[0].sceneX - root.startX
        root.dy = pts[0].sceneY - root.startY
        // Past the slop this is a swipe, not a hold -- and it also un-arms, so
        // a hold you thought better of can be slid away from.
        if (Math.abs(root.dx) > root.holdSlop || Math.abs(root.dy) > root.holdSlop) {
          hold.stop()
          root.armed = false
        }
        watchdog.restart()
      }

      onReleased: pts => {
        if (!root.tracking) return
        if (root.armed) root.run("close")
        else root.commit()
        root.reset()
      }

      onCanceled: pts => root.reset()
    }
  }
}
