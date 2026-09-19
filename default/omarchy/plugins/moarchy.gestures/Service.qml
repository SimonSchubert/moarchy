// Touchscreen gestures, as shell surfaces rather than a daemon.
//
// Implements docs/gestures.md. AC ids in comments below refer to that file,
// which is the contract; this file is one way of meeting it.
//
// The manifest declares kind "panel", not "service". A plugin declared as a
// service gets mounted twice and drew two stacked pills; as a panel it is
// mounted once. The rule is what the plugin owns, not what it does.
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
// So do it the way phosh does: layer-shell surfaces that own an edge and
// receive the touch themselves.
//
// ---------------------------------------------------------------------------
// The four surfaces, and why each sits on the layer it does
// ---------------------------------------------------------------------------
//   strip         Overlay, bottom, 20px, exclusive.  A sheet and home (A, B, Q).
//                 Overlay because moarchy-keyboard is on Top with an exclusive
//                 zone, so anything lower loses the bottom edge to the keyboard.
//   home          Bottom, full screen, no exclusion.  The strip's sheet (D).
//                 *Below* every window, so on a blank workspace it receives the
//                 touch and on an occupied one the app is over it and it
//                 receives nothing. The layer does the work -- there is no "is
//                 this workspace empty" test anywhere in this file, because
//                 asking that question is what made the app drawer open when it
//                 should not have.
//   backEdge      Overlay, left, 16px.  Back (G).
//   workspaceOverviewEdge  Overlay, right, 16px.  The right edge's sheet (P).
//                 Above windows, because both have to take the touch before the
//                 app does. They are the two places here that steal input from
//                 an app, each is bounded to 16px, and like the strip neither
//                 ever grows. Both stop short of the same two ends for the same
//                 reasons (G10, G10b) -- the keyboard's outermost key column and
//                 the app's own header controls are at both edges, not one.
//
// Wayland's implicit grab is what makes all four work: wl_touch.down goes to
// the surface under the finger and motion keeps arriving there however far the
// finger travels. So a 20px strip can track a full-height swipe, and none of
// these surfaces has to grow mid-gesture -- which also means a bug here can
// never leave the phone with an unusable touchscreen.
//
// ---------------------------------------------------------------------------
// What the up-drag from the strip means
// ---------------------------------------------------------------------------
//   0 ---------------- 50% ---------------- 100% -- and past it
//   back down               stays up                    HOME
//
// One drag, two stops, and the first one is the launcher from wherever you
// are: over an app, over a home screen, over nothing. The home screen's own
// up-drag (D1) raises the same sheet and differs only in tracking the finger
// 1:1, because there the thing under the thumb *is* the sheet.
//
// It used to be the carousel in that first band, with the app drawer reachable
// only from a blank workspace (the Android split: nav area is the workspace overview,
// home screen is the launcher). The carousel is gone: the app drawer shows what is
// open along its top (M), so a switcher that could only switch was a second
// surface, a second model of what is running, and a gesture whose meaning
// depended on whether anything was.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui
import "../moarchy.common/ShellApps.js" as ShellApps
import "../moarchy.common/Sheet.js" as Sheet
import "../moarchy.common/Edge.js" as Edge
import "../moarchy.common" as Shared

Item {
  id: root

  // ------------------------------------------------------------- geometry
  //
  // Height of the strip that accepts touch. Deep enough to hit without looking,
  // shallow enough that it rarely lands on an app's own bottom controls.
  readonly property int stripHeight: Style.space(20)

  // G8. About 3mm on this panel, which is roughly what Android's back edge
  // feels like at its default sensitivity. Deliberately one property rather
  // than a number inlined in a binding: Android makes this device-configurable
  // *and* user-adjustable *and* queryable by apps, which is three admissions
  // that no single value is right. Expect to change it.
  readonly property int backEdgeWidth: Style.space(16)

  // P8. The right edge's band, which is G8's number and G8's argument: it is a
  // property rather than a literal because no single value is right, and the two
  // edges are separate properties because the same finger does not have the same
  // reach at both sides of a phone it is holding in one hand.
  readonly property int workspaceOverviewEdgeWidth: Style.space(16)

  // G10, P8. How far short of the bottom an edge surface stops. Below this the
  // strip wants taps, and above the strip the keyboard does -- and the back edge
  // was taking both, because it is on Overlay and they are not.
  //
  // One property for both edges, not because they happen to agree but because
  // the two things it clears run the full width of the screen: the strip is
  // edge to edge, and the keyboard's outermost key columns are the ones this
  // number exists to hand back -- `a` and shift on the left, backspace and enter
  // on the right.
  //
  // A number rather than an arrangement, and that is forced. Sway resolves
  // exclusive zones layer by layer from Overlay down, so the keyboard's zone
  // (Top) is subtracted after this surface has been placed: ExclusionMode
  // .Normal here would move nothing. Nor can a tap be handed down to the
  // keyboard after the fact -- Wayland picks the recipient from the input
  // region before delivering the touch. Cutting the region is the only knob.
  //
  // The panel height is not scaled with the theme (Osk.qml says why): scaling
  // it would cut the back edge shorter than the keys it exists to clear.
  readonly property int edgeBottomInset:
    root.stripHeight + osk.keyboardPanelHeight

  // G10b. What a GTK app's header bar reserves at the top, in logical px.
  //
  // Measured on the device and not chosen, for the same reason as the
  // keyboard's 200 in Osk.qml: it is another toolkit's chrome, and libadwaita has
  // never heard of this theme's spacing scale. Spot's header runs from y=52 to
  // y=144 physical at scale 2 -- 46.5 logical plus its divider -- which is
  // AdwHeaderBar's own 47. GTK3 and Kirigami land within a pixel or two of it.
  readonly property int headerBarHeight: 47

  // G10b, P8. How far short of the TOP an edge surface stops, so the controls an
  // app puts along its header are tappable: libadwaita's back chevron, a
  // hamburger and Geary's folder button on the left, the window menu and the
  // primary action on the right.
  //
  // This surface is anchored top and bottom on Overlay, and sway resolves
  // exclusive zones from Overlay down, so the bar's zone (Top) is subtracted
  // after this is placed: y=0 here is the top of the SCREEN, not the top of
  // the app. So the inset carries the bar as well as the header.
  //
  // The bar half goes through the theme (it is our surface); the header half
  // does not (it is not). Same split as the bottom inset, opposite ends.
  readonly property int edgeTopInset:
    Style.bar.sizeHorizontal + root.headerBarHeight

  // I1a. Is the on-screen keyboard reserving space right now?
  //
  // Read off `home`'s own configure, which is the only live answer available
  // here. The busctl probe below answers a different question and answers it
  // slowly: `keyboardUp` is what the back gesture asks on press and reads on
  // release, it is stale between gestures, and `sm.puri.OSK0`'s `Visible` has
  // been seen to read true with nothing drawn. A surface the compositor has
  // resized cannot be wrong about it.
  //
  // Why `home` can answer at all: sway resolves exclusive zones from Overlay
  // downwards, so a Bottom surface is arranged after the keyboard's Top zone
  // has been subtracted and shrinks with it. The strip cannot answer the same
  // question -- it is Overlay, and G10's inset is a hand-computed number for
  // exactly that reason.
  //
  // `home` is one strip taller than the free area (its negative bottom
  // margin), so neither cluster is an exact number -- which is what the half-
  // panel threshold in Osk.qml is for. The bar's own band is nowhere near it.
  readonly property bool keyboardReserving: osk.reserving(home)

  // I1a. Fill the band the strip reserves with the theme's background instead
  // of leaving the wallpaper showing through it.
  //
  // Both halves are cases where the wallpaper is the right answer and the fill
  // would be wrong: an empty workspace *is* the home screen, and with the
  // keyboard up the band sits under the keyboard rather than under the app.
  //
  // `focusedToplevel()` for "is this workspace empty", because it is already
  // the answer `run("home")` trusts for that question -- and since K1 it is an
  // honest one: the shell's own screens are windows and answer it themselves.
  readonly property bool fillStripBand:
    !!root.focusedToplevel() && !root.keyboardReserving

  // I1b. The arranged area of moarchy-home, filled so a workspace switch does
  // not flash wallpaper in the hole the window leaves. I1a is only the strip
  // band, and it is off while the keyboard is up -- which is exactly when a
  // swipe away from the terminal is ugliest, because the keyboard's exclusive
  // zone has already cut this surface to the window area and that area is
  // transparent. Representation is the same signal run("home") trusts: it
  // stays true through a layer-surface Exclusive, which focus does not.
  //
  // coveringSwitch is the latch for the frames where both of those flicker
  // false between workspaces. Set in run("next"/"prev"), cleared after the
  // new workspace has had time to name a window.
  property bool coveringSwitch: false
  readonly property bool fillWorkspace:
    root.coveringSwitch
    || root.focusedWorkspaceWindows() > 0
    || !!root.focusedToplevel()

  // G6. Rightward travel that commits a back swipe -- three times the band, so
  // brushing the edge never closes an app.
  readonly property int backCommit: Style.space(48)

  // G12. How big the cue is, and therefore how far past the band this surface
  // reaches. Style.space because it is ours and it is chrome, unlike G10's 200
  // -- that number belongs to another client's panel and does not know this
  // theme exists.
  readonly property int backCueSize: Style.space(44)

  // Where down the edge the finger is, in this surface's own coordinates, so
  // the cue rides under the thumb rather than sitting at a fixed height.
  property real backCueY: 0

  // G12's instrument. One integer per frame of the gesture, the same shape
  // `app-drawer dragTrace` is and for the same reason: "does it follow the finger"
  // is a question about the number of samples, and an arc that appeared at the
  // threshold would look identical in a screenshot.
  property var backTrace: []

  // One entry, capped. -1 marks a real cancel and -2 a stranded touch the
  // watchdog retired, which the app drawer's trace has distinguished since F2 and
  // this one could not: the back edge had no watchdog to fire (H1, H5).
  function markBackTrace(v: int): void {
    if (root.backTrace.length >= 200) return
    var next = root.backTrace.slice()
    next.push(v)
    root.backTrace = next
  }

  // Travel that commits a sideways swipe. Below this the pill springs back and
  // nothing happens, so resting a thumb on the edge is not a workspace switch.
  readonly property int commitDistance: Style.space(56)

  // The pill moves a fraction of the finger's travel. Full 1:1 tracking on a
  // 360px screen runs the pill off the edge long before the commit threshold.
  readonly property real damping: 0.32

  // Movement past this is a drag rather than a stationary touch, and it is what
  // cancels the hold (C3) as well as what latches a drag. One number for both,
  // deliberately: a touch that is a drag and a touch that is a hold are the
  // same touch until this is crossed, so two numbers would leave a band in
  // which it was neither or both.
  readonly property int slop: Style.space(8)

  // The old strip travel, kept only as the fallback in targetTravel() for a
  // app drawer that has not published a `closeTravel` yet -- during startup, or if
  // the plugin failed to load. Nothing measures a real gesture against it any
  // more (D2a): a sheet is dragged in units of itself.
  readonly property real pullTravel:
    Math.max(1, (strip.screen ? strip.screen.height : 720) * 0.45)

  // A4. Where the second stop is: past a *full* sheet, and never inside the
  // travel that opens one.
  //
  // It was 0.85, and before that 0.75 of a shorter travel. Both sat inside the
  // reach of an ordinary swipe -- measured from a real one on the device, an
  // unremarkable flick up from the strip runs to 92% of the sheet at 2.5 px/ms.
  // So the gesture that means "show me the launcher" was landing in the home
  // band, taking the app drawer it had just dragged up away with it. No threshold
  // inside 0..1 separates those two intents, because they are the same
  // movement.
  //
  // Past 1.0 they separate cleanly. From an app that is a sweep to the very top
  // of the screen -- the sheet is full and the finger kept going -- and from an
  // already-open app drawer it is one homeExtra further (A6), which is the path
  // that actually gets used: app, swipe, launcher, swipe, wallpaper.
  readonly property real homeCommit: 1.0

  // A6, A7. How much *further* the finger has to travel to reach home when the
  // sheet is already up. Without it `homeCommit` is behind the drag before it
  // starts -- an open app drawer sits at pull 1.0, which is past 0.85 -- so every
  // touch on the strip would go home, including the ones that mean nothing.
  // Measured from where this drag began rather than from the bottom of the
  // sheet, so the gesture costs the same finger movement either way.
  readonly property real homeExtra: 0.15

  // D2, P2. Half the sheet decides, on every surface that drags one: released
  // past halfway it animates open, short of it back shut. That is what a sheet
  // does everywhere else -- the sheet is the thing being positioned, so the
  // question is which end it is nearer -- and it is what was asked for, in those
  // words.
  //
  // It was 0.35, inherited from the control center, whose sheet is a different shape and
  // whose drag has no second stop past it. It was `appDrawerCommit` while the
  // app drawer was the only sheet an edge could pull up; the workspace overview is dragged by
  // the same rule on the other axis (P2), and one threshold is what keeps "far
  // enough" something you learn once.
  readonly property real sheetCommit: 0.5

  // A3. Speed past which a release commits whatever the travel, in logical px
  // per ms. It was 0.6 against a reading that could not be trusted: measured
  // from the strip, ordinary swipes whose real speed was 0.70, 0.66 and 0.58
  // came through as 0.59, 0.87 and 2.79, so the same gesture opened the app drawer
  // or did not, at random. With the reading fixed (DragTracker, "measuring
  // speed") the number can mean something, and 0.3 is what it should mean: a
  // deliberate swipe on this phone lands at 0.35-0.7 and a slow positioning
  // drag under 0.33, so the band sits in the gap between the two intents
  // rather than inside the first one.
  readonly property real fling: 0.3

  // D2a. What one pixel of finger is worth to the sheet being dragged: one
  // pixel, on every surface that drags it.
  //
  // The app drawer's *close* drag has always been 1:1 against the sheet's own
  // height, because there the handle is the sheet. The open drag from the
  // wallpaper was the first to match it -- before that the same finger movement
  // opened the app drawer 2.2x faster than it closed it, and a drag from mid-screen
  // arrived fully open with half the screen still to go (measured: a 250px drag
  // left it at 77%).
  //
  // The strip was the last holdout, on the reasoning that the pill is not the
  // thing being dragged, so a full-screen reach there would cost something and
  // buy nothing. That was a switcher's argument. Pulling a launcher onto the
  // screen at 2.2x finger speed is the "too sensitive" this is the fix for.
  //
  // Read off the app drawer rather than recomputed here, so no two drags on it can
  // drift apart -- `closeTravel` is the property its own close divides by.
  // pullTravel survives as the fallback for a app drawer that has not published
  // one, and as the unit the sideways gestures were tuned in.
  function targetTravel(): real {
    if (root.dragTarget) {
      var travel = Number(root.dragTarget.closeTravel)
      if (isFinite(travel) && travel > 1) return travel
    }
    // Q4a. With no sheet on this edge the drag still has the second stop,
    // and the screen is what it is measured against -- A4's "a sweep to the
    // very top". `pullTravel` below is 45% of that, which would put home
    // inside an ordinary swipe: the very thing A4's stop moved past 1.0 to
    // get away from.
    if (root.pendingMode === "home" || root.dragMode === "home")
      return Math.max(1, strip.screen ? strip.screen.height : 720)
    return root.pullTravel
  }

  // ---------------------------------------------------------- shared state
  //
  // Two surfaces drag the same sheet -- the strip and the wallpaper -- and
  // each has a DragTracker of its own, because each keeps its own origin (a
  // touch on one must not clobber the other's) and the wallpaper has no second
  // stop past the sheet. What they share is everything below, which is read by
  // the pill, by commit(), by homeArmed and by status().
  //
  // `lastDrag` is whichever of them the current gesture belongs to, set on
  // press and cleared by reset(). Keyed on that rather than on `active` so the
  // numbers survive the release: the commit decision runs between the finger
  // lifting and reset(), and an alias that went to 0 at the lift would decide
  // every gesture as a zero-travel one.
  property var lastDrag: null
  readonly property bool tracking: root.lastDrag !== null
  readonly property real dx: root.lastDrag ? root.lastDrag.dx : 0
  readonly property real dy: root.lastDrag ? root.lastDrag.dy : 0
  // Signed **toward open**, not in scene coordinates: positive means "let go
  // now and the sheet should end up further open". Named for it, because both
  // release rules below are fling tests and reading the scene sign into one of
  // them is what sprang the app drawer shut on a quick flick up.
  readonly property real openVelocity:
    root.lastDrag ? root.lastDrag.openVelocity : 0

  // Which sheet this gesture has latched onto: "none", "home", or an id.
  // Latched on the first clearly-upward movement -- clearly-leftward, on the
  // right edge -- and held for the rest of the gesture, so a swipe that starts
  // along the axis and drifts across it cannot hand the sheet back mid-pull and
  // change workspace instead.
  //
  // It is also what dropDrag() reads to know a cancelled touch left a sheet
  // parked half-open. A latch that set no mode would put nothing back.
  property string dragMode: "none"

  // Which surface is driving: "strip" or "home". They raise the same sheet and
  // differ in exactly two ways -- how much finger a full sheet costs (D2a),
  // and whether there is a second stop past it (A4). A home screen has no home
  // to go to.
  property string dragSource: ""

  // What the surface decided on press, before it was known the gesture was
  // even upward.
  // "none", "home", or the id of the sheet being dragged. It was the word
  // `app-drawer` while the app drawer was the only thing an edge could raise; with
  // the target a setting (Q1) the branch means "a sheet is being dragged"
  // and the id is the more useful thing to carry -- `gestures status` names
  // which one, where `mode=appDrawer` could only ever say that it was one.
  //
  // "home" is the strip with no sheet on it (Q4): nothing to drag, and the
  // second stop still there.
  property string pendingMode: "none"

  // A direct object reference, resolved once per gesture. The alternative --
  // shell.callIfLoaded(id, method, arg) -- marshals a string per call, and
  // this runs at touch-event rate.
  property var dragTarget: null

  // Which sheet that object is, so the commit can go through the host by id.
  // Two edges drag two different sheets now -- the strip and the wallpaper the
  // app drawer (A, D), the right edge the workspace overview (P) -- and `releaseTarget` used
  // to name the app drawer outright. A commit that summoned the wrong sheet would
  // leave the one being dragged parked at 1.0 with the host believing it shut.
  property string dragSheet: ""

  // Where the pull stood when the finger went down, so the same strip can push
  // a sheet back as well as pull it up.
  property real dragStartPull: 0

  // The live pull, in units of the sheet's height (targetTravel()). The
  // tracker's *unclamped* travel, because A4's second stop is past 1.0 and a
  // clamped one cannot reach it.
  readonly property real pull: root.lastDrag ? root.lastDrag.travelled : 0

  // Where home commits for *this* drag: 85% of the sheet, or one homeExtra
  // past wherever the drag began, whichever is further up.
  function homeThreshold(): real {
    return Math.max(root.homeCommit, root.dragStartPull + root.homeExtra)
  }

  readonly property bool homeArmed:
    root.dragSource === "strip" && root.dragMode !== "none"
    && root.pull >= root.homeThreshold()

  // Host-injected. Neither may be `readonly` or `required`: readonly makes the
  // assignment throw, required makes the component fail to instantiate at all,
  // because a plugin is created first and configured afterwards. Either way the
  // failure is silent.
  property var shell: null

  // -------------------------------------------------------- compositor state
  //
  // Hyprland.eventSocketPath is empty when Quickshell never found
  // $HYPRLAND_INSTANCE_SIGNATURE -- which happens if the shell was started
  // outside the session environment. Falling back to forking hyprctl there
  // keeps every gesture working; silently dispatching into a dead socket
  // would not. bin/moarchy-restart-shell exports the signature for exactly
  // this reason, the way it exported $SWAYSOCK before it.
  readonly property bool haveHl: String(Hyprland.eventSocketPath || "").length > 0

  // The compositor's models populate on FIRST ACCESS, not at construction:
  // read before anything has touched them and every one of them is empty,
  // which reads exactly like a compositor with nothing running on it.
  // Measured 2026-09-19: a probe that read Hyprland.workspaces at
  // Component.onCompleted saw 0 and the same read 1.5s later saw 2.
  //
  // A function and not a second Component.onCompleted: QML allows one per
  // object, and a second silently replaces the first -- "Property value set
  // multiple times", which costs whichever handler lost.
  function warmCompositorModels(): void {
    void (Hyprland.workspaces ? Hyprland.workspaces.values.length : 0)
    void (Hyprland.toplevels ? Hyprland.toplevels.values.length : 0)
  }

  // The one place a compositor command is sent. Callers below name an
  // INTENT -- focusWorkspace, closeFocused -- and this file is the only one
  // that knows what that costs in Hyprland's Lua.
  //
  // Lua, not the legacy string syntax: under a .lua config `hyprctl dispatch`
  // wraps its argument as `return hl.dispatch(<arg>)`, so `dispatch dpms off`
  // is a syntax error rather than a command. `hyprctl keyword` does not work
  // at all and its replacement is `hyprctl eval`.
  function dispatch(cmd: string): void {
    if (root.haveHl) Hyprland.dispatch(cmd)
    else Quickshell.execDetached(["hyprctl", "dispatch", cmd])
  }

  // ------------------------------------------------ the compositor vocabulary
  // Seven shapes, which is the whole of what this shell asks a compositor to
  // do. Everything else in the tree calls these rather than building a
  // command, so a third compositor is this block and nothing else.
  function focusWorkspace(n): void {
    root.dispatch('hl.dsp.focus({ workspace = "' + String(n) + '" })')
  }
  // `e`, and the letter is the whole of it. A bare "+1" is relative by ID and
  // Hyprland CREATES the workspace it names, so on a phone holding workspaces
  // 1 and 6 a swipe off 1 lands on a brand-new empty 2 -- bare wallpaper, no
  // app -- and the next lands on 3, walking away from both real workspaces
  // instead of rotating between them. Sway had no such thing to get wrong:
  // `workspace next` was already "next existing".
  //
  // "e+1"/"e-1" move among workspaces that EXIST and wrap at the ends, which
  // is what "next app" means here (docs/gestures.md B3). Measured on sargo
  // 2026-09-19: from 1 of [1,6], "+1" gave 2 of [2,6]; "e+1" gave 6 of [6].
  function focusWorkspaceRelative(delta: int): void {
    root.dispatch('hl.dsp.focus({ workspace = "e' + (delta > 0 ? "+" : "") + delta + '" })')
  }
  function focusAddress(addr: string): void {
    root.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
  }
  function closeFocused(): void {
    root.dispatch('hl.dsp.window.close()')
  }
  function closeAddress(addr: string): void {
    root.dispatch('hl.dsp.window.close({ window = "address:' + addr + '" })')
  }
  function moveAddressToWorkspace(addr: string, n): void {
    root.dispatch('hl.dsp.window.move({ window = "address:' + addr
                  + '", workspace = "' + String(n) + '" })')
  }

  // A foreign-toplevel handle carries no address, so map it through the
  // compositor's own model: HyprlandToplevel.wayland is the same object this
  // shell holds as a Toplevel.
  function addressFor(tl): string {
    if (!tl) return ""
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].wayland === tl) return String(list[i].address || "")
    return ""
  }

  // P4, K12. Focus a window. Every caller in this shell lands here, so there is
  // one answer to "how do you focus something" and one place to change it.
  //
  // NOT `Toplevel.activate()`. The foreign-toplevel activate request does
  // nothing, on EITHER compositor. Measured against sway 1.12 on 2026-09-08
  // and against Hyprland 0.56.2 on 2026-09-19: the request is sent, no warning
  // appears anywhere, and the focused workspace does not move. `close()` on
  // the same handle works, so it is the activate path and not a dead protocol.
  //
  // It had been silently broken for as long as a tap on a card was a thing.
  // The check passed throughout, because it asserted that the workspace the
  // tap landed on holds a window -- which is also true when the tap changed
  // nothing and you were already looking at one.
  //
  // By ADDRESS, which is the improvement the compositor change buys here. The
  // sway version matched on app_id AND title, because a foreign-toplevel
  // handle carries no con_id and there was nothing else to address a window
  // by -- so two windows with the same app and title were ambiguous and sway
  // acted on both. An address is unique, and that known cost is gone.
  function focusToplevel(tl): bool {
    if (!tl) return false
    var addr = root.addressFor(tl)
    if (addr === "") return false
    root.focusAddress(addr)
    return true
  }

  function isOpen(id: string): bool {
    return root.shell && typeof root.shell.isPluginOpen === "function"
           && root.shell.isPluginOpen(id)
  }

  // Every full-screen overlay this shell can put over an app, topmost first.
  //
  // G11. That order is the layer order and it is load-bearing: the control center is
  // Overlay and the other two are Top, so a back swipe walking this list from
  // the front closes the sheet being looked at. Two of them can be up at once
  // since the control center stopped dismissing the app drawer (control-center.md S28), which is
  // what made the order matter rather than merely read well.
  //
  // This used to be three ids written out at each of the two call sites, and
  // Settings and Themes were in neither. A back swipe over Settings therefore
  // fell straight through to closing the *app behind it* -- with the sheet
  // still on screen, so nothing looked wrong until you dismissed it and found
  // the app gone. Adding a screen must not mean remembering two lists.
  //
  // Sheets only, and that is the whole list now. Settings, Wi-Fi and Bluetooth
  // used to be concatenated on the end of it: they are windows
  // (docs/gestures.md K1), the compositor puts them away and brings them back,
  // and every function below that walks this list would close one if it were
  // still here.
  // B1, I2: the list itself is `moarchy.common/Sheet.js`, which every plugin's
  // own `open()` now reads through the same rank. This was the fourth copy of
  // it, and the one whose order carries the meaning above -- so it is read from
  // there rather than restated here, topmost first.
  readonly property var overlayIds: Sheet.ids()

  // K7. The shell app whose window is focused, or null.
  //
  // Focus and not "is it open": a shell app is a window, so the question the
  // back gesture asks is the one it asks of any app -- which one am I in --
  // and there can be three of them mapped at once on three workspaces.
  function focusedShellApp() {
    return ShellApps.forToplevel(root.shell, root.focusedToplevel())
  }

  // A7, A8. The surfaces an up-swipe *clears* rather than switches away from.
  //
  // Derived from overlayIds rather than written out again: a second list of
  // ids is exactly how Settings and Themes came to be missing from the back
  // gesture. Minus whatever the strip raises, which a second drag continues
  // into the home band rather than clears (A6).
  //
  // Read off the setting and not off an id (Q1). Naming the app drawer here is
  // what would make a second drag clear the workspace overview instead of carrying it
  // on, the moment somebody put the workspace overview on this edge. With `none` there
  // is no exemption and A8's sweep is total, which is right: an edge that
  // raises nothing has nothing to continue.
  //
  // Vendored popups are deliberately not consulted here, unlike in
  // topmostOverlay(). That branch reads the host's openPanelIds, which carries
  // every mounted `omarchy.` surface and not only the popups. A false positive
  // costs nothing where it is used today -- by then we have already decided to
  // clear something -- but as this gate it would stop the strip ever raising
  // the app drawer at all.
  function coveringSheet(): bool {
    for (var i = 0; i < root.overlayIds.length; i++) {
      var id = root.overlayIds[i]
      if (id === root.bottomTarget) continue
      if (root.isOpen(id)) return true
    }
    return false
  }

  function panelItem(id: string): var {
    if (!root.shell || !root.shell.panelLoaders) return null
    var loader = root.shell.panelLoaders[id]
    return loader && loader.item ? loader.item : null
  }

  function topmostOverlay(): string {
    for (var i = 0; i < root.overlayIds.length; i++)
      if (root.isOpen(root.overlayIds[i])) return root.overlayIds[i]

    // Vendored popups: omarchy.menu, omarchy.emojis, the speed tests, the image
    // selector. install/port-4x.sh stubs out HyprlandFocusGrab -- it has no
    // Quickshell.I3 counterpart -- so none of them dismiss on tap-outside and a
    // gesture is the only way out. openPanelIds is the host's own record of
    // what summon() put up; guarded, because a shell without it has to fall
    // through to closing the app rather than throwing here.
    //
    // `omarchy.` only, and never the bar. That list carries everything mounted,
    // including surfaces that are always up: hiding moarchy.gestures
    // would take away the strip the gesture arrived on, with no way back. The
    // prefix test excludes our own ids for free -- "moarchy." does not
    // start with "omarchy.". Since the rename those two differ by a single
    // transposition (m-o-a versus o-m-a), so this is worth stating rather
    // than leaving to the eye: it reads like a prefix and is not one.
    //
    // A set, not a list (refactor.md N1). The host declares `openPanelIds: ({})` and keys
    // it by plugin id, so `.length` is undefined -- which is how this branch
    // came to never run once, with nothing to say so: a back swipe over a
    // vendored popup fell straight past it to the focused window and closed
    // the app underneath the popup instead. It is B4's failure on the one path
    // B4 did not cover, and Splash.qml has been reading the same property
    // correctly, as a map, the whole time.
    //
    // The last match rather than the first. The host rebuilds the object by
    // copying what was in it and adding the new id, so key order is open
    // order and the popup summoned most recently is the one on top.
    var open = root.shell ? root.shell.openPanelIds : null
    var top = ""
    for (var id in open) {
      if (open[id] !== true) continue
      if (id.indexOf("omarchy.") === 0 && id !== "omarchy.bar") top = id
    }
    return top
  }

  // B3. Everything this shell had drawn over the workspace, put away before it
  // changes underneath. A sheet left standing while the workspace moves is a
  // gesture that visibly does nothing and silently does something.
  //
  // All of them rather than the topmost one. The two can differ -- the control center
  // pulls down over the theme picker -- and hiding only the top of that pair
  // would leave the other one covering the workspace the swipe had just
  // reached, which is the same failure one layer down.
  //
  // Vendored popups are deliberately not swept. topmostOverlay()'s fallback
  // reads the host's openPanelIds, which carries every mounted `omarchy.`
  // surface and not only the popups; a false positive costs nothing where it
  // is used today, and here it would take a surface off the screen on a swipe
  // that had nothing to do with it.
  function hideCoveringSurfaces(): void {
    if (!root.shell || typeof root.shell.hide !== "function") return
    for (var i = 0; i < root.overlayIds.length; i++)
      if (root.isOpen(root.overlayIds[i])) root.shell.hide(root.overlayIds[i])
  }

  // A7, A8. Put the topmost surface away outright. Never walks a screen's own
  // page stack: an up-flick means "get me out of here", not "up one level".
  function hideTopmostOverlay(): bool {
    var id = root.topmostOverlay()
    if (!id || !root.shell) return false
    root.shell.hide(id)
    return true
  }

  // G3. Same order, but an overlay that owns a page stack gets first refusal.
  // goBack() answers true when it consumed the gesture; false means "nothing
  // left, close me".
  //
  // The app drawer owns one: goBack() retires its app-detail card, so this branch
  // fires on every back swipe over an open card. It said the opposite until
  // refactor.md N4 -- that no sheet in overlayIds owned a stack and this was kept for a
  // future one -- which had been untrue since the card landed, and a comment
  // calling a live branch dormant is an invitation to delete it.
  function backTopmostOverlay(): bool {
    var id = root.topmostOverlay()
    if (!id || !root.shell) return false
    var item = root.panelItem(id)
    if (item && typeof item.goBack === "function" && item.goBack() === true) return true

    // A surface that draws a distinction between hidden and closed gets to
    // close itself. Nothing in this list does any more -- that distinction was
    // the shell apps', and a window has a workspace instead of it -- so this is
    // the same escape hatch the goBack() above is, kept for the same reason.
    if (item && typeof item.quit === "function") { item.quit(); return true }

    root.shell.hide(id)
    return true
  }

  // The window a back gesture would close.
  //
  // NOT ToplevelManager.activeToplevel on its own. That reads null here even
  // with a window plainly focused -- the back gesture ran, found nothing, and
  // closed nothing, while `toplevels` was populated the whole time. The
  // per-toplevel `activated` flag is the one that demonstrably tracks focus:
  // it is what the workspace overview's focused card is marked from (P4). So prefer the
  // singleton when it answers and fall back to the flag that works, rather
  // than depending on a derived property that does not.
  function focusedToplevel() {
    if (ToplevelManager.activeToplevel) return ToplevelManager.activeToplevel
    var list = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].activated) return list[i]
    return null
  }

  // The last window that had focus on the workspace we are standing on, so
  // that "is this workspace occupied" still has an answer once our own
  // surfaces have taken the focus away (windows.md L10, gestures.md F5).
  //
  // Latched rather than read, because there is no live signal left to read.
  // A sheet holds keyboard_interactivity Exclusive while it is on screen, so
  // sway deactivates the window underneath and every toplevel reads
  // `activated` false -- measured: `gestures status` over an app goes from
  // `focus=org.kde.keysmith` to `focus=none` the moment the app drawer maps, and
  // back again when it closes. The app drawer is the surface that asks this
  // question, which is why it is the surface that cannot answer it.
  //
  // Only ever *set* from a real focus, and cleared only by a workspace
  // change. Clearing it when a sheet goes down instead looked tidier and was
  // wrong: releaseStrip() hides the sheet and *then* goes home, and focus
  // takes a compositor round trip to come back -- so home asked the question
  // in the one frame where the live answer and the latched one were both
  // gone, and did nothing at all. A latch that is only invalidated by the
  // thing that actually invalidates it has no such frame.
  property var lastFocusedToplevel: null

  // Sample the focus, at a moment where it is still the app's.
  //
  // Both callers are "one of our sheets is about to take the screen", and
  // both are early enough: a drag grabs focus at `progress > 0`, which is
  // frames after the press this runs on, and a summon grabs it a compositor
  // round trip after the property change this runs on.
  function noteFocused(): void {
    var tl = root.focusedToplevel()
    if (tl) root.lastFocusedToplevel = tl
  }

  // A sheet going up, for the summon path: `shell toggle`, the store's Open,
  // a check's `app-drawer open`. The drag path cannot use it -- `releaseTarget()`
  // only summons once the finger lifts, long after the sheet took focus --
  // and goes through resolveTarget() on the press instead.
  Connections {
    target: root.shell
    function onOpenPanelIdsChanged() { root.noteFocused() }
  }

  // A workspace change, which is the one thing that makes the latch an answer
  // about somewhere else. Everything else leaves it true: a window that
  // closed is caught by the liveness test in workspaceOccupied(), and focus
  // moving between two windows of one workspace does not change whether that
  // workspace has any.
  //
  // Workspace events are the one class Quickshell refreshes this model on,
  // which is what makes clearing reliable where the reading it replaced is
  // not.
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { root.lastFocusedToplevel = null }
  }

  // F1. The lowest workspace number the compositor does not currently have.
  //
  // This used to ask each workspace whether its `representation` was empty,
  // and that was wrong for the same reason it was wrong when the strip used it
  // to choose which sheet to raise: `representation` changed on
  // *window* events while the model refreshed on *workspace* events, so a
  // workspace that gained a window still read empty. Home then switched
  // straight onto an occupied workspace. It failed as
  // `the home drag left workspace 2 holding 'V[moa-selftest]'`, which is the
  // bug naming itself.
  //
  // Existence does not go stale the same way: Sway destroys an empty
  // workspace as soon as it loses focus, so a number that is not in the list
  // is one that has nothing on it. It keeps the sideways swipe order
  // contiguous.
  //
  // `number` is the visible workspace number. `id` is an internal Sway handle,
  // and dispatching against it switches somewhere else, silently.
  //
  // ---------------------------------------------------------------------
  // One rule, two implementations (docs/refactor.md C1, C3)
  // ---------------------------------------------------------------------
  // bin/moarchy-one-app-per-workspace picks a slot by the same rule, in
  // Python, and the two are a matched pair: change one and change the other.
  // They stay separate because this one runs inside a gesture and the
  // alternative is forking `swaymsg` and parsing its JSON before `home` can
  // dispatch -- which the same constraint that keeps `dragTarget` a direct
  // object reference rules out.
  //
  // They had drifted, in both directions:
  //
  //   the cap    This returned 10 once 1..10 were taken -- an *occupied*
  //              workspace, so home landed on an app. Exactly the failure the
  //              paragraph above records, from a different cause. There is no
  //              ceiling now: sway's bindings stop at 10 but this is not a
  //              binding, and Python never had one.
  //   named      Python keyed on `int(name)`, so "3:web" raised ValueError and
  //              was skipped while sway reported it as number 3 -- a taken
  //              number read as free. Both key on the number now, and both
  //              ignore the -1 sway gives a workspace whose name carries none.
  //
  // `omarchy-shell gestures status` publishes this answer so the selftest can
  // compare the two rather than trust that they still agree.
  // What sway says is laid out on the focused workspace, or "" for a bare one.
  // Read off the workspace and not off the seat, so an exclusive-focus layer
  // surface over an app cannot make the app disappear from the answer.
  function focusedWorkspaceWindows(): int {
    var ws = Hyprland.focusedWorkspace
    if (!ws) return 0
    if (ws.toplevels && ws.toplevels.values) return ws.toplevels.values.length
    return ws.lastIpcObject ? Number(ws.lastIpcObject.windows || 0) : 0
  }

  // Is there an app on the workspace I am standing on? windows.md L10, F5.
  //
  // One question with two readers -- the home swipe and the app drawer's
  // pre-launch hop -- so one answer, here. They each had their own before, and
  // the same defect reached them one at a time.
  //
  // Focus, and focus as it was before we covered it. Nothing else:
  //
  //   the focused toplevel   right whenever anything is focused, and null
  //                          under any sheet of ours, because an exclusive
  //                          keyboard grab deactivates the window beneath
  //   the last focused one   latched before the sheet took the focus, held
  //                          until the workspace changes, and checked against
  //                          the live list here -- a window that closed while
  //                          the sheet was up must not answer for a workspace
  //                          it has left
  //
  // **Not sway's `representation`,** which used to be the second signal and
  // is wrong in both directions. It is refreshed on *workspace* events while a
  // window arrives on a *window* one, so it reads "" over an app that mapped
  // since the last switch. It is built from the workspace's *tiling* list, so
  // a floating window is not in it at all -- which is every Android window,
  // because moarchy-waydroid-setup floats them to let them overhang the output
  // (android.md AC 5): that pair is how an app came to open *underneath*
  // Spotify, full width and invisible behind it. And an emptied workspace
  // keeps a `V[]` that is not the empty string, so it says "occupied" of a
  // workspace with nothing on it -- measured on sargo, where it would send
  // home from home to a different empty workspace.
  //
  // It is still published by `gestures status`, as the reading that was not
  // enough rather than as the answer.
  function workspaceOccupied(): bool {
    if (root.focusedToplevel()) return true
    if (!root.lastFocusedToplevel) return false
    var open = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    return open.indexOf(root.lastFocusedToplevel) >= 0
  }

  function firstFreeWorkspace(): int {
    var taken = ({})
    var list = Hyprland.workspaces ? Hyprland.workspaces.values : []
    for (var i = 0; i < list.length; i++) {
      // `id` IS the visible number on Hyprland -- unlike sway, which kept a
      // separate internal handle. A special workspace (the scratchpad) has a
      // negative id, which the > 0 guard skips exactly as it always did.
      var n = list[i] ? Number(list[i].id) : -1
      if (n > 0) taken[n] = true
    }
    var free = 1
    while (taken[free]) free++
    return free
  }

  // windows.md L10. Go and stand on the workspace the next window will land on.
  //
  // Guarded, for run("home")'s reason: already on an empty workspace there is
  // nowhere to go, and going anyway hops to a *different* empty one, strands
  // a gap in the numbering and sends the sideways swipe through it.
  //
  // Called before the launch rather than after the window maps. What follows
  // is seconds of gtk-launch on this hardware, and bin/moarchy-one-app-per-
  // workspace only moves the new window once it exists -- so until then you
  // are looking at the app you launched *from*, with the splash over it.
  // That daemon is the guarantee and this is the one that makes it look
  // immediate: it counts the same occupants (W6), so a launch this one
  // declines to move is one the daemon will not move either.
  function goToFreeWorkspace(): void {
    if (root.workspaceOccupied())
      root.focusWorkspace(root.firstFreeWorkspace())
  }

  // ------------------------------------------------------ driving an overlay
  function resolveTarget(id: string, edge: string): void {
    // Before anything can go up over the workspace, which is the last moment
    // the app on it still holds focus (windows.md L10). On the press rather
    // than on the latch: most presses are a sideways swipe and this costs
    // them a property read, where `beginSheet()` would miss the swipe up that
    // carries straight on from an already-open app drawer.
    root.noteFocused()
    root.dragTarget = null
    root.dragSheet = ""
    root.dragStartPull = 0
    if (!root.shell || !root.shell.panelLoaders) return
    var loader = root.shell.panelLoaders[id]
    if (!loader || !loader.item) return
    root.dragTarget = loader.item
    root.dragSheet = id
    // Q2, Q3. The sheet is told which edge raised it, and only while it is
    // at rest shut. A sheet already up keeps the edge it came in on for the
    // rest of its life on screen: rewriting it here would teleport it across
    // the screen on the first frame of the drag that meant to continue it
    // (A6), and half a sheet held to one edge and half to another is not a
    // state this shell has a name for.
    if (typeof loader.item.entryEdge !== "undefined"
        && !loader.item.dragging && (Number(loader.item.progress) || 0) <= 0)
      loader.item.entryEdge = edge
    // Do not map the sheet here. resolveTarget runs on every strip press, and
    // most of those are a workspace swipe (B1: horizontal wins). Warming on
    // press mapped the full grid, laid it out, and left it composited on Top
    // for the duration of the switch -- the hitch that vanished when the
    // app drawer plugin failed to load. beginDrawer() maps once the tracker has
    // latched upward, which is still inside the slop of a real open.
    //
    // The app drawer's progress *is* the pull, on both surfaces, now that both
    // measure against the same travel. An already-open app drawer therefore starts
    // the next drag at 1.0, which is what lets a second swipe carry straight on
    // into the home band (A6) rather than starting over at the bottom of a
    // sheet that is already up.
    root.dragStartPull = Number(loader.item.progress) || 0
  }

  // N3, P8. Map the sheet, now that the gesture has latched. Both sheets that
  // are dragged from an edge stay mapped as a band and grow on this call, so
  // this knows which one only as "the target".
  function beginSheet(): void {
    if (root.dragTarget && typeof root.dragTarget.warming !== "undefined")
      root.dragTarget.warming = true
  }

  function setTargetProgress(pull: real): void {
    if (!root.dragTarget) return
    root.dragTarget.dragging = true
    root.dragTarget.progress = Math.max(0, Math.min(1, pull))
    // The approach to the home stop, as a 0..1 ramp the sheet lifts with. It
    // runs over the last homeExtra *before* the stop rather than after it, so
    // the cue arrives while the gesture can still be changed -- reaching full
    // exactly where letting go starts meaning home.
    //
    // Guarded like `warming` above, and for a sharper reason: assigning a
    // property a QML object does not declare throws, and a throw here aborts
    // the handler mid-frame -- so a sheet without the cue would not simply go
    // uncued, it would stop being moved at all from the first frame past the
    // ramp's start. The app drawer is the only sheet that draws it (Q1).
    if (root.dragSource === "strip"
        && typeof root.dragTarget.homeHint !== "undefined") {
      var arms = root.homeThreshold()
      root.dragTarget.homeHint = Math.max(0, Math.min(1,
        (pull - (arms - root.homeExtra)) / root.homeExtra))
    }
  }

  // Committing goes through the host rather than setting progress to 1 here,
  // so openPanelIds and the plugin cannot drift apart and leave the next swipe
  // toggling the wrong way.
  function releaseTarget(open): void {
    if (!root.dragTarget) return
    root.dragTarget.dragging = false
    // Zeroed on every strip release, open or not, and the `open` case is the
    // one that bites: a drag released in the app drawer band at, say, 55% leaves
    // homeHint at 0.43, and a hint nobody retires is a sheet that settles and
    // stays 34px above where it belongs. The carousel got away with carrying
    // this only because `summon` re-entered its open() every time; a sheet
    // that is *already* open may never see that call.
    //
    // After `dragging = false`, so the Behavior is live and this eases rather
    // than snaps -- which is the whole of F4.
    if (root.dragSource === "strip"
        && typeof root.dragTarget.homeHint !== "undefined")
      root.dragTarget.homeHint = 0
    // The sheet this gesture resolved, not the app drawer by name (P2).
    // `dragSheet` and `dragTarget` are set together or not at all, so reaching
    // here with a target means there is an id to commit through.
    if (open) Sheet.summon(root.shell, root.dragSheet)
    else if (root.shell) root.shell.hide(root.dragSheet)
    else root.dragTarget.progress = open ? 1 : 0
  }

  // How far the pill may slide from centre before it stops following.
  readonly property int pillTravel: Style.space(80)

  readonly property real pillOffset: root.tracking
    ? Math.max(-root.pillTravel, Math.min(root.pillTravel, root.dx * root.damping))
    : 0

  // B1, B2. Horizontal wins ties: a sideways swipe that drifts upward is still
  // a workspace change, which is the gesture people actually aim for. Reached
  // only when no overlay was being dragged -- a latched drag is decided by
  // travel and speed in onReleased instead.
  function commit(): void {
    if (Math.abs(root.dx) >= Math.abs(root.dy)) {
      if (root.dx <= -root.commitDistance) root.run("next")
      else if (root.dx >= root.commitDistance) root.run("prev")
    } else if (root.dy <= -root.commitDistance) {
      root.run("clear")
    }
  }

  // Every compositor call lives here, including the IPC ones.
  //
  //   next/prev  `*_on_output` keeps the switch on this screen, and matches
  //              what lisgd bound, so muscle memory carries over.
  //   home       A blank workspace, which on a phone that runs one app per
  //              workspace is what a home screen is. No extra surface,
  //              nothing resident, wallpaper and bar already there.
  //   clear      A7, A8, A9. Put away whatever is covering the screen. Never
  //              opens anything -- an up-flick from the strip means "get me
  //              out of here", not a toggle, and with nothing up it does
  //              nothing.
  function run(action: string): void {
    if (action === "next" || action === "prev") {
      // B3. Sheets only, and before the dispatch: a sheet left standing while
      // the workspace moves underneath is a gesture that visibly does nothing
      // and silently does something. A shell app is not swept -- it is a window
      // (K1), the switch leaves it behind on its own workspace, and the swipe
      // back arrives on it (K2). Sweeping it here is what made a shell app
      // impossible to swipe back to.
      root.hideCoveringSurfaces()
      // I1b. Paint before sway unmaps the window, so the first frame of the
      // switch is the theme colour rather than the wallpaper.
      root.coveringSwitch = true
      coverSettle.restart()
      root.focusWorkspaceRelative(action === "next" ? 1 : -1)
    }
    else if (action === "home") {
      // K4. A shell app goes where an app goes: nowhere. It stays mapped on its
      // own workspace, it keeps its tile in the workspace overview, and this gesture
      // leaves it the way it leaves `foot` -- by going somewhere else.
      //
      // Already on a home screen? Then there is nowhere to go, and going anyway
      // would hop to a *different* empty workspace and churn the numbering for
      // nothing.
      //
      // Occupancy, and it is asked through workspaceOccupied() because this
      // and the app drawer's pre-launch hop are the same question and drifting
      // answers to it have now cost two gestures.
      //
      // `focusedToplevel()` alone was the test here, on the reasoning that no
      // toplevel is activated when focus is on an empty workspace -- true, and
      // true for a second reason as well: an exclusive-focus *layer surface*
      // deactivates the window beneath it, so with one up every toplevel reads
      // unfocused too. The app drawer is such a surface -- it owns a search field,
      // so it takes the keyboard -- and it is what is on screen when this
      // runs, because the home band is reached by dragging it. So the drag hid
      // the app drawer, called this, and this concluded the phone was already home
      // and returned: the app drawer slid away and nothing happened.
      //
      // `representation` was added beside it and fixed that, for every app
      // sway has in its tiling list. It does not cover an Android one -- a
      // floating window is in no representation at all -- so from Spotify the
      // home swipe went back to doing nothing, which is the same defect
      // arriving a second time through the same gap.
      if (root.workspaceOccupied())
        root.focusWorkspace(root.firstFreeWorkspace())
    }
    else if (action === "clear") root.hideTopmostOverlay()

    // C1, C5. The default coding agent, from a gesture that has no name to
    // give it.
    else if (action === "agent") {
      // B3's reason, on a gesture that opens a window rather than switching to
      // one: the agent arrives on a workspace of its own, and a sheet left
      // standing over it is a hold that appears to have done nothing at all.
      root.hideCoveringSurfaces()

      // Q10. Whatever the hold is set to, which ships as the coding agent and
      // so still means C1 on a phone nobody has configured. `moarchy-trigger`
      // is the one place that decides what a value means, because the power
      // button's double press fires the same vocabulary from a sway binding
      // and a rule written at both ends is the defect refactor.md B1 records.
      //
      // Still the agent's own launcher underneath: with one picked it opens
      // it, with none it opens the picker, and the app drawer's tile is rewritten
      // on the way so the icon and this gesture cannot come to name different
      // agents (settings.md P12).
      //
      // execDetached rather than a Process, for the reason hideKeyboard gives:
      // there is no answer to wait for, and what it starts must outlive a
      // shell restart the way anything else launched from the grid does.
      Quickshell.execDetached(["moarchy-trigger", "fire", "hold"])
    }
  }

  // ------------------------------------------------------------------- back
  //
  // G1. One gesture that undoes the topmost thing: keyboard, then any open
  // overlay, then the focused app, then nothing.
  //
  // Whether the keyboard is up cannot be answered synchronously -- the keyboard
  // owns it over DBus and there is no Wayland signal for it -- so the probe is
  // started on press and read on release. A deliberate swipe has to travel
  // backCommit, which takes longer than busctl does; if it somehow has not
  // answered yet, retry once rather than guess, because guessing wrong here
  // closes an app the user only meant to un-cover.
  property bool keyboardUp: false
  property bool keyboardKnown: false
  property int backRetries: 0
  readonly property int backRetryLimit: 6

  Shared.Probe {
    id: keyboardProbe
    command: ["busctl", "--user", "get-property", "sm.puri.OSK0",
              "/sm/puri/OSK0", "sm.puri.OSK0", "Visible"]
    // `busctl get-property` prints the variant as e.g. `b true`.
    onAnswered: {
      root.keyboardUp = String(text).indexOf("true") >= 0
      root.keyboardKnown = true
    }
  }

  Timer {
    id: backRetry
    interval: 120
    onTriggered: root.performBack()
  }

  // I1b. Long enough for the destination window to map on this hardware;
  // short enough that a swipe onto an empty workspace does not keep the
  // theme colour over the wallpaper. Harmless if fillWorkspace is still
  // true for another reason -- the fill does not depend on this flag alone.
  Timer {
    id: coverSettle
    interval: 280
    onTriggered: root.coveringSwitch = false
  }

  // Warmed once at startup, so the first back gesture is not the one that pays
  // for a cold DBus connection. The probe is fast once the path has been
  // exercised and slow the very first time, and performBack spends its whole
  // retry budget waiting before falling back to the keyboard branch -- correct,
  // but it means the first back after a shell restart gets consumed by the
  // probe instead of reaching the overlay underneath.
  Component.onCompleted: {
    root.warmCompositorModels()
    root.startKeyboardProbe()
  }

  function startKeyboardProbe(): void {
    root.keyboardKnown = false
    root.backRetries = 0
    // Toggled off first. Setting `running` true on a Process that is already
    // running is a no-op, so a probe still in flight from the previous gesture
    // left keyboardKnown false and the answer stale.
    keyboardProbe.running = false
    keyboardProbe.running = true
  }

  // G2. The one call this plugin makes, and the one way the keyboard goes
  // down. The incantation itself is moarchy.common/Osk.qml, which a tap on a
  // text field also asks (G14a).
  Shared.Osk { id: osk }

  // Q1. Which sheet each of the two configurable edges raises. Watched, so a
  // change is live on the next gesture with nothing restarted (Q8) -- the
  // same file and the same watch the corner radii already arrive through.
  //
  // "" is `none`, and it needs no branch of its own anywhere below:
  // resolveTarget() already leaves `dragTarget` null for an id it cannot
  // find, and every tracker already tests for one before it latches (Q5).
  Shared.UiFile { id: ui }

  readonly property string bottomTarget: ui.bottomTargetId
  readonly property string rightTarget: ui.rightTargetId

  function hideKeyboard(): void { osk.hide() }

  // ------------------------------------------------------- G12: the back cue
  //
  // How far the back gesture has come, 0 at the edge and 1 at the commit. The
  // edge is the one gesture on this phone with nothing to look at: the surface
  // is transparent and reserves nothing, so where it stops is invisible from
  // the outside -- which is the same argument C2's shake makes for the hold.
  property real backPull: 0

  // True from the moment the gesture commits until the cue has finished, so
  // the arc does not snap away under the finger that earned it.
  property real backFlash: 0

  function performBack(): void {
    if (!root.keyboardKnown && root.backRetries < root.backRetryLimit) {
      root.backRetries++
      backRetry.restart()
      return
    }

    // G2. If the probe still has not answered, take the keyboard branch
    // anyway: it is the reversible one. Acting on a stale `keyboardUp` closed
    // an app while the keyboard was plainly up, which is the one outcome this
    // gesture must never produce by accident.
    if (root.keyboardUp || !root.keyboardKnown) { root.hideKeyboard(); return }

    // G3
    if (root.backTopmostOverlay()) return

    // K7. A shell app owns a page stack, and back walks up it before leaving
    // the window. Asked of the *focused window* and not of a list of open
    // overlays: a shell app is a window (K1), so "which one am I in" is the
    // same question G4 asks a line below, and asking it here is what keeps back
    // inside Settings from falling through to closing the app on the workspace
    // beside it.
    //
    // goBack() answers true when it consumed the gesture; false means there is
    // nothing left, and the window takes G4's close request like any other.
    var own = root.focusedShellApp()
    if (own && typeof own.goBack === "function" && own.goBack() === true) return

    // G4, G7. close() is xdg_toplevel.close -- a close *request*, so an editor
    // with unsaved work prompts rather than dies. That is what makes firing it
    // from a swipe acceptable at all.
    var tl = root.focusedToplevel()
    if (tl) { tl.close(); return }

    // G4 again, for when the foreign-toplevel state says nothing is activated
    // and a window is plainly there. Sway can end up with a workspace focused
    // and no window inside it focused -- `[app_id=...] focus` then reports
    // success and changes nothing -- and in that state this gesture silently
    // did nothing at all.
    //
    // `kill` is the same close *request*, addressed to whatever Sway considers
    // focused. It closes the window in that state and is a no-op on a genuinely
    // empty workspace, which keeps G5 true: on a bare home screen there is
    // nothing focused for it to reach.
    root.closeFocused()
  }

  // ------------------------------------------------------- press and hold
  //
  // C. A press that stays put starts the default coding agent. Every other
  // gesture on this strip is decided by travel; this is the one a clock
  // decides, and so the one with nothing to look at while it is being decided.
  // That is what the shake is for (C2), and it is not decoration: a 4px line
  // under a motionless thumb looks exactly like a 4px line under a thumb that
  // is resting, and a gesture nobody can tell is happening is a gesture nobody
  // finds.
  //
  // Timers rather than a TapHandler, for the reason the app drawer's hold gives at
  // length (L1): the MultiPointTouchArea below owns the exclusive grab, so a
  // handler beside it would get a passive one and lose the press wherever that
  // area decided the gesture was over. A timer armed on press has no grab to
  // lose.

  // C1. L1's number, deliberately. A phone has one hold, not one per surface.
  readonly property int holdDelay: 500

  // C2. How long the press stays silent before the pill starts to move. Every
  // gesture here opens with a press -- A's drag, B's swipe, a tap that means
  // nothing -- so a cue that begins on contact fires on all of them, and a cue
  // that fires on everything says nothing.
  readonly property int holdCueDelay: 150

  // How far the pill swings, either side of where it sits. Enough to read as
  // deliberate on a line this thin, and well short of pillTravel, so the shake
  // cannot be mistaken for the pill following a finger sideways (pillOffset).
  readonly property int holdShakeTravel: Style.space(4)

  property bool holdShaking: false

  // C3. True from the moment the hold fires until the next press: the rest of
  // that touch means nothing, because it has already meant something. Cleared
  // on press and not on release, which is L2's correction -- cleared on release
  // it is already false by the time the release path asks.
  property bool holdFired: false

  // Written by the animations beside the pill and read by its bindings. The
  // pill's x IS a binding, so an animation that targeted it directly would
  // break that binding for good and the pill would stop tracking a sideways
  // drag ever after.
  property real holdShake: 0
  property real holdPop: 0

  function armHold(): void {
    root.holdFired = false
    holdCue.restart()
    holdTimer.restart()
  }

  // Idempotent, and called from every path that ends a touch -- including the
  // ones where nothing was armed.
  function cancelHold(): void {
    holdTimer.stop()
    holdCue.stop()
    root.holdShaking = false
    root.holdShake = 0
  }

  Timer {
    id: holdCue
    interval: root.holdCueDelay
    onTriggered: root.holdShaking = true
  }

  Timer {
    id: holdTimer
    interval: root.holdDelay
    onTriggered: {
      // The shake stops before the flash starts, or the pill is swinging while
      // it swells and the two cues read as one smear.
      root.cancelHold()
      root.holdFired = true
      holdFlash.restart()
      root.run("agent")
    }
  }

  // Back to rest. Every path out of a gesture goes through this.
  function reset(): void {
    // Clearing `lastDrag` retires `tracking`, `pull`, `velocity`, `dx` and
    // `dy` in one assignment, which is what they were zeroed one by one for.
    // Before cancelHold(), so the pill's Behavior is live again and a shake
    // that was in flight springs back to centre instead of snapping there.
    //
    // holdFired is deliberately NOT cleared here: the release path has already
    // read it by the time this runs, and clearing it on the way out would
    // leave the flag false for a touch that has not started yet. The next
    // press retires it (C3), which is L2's correction over again.
    root.lastDrag = null
    root.cancelHold()
    // N3. A sheet warmed for a gesture that never became one goes back to
    // unmapped. `progress` keeps it up while it is actually being drawn, so
    // this only retires a map nothing used.
    if (root.dragTarget && typeof root.dragTarget.warming !== "undefined")
      root.dragTarget.warming = false
    root.dragMode = "none"
    root.pendingMode = "none"
    root.dragSource = ""
    root.dragTarget = null
    root.dragSheet = ""
    root.dragStartPull = 0
  }

  // A2-A4, A6. What a release on the strip means, in one place rather than in
  // the strip's own handler: travel past the home stop goes home, and below it
  // the sheet commits on travel or on a fling in either direction.
  //
  // Distance alone decides home. A fling may never carry the drag past a stop
  // the finger did not reach, or the destination stops being predictable.
  function releaseStrip(): void {
    if (root.pull >= root.homeThreshold()) {
      root.releaseTarget(false)
      root.run("home")
    } else {
      root.releaseTarget(root.openVelocity >= root.fling
        || (root.openVelocity > -root.fling && root.pull >= root.sheetCommit))
    }
  }

  // A touch sequence normally ends in released or canceled, but a compositor
  // restart or a lost seat can strand one mid-gesture. Nothing dangerous
  // happens if it does -- no surface here grows, so input is never trapped --
  // but a sheet would sit parked half-open with nothing left to finish it.
  //
  // It is DragTracker's now, and arrives with it on all four surfaces rather
  // than on the two that remembered (F2).
  function dropDrag(): void {
    // A dropped touch changed nothing, so the sheet goes back where it was.
    if (root.dragMode !== "none") root.releaseTarget(false)
    root.reset()
  }

  // A6. The strip continues an already-open sheet rather than restarting it,
  // so a second drag runs on into the home band. resolveTarget() reads
  // dragSource to decide that, which is why both are set before this is.
  Shared.DragTracker {
    id: stripDrag
    travel: root.targetTravel()
    openDirection: -1
    // Upward only, which on Y is a negative delta.
    latchSign: -1
    // B2. A sideways swipe on this strip is a different gesture and must never
    // latch this one, however far the thumb's arc wanders vertically.
    axisDominant: true
    slop: root.slop
    // C3. A hold that has fired takes the rest of the touch with it: the agent
    // is on its way and the sheets are already swept, so a finger that wanders
    // afterwards must not also arrive at the app drawer it just put away.
    // Q4. `pendingMode` already carries the answer: it is "none" when a
    // sheet is covering the screen, "home" when this edge raises nothing,
    // and an id when there is something to drag. Testing `dragTarget` here
    // as well is what would take the second stop away with the sheet.
    latchable: !root.holdFired && root.pendingMode !== "none"
    startFrom: root.dragStartPull

    onBegan: {
      root.dragMode = root.pendingMode
      if (root.dragMode !== "none" && root.dragMode !== "home")
        root.beginSheet()
    }
    onMoved: p => root.setTargetProgress(stripDrag.travelled)
    onFinished: (p, v) => root.releaseStrip()
    onCanceled: from => root.dropDrag()
  }

  // D. The wallpaper raises the same sheet with the same rule and has no
  // second stop: a home screen has nowhere further to go.
  Shared.DragTracker {
    id: homeDrag
    travel: root.targetTravel()
    openDirection: -1
    latchSign: -1
    axisDominant: true
    slop: root.slop
    latchable: root.dragTarget !== null && root.dragStartPull < 1
    startFrom: root.dragStartPull

    onBegan: {
      root.dragMode = root.dragSheet
      root.beginSheet()
    }
    onMoved: p => root.setTargetProgress(homeDrag.travelled)
    onFinished: (p, v) => root.releaseTarget(
      root.openVelocity >= root.fling
      || (root.openVelocity > -root.fling && root.pull >= root.sheetCommit))
    onCanceled: from => root.dropDrag()
  }

  // G6, G8. The back edge, which is the fifth gesture and was the one §F did
  // not reach (H1). It travels sideways, so it is this component with `axis`
  // set rather than the private copy of it that stood here -- start
  // coordinates, clamp, axis test and per-frame trace ring, and no watchdog, so
  // a touch the compositor took away left the cue drawn on screen with nothing
  // to retire it.
  Shared.DragTracker {
    id: backDrag
    axis: "x"
    travel: root.backCommit
    // Inward raises it, and only inward latches: rightward is a positive delta
    // on X the way downward is on Y.
    openDirection: 1
    latchSign: 1
    // G6. A vertical scroll that begins at the edge is not a back.
    axisDominant: true

    onBegan: root.backTrace = []

    // The cue is the release rule as a ramp, and the axis test stays in it: a
    // gesture the release would refuse must never show an arc, or the arc
    // promises something that then does not happen. The tracker latches once
    // and keeps tracking; whether *this frame* still counts as sideways is the
    // surface's own question (F3).
    onMoved: p => {
      root.backPull = Math.abs(backDrag.dx) > Math.abs(backDrag.dy) ? p : 0
      root.markBackTrace(Math.round(root.backPull * 100))
    }

    onFinished: (p, v) => {
      // G6. Inward, far enough, and more sideways than not.
      var commits = backDrag.dx >= root.backCommit
                    && Math.abs(backDrag.dx) > Math.abs(backDrag.dy)
      root.backPull = 0
      if (commits) { backFlashAnim.restart(); root.performBack() }
    }

    onStranded: root.markBackTrace(-2)
    onCanceled: from => { root.backPull = 0; root.markBackTrace(-1) }
  }

  // P1, P2. The right edge, which drags a sheet rather than arming a command --
  // so unlike the back edge it looks like the strip's tracker with `axis` set,
  // not like backDrag.
  //
  // Leftward opens, which is a negative delta on X the way upward is on Y, so
  // `openDirection` and `latchSign` are both -1. `axisDominant`, because a
  // vertical drag that begins at the edge is an app being scrolled, exactly as
  // G6 says of the other side.
  Shared.DragTracker {
    id: workspaceOverviewDrag
    axis: "x"
    travel: root.targetTravel()
    openDirection: -1
    latchSign: -1
    axisDominant: true
    slop: root.slop
    // Nothing to drag means nothing to latch: the plugin can have failed to
    // load, and an already-open workspace overview has nowhere further to go -- there is
    // no second stop past this sheet the way there is past the app drawer (A4).
    latchable: root.dragTarget !== null && root.dragStartPull < 1
    startFrom: root.dragStartPull

    onBegan: {
      root.dragMode = root.dragSheet
      root.beginSheet()
    }
    onMoved: p => root.setTargetProgress(workspaceOverviewDrag.travelled)

    // The app drawer's release rule, on the other axis (P2). `v` is signed toward
    // open, so a fling out from the edge is the positive one.
    onFinished: (p, v) => {
      root.releaseTarget(v >= root.fling
        || (v > -root.fling && workspaceOverviewDrag.travelled >= root.sheetCommit))
      root.reset()
    }

    onCanceled: from => root.dropDrag()
  }

  // Lets the wiring be tested without a finger:
  //   omarchy-shell gestures swipe left
  //   omarchy-shell gestures back
  IpcHandler {
    target: "gestures"

    function swipe(direction: string): string {
      if (direction === "left") { root.run("next"); return "ok: next workspace" }
      if (direction === "right") { root.run("prev"); return "ok: previous workspace" }
      if (direction === "home") { root.run("home"); return "ok: home" }
      if (direction === "up") {
        // The same choice a real strip swipe makes, so this exercises the
        // decision and not just one branch of it. Both branches of it, now:
        // the third case -- "nothing is open, so there is nothing to show" --
        // went with the carousel (A9).
        if (root.coveringSheet()) {
          root.run("clear")
          return "ok: cleared"
        }
        // Distance is what picks the second stop (A4) and an IPC verb has no
        // distance, so this one always means the first. `swipe home` is the
        // other one, and it is already here.
        //
        // Q1: the sheet the strip raises, because this verb exists to make
        // the same choice a real strip swipe makes. `gestures workspaceOverview` is
        // the other kind of verb -- it is named after a plugin and summons
        // that plugin, whatever any edge is set to.
        if (root.bottomTarget === "") return "ok: nothing on the bottom edge"
        Sheet.summon(root.shell, root.bottomTarget)
        return "ok: " + root.bottomTarget
      }
      return "usage: swipe left|right|up|home"
    }

    // C1. The hold, without a finger.
    //
    // This one really launches: there is nothing behind it to stub, so on a
    // phone that has picked an agent it has never installed, the first call
    // downloads it through mise. That is why the gesture suite does not fire it
    // -- a check that installs a package to prove a gesture works has changed
    // the phone it was measuring.
    function hold(): string {
      root.run("agent")
      return "ok: agent"
    }

    // P1. The right edge, without a finger. Distance is what opens the sheet
    // and an IPC verb has no distance, so this is the committed end of it --
    // `workspace-overview progress` is where a real drag is measured.
    function workspaceOverview(): string {
      Sheet.summon(root.shell, Sheet.WORKSPACE_OVERVIEW)
      return "ok: workspaceOverview"
    }

    // Q1. What each configurable edge is set to, as ids. The words live in
    // ui.toml and the ids live in Sheet.js; this is the one place outside
    // the shell that the two are seen to have met.
    function targets(): string {
      return "bottom=" + (root.bottomTarget || "none")
             + " right=" + (root.rightTarget || "none")
    }

    // Q1, Q9. The summon an edge performs, named by the edge rather than by
    // the plugin -- so a check can exercise the configurable path without
    // knowing what it is configured to.
    function edge(which: string): string {
      var id = which === "bottom" ? root.bottomTarget
             : which === "right" ? root.rightTarget : null
      if (id === null) return "usage: edge bottom|right"
      if (id === "") return "ok: nothing on the " + which + " edge"
      Sheet.summon(root.shell, id)
      return "ok: " + id
    }

    // G. Reachable without a finger, and the only way to test the priority
    // order without a keyboard on screen.
    function back(): string {
      root.startKeyboardProbe()
      root.performBack()
      return "ok: back"
    }

    // G10. The back edge is transparent and reserves nothing, so where it stops
    // is invisible from the outside and unmeasurable with a finger: a tap below
    // the cut and a tap on a dead edge look identical, which is the confusion
    // that let the keyboard's left column stay swallowed. Ask instead.
    // G12. One integer per frame of a back gesture, cleared on the next press.
    // The same instrument `app-drawer dragTrace` is, for the same reason: a cue
    // that appeared at the threshold and one that followed the finger look
    // identical in a screenshot and identical to `state`, and only the sample
    // count tells them apart.
    function backTrace(): string { return root.backTrace.join(" ") }

    function geometry(): string {
      // G13. `w` is the *input* band and stays that, with the drawn width
      // published beside it. Repurposing `w` would change what every existing
      // reader is asserting without the reader noticing.
      //
      // P8's numbers are appended rather than given a verb of their own, for
      // the same reason `w` keeps its meaning: the two edges share both insets,
      // so a check that read one edge's `inset` and the other's from a second
      // command could pass while they had come apart.
      return "backEdge w=" + root.backEdgeWidth
             + " surfaceW=" + Math.round(backEdge.width)
             + " h=" + Math.round(backEdge.height)
             + " inset=" + root.edgeBottomInset
             // G10b. Published beside the bottom one, because `h` alone cannot
             // say which end a missing band was lost at.
             + " topInset=" + root.edgeTopInset
             + " header=" + root.headerBarHeight
             + " strip=" + root.stripHeight
             + " panel=" + osk.keyboardPanelHeight
             + " screen=" + (backEdge.screen ? backEdge.screen.height : 0)
             // I1a. The band under the pill, and the two answers it is decided
             // from. `home` is published because it is the measurement -- a
             // check that read only `band` could not tell "the keyboard is up"
             // from "this surface never got a configure".
             + " home=" + Math.round(home.height)
             + " kbd=" + (root.keyboardReserving ? 1 : 0)
             + " band=" + (root.fillStripBand ? 1 : 0)
             // P8. The right edge. `workspaceOverviewW` is its input band, and it has no
             // drawn width to publish beside it -- the surface is the band,
             // because nothing is drawn on it (P1). `workspaceOverviewSurfaceW` says so
             // rather than being left out: an equal pair is the assertion.
             + " workspaceOverviewW=" + root.workspaceOverviewEdgeWidth
             + " workspaceOverviewSurfaceW=" + Math.round(workspaceOverviewEdge.width)
             + " workspaceOverviewH=" + Math.round(workspaceOverviewEdge.height)
    }

    function status(): string {
      var tl = root.focusedToplevel()
      // C3. `free` is the answer bin/moarchy-one-app-per-workspace computes
      // independently for the same phone, and publishing it is the only way
      // the selftest can hold the two implementations against each other.
      // K7. `shellapp` is the plugin id of the shell app the back gesture would
      // hand this swipe to, or `none`. Published because the resolution is by
      // toplevel handle and is otherwise invisible from outside: a card with a
      // missing icon and a back swipe that closes the wrong thing are the same
      // fault, and this is the one place a check can see it.
      var own = root.focusedShellApp()
      var focus = " focus=" + (tl ? (tl.appId || "?") : "none")
                  + " apps=" + (ToplevelManager.toplevels
                                ? ToplevelManager.toplevels.values.length : 0)
                  + " free=" + root.firstFreeWorkspace()
                  + " shellapp=" + (own ? own.pluginId : "none")
                  // What sway says is laid out here. It was the home switch's
                  // second signal (F5) and is no longer any switch's signal
                  // at all, and it is published for exactly that reason: it
                  // is the reading that looks like it answers this question
                  // and does not, in both directions, and a check can only
                  // say which reading moved if it can see them all.
                  + " wins=" + root.focusedWorkspaceWindows()
                  // windows.md L10, F5. The answer the two fields above are
                  // read for, and now neither of them: over an Android app
                  // with the app drawer up, `focus` is none and `rep` is "" and
                  // the workspace is occupied all the same. A check that
                  // could only see the inputs would have to reimplement the
                  // rule to test it.
                  + " occupied=" + (root.workspaceOccupied() ? "yes" : "no")
                  // C2. Where the hold stands. Published because the cue it
                  // drives is a 4px line moving 4px, which no other check can
                  // see -- and because `idle` here is the cheapest proof from
                  // outside that the build on the phone is one that has the
                  // gesture at all.
                  + " hold=" + (root.holdFired ? "fired"
                                : root.holdShaking ? "shaking"
                                : holdTimer.running ? "armed" : "idle")
                  // Q1. Which sheet each configurable edge raises, so a
                  // check that is about to drag one can say what it expected
                  // -- and so "the edge did nothing" can be told from "the
                  // edge is set to nothing" without reading the file.
                  + " bottom=" + (root.bottomTarget || "none")
                  + " right=" + (root.rightTarget || "none")
      if (!root.tracking) return "idle" + focus
      return "tracking mode=" + root.dragMode
             + " pull=" + Math.round(root.pull * 100)
             + " dx=" + Math.round(root.dx) + " dy=" + Math.round(root.dy) + focus
    }
  }

  // ======================================================= the bottom strip
  PanelWindow {
    id: strip

    // Anchoring left+right+bottom without `top` gives a full-width strip whose
    // height we set. Sizing the surface to the strip means the surface *is* the
    // input region, so touch outside it reaches the app with no `mask` needed.
    anchors { bottom: true; left: true; right: true }
    implicitHeight: root.stripHeight

    // Transparent everywhere, including over an Android window, and that last
    // part is a claim about the container rather than about this file --
    // docs/android.md AC 12. Android draws its own gesture handle inside the
    // app surface, 108dp wide and 10dp up from the bottom of ITS display,
    // which lands on the same rows as this pill; for a few hours this strip
    // went opaque to cover it and the app's own background stopped an inch
    // short of the screen. `moarchy-waydroid-setup` now takes the handle out at
    // the source -- a fabricated RRO zeroing SystemUI's
    // `navigation_handle_radius` -- so there is nothing left here to hide, and
    // what fills this band is the app's own background in the nav bar inset
    // region it has already padded its content clear of.
    color: "transparent"

    WlrLayershell.namespace: "moarchy-gestures"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Reserve the strip instead of floating over the app, the way Android's
    // navigation bar does. Layer-shell surfaces are arranged against the
    // remaining area, so the on-screen keyboard is placed *above* the strip
    // rather than on top of it, and the pill stays reachable while typing.
    //
    // Measured, not assumed: on Bottom the keyboard took the edge and stranded
    // the app drawer above it, and restarting either one in either order changed
    // nothing -- it is layer order, not map order.
    exclusionMode: ExclusionMode.Auto

    Rectangle {
      id: pill

      width: Style.space(96)
      height: Math.max(2, Style.space(4))
      radius: height / 2
      anchors.verticalCenter: parent.verticalCenter
      x: (parent.width - width) / 2 + root.pillOffset + root.holdShake

      // Brightens while tracking, and stretches as an upward swipe approaches
      // the first stop. Armed for home it goes accent, and the sheet has been
      // lifting for the last 15% of travel on its way there (homeHint):
      // between them they are the cue that letting go now goes somewhere else
      // than the sheet you are looking at.
      //
      // C2. The hold borrows that same vocabulary for its own moment -- accent
      // and a swell -- rather than inventing a third colour for a strip that
      // has room for one idea at a time. It differs in that it decays
      // (holdPop), because arming for home is a state you can still leave and
      // firing the hold is a thing that has already happened.
      color: root.homeArmed ? Color.accent
           : root.holdPop > 0 ? Util.alpha(Color.accent, 0.4 + 0.6 * root.holdPop)
           : Util.alpha(Color.foreground, root.tracking ? 0.9 : 0.3)
      scale: root.homeArmed ? 1.6
           : 1 + 0.5 * root.holdPop
             + Math.min(0.4, Math.max(0, -root.dy) / (root.commitDistance * 4))

      // The pill used to be guaranteed its contrast, because the band behind it
      // was either this strip's own colour or the wallpaper. Over an Android
      // app it is the app's background: 15 on YouTube, 255 on Maps, and a 30%
      // foreground pill measures 235 against the second -- there, but only
      // just.
      //
      // So carry the contrast rather than borrow it. This ring is
      // `Color.background`, which is the colour of whatever this strip sits on
      // everywhere except an Android window, so it is invisible by
      // construction in the case it is not needed and an outline in the case it
      // is. A child with a negative z draws behind its parent, which also means
      // it inherits the pill's x and scale -- the two things every animation in
      // here drives -- without a binding of its own.
      Rectangle {
        z: -1
        anchors.fill: parent
        anchors.margins: -1
        radius: height / 2
        color: Util.alpha(Color.background, 0.55)
      }

      Behavior on x {
        enabled: !root.tracking
        SpringAnimation { spring: 4; damping: 0.35 }
      }
      // Arming happens mid-touch, so this one has to run while tracking --
      // otherwise the accent state snaps in with no cue.
      Behavior on scale {
        enabled: !root.tracking || root.homeArmed
        SpringAnimation { spring: 4; damping: 0.35 }
      }
      Behavior on color { ColorAnimation { duration: 140 } }

      // C2. The shake, which is the whole of what a hold shows before it fires.
      //
      // Three legs rather than a symmetric wobble: out, back through centre to
      // the far side, then home. A 220ms round trip reads as impatience --
      // something waiting to happen -- where a slower one reads as drift and a
      // faster one as a rendering fault. It loops until the hold fires or the
      // touch ends, so the cue lasts exactly as long as the thing it is a cue
      // for.
      //
      // `running` is bound rather than started by hand: cancelHold() has four
      // callers and every one of them would otherwise have to remember this.
      SequentialAnimation {
        id: holdShakeAnim
        running: root.holdShaking
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "holdShake"
                          to: root.holdShakeTravel; duration: 55
                          easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "holdShake"
                          to: -root.holdShakeTravel; duration: 110
                          easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "holdShake"
                          to: 0; duration: 55
                          easing.type: Easing.InOutSine }
      }

      // And the moment it fires. Self-retiring, unlike homeArmed: the finger
      // may sit on the strip for as long as it likes after the agent has been
      // asked for, and a pill that stays accent until it is lifted is a strip
      // that looks stuck.
      SequentialAnimation {
        id: holdFlash
        NumberAnimation { target: root; property: "holdPop"; to: 1
                          duration: 90; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "holdPop"; to: 0
                          duration: 320; easing.type: Easing.InOutSine }
      }
    }

    MultiPointTouchArea {
      anchors.fill: parent
      maximumTouchPoints: 1

      onPressed: pts => {
        if (pts.length === 0) return
        root.dragMode = "none"
        root.dragTarget = null

        // The whole decision, and it is now three lines:
        //
        //   a sheet covering the screen -> the release clears it (A8)
        //   a sheet set on this edge    -> drag it (A1-A4, Q1)
        //   neither                     -> home, and nothing else (Q4)
        //
        // Four cases became two when the carousel went. "The sheet is
        // already up" is gone because this edge's own sheet is not a special
        // case of itself -- coveringSheet() exempts it, so a second drag
        // continues into the home band (A6). "Is anything open at all" is
        // gone with A9: the sheet opens over an app, over a home screen and
        // over nothing, so there is no state left to ask the compositor about.
        //
        // What survives from the old note is why the first line is a
        // *derived* list: it used to name the control center and the app drawer by hand,
        // which left Settings and the theme picker falling through it.
        root.dragSource = "strip"
        // Q4, Q5. A target that did not resolve -- `none`, or a plugin that
        // is not loaded -- is the same answer as no target at all, and both
        // still leave the second stop, because home is not a sheet.
        var covered = root.coveringSheet()
        root.resolveTarget(covered ? "" : root.bottomTarget, Edge.BOTTOM)
        root.pendingMode = covered ? "none"
                         : (root.dragTarget ? root.dragSheet : "home")

        // C1. And the clock, which is the only thing on this strip that starts
        // anything without being told which way the finger went. It is armed on
        // every press and cancelled by the first pixel past the slop, so the
        // cost to a swipe is a timer that never reaches 500ms.
        root.armHold()

        root.lastDrag = stripDrag
        stripDrag.press(pts[0].sceneX, pts[0].sceneY)
      }

      onUpdated: pts => {
        if (pts.length === 0 || !root.tracking) return
        stripDrag.move(pts[0].sceneX, pts[0].sceneY)

        // C3. Travel cancels the hold, on either axis and in either direction,
        // and it cannot be the tracker's latch that does it: a sideways swipe
        // never latches -- the whole of B runs un-latched -- so a thumb that
        // had crossed half the screen would still be sitting on a live timer.
        // The tracker publishes dx and dy before it decides anything, which is
        // what makes them readable here.
        if (Math.abs(root.dx) > root.slop || Math.abs(root.dy) > root.slop)
          root.cancelHold()
      }

      onReleased: pts => {
        if (!root.tracking) return
        // Read before release(), which clears it.
        var latched = stripDrag.latched
        // Commits through onFinished when it latched; A2-A4 live in
        // releaseStrip().
        stripDrag.release()
        // C3. Reached only when the hold did not fire. A fired one has
        // consumed the press, and the lift after it means nothing -- which is
        // what keeps a 500ms press that drifted 6px from also changing
        // workspace on the way out.
        if (!latched && !root.holdFired) root.commit()
        root.reset()
      }

      // dropDrag() is the tracker's canceled handler, so this needs no body
      // beyond handing the cancel on -- including the stranded case, which
      // arrives the same way.
      onCanceled: pts => stripDrag.cancel()
    }
  }

  // ======================================================= the home screen
  //
  // D. Full screen and on the Bottom layer, which is the entire mechanism:
  // above the wallpaper, below every window. On a blank workspace it gets the
  // touch; on an occupied one the app is over it and it gets nothing. Gaps are
  // `outer 0` here, so a lone window reaches the screen edge and leaves no
  // border for this to catch a stray swipe in.
  //
  // Nothing about this asks the compositor which workspace is focused or
  // whether anything is on it. That question is what the previous version got
  // wrong, and the answer is not needed: layer order already knows.
  PanelWindow {
    id: home

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "moarchy-home"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Reserve nothing. This must never change any window's geometry -- it is
    // only here to catch a gesture on empty space, and now to fill the band the
    // strip reserves (I1a).
    //
    // `Normal` with a zero zone rather than `Ignore`, which is what this was.
    // Both reserve nothing; the difference is that `Ignore` asks for the whole
    // output and `Normal` is arranged into what the exclusive surfaces left --
    // which is what lets this surface's own height say whether the keyboard is
    // up (`keyboardReserving`). Nothing about the touch catcher depends on the
    // difference: the bands it gives up are the bar's and the keyboard's, and
    // both of those are opaque surfaces above this one that were taking those
    // touches already.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    // And then back down over the strip, so the band the strip reserves is
    // still this surface's to paint. The same negative margin the sheets use
    // for the same reason (I1, I3): wlroots stores layer-shell margins as
    // int32_t and subtracts them without clamping, so a negative one extends
    // the surface rather than shrinking it.
    margins.bottom: -root.stripHeight

    // I1a / I1b. Theme background, filled from underneath.
    //
    // Underneath is the whole trick. Bottom is below every window, so at rest
    // this is covered except in the band no window is drawn in; and it is
    // below every sheet, so the app drawer, the control center and the theme picker draw
    // over it exactly as before. Painting from the *strip* instead would have
    // put it over all four.
    //
    // The whole arranged area, not only the strip band. A strip swipe unmaps
    // the window for a frame, and an unfilled surface is the wallpaper
    // flashing through -- ugliest from a terminal, where the keyboard is up
    // and I1a has already turned the band fill off. The fill is already
    // painted before that frame because an occupied workspace keeps it up.
    // An empty workspace is the home screen and still shows the wallpaper.
    //
    // Gutters (gaps on, or two windows tiled) pick up the same colour. That
    // is the cost of the fill being there before the window leaves.
    Rectangle {
      anchors.fill: parent
      color: Color.background
      visible: root.fillWorkspace
    }

    MultiPointTouchArea {
      anchors.fill: parent
      maximumTouchPoints: 1

      // Its own tracker, because this surface and the strip can both be
      // mid-gesture in principle and one origin shared between them would let
      // either clobber the other's.
      onPressed: pts => {
        if (pts.length === 0) return
        root.dragMode = "none"
        // Set before resolveTarget, which reads it to decide where this drag
        // starts from.
        root.dragSource = "home"
        // Q1. The strip's sheet, because the wallpaper is the strip's drag
        // without the second stop (D1) and not a gesture with a destination
        // of its own. With no sheet on that edge there is nothing here to
        // reach -- a home screen is already home -- so this one does not get
        // the "home" mode the strip does, and `latchable` below still tests
        // for a target.
        root.resolveTarget(root.bottomTarget, Edge.BOTTOM)
        root.pendingMode = root.dragTarget ? root.dragSheet : "none"

        root.lastDrag = homeDrag
        homeDrag.press(pts[0].sceneX, pts[0].sceneY)
      }

      onUpdated: pts => {
        if (pts.length > 0) homeDrag.move(pts[0].sceneX, pts[0].sceneY)
      }

      // D4. Sideways and downward do nothing here, so there is no commit()
      // fallback -- an un-latched gesture on the wallpaper simply ends.
      onReleased: pts => {
        if (!root.tracking) return
        homeDrag.release()
        root.reset()
      }

      onCanceled: pts => homeDrag.cancel()
    }
  }

  // ========================================================== the left edge
  //
  // G. The one surface here that takes touch ahead of an app, which is why it
  // is 16px and why it never grows. Overlay rather than Top so it sits above
  // the app drawer and the control center and can close them (G3) -- on Top they would map
  // later and win.
  PanelWindow {
    id: backEdge

    anchors { top: true; bottom: true; left: true }

    // G13. Wider than the band it takes touches in, so the cue has somewhere
    // to be drawn, and masked back down to the band so nothing else changes.
    // A masked-out region falls through to the next surface in the layer,
    // which is what the control center already relies on to keep this very edge working
    // underneath it.
    //
    // The mask is unconditional and that is the whole risk here: this surface
    // is on Overlay and sits over every app, so an unmasked widening would
    // quietly take the leftmost `backCueSize` of every window on the phone.
    // `geometry` publishes both widths for exactly that reason.
    implicitWidth: root.backEdgeWidth + root.backCueSize
    mask: Region { x: 0; y: 0; width: root.backEdgeWidth; height: backEdge.height }
    color: "transparent"

    // G10. Anchored top and bottom, then pulled up off the bottom edge. A
    // positive bottom margin shrinks a surface anchored to both -- the same
    // lever the app drawer uses in the other direction, where a negative one
    // extends it past the usable area (I5a).
    margins.bottom: root.edgeBottomInset
    // G10b. The same lever at the other end, for the app's header bar.
    margins.top: root.edgeTopInset

    WlrLayershell.namespace: "moarchy-back"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // G12. The cue, in the band the surface gained for it. Drawn and not
    // tappable: the input region above is still `backEdgeWidth` wide, and
    // everything to the right of it falls through to the app.
    //
    // One rounded quad and one glyph, moved by `x` rather than grown by
    // `scale` (style.md G4): a translation is free and a scale re-rasters the
    // chevron every frame, on a Mali-400, while a finger is already driving
    // the compositor.
    Item {
      id: backCue
      anchors.verticalCenter: parent.verticalCenter
      // Follows the finger down the edge as well as in, so the cue is under
      // the thumb rather than halfway up the screen from it. Clamped inside
      // the surface, which is already inset from both ends (G10, G10b).
      y: Math.max(0, Math.min(parent.height - height, root.backCueY - height / 2))
      x: -width * (1 - root.backPull)
      width: root.backCueSize
      height: root.backCueSize
      visible: root.backPull > 0 || root.backFlash > 0

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        // Armed at the commit it goes accent, which is the strip's own
        // vocabulary for "letting go now does something" (C2, A4) rather than
        // a third colour invented for one gesture.
        color: root.backPull >= 1 || root.backFlash > 0
               ? Util.alpha(Color.accent, 0.55 + 0.45 * Math.max(root.backFlash, 0))
               : Util.alpha(Color.background, 0.82)
        border.width: 1
        border.color: Util.alpha(Color.foreground, 0.18)
      }

      // The same chevron Settings' own back button wears, through the same
      // component: a Nerd Font glyph is rarely centred inside the box the font
      // reserves for it, and `anchors.centerIn` centres the box.
      Ui.OpticalGlyph {
        anchors.fill: parent
        text: ""
        fontFamily: Style.font.family
        fontSize: Style.font.icon
        color: root.backPull >= 1 || root.backFlash > 0
               ? Color.background : Color.foreground
      }

      Behavior on x {
        // style.md G5. Off while the finger is driving it, on for the spring
        // back and for the retreat after a commit.
        enabled: root.backPull <= 0
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
      }
    }

    MultiPointTouchArea {
      anchors.fill: parent
      maximumTouchPoints: 1

      // `backCueY` is where the arc is drawn and belongs to the touch, not to
      // the drag, so it stays here. Everything else backDrag owns.
      onPressed: pts => {
        if (pts.length === 0) return
        root.backCueY = pts[0].y
        root.backPull = 0
        backDrag.press(pts[0].sceneX, pts[0].sceneY)
        // Started now so it has answered by the time the swipe has travelled
        // far enough to commit.
        root.startKeyboardProbe()
      }

      onUpdated: pts => {
        if (pts.length === 0) return
        root.backCueY = pts[0].y
        backDrag.move(pts[0].sceneX, pts[0].sceneY)
      }

      // A release with no points still ends the gesture on what the last frame
      // measured, where this used to throw the whole swipe away. Every other
      // surface has always committed that way, and F8 is the reason: a press
      // that returns without ending leaves the watchdog armed.
      onReleased: pts => backDrag.release()
      onCanceled: pts => backDrag.cancel()
    }

    // The cue's own moment, borrowed from the hold's flash (C2) rather than
    // timed separately: in 90ms, out over 320, so the arc acknowledges the
    // commit and leaves instead of vanishing on the frame the app closes.
    SequentialAnimation {
      id: backFlashAnim
      NumberAnimation { target: root; property: "backFlash"; to: 1
                        duration: 90; easing.type: Easing.OutCubic }
      NumberAnimation { target: root; property: "backFlash"; to: 0
                        duration: 320; easing.type: Easing.OutCubic }
    }
  }

  // ======================================================= the right edge
  //
  // P1. The second surface here that takes touch ahead of an app, and the same
  // bargain as the first: 16px, never grown, on Overlay so it sits above the
  // app drawer and the control center rather than under them.
  //
  // It is the plainest surface in this file -- no cue, no mask, no widening --
  // and each of those absences follows from one fact. The back edge draws an arc
  // because a back swipe has nothing else to look at (G12); this one pulls a
  // sheet in under the finger, so the thing that says how far the gesture has
  // got is the gesture's own result. Nothing is drawn here, so there is no cue
  // to make room for, so the surface is exactly the band it takes touch in and
  // has nothing to mask back off (G13's whole subject).
  PanelWindow {
    id: workspaceOverviewEdge

    anchors { top: true; bottom: true; right: true }
    implicitWidth: root.workspaceOverviewEdgeWidth
    color: "transparent"

    // P8. The same two insets as the other edge, in the same direction: a
    // positive margin shrinks a surface anchored to both ends. The keyboard's
    // right-hand column -- backspace, enter -- and an app's own header controls
    // are what they hand back here, where on the left it is shift and a back
    // chevron.
    margins.bottom: root.edgeBottomInset
    margins.top: root.edgeTopInset

    WlrLayershell.namespace: "moarchy-workspace-overview-edge"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    MultiPointTouchArea {
      anchors.fill: parent
      maximumTouchPoints: 1

      onPressed: pts => {
        if (pts.length === 0) return
        // Resolved on the press and not on the latch, the way the strip does
        // it: the tracker has to know on its first frame whether there is
        // anything to drag and where it already stands. Mapping the sheet is
        // the part that waits -- beginSheet() runs from onBegan (P8).
        root.dragSource = "rightEdge"
        root.resolveTarget(root.rightTarget, Edge.RIGHT)
        workspaceOverviewDrag.press(pts[0].sceneX, pts[0].sceneY)
      }

      onUpdated: pts => {
        if (pts.length === 0) return
        workspaceOverviewDrag.move(pts[0].sceneX, pts[0].sceneY)
      }

      // reset() after release() and not instead of it. A latched drag has
      // already been through onFinished by the time this line runs and reset is
      // idempotent; an unlatched one -- a brush on the edge, or a press with the
      // sheet already open, which cannot latch -- never reaches a handler at all
      // and would otherwise leave `dragTarget` resolved for the next gesture.
      onReleased: pts => { workspaceOverviewDrag.release(); root.reset() }
      onCanceled: pts => workspaceOverviewDrag.cancel()
    }
  }
}
