// The share card: a widget of the user's own as a QR code and a link
// (docs/home.md HM46, HM47).
//
// Omalauncher's ShareWidgetScreen, without the upload: the whole file is in the
// link's fragment, so a phone that scans the code has the widget without it
// passing through any server. `moarchy-home share` makes the link and is the
// one place its format is written; `qrencode` draws it, black on white
// whatever the theme, because that is what cameras read best.
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Upstream
import "../moarchy.common" as Shared

Item {
  id: card

  property var host: null
  property bool open: false
  property string widgetId: ""

  signal closed()

  visible: card.open
  z: 210

  property string link: ""
  property string qr: ""            // a PNG path, or "" when there is none
  property string problem: ""
  property int stamp: 0             // a new image path per open, past the cache

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

  onOpenChanged: if (card.open) {
    card.link = ""
    card.qr = ""
    card.problem = ""
    card.stamp++
    make.command = ["bash", "-c",
      // argv, never text built into the script: the id is the user's.
      "link=$(moarchy-home share \"$1\" 2>/dev/null) || { echo 'error'; exit 0; }\n" +
      "printf 'link %s\\n' \"$link\"\n" +
      "if [ ${#link} -le 2953 ] && qrencode -l L -m 2 -s 8 -o \"$2\" \"$link\" 2>/dev/null; then\n" +
      "  printf 'qr %s\\n' \"$2\"\n" +
      "fi\n",
      "share", card.widgetId,
      card.runtimeDir + "/moarchy-share-" + card.stamp + ".png"]
    make.running = true
  }

  Shared.Probe {
    id: make
    onAnswered: {
      var lines = String(text).split("\n")
      for (var i = 0; i < lines.length; i++) {
        var l = lines[i]
        if (l.indexOf("link ") === 0) card.link = l.substring(5)
        else if (l.indexOf("qr ") === 0) card.qr = l.substring(3)
      }
      if (card.link === "") card.problem = "could not read ~/.config/omarchy/widgets/" + card.widgetId + ".qml"
      else if (card.qr === "") card.problem = "too long for a QR code; copy the link instead"
    }
  }

  // A tap outside the card puts it away.
  Rectangle {
    anchors.fill: parent
    color: Upstream.Color.menu.scrim
  }
  MouseArea {
    anchors.fill: parent
    // no press state (style.md H7): a scrim that dismisses
    onClicked: card.closed()
  }

  Rectangle {
    id: frame
    anchors.centerIn: parent
    width: Math.min(Style.space(340), parent.width - Style.space(24))
    height: column.implicitHeight + Style.space(24)
    color: Util.alpha(Upstream.Color.background, 0.97)
    radius: card.host ? card.host.radiusCard : 0
    border.width: Style.space(2)
    border.color: card.host ? card.host.accent : "transparent"

    MouseArea {
      anchors.fill: parent
      // no press state (style.md H7): a tap swallower behind a modal
    }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(12)
      spacing: Style.space(10)

      Text {
        width: column.width
        text: "share " + card.widgetId
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.weight: card.host ? card.host.textWeight : Font.Normal
        color: card.host ? card.host.textOnSurface : "transparent"
      }

      // Black on white on any theme, with its own quiet zone.
      Rectangle {
        width: column.width
        height: width
        visible: card.qr !== ""
        color: "white"
        Image {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          source: card.qr ? "file://" + card.qr : ""
          cache: false
          smooth: false
          fillMode: Image.PreserveAspectFit
        }
      }

      Text {
        width: column.width
        visible: card.problem !== "" || card.link === ""
        text: card.problem !== "" ? card.problem : "making the link…"
        wrapMode: Text.Wrap
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.weight: card.host ? card.host.textWeight : Font.Normal
        color: card.host ? card.host.subdued : "transparent"
      }

      Text {
        width: column.width
        visible: card.link !== ""
        text: "the whole file is in the link, after the #; nothing is uploaded"
        wrapMode: Text.Wrap
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.weight: card.host ? card.host.textWeight : Font.Normal
        color: card.host ? card.host.subdued : "transparent"
      }

      Item {
        width: column.width
        height: Style.space(44)
        visible: card.link !== ""

        property bool copied: false
        id: copyRow

        Shared.PressVeil {
          anchors.fill: parent
          radius: parent.height / 2
          ink: card.host ? card.host.accent : "transparent"
          on: copyArea.pressed
        }
        Text {
          anchors.centerIn: parent
          text: copyRow.copied ? "copied" : "copy link"
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.weight: card.host ? card.host.textWeight : Font.Normal
          color: card.host ? card.host.accent : "transparent"
        }
        MouseArea {
          id: copyArea
          anchors.fill: parent
          onClicked: {
            Quickshell.execDetached(["wl-copy", "--", card.link])
            copyRow.copied = true
          }
        }
        Connections {
          target: card
          function onOpenChanged() { copyRow.copied = false }
        }
      }
    }
  }
}
