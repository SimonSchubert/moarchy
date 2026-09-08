// A shell screen that is an ordinary window.
//
// Usage:
//     import "../moarchy.common" as Shared
//     Shared.AppWindow {
//       id: settingsWindow
//       appName: "Settings"
//       pageTitle: root.pageTitle
//       color: root.surface
//       onMapped: ...
//       onUnmapped: ...
//     }
//
// ---------------------------------------------------------------------------
// Why a window and not a layer surface
// ---------------------------------------------------------------------------
// docs/gestures.md K. Settings, Wi-Fi and Bluetooth are screens you sit in, and
// for two releases the shell emulated an app around each of them: a carousel
// card built by hand, a workspace claimed on their behalf, a hide fired from a
// focus watcher. Every one of those re-implemented something sway already does
// for every window on the phone, and the emulation stopped one gesture short --
// you could swipe *out* of Settings and never swipe back *in*, because the
// workspace it had claimed was empty by the time the swipe returned to it.
//
// Quickshell's FloatingWindow is an xdg toplevel owned by the shell's own
// process. Sway tiles it, bin/moarchy-one-app-per-workspace moves it to a free
// workspace and focuses it, and ToplevelManager reports it -- including to the
// process that created it, which is what makes the carousel card a real card.
// (Measured on the device before any of this was written: n=0 on the first
// poll and then the window's own handle, appId "org.quickshell". The first
// answer is the manager still connecting, not an exclusion.)
//
// ---------------------------------------------------------------------------
// Identity is the title, and that is forced (K9)
// ---------------------------------------------------------------------------
// Qt sets the xdg-toplevel app id once per process, from
// QGuiApplication::desktopFileName, and qtwayland 6.11 has no per-window
// override -- libQt6WaylandClient calls desktopFileName() and nothing else. So
// all three screens carry app_id "org.quickshell", the shell's own, and the
// only thing that tells them apart is the window title. Each sets its own, and
// this file resolves the handle by matching it.
//
// The match is a prefix on `appName` rather than the whole title. The title
// carries the page ("Settings -- Appearance") and changes as you navigate; the
// compositor echoes those changes back through the toplevel handle a frame
// later, so an equality match has a window in which it resolves to nothing.
// The prefix is stable, and no two of the three share one.
//
// ---------------------------------------------------------------------------
// `visible` is driven, never bound
// ---------------------------------------------------------------------------
// A window can be closed from outside -- xdg_toplevel.close, which is what the
// carousel's card flick sends -- and Quickshell answers that by setting
// `visible` false. A QML binding assigned to from C++ is *broken*, not
// re-evaluated, so a screen whose `visible: root.opened` had been overwritten
// once would never map again however many times it was summoned afterwards.
//
// So the window owns the state and the screen reads it back:
//
//     readonly property bool opened: settingsWindow.visible
//
// and open()/close() set `visible` directly. `mapped` and `unmapped` are how a
// screen hooks the two edges without another onVisibleChanged of its own.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "ShellApps.js" as ShellApps

FloatingWindow {
  id: win

  // The host, so this window can reach moarchy.gestures to focus itself. Set by
  // the plugin that declares it; without it show() on an already-mapped window
  // falls back to a request this compositor ignores.
  property var shell: null

  // What the carousel calls this screen, and the first half of the title.
  property string appName: ""

  // The page inside it, or "" at the top level. The card's third line
  // (docs/gestures.md K5) and the second half of the title.
  property string pageTitle: ""

  // The glyph the card wears, since there is no desktop entry to look one up
  // in -- this is a window the shell draws, not a package anyone installed.
  property string glyph: ""

  // The plugin that owns this window, so the carousel can print an id the
  // selftest can grep for and the back gesture can find the page stack.
  property string pluginId: ""

  signal mapped
  signal unmapped

  // Quickshell maps a window as soon as it is constructed, and a plugin with
  // `keepLoaded` is constructed when the shell starts -- so without this the
  // phone came up with Settings and Wi-Fi already open on workspaces 1 and 2,
  // before anything had been summoned. Worse than it sounds: they mapped ahead
  // of the bar and the strip, so sway sized them against an output with no
  // exclusive zones on it yet and they came up 360x720 rather than the 360x674
  // every other window gets. Both halves of that go away by not mapping until
  // something asks.
  //
  // A binding to a constant, deliberately. show() assigns `visible` directly
  // and breaks it, which is the intent: from then on the window's visibility is
  // driven and nothing re-asserts false underneath it.
  visible: false

  // Construction sets `visible` false over Quickshell's own default, and that
  // fires visibleChanged before the plugin around this window has finished
  // building itself. `unmapped` reaches into that plugin -- resetting a page
  // stack, clearing a passphrase -- so it must not be emitted for the frame in
  // which the window is being set up rather than taken down.
  property bool completed: false
  Component.onCompleted: win.completed = true

  title: win.pageTitle && win.pageTitle !== win.appName
         ? win.appName + " — " + win.pageTitle
         : win.appName

  // A size for the frame between mapping and sway's first configure. Sway
  // tiles this to the workspace immediately -- measured 360x674 on this panel,
  // the full area left by the bar and the strip -- so these are never what the
  // window ends up as, only what it asks for.
  implicitWidth: win.screen ? win.screen.width : 360
  implicitHeight: win.screen ? win.screen.height : 720

  // The compositor's handle on this window, or null while it is unmapped.
  // Everything the carousel and the back gesture ask of a shell app goes
  // through this, so it is the one piece of resolution in the shell.
  property var toplevel: null

  readonly property bool activated: !!(win.toplevel && win.toplevel.activated)

  function matches(tl): bool {
    return !!tl && tl.appId === "org.quickshell" && win.appName !== ""
           && String(tl.title || "").indexOf(win.appName) === 0
  }

  function claimToplevel(): void {
    if (win.toplevel) return
    var list = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    for (var i = 0; i < list.length; i++)
      if (win.matches(list[i])) { win.toplevel = list[i]; return }
  }

  // Bring this window to the front, which on sway means switching to the
  // workspace it is on. K12: summoning a screen that is already running is a
  // focus, not a second window.
  function focusWindow(): void {
    if (win.toplevel) ShellApps.focusToplevel(win.shell, win.toplevel)
  }

  // The false is not redundant, and leaving it out bricks the screen.
  //
  // When the compositor closes the window -- xdg_toplevel.close, which is what
  // the carousel's card flick sends and what `swaymsg kill` and a paired
  // keyboard's close binding send -- Quickshell drops the backing window and
  // emits visibleChanged, so this property *reads* false. Its stored value does
  // not follow: the next `visible = true` compares equal to what it thinks it
  // already is and returns without doing anything, and the screen can never be
  // opened again until the shell restarts.
  //
  // Isolated on the device before this line was written, with a two-window
  // config and nothing of this shell in it: after an external close, `visible =
  // true` left `visible` reading false; `visible = false` then `visible = true`
  // mapped the window again. Assigning false while it already reads false emits
  // no change signal, so this costs nothing on the ordinary path.
  function show(): void {
    if (win.visible) { win.focusWindow(); return }
    win.visible = false
    win.visible = true
  }

  function hide(): void {
    win.visible = false
  }

  onVisibleChanged: {
    win.toplevel = null
    if (!win.completed) return
    if (win.visible) { win.claimToplevel(); win.mapped() }
    else win.unmapped()
  }

  // The handle usually arrives with the map, but not always in the same frame,
  // and it can go away under us when the window is closed from outside. Both
  // edges are watched here rather than polled: `values` notifies on every
  // window opening or closing anywhere, which is exactly when either could
  // change.
  Connections {
    target: ToplevelManager.toplevels

    function onValuesChanged() {
      if (!win.visible) { win.toplevel = null; return }
      if (!win.toplevel) { win.claimToplevel(); return }
      var list = ToplevelManager.toplevels.values
      for (var i = 0; i < list.length; i++) if (list[i] === win.toplevel) return
      win.toplevel = null
    }
  }

  // Insurance, and it stops itself. `values` fires when the *set* of toplevels
  // changes, and a handle that arrives without changing the set -- or a first
  // frame where the title has not been committed yet -- would leave this
  // window with no handle and no second chance. Runs only while unresolved.
  Timer {
    interval: 200
    repeat: true
    running: win.visible && !win.toplevel
    onTriggered: win.claimToplevel()
  }
}
