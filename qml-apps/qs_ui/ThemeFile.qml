// The palette, watched -- and the corners, because they are drawn with it.
//
// Nine plugins carried this block byte for byte before it lived here: the same
// path, the same watch, the same reload guard. That is the repo's own test for
// what belongs in shared/ -- "the half that is genuinely the same" -- and it
// had quietly failed it nine times over.
//
// `~/.local/state/omarchy/current/theme/colors.toml` is the staged copy
// omarchy-theme-set writes, so following it means a theme switch is picked up
// with no knowledge of where themes are installed.
//
// `~/.config/omarchy/ui.toml` is the other file, and a separate one on purpose:
// corners are a preference that survives a palette swap. It is watched here
// rather than by each app because `colours` is what every box is already
// handed -- Metrics.js says why the shape rides on it.
import QtQuick
import Quickshell
import Quickshell.Io
import "Theme.js" as Theme
import "Metrics.js" as Metrics

FileView {
  id: file

  // Dark until a file says otherwise, which is what an app has before it has
  // read anything.
  property var scheme: Theme.fallback(true)
  readonly property var colours: Metrics.shaped(file.scheme, file.ui.chrome)

  property UiFile ui: UiFile {}

  path: {
    var home = Quickshell.env("HOME") || ""
    return home + "/.local/state/omarchy/current/theme/colors.toml"
  }

  watchChanges: true
  // A missing colors.toml is an ordinary desktop without omarchy, not an error
  // worth a line in the shell's log.
  printErrors: false

  onLoaded: file.scheme = Theme.parse(file.text())
  // Qt.callLater so the reload does not re-enter the change that caused it.
  onFileChanged: Qt.callLater(function () { file.reload() })
}
