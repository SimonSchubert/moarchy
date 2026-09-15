// The palette, watched.
//
// Nine plugins carried this block byte for byte before it lived here: the same
// path, the same watch, the same reload guard. That is the repo's own test for
// what belongs in shared/ -- "the half that is genuinely the same" -- and it
// had quietly failed it nine times over.
//
// `~/.local/state/omarchy/current/theme/colors.toml` is the staged copy
// omarchy-theme-set writes, so following it means a theme switch is picked up
// with no knowledge of where themes are installed.
import QtQuick
import Quickshell
import Quickshell.Io
import "Theme.js" as Theme

FileView {
  id: file

  // Dark until a file says otherwise, which is what an app has before it has
  // read anything.
  property var colours: Theme.fallback(true)

  path: {
    var home = Quickshell.env("HOME") || ""
    return home + "/.local/state/omarchy/current/theme/colors.toml"
  }

  watchChanges: true
  // A missing colors.toml is an ordinary desktop without omarchy, not an error
  // worth a line in the shell's log.
  printErrors: false

  onLoaded: file.colours = Theme.parse(file.text())
  // Qt.callLater so the reload does not re-enter the change that caused it.
  onFileChanged: Qt.callLater(function () { file.reload() })
}
