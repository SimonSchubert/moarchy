// The chrome file, watched. Same path the shell plugins read.
//
// Metrics.space, not Style.space: qs.Commons is optional for a standalone
// app, and Metrics already probes it the same way type size does.
import QtQuick
import Quickshell
import Quickshell.Io
import "Ui.js" as Ui
import "Metrics.js" as Metrics

FileView {
  id: file

  property var chrome: Ui.fallback()

  readonly property string corners: file.chrome.corners
  readonly property string controlCenter: file.chrome.controlCenter

  readonly property int radiusSheet: file.px(file.chrome.sheet)
  readonly property int radiusTile: file.px(file.chrome.tile)
  readonly property int radiusCard: file.px(file.chrome.card)
  readonly property int controlCenterTile: file.px(file.chrome.controlCenterTile)
  readonly property int controlCenterSlider: file.px(file.chrome.controlCenterSlider)
  readonly property int controlCenterRound: file.px(file.chrome.controlCenterRound)

  function radiusOn(size) {
    return Ui.radiusOn(file.radiusTile, size)
  }

  function px(n) {
    var v = Number(n)
    if (!isFinite(v) || v <= 0) return 0
    return Metrics.space(v, file)
  }

  path: {
    var home = Quickshell.env("HOME") || ""
    return home + "/.config/omarchy/ui.toml"
  }

  watchChanges: true
  printErrors: false

  onLoaded: file.chrome = Ui.parse(file.text())
  onLoadFailed: file.chrome = Ui.fallback()
  onFileChanged: Qt.callLater(function () { file.reload() })
}
