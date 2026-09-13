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
// The three surfaces, and why each sits on the layer it does
// ---------------------------------------------------------------------------
//   strip     Overlay, bottom, 20px, exclusive.  Recents and home (A, B).
//             Overlay because moarchy-keyboard is on Top with an exclusive zone, so
//             anything lower loses the bottom edge to the keyboard.
//   home      Bottom, full screen, no exclusion.  The drawer (D).
//             *Below* every window, so on a blank workspace it receives the
//             touch and on an occupied one the app is over it and it receives
//             nothing. The layer does the work -- there is no "is this
//             workspace empty" test anywhere in this file, because asking that
//             question is what made the drawer open when it should not have.
//   backEdge  Overlay, left, 16px.  Back (G).
//             Above windows, because it has to take the touch before the app
//             does. That is the one place here that steals input from an app,
//             it is bounded to 16px, and like the strip it never grows.
//
// Wayland's implicit grab is what makes all three work: wl_touch.down goes to
// the surface under the finger and motion keeps arriving there however far the
// finger travels. So a 20px strip can track a full-height swipe, and none of
// these surfaces has to grow mid-gesture -- which also means a bug here can
// never leave the phone with an unusable touchscreen.
//
// ---------------------------------------------------------------------------
// What the up-drag from the strip means
// ---------------------------------------------------------------------------
//   0 ---- 40% -------- 75% ---- 100%   of pullTravel
//   app    RECENTS       HOME
//
// It never opens the drawer (A5). The drawer is one drag up on the home screen
// itself (D1), which is the Android split: the nav area is the overview, the
// home screen is the launcher.
import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "../moarchy.common/ShellApps.js" as ShellApps

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

  // What the on-screen keyboard reserves at the bottom, in logical px.
  //
  // Measured, not chosen: it is moarchy-keyboard's panel and this shell does
  // not set it. The same figure I5b pins the drawer's reflow to -- at 176 the
  // drawer settles over the top key row.
  //
  // Deliberately *not* through Style.space, which every other length here goes
  // through. Style.space applies this theme's spacing scale, and the keyboard
  // is a separate client that never sees it: scaling this with the theme would
  // cut the back edge shorter than the keys it exists to clear.
  readonly property int keyboardPanelHeight: 200

  // G10. How far short of the bottom the back edge stops. Below this the strip
  // wants taps, and above the strip the keyboard does -- and this surface was
  // taking both, because it is on Overlay and they are not.
  //
  // A number rather than an arrangement, and that is forced. Sway resolves
  // exclusive zones layer by layer from Overlay down, so the keyboard's zone
  // (Top) is subtracted after this surface has been placed: ExclusionMode
  // .Normal here would move nothing. Nor can a tap be handed down to the
  // keyboard after the fact -- Wayland picks the recipient from the input
  // region before delivering the touch. Cutting the region is the only knob.
  readonly property int backEdgeBottomInset:
    root.stripHeight + root.keyboardPanelHeight

  // G10b. What a GTK app's header bar reserves at the top, in logical px.
  //
  // Measured on the device and not chosen, for the same reason as the
  // keyboard's 200 above: it is another toolkit's chrome, and libadwaita has
  // never heard of this theme's spacing scale. Spot's header runs from y=52 to
  // y=144 physical at scale 2 -- 46.5 logical plus its divider -- which is
  // AdwHeaderBar's own 47. GTK3 and Kirigami land within a pixel or two of it.
  readonly property int headerBarHeight: 47

  // G10b. How far short of the TOP the back edge stops, so the control an app
  // puts at its top-left -- libadwaita's back chevron, a hamburger, Geary's
  // folder button -- is tappable.
  //
  // This surface is anchored top and bottom on Overlay, and sway resolves
  // exclusive zones from Overlay down, so the bar's zone (Top) is subtracted
  // after this is placed: y=0 here is the top of the SCREEN, not the top of
  // the app. So the inset carries the bar as well as the header.
  //
  // The bar half goes through the theme (it is our surface); the header half
  // does not (it is not). Same split as the bottom inset, opposite ends.
  readonly property int backEdgeTopInset:
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
  // Half a keyboard is the threshold rather than an exact height, the way
  // I5e's is: `home` is one strip taller than the free area (its negative
  // bottom margin), so neither cluster is an exact number and the test only
  // has to fall between them. The bar's own band is nowhere near it.
  readonly property bool keyboardReserving:
    !!home.screen
    && home.height < home.screen.height - root.keyboardPanelHeight / 2

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

  // G6. Rightward travel that commits a back swipe -- three times the band, so
  // brushing the edge never closes an app.
  readonly property int backCommit: Style.space(48)

  // Travel that commits a sideways swipe. Below this the pill springs back and
  // nothing happens, so resting a thumb on the edge is not a workspace switch.
  readonly property int commitDistance: Style.space(56)

  // The pill moves a fraction of the finger's travel. Full 1:1 tracking on a
  // 360px screen runs the pill off the edge long before the commit threshold.
  readonly property real damping: 0.32

  // Movement past this is a drag rather than a stationary touch. It used to
  // also cancel a hold-to-close; there is no hold any more (C1).
  readonly property int slop: Style.space(8)

  // Travel that a full drag takes. Not the whole screen: dragging from the
  // bottom edge to the top is a longer reach than a phone gesture should need.
  readonly property real pullTravel:
    Math.max(1, (strip.screen ? strip.screen.height : 720) * 0.45)

  // A1-A4. The carousel is fully up at 40%, which leaves the rest of the drag
  // to mean "keep going"; 75% is far enough that landing on home is deliberate.
  readonly property real recentsFull: 0.40
  readonly property real recentsCommit: 0.15
  readonly property real homeCommit: 0.75

  // D1-D2. The drawer's own thresholds, matching the shade so the two drags
  // feel like one gesture in opposite directions.
  readonly property real drawerCommit: 0.35
  readonly property real fling: 0.6

  // D2a. What one pixel of finger is worth to the sheet being dragged.
  //
  // The strip keeps pullTravel: it is a fixed band that does not move under the
  // thumb, so a shorter travel there only means the carousel arrives without a
  // full-screen reach -- the pill is not the thing being dragged.
  //
  // The drawer is the opposite case, and it was getting the strip's number. Its
  // *close* drag is already 1:1 against the sheet's own height, because the
  // handle is the sheet -- so with pullTravel opening it the same finger travel
  // moved the drawer 2.2x faster out than in, and a drag from mid-screen
  // arrived fully open with half the screen still to go. Measured on the
  // device: a 250px drag left the drawer at 77%.
  //
  // Read off the drawer rather than recomputed here, so the two directions
  // cannot drift apart -- `closeTravel` is the property its own drag divides
  // by. Falls back to pullTravel when the drawer is not the thing being
  // dragged, or has not published one.
  function targetTravel(): real {
    if (root.dragMode === "drawer" && root.dragTarget) {
      var travel = Number(root.dragTarget.closeTravel)
      if (isFinite(travel) && travel > 1) return travel
    }
    return root.pullTravel
  }

  // ---------------------------------------------------------- shared state
  property bool tracking: false
  property real startX: 0
  property real startY: 0
  property real dx: 0
  property real dy: 0
  property real velocity: 0
  property real lastY: 0
  property real lastT: 0

  // Which overlay this gesture drives: "none", "drawer" or "recents". Latched
  // on the first clearly-upward movement and held for the rest of the gesture,
  // so a swipe that starts up and drifts sideways cannot hand the sheet back
  // mid-pull and change workspace instead.
  property string dragMode: "none"

  // What the surface decided on press, before it was known the gesture was
  // even upward.
  property string pendingMode: "none"

  // A direct object reference, resolved once per gesture. The alternative --
  // shell.callIfLoaded(id, method, arg) -- marshals a string per call, and
  // this runs at touch-event rate.
  property var dragTarget: null

  // Where the pull stood when the finger went down, so the same strip can push
  // a sheet back as well as pull it up.
  property real dragStartPull: 0

  // The live pull, in units of pullTravel.
  property real pull: 0

  readonly property bool homeArmed:
    root.dragMode === "recents" && root.pull >= root.homeCommit

  // Host-injected. Neither may be `readonly` or `required`: readonly makes the
  // assignment throw, required makes the component fail to instantiate at all,
  // because a plugin is created first and configured afterwards. Either way the
  // failure is silent.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
                               || (Quickshell.env("HOME") + "/.local/share/omarchy")
  property var shell: null

  // -------------------------------------------------------- compositor state
  //
  // I3.socketPath is empty when Quickshell never found $SWAYSOCK -- which
  // happens if the shell was started outside the session environment. Falling
  // back to forking swaymsg there keeps every gesture working; silently
  // dispatching into a dead socket would not.
  readonly property bool haveI3: String(I3.socketPath || "").length > 0

  function dispatch(cmd: string): void {
    if (root.haveI3) I3.dispatch(cmd)
    else Quickshell.execDetached(["swaymsg", cmd])
  }

  // E2, K12. Focus a window. Every caller in this shell lands here, so there is
  // one answer to "how do you focus something" and one place to change it.
  //
  // NOT `Toplevel.activate()`, which is what the carousel used and what this
  // replaced. The foreign-toplevel activate request does nothing on this
  // compositor: measured 2026-09-08 from inside the running shell, against
  // `foot` on another workspace and against one of this shell's own windows,
  // and in both cases the request was sent, no warning appeared anywhere, and
  // the focused workspace did not move. `close()` on the same handle works, so
  // this is sway's activate path and not a dead protocol -- sway 1.12 matches
  // the request's seat against its own seats and drops it when nothing matches.
  //
  // It had been silently broken for as long as the carousel has existed. E2
  // passed throughout, because it asserted that the workspace the tap landed on
  // holds a window -- which is also true when the tap changed nothing and you
  // were already looking at one.
  //
  // Criteria, because a foreign-toplevel handle carries no con_id and there is
  // nothing else to address a window by. Two windows with the same app id *and*
  // the same title are ambiguous and sway will act on both; that is the known
  // cost, and it is a better failure than the request that did nothing at all.
  function swayEscape(text: string): string {
    return String(text).replace(/[\\^$.|?*+()\[\]{}"]/g, "\\$&")
  }

  function focusToplevel(tl): bool {
    if (!tl) return false
    var criteria = '[app_id="^' + root.swayEscape(tl.appId || "") + '$"'
    var title = String(tl.title || "")
    if (title !== "") criteria += ' title="^' + root.swayEscape(title) + '$"'
    root.dispatch(criteria + '] focus')
    return true
  }

  function isOpen(id: string): bool {
    return root.shell && typeof root.shell.isPluginOpen === "function"
           && root.shell.isPluginOpen(id)
  }

  // Every full-screen overlay this shell can put over an app, in dismissal
  // order rather than z-order.
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
  readonly property var overlayIds: [
    "moarchy.shade",
    "moarchy.drawer",
    "moarchy.recents",
    "moarchy.themes"
  ]

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
  // gesture. Minus the carousel, which a second drag continues into the home
  // band rather than clears (A6).
  //
  // Vendored popups are deliberately not consulted here, unlike in
  // topmostOverlay(). That branch reads the host's openPanelIds, which carries
  // every mounted `omarchy.` surface and not only the popups. A false positive
  // costs nothing where it is used today -- by then we have already decided to
  // clear something -- but as this gate it would stop the strip ever raising
  // the carousel at all.
  function coveringSheet(): bool {
    for (var i = 0; i < root.overlayIds.length; i++) {
      var id = root.overlayIds[i]
      if (id === "moarchy.recents") continue
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
    var open = root.shell ? root.shell.openPanelIds : null
    if (open && open.length) {
      for (var j = open.length - 1; j >= 0; j--) {
        var candidate = String(open[j] || "")
        if (candidate.indexOf("omarchy.") === 0 && candidate !== "omarchy.bar")
          return candidate
      }
    }
    return ""
  }

  // B3. Everything this shell had drawn over the workspace, put away before it
  // changes underneath. A sheet left standing while the workspace moves is a
  // gesture that visibly does nothing and silently does something.
  //
  // All of them rather than the topmost one. The two can differ -- the shade
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
  // No sheet in overlayIds owns one today -- the three screens that do are
  // windows and reach performBack()'s own K7 branch instead. Kept because the
  // next sheet with a stack must not have to rediscover the ordering.
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

  // Every window, this shell's three screens included (K1).
  function hasWindows(): bool {
    var list = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    return list.length > 0
  }

  // A9. Nothing open anywhere means the strip's up-swipe has nothing to show.
  //
  // One question again. This used to ask the carousel a second one -- "is a
  // shell app running" -- because Settings was an app without being a window
  // and ToplevelManager could not see it. Since K1 it can, and hasWindows() is
  // the whole answer.
  function hasApps(): bool {
    return root.hasWindows()
  }

  // The window a back gesture would close.
  //
  // NOT ToplevelManager.activeToplevel on its own. That reads null here even
  // with a window plainly focused -- the back gesture ran, found nothing, and
  // closed nothing, while `toplevels` was populated the whole time. The
  // per-toplevel `activated` flag is the one that demonstrably tracks focus:
  // it is what puts the accent border on the right card in the carousel. So
  // prefer the singleton when it answers and fall back to the flag that
  // works, rather than depending on a derived property that does not.
  function focusedToplevel() {
    if (ToplevelManager.activeToplevel) return ToplevelManager.activeToplevel
    var list = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].activated) return list[i]
    return null
  }

  // F1. The lowest workspace number Sway does not currently have.
  //
  // This used to ask each workspace whether its `representation` was empty,
  // and that was wrong for the same reason it was wrong when the strip used it
  // to choose between the carousel and the drawer: `representation` changes on
  // *window* events and I3 refreshes workspaces on *workspace* events, so a
  // workspace that gained a window still reads empty. Home then switched
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
  function firstFreeWorkspace(): int {
    var taken = ({})
    var list = I3.workspaces ? I3.workspaces.values : []
    for (var i = 0; i < list.length; i++) {
      var n = list[i] ? Number(list[i].number) : -1
      if (n > 0) taken[n] = true
    }
    var free = 1
    while (taken[free]) free++
    return free
  }

  // ------------------------------------------------------ driving an overlay
  function resolveTarget(id: string): void {
    root.dragTarget = null
    root.dragStartPull = 0
    if (!root.shell || !root.shell.panelLoaders) return
    var loader = root.shell.panelLoaders[id]
    if (!loader || !loader.item) return
    root.dragTarget = loader.item
    var progress = Number(loader.item.progress) || 0
    // The drawer's progress *is* the pull. The carousel reaches its stop at
    // 40% of the travel, so an open one starts the next drag already there --
    // which is what lets a second swipe carry straight on into the home band
    // (A6).
    root.dragStartPull = id === "moarchy.recents"
      ? progress * root.recentsFull
      : progress
  }

  // ------------------------------------------------------------- J. preview
  //
  // The carousel paints a still of the app being put away (docs/gestures.md
  // J). Armed at the latch rather than at the press: the capture needs the
  // carousel's surface mapped, and that only happens once progress leaves 0.
  //
  // Only when there is actually an app on screen to picture. A6 -- a second
  // drag with the carousel already up -- is a drag over the switcher, and the
  // app it would capture is already behind it.
  function armPreview(): void {
    if (root.dragMode !== "recents" || !root.dragTarget) return
    if (!root.dragTarget.armPreview) return
    if (root.isOpen("moarchy.recents")) return
    // K11. A shell app is a window, so this one question covers it too. It used
    // to need a second clause: an exclusive-focus layer surface deactivates the
    // window beneath it, so with Settings up every toplevel read unfocused and
    // focusedToplevel() alone refused to arm.
    if (!root.focusedToplevel()) return
    root.dragTarget.armPreview()
  }

  // `restore` true means the gesture changed nothing and the app goes back to
  // full size (J5); false means it was put away and the preview stays where
  // the finger left it (J6).
  function disarmPreview(restore): void {
    if (!root.dragTarget || !root.dragTarget.disarmPreview) return
    root.dragTarget.disarmPreview(restore)
  }

  function setTargetProgress(pull: real): void {
    if (!root.dragTarget) return
    root.dragTarget.dragging = true
    if (root.dragMode === "recents") {
      root.dragTarget.progress = Math.max(0, Math.min(1, pull / root.recentsFull))
      // Past the carousel's stop the rest of the drag has to mean something,
      // so hand it over as a 0..1 ramp the cards fade and travel with.
      root.dragTarget.homeHint = Math.max(0, Math.min(1,
        (pull - root.recentsFull) / (root.homeCommit - root.recentsFull)))
    } else {
      root.dragTarget.progress = Math.max(0, Math.min(1, pull))
    }
  }

  // Committing goes through the host rather than setting progress to 1 here,
  // so openPanelIds and the plugin cannot drift apart and leave the next swipe
  // toggling the wrong way.
  function releaseTarget(open): void {
    if (!root.dragTarget) return
    var id = root.dragMode === "recents" ? "moarchy.recents"
                                         : "moarchy.drawer"
    root.dragTarget.dragging = false
    if (root.dragMode === "recents" && !open) root.dragTarget.homeHint = 0
    if (open && root.shell) root.shell.summon(id, "{}")
    else if (root.shell) root.shell.hide(id)
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

  // Every compositor call lives here, including the IPC ones and the one the
  // carousel fires when its last card is closed.
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
      root.dispatch(action === "next" ? "workspace next_on_output"
                                      : "workspace prev_on_output")
    }
    else if (action === "home") {
      // F3. The keyboard goes with the app. It does not pop *up* on the way
      // home -- it fails to go *down*, and lands on the wallpaper with nothing
      // behind it, which is why it reads as having appeared. Sway sends the
      // text-input leave when focus moves off the app, but a home screen is an
      // empty workspace and there is no window there to take the input state
      // over, so nothing lowers it. Measured: up after 3 of 5 homes, down in
      // exactly the two that happened to land on a workspace that still had a
      // window; with the keyboard already down, 6 of 6 homes left it down, so
      // nothing here raises it.
      //
      // Unconditional. SetVisible false on a keyboard already down is a no-op,
      // and hideKeyboard is execDetached -- reading `keyboardUp` first would
      // mean waiting on the probe's round trip on the one gesture that has to
      // feel instant, and acting on a stale answer is what G2's comment above
      // already warns about.
      root.hideKeyboard()

      // K4. A shell app goes where an app goes: nowhere. It stays mapped on its
      // own workspace, its card stays in the carousel, and this gesture leaves
      // it the way it leaves `foot` -- by going somewhere else.
      //
      // Already on a home screen: no toplevel is activated when focus is on an
      // empty workspace, which makes this the one reliable "is this workspace
      // empty" question available here. Without it, home from home would hop
      // to a *different* empty workspace and churn the numbering for nothing.
      //
      // One question, and it used to be two. While a shell app was a layer
      // surface it held the seat's keyboard, sway deactivated the window
      // beneath it, and every toplevel read unfocused -- so an app under the
      // sheet was indistinguishable from a bare home screen under it and this
      // fell back to "is there a window anywhere", which hopped a workspace
      // whenever anything at all was open. A focused window answers for itself.
      if (root.focusedToplevel())
        root.dispatch("workspace number " + root.firstFreeWorkspace())
    }
    else if (action === "clear") root.hideTopmostOverlay()
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

  Process {
    id: keyboardProbe
    command: ["busctl", "--user", "get-property", "sm.puri.OSK0",
              "/sm/puri/OSK0", "sm.puri.OSK0", "Visible"]
    stdout: StdioCollector {
      // `busctl get-property` prints the variant as e.g. `b true`.
      onStreamFinished: {
        root.keyboardUp = String(text).indexOf("true") >= 0
        root.keyboardKnown = true
      }
    }
  }

  Timer {
    id: backRetry
    interval: 120
    onTriggered: root.performBack()
  }

  // Warmed once at startup, so the first back gesture is not the one that pays
  // for a cold DBus connection. The probe is fast once the path has been
  // exercised and slow the very first time, and performBack spends its whole
  // retry budget waiting before falling back to the keyboard branch -- correct,
  // but it means the first back after a shell restart gets consumed by the
  // probe instead of reaching the overlay underneath.
  Component.onCompleted: root.startKeyboardProbe()

  function startKeyboardProbe(): void {
    root.keyboardKnown = false
    root.backRetries = 0
    // Toggled off first. Setting `running` true on a Process that is already
    // running is a no-op, so a probe still in flight from the previous gesture
    // left keyboardKnown false and the answer stale.
    keyboardProbe.running = false
    keyboardProbe.running = true
  }

  function hideKeyboard(): void {
    Quickshell.execDetached(["busctl", "--user", "call", "sm.puri.OSK0",
                             "/sm/puri/OSK0", "sm.puri.OSK0", "SetVisible",
                             "b", "false"])
  }

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
    root.dispatch("kill")
  }

  // Back to rest. Every path out of a gesture goes through this.
  function reset(): void {
    watchdog.stop()
    root.tracking = false
    root.dragMode = "none"
    root.pendingMode = "none"
    root.dragTarget = null
    root.dragStartPull = 0
    root.pull = 0
    root.velocity = 0
    root.dx = 0
    root.dy = 0
  }

  // A touch sequence normally ends in released or canceled, but a compositor
  // restart or a lost seat can strand one mid-gesture. Nothing dangerous
  // happens if it does -- no surface here grows, so input is never trapped --
  // but a sheet would sit parked half-open with nothing left to finish it.
  Timer {
    id: watchdog
    interval: 4000
    onTriggered: {
      if (root.dragMode !== "none") {
        // A dropped touch changed nothing, so the app goes back (J5) -- and
        // this is the path that catches a capture which never arrived.
        root.disarmPreview(true)
        root.releaseTarget(false)
      }
      root.reset()
    }
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
        // decision and not just one branch of it.
        if (root.coveringSheet()) {
          root.run("clear")
          return "ok: cleared"
        }
        if (!root.hasApps()) return "ok: nothing (no apps open)"
        if (root.shell) root.shell.summon("moarchy.recents", "{}")
        return "ok: recents"
      }
      return "usage: swipe left|right|up|home"
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
    function geometry(): string {
      return "backEdge w=" + Math.round(backEdge.width)
             + " h=" + Math.round(backEdge.height)
             + " inset=" + root.backEdgeBottomInset
             // G10b. Published beside the bottom one, because `h` alone cannot
             // say which end a missing band was lost at.
             + " topInset=" + root.backEdgeTopInset
             + " header=" + root.headerBarHeight
             + " strip=" + root.stripHeight
             + " panel=" + root.keyboardPanelHeight
             + " screen=" + (backEdge.screen ? backEdge.screen.height : 0)
             // I1a. The band under the pill, and the two answers it is decided
             // from. `home` is published because it is the measurement -- a
             // check that read only `band` could not tell "the keyboard is up"
             // from "this surface never got a configure".
             + " home=" + Math.round(home.height)
             + " kbd=" + (root.keyboardReserving ? 1 : 0)
             + " band=" + (root.fillStripBand ? 1 : 0)
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
    // the drawer above it, and restarting either one in either order changed
    // nothing -- it is layer order, not map order.
    exclusionMode: ExclusionMode.Auto

    Rectangle {
      id: pill

      width: Style.space(96)
      height: Math.max(2, Style.space(4))
      radius: height / 2
      anchors.verticalCenter: parent.verticalCenter
      x: (parent.width - width) / 2 + root.pillOffset

      // Brightens while tracking, and stretches as an upward swipe approaches
      // the first stop. Armed for home it goes accent -- once the carousel
      // covers the screen the pill is the only cue left that letting go now
      // goes somewhere else.
      color: root.homeArmed ? Color.accent
                            : Util.alpha(Color.foreground, root.tracking ? 0.9 : 0.3)
      scale: root.homeArmed ? 1.6
           : 1 + Math.min(0.4, Math.max(0, -root.dy) / (root.commitDistance * 4))

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
    }

    MultiPointTouchArea {
      anchors.fill: parent
      maximumTouchPoints: 1

      onPressed: pts => {
        if (pts.length === 0) return
        root.startX = pts[0].sceneX
        root.startY = pts[0].sceneY
        root.lastY = pts[0].sceneY
        root.lastT = Date.now()
        root.dx = 0
        root.dy = 0
        root.pull = 0
        root.velocity = 0
        root.tracking = true
        root.dragMode = "none"
        root.dragTarget = null

        // The whole decision, and it never mentions the drawer (A5).
        //
        //   a sheet covering the screen -> the release clears it (A7, A8)
        //   the carousel already up     -> keep dragging it, on to home (A6)
        //   apps open                   -> the carousel (A1-A4)
        //   nothing open at all         -> nothing (A9)
        //
        // The first line used to name the shade and the drawer and nothing
        // else, which left Settings to fall through to it -- and only when no
        // window was open, because with one the third line claimed the gesture
        // first and raised the carousel over the top of Settings, leaving it
        // there. Settings is a window now (K1), so the third line claims it in
        // both cases with no clause of its own; the theme picker and any other
        // sheet reach the first one in both cases, which they did not before.
        if (root.coveringSheet())
          root.pendingMode = "none"
        else if (root.isOpen("moarchy.recents") || root.hasApps())
          root.pendingMode = "recents"
        else
          root.pendingMode = "none"

        if (root.pendingMode === "recents") root.resolveTarget("moarchy.recents")
        watchdog.restart()
      }

      onUpdated: pts => {
        if (pts.length === 0 || !root.tracking) return
        var y = pts[0].sceneY
        // Declared here, not inside the latched branch below. `var` is
        // function-scoped, so a declaration inside the `if` is hoisted but
        // stays undefined until that branch runs -- and `root.lastT = now` at
        // the bottom then assigns undefined to a double on every un-latched
        // move. QML rejects it and logs, so lastT kept a stale value and the
        // first latched frame measured its velocity over the wrong interval.
        var now = Date.now()
        root.dx = pts[0].sceneX - root.startX
        root.dy = y - root.startY

        // B2. Re-tested every frame rather than only at the first movement, so
        // a thumb that starts its arc sideways still latches once the upward
        // travel dominates, instead of falling through to a workspace switch.
        if (root.dragMode === "none" && root.dragTarget && root.pendingMode !== "none"
            && root.dy < -root.slop && Math.abs(root.dy) > Math.abs(root.dx)) {
          root.dragMode = root.pendingMode
          root.armPreview()
        }

        if (root.dragMode !== "none") {
          var dt = Math.max(1, now - root.lastT)
          // Smoothed, so one jittery frame at the end of a slow drag cannot
          // read as a fling. Negative is upward, so the sign is flipped to
          // make "faster open" positive.
          root.velocity = root.velocity * 0.6 + ((root.lastY - y) / dt) * 0.4
          root.pull = root.dragStartPull - root.dy / root.pullTravel
          root.setTargetProgress(root.pull)
        }
        root.lastY = y
        root.lastT = now
        watchdog.restart()
      }

      onReleased: pts => {
        if (!root.tracking) return
        if (root.dragMode === "recents") {
          // A2-A4. Distance alone decides home. A fling is allowed to rescue a
          // short, fast flick into the recents band -- people do that when they
          // know where they are going -- but never to carry the drag past a
          // stop the finger did not reach, or the destination stops being
          // predictable.
          if (root.pull >= root.homeCommit) {
            root.disarmPreview(false)
            root.releaseTarget(false)
            root.run("home")
          } else if (root.pull >= root.recentsCommit || root.velocity >= root.fling) {
            root.disarmPreview(false)
            root.releaseTarget(true)
          } else {
            // A2: nothing happened, so the app comes back rather than
            // appearing to have been put somewhere.
            root.disarmPreview(true)
            root.releaseTarget(false)
          }
        } else {
          root.commit()
        }
        root.reset()
      }

      onCanceled: pts => {
        if (root.dragMode !== "none") {
          root.disarmPreview(true)
          root.releaseTarget(false)
        }
        root.reset()
      }
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

    // I1a. The band, filled from underneath.
    //
    // Underneath is the whole trick, and it is why this costs nothing anywhere
    // else. Bottom is below every window, so on an occupied workspace this is
    // covered except in the band no window is drawn in; and it is below every
    // sheet, so the drawer, the shade, the carousel and the theme picker draw
    // over it exactly as before. Painting the band from the *strip* instead
    // would have put it over all four.
    //
    // Only the band, not the whole surface. A window with gaps on, or two
    // tiled side by side, would otherwise get the theme colour in the gutters
    // as well -- a change nobody asked for, in a place the wallpaper is meant
    // to show.
    Rectangle {
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: root.stripHeight
      color: Color.background
      visible: root.fillStripBand
    }

    MultiPointTouchArea {
      anchors.fill: parent
      maximumTouchPoints: 1

      // Its own start coordinates, because this surface and the strip can both
      // be mid-gesture in principle and sharing them would let one clobber the
      // other's origin.
      property real homeStartY: 0
      property real homeStartX: 0
      property bool homeDragging: false

      onPressed: pts => {
        if (pts.length === 0) return
        homeStartX = pts[0].sceneX
        homeStartY = pts[0].sceneY
        homeDragging = false
        root.lastY = pts[0].sceneY
        root.lastT = Date.now()
        root.velocity = 0
        root.tracking = true
        root.dragMode = "none"
        root.pendingMode = "drawer"
        root.resolveTarget("moarchy.drawer")
        watchdog.restart()
      }

      onUpdated: pts => {
        if (pts.length === 0 || !root.tracking) return
        var y = pts[0].sceneY
        var now = Date.now()
        root.dx = pts[0].sceneX - homeStartX
        root.dy = y - homeStartY

        if (!homeDragging && root.dragTarget && root.dragStartPull < 1
            && root.dy < -root.slop && Math.abs(root.dy) > Math.abs(root.dx)) {
          homeDragging = true
          root.dragMode = "drawer"
        }

        if (homeDragging) {
          var dt = Math.max(1, now - root.lastT)
          root.velocity = root.velocity * 0.6 + ((root.lastY - y) / dt) * 0.4
          root.pull = root.dragStartPull - root.dy / root.targetTravel()
          root.setTargetProgress(root.pull)
        }
        root.lastY = y
        root.lastT = now
        watchdog.restart()
      }

      onReleased: pts => {
        if (!root.tracking) return
        // D4. Sideways and downward do nothing here, so there is no commit()
        // fallback -- an un-latched gesture on the wallpaper simply ends.
        if (homeDragging) {
          var open = root.velocity >= root.fling
                     || (root.velocity > -root.fling && root.pull >= root.drawerCommit)
          root.releaseTarget(open)
        }
        homeDragging = false
        root.reset()
      }

      onCanceled: pts => {
        if (homeDragging) root.releaseTarget(false)
        homeDragging = false
        root.reset()
      }
    }
  }

  // ========================================================== the left edge
  //
  // G. The one surface here that takes touch ahead of an app, which is why it
  // is 16px and why it never grows. Overlay rather than Top so it sits above
  // the drawer and the carousel and can close them (G3) -- on Top they would
  // map later and win.
  PanelWindow {
    id: backEdge

    anchors { top: true; bottom: true; left: true }
    implicitWidth: root.backEdgeWidth
    color: "transparent"

    // G10. Anchored top and bottom, then pulled up off the bottom edge. A
    // positive bottom margin shrinks a surface anchored to both -- the same
    // lever the drawer uses in the other direction, where a negative one
    // extends it past the usable area (I5a).
    margins.bottom: root.backEdgeBottomInset
    // G10b. The same lever at the other end, for the app's header bar.
    margins.top: root.backEdgeTopInset

    WlrLayershell.namespace: "moarchy-back"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    MultiPointTouchArea {
      anchors.fill: parent
      maximumTouchPoints: 1

      property real edgeStartX: 0
      property real edgeStartY: 0

      onPressed: pts => {
        if (pts.length === 0) return
        edgeStartX = pts[0].sceneX
        edgeStartY = pts[0].sceneY
        // Started now so it has answered by the time the swipe has travelled
        // far enough to commit.
        root.startKeyboardProbe()
      }

      onReleased: pts => {
        if (pts.length === 0) return
        var edx = pts[0].sceneX - edgeStartX
        var edy = pts[0].sceneY - edgeStartY
        // G6. Inward, far enough, and more sideways than not -- so a vertical
        // scroll that begins at the edge is never a back.
        if (edx >= root.backCommit && Math.abs(edx) > Math.abs(edy)) root.performBack()
      }
    }
  }
}
