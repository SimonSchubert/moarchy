// What the OWL runtime needs from home (docs/owl.md OW1): moarchy's half of
// running an OWL widget, and the only half moarchy writes -- the runtime is the
// store's, unpatched, in ../moarchy.owl.
//
// One per home, made by Home through a Loader, so a missing runtime costs the
// OWL tiles and nothing else.
import QtQuick
import Quickshell
import Quickshell.Io
import "../moarchy.owl" as Owl
import "../moarchy.owl/Owl.js" as OwlJs
import "../moarchy.common" as Shared
import "../moarchy.common/ShellApps.js" as ShellApps

Owl.OwlHost {
  id: owlHost

  // Home, for its shell, its grid and its agent.
  property var home: null

  monoFamily: "JetBrainsMono Nerd Font"
  iconFamily: "JetBrainsMono Nerd Font"
  sansFamily: "JetBrainsMono Nerd Font"
  // OW4. A phone's rate, not a display's: on a Pixel 3a the runtime's clock is
  // most of an OWL widget's cost, and 15 frames is still motion.
  //
  // home.md HM5b. And 1 while a page moves: an animated widget's frame is
  // ~21 ms of the GUI thread the page turn needs. Slowed rather than stopped,
  // because stopping is `active`, and `active` restarts a widget's clock.
  frameRate: owlHost.home && owlHost.home.moving ? 1 : 15
  launcherVersion: "moarchy"

  // OW3. Omalauncher's cell is 69 dp; one cell and gap of home's grid is that.
  readonly property real dp: owlHost.home ? (owlHost.home.grid.cell + owlHost.home.gapIn) / 69 : 1
  gapsIn: owlHost.home ? owlHost.home.gapIn / owlHost.dp : 5
  gapsOut: owlHost.home ? owlHost.home.gapOut / owlHost.dp : 10
  borderWidth: owlHost.home ? owlHost.home.frameBorder / owlHost.dp : 2

  // The current theme, as OWL's names for colours: read the way the runtime's
  // own board reads it, and again when the theme changes.
  property var palette: OwlJs.themeFromToml("")
  // A property and not a child: OwlHost's root has no default property to hold one.
  property FileView themeFile: FileView {
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: owlHost.palette = OwlJs.themeFromToml(text())
  }

  // A window a widget starts goes on a workspace of its own first, as the app
  // drawer's launches do (windows.md L10).
  function launch(command) {
    if (owlHost.home) ShellApps.goToFreeWorkspace(owlHost.home.shell)
    Quickshell.execDetached(command)
  }

  property var osk: Shared.Osk {}
  function fieldFocused(focused) { if (focused) owlHost.osk.show() }

  function act(widget, name, args) {
    var a = args || []
    function s(i) { return a[i] === undefined || a[i] === null ? "" : String(a[i]) }
    // The phone has no notify-send; this is how moarchy says something.
    if (name === "notify")
      return Quickshell.execDetached(["omarchy-notification-send", "--", s(0), s(1)])
    // The coding agent the prompt bar asks (home.md HM23), which this shell has.
    if (name === "ask" && owlHost.home)
      return owlHost.home.askAgent(s(0))
    return owlHost.defaultAct(widget, name, args)
  }
}
