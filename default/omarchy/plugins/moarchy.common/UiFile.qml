// The chrome file, watched.
//
// Same shape as qs_ui/ThemeFile.qml: one path, one watch, fallbacks when the
// file is missing. Nine surfaces read D1 radii; putting the watch here is
// what stops a tenth from writing Style.space(18) again.
//
// `~/.config/omarchy/ui.toml` is the user file. It is never copied into a
// home by the package (docs/structure.md P1). Missing is the large/roomy
// look this phone shipped with -- themed by presence, never broken by
// absence, which is style.md I2's rule for colours, applied to shape.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Ui.js" as Ui

FileView {
  id: file

  property var chrome: Ui.fallback()

  readonly property string corners: file.chrome.corners
  readonly property string shade: file.chrome.shade

  // Scaled like every other length on this shell. Zero stays zero: Style.space
  // floors at 1, which would make "square" a 1px radius nobody asked for.
  readonly property int radiusSheet: file.px(file.chrome.sheet)
  readonly property int radiusTile: file.px(file.chrome.tile)
  readonly property int radiusCard: file.px(file.chrome.card)
  readonly property int shadeTile: file.px(file.chrome.shadeTile)
  readonly property int shadeSlider: file.px(file.chrome.shadeSlider)
  readonly property int shadeRound: file.px(file.chrome.shadeRound)

  function radiusOn(size) {
    return Ui.radiusOn(file.radiusTile, size)
  }

  function px(n) {
    var v = Number(n)
    if (!isFinite(v) || v <= 0) return 0
    return Style.space(v)
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
