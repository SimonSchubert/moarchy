// The arrangement file, watched (docs/widgets.md W16, W22).
//
// Same shape as UiFile.qml: one path, one watch, a good answer when the file is
// missing. It holds the text and nothing else -- what the text *means* is
// Widgets.js, because a library cannot own I/O and a FileView should not own a
// rule.
//
// `~/.config/omarchy/widgets.toml` and deliberately not `ui.toml` (W17):
// `moarchy-ui write_file` rewrites that file whole from a fixed set of
// variables, so a key it does not know is deleted the next time anybody changes
// a corner radius.
import QtQuick
import Quickshell
import Quickshell.Io
import "Widgets.js" as Widgets

FileView {
  id: file

  // The text, as a property rather than through text(). A host binds its column
  // to this, and text() is a function with nothing to notify on -- so an
  // arrangement edited on the phone would not reach the surface until something
  // else happened to re-evaluate (W22).
  property string body: ""

  // W18. Absent is the catalogue's own order in its default states, which is
  // the control center as it ships. The package writes no file into a home
  // (structure.md P1), so absence is the shipping state and has to be the good
  // one -- resolve() makes that true for "" and this only has to hand it over.
  function resolve(hostId) { return Widgets.resolve(file.body, hostId) }
  function shown(hostId) { return Widgets.shown(file.body, hostId) }

  path: {
    var home = Quickshell.env("HOME") || ""
    return home + "/.config/omarchy/widgets.toml"
  }

  watchChanges: true
  printErrors: false

  onLoaded: file.body = file.text()
  onLoadFailed: file.body = ""
  onFileChanged: Qt.callLater(function () { file.reload() })
}
