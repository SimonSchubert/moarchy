// A JSON file that is never silently destroyed.
//
// Every app here keeps its state in one or two JSON files under
// ~/.local/share/moarchy-<app>/, and every one of them has the same two
// problems to solve: reload when something else writes the file, and do not
// overwrite a file that failed to parse. The second is the one that costs a
// user their notes, and it is what the GTK apps' stores already do.
//
// Writes are atomic without anything here doing it: FileView's `atomicWrites`
// defaults to true and renames a temp file into place, which is `os.replace`
// in Python by another name. Measured rather than assumed -- with the default
// the target's inode changes on write, and with `atomicWrites: false` it does
// not.
import QtQuick
import Quickshell
import Quickshell.Io
import "Json.js" as Json

FileView {
  id: file

  // The parsed object, or null for a file that is absent, empty or corrupt.
  // Every consumer treats null as "start from nothing", which is what the
  // Python stores return in the same three cases.
  signal parsed(var data)

  // Raised when a file was moved aside, so an app can say so rather than
  // looking as though it forgot.
  signal quarantined(string movedTo)

  printErrors: false
  watchChanges: true

  // Qt.callLater so a write of our own does not re-enter the read that caused
  // it. The GTK side has the same guard for the same reason.
  onFileChanged: Qt.callLater(function () { file.reload() })
  onLoaded: file.handle(file.text())

  // A file that is not there yet is the ordinary first run, and it has to be
  // reported: `loaded` never fires for it, so an app waiting for this signal to
  // build its default state waits for ever. Three apps had already grown a
  // private workaround for this before it was fixed here, which is what a gap
  // in a shared kit looks like from the outside.
  onLoadFailed: file.parsed(null)

  function handle(raw: string): void {
    var verdict = Json.classify(raw)
    if (verdict.state === Json.CORRUPT) {
      file.quarantine()
      file.parsed(null)
      return
    }
    file.parsed(verdict.state === Json.OK ? verdict.data : null)
  }

  function quarantine(): void {
    var dest = Json.brokenPath(file.path, Date.now() / 1000)
    // mv rather than FileView: there is no rename in the API, and a copy would
    // leave the broken original in place to be overwritten by the next save --
    // which is the whole failure this exists to prevent. `--` because a path
    // is data.
    Quickshell.execDetached(["mv", "--", file.path, dest])
    file.quarantined(dest)
  }
}
