// A shell screen that is an ordinary window.
//
// Copied into each plugin rather than imported from moarchy.common: a
// third-party plugin cannot see first-party siblings. The comments in
// default/omarchy/plugins/moarchy.common/AppWindow.qml are the source of
// truth for why this is a FloatingWindow and not a layer surface -- apps
// have text fields, and a layer Overlay draws over the on-screen keyboard.
import QtQuick
import Quickshell
import Quickshell.Wayland

FloatingWindow {
  id: win

  property var shell: null
  property string appName: ""
  property string pageTitle: ""
  property string glyph: ""
  property string pluginId: ""

  signal mapped
  signal unmapped

  visible: false
  property bool completed: false
  Component.onCompleted: win.completed = true

  title: win.pageTitle && win.pageTitle !== win.appName
         ? win.appName + " — " + win.pageTitle
         : win.appName

  implicitWidth: win.screen ? win.screen.width : 360
  implicitHeight: win.screen ? win.screen.height : 720

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

  function focusWindow(): void {
    if (!win.toplevel) return
    var loaders = win.shell && win.shell.panelLoaders
    var loader = loaders ? loaders["moarchy.gestures"] : null
    var gestures = loader && loader.item ? loader.item : null
    if (gestures && typeof gestures.focusToplevel === "function") {
      gestures.focusToplevel(win.toplevel)
      return
    }
    if (typeof win.toplevel.activate === "function") win.toplevel.activate()
  }

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

  Timer {
    interval: 200
    repeat: true
    running: win.visible && !win.toplevel
    onTriggered: win.claimToplevel()
  }
}
