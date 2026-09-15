// One sentence, at the bottom, for a few seconds.
//
// Seven plugins had their own copy of this rectangle, its timer and the
// three-line `say()` that drove it. It is a pill of the theme's own foreground
// with the background as ink -- inverted on purpose, so it reads as a message
// about the app rather than as part of it.
//
// A sentence and not a spinner: every message this shows is something a person
// can act on ("CoinGecko is rate-limiting this connection"), and a spinner
// would be the app declining to say which of its several problems it has.
import QtQuick
import "Theme.js" as Theme
import "Metrics.js" as Metrics

Rectangle {
  id: root

  property var colours: null
  property int bodySize: Metrics.BODY
  // How long a message stays. Long enough to read a sentence, short enough
  // that ticking four things in a row is not four waits.
  property int linger: 3000

  readonly property string message: label.text

  function show(text) {
    label.text = String(text || "")
    if (label.text.length) timer.restart()
  }

  function clear() { label.text = "" }

  visible: label.text.length > 0
  width: Math.min(parent ? parent.width - 32 : 320, label.implicitWidth + 28)
  height: 40
  radius: 20
  color: root.colours
         ? Theme.mix(root.colours.foreground, root.colours.background, 0.92)
         : "#e8e8e8"

  Timer {
    id: timer
    interval: root.linger
    onTriggered: label.text = ""
  }

  Text {
    id: label
    anchors.centerIn: parent
    width: parent.width - 28
    text: ""
    color: root.colours ? root.colours.background : "#1d1d20"
    font.family: Metrics.FONT
    font.weight: Font.DemiBold
    font.pixelSize: Metrics.typeSize(root.bodySize, "caption")
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    maximumLineCount: 1
  }
}
