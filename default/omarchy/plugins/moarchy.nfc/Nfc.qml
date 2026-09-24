// NFC, as one button.
//
// Tap Read, hold a card or tag to the back of the phone, see what it is. The
// screen does not talk to the NFC controller itself: `moarchy-nfc read` does,
// because polling needs CAP_NET_ADMIN and the kernel ties a poll to the socket
// that started it. This file only starts that helper, waits, and draws its
// key=value answer -- the same split moarchy.sim uses, for the same reason: the
// half that touches hardware can be run and tested from a shell.
//
// Closing the screen mid-read stops the helper. It turns the controller back
// off on SIGTERM, so an abandoned read does not leave the radio and its
// reference clock running.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui
import "../moarchy.common/Theme.js" as Theme
import "../moarchy.common" as Shared
import "../moarchy.common/Sheet.js" as Sheet

Item {
  id: root

  property var shell: null
  readonly property string pluginId: "moarchy.nfc"
  readonly property bool opened: nfcWindow.visible
  readonly property var appWindow: nfcWindow
  property string returnTo: ""

  readonly property color surface: Color.popups.background
  readonly property color textOnSurface: Color.popups.text
  readonly property color container: Util.alpha(Color.popups.text, 0.08)
  readonly property color containerHigh: Util.alpha(Color.popups.text, 0.14)
  readonly property color accent: Color.accent
  readonly property color textOnAccent: Color.background
  readonly property color danger: Color.urgent
  readonly property int textWeight: Font.DemiBold

  Shared.UiFile { id: ui }
  readonly property int radiusTile: ui.radiusTile

  // Same absolute path rule as moarchy.sim: a bare name resolves against the
  // shell's PATH, and a Process that cannot find its binary still fires its
  // collector -- with empty text, which would read as "no card".
  readonly property string nfcTool: "/usr/lib/moarchy/bin/moarchy-nfc"
  readonly property int readSeconds: 20

  // idle | reading | found | timeout | error | absent
  property string phase: "idle"
  property var tag: ({})
  property string errorText: ""

  readonly property string glyphNfc: String.fromCodePoint(0xF0396)
  readonly property string glyphTap: String.fromCodePoint(0xF0397)

  readonly property string pageTitle: {
    if (root.phase === "found") return root.tag.type ? "Tag read" : "Read"
    if (root.phase === "reading") return "Reading"
    return "NFC"
  }

  function open(payloadJson) {
    Sheet.cover(root.shell, root.pluginId, Sheet.WINDOW)
    nfcWindow.show()
    root.returnTo = ""
    var payload = Sheet.payload(payloadJson)
    if (payload.returnTo) root.returnTo = String(payload.returnTo)
    if (root.phase !== "found") root.phase = "idle"
    presenceProbe.running = true
  }

  function close() { nfcWindow.hide() }

  function startRead() {
    if (root.phase === "reading" || root.phase === "absent") return
    root.errorText = ""
    root.tag = ({})
    root.phase = "reading"
    readProc.running = true
  }

  function stopRead() {
    if (readProc.running) readProc.running = false
    if (root.phase === "reading") root.phase = "idle"
  }

  function parse(text) {
    var kv = {}
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var eq = lines[i].indexOf("=")
      if (eq > 0) kv[lines[i].slice(0, eq)] = lines[i].slice(eq + 1)
    }
    return kv
  }

  Shared.Probe {
    id: presenceProbe
    command: [root.nfcTool, "status"]
    onAnswered: (text) => {
      var kv = root.parse(text)
      if (kv.present === "no") root.phase = "absent"
      else if (root.phase === "absent") root.phase = "idle"
    }
  }

  Process {
    id: readProc
    command: [root.nfcTool, "read", String(root.readSeconds)]
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.phase !== "reading") return      // stopped by closing the screen
        var kv = root.parse(this.text)
        if (kv.status === "found") {
          root.tag = kv
          root.phase = "found"
        } else if (kv.status === "timeout") {
          root.phase = "timeout"
        } else if (kv.status === "no-device") {
          root.phase = "absent"
        } else {
          root.errorText = kv.error || "The NFC reader did not answer"
          root.phase = "error"
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: if (this.text.trim() !== "" && root.phase === "reading")
        root.errorText = this.text.trim()
    }
  }

  // The rows worth showing, in reading order. A tag only has some of these.
  readonly property var rows: [
    { key: "type", label: "Type" },
    { key: "manufacturer", label: "Chip maker" },
    { key: "tech", label: "Technology" },
    { key: "uid", label: "UID" },
    { key: "atqa", label: "ATQA" },
    { key: "sak", label: "SAK" },
    { key: "ats", label: "ATS" },
    { key: "protocols", label: "Protocols" }
  ]

  Shared.AppWindow {
    id: nfcWindow
    shell: root.shell
    appName: "NFC"
    pageTitle: root.pageTitle
    pluginId: root.pluginId
    glyph: root.glyphNfc
    color: root.surface

    onMapped: presenceProbe.running = true
    onUnmapped: root.stopRead()

    Rectangle {
      anchors.fill: parent
      color: root.surface

      Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(24), Style.space(320))
        spacing: Style.space(12)

        Text {
          id: bigGlyph
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.phase !== "found"
          text: root.phase === "reading" ? root.glyphTap : root.glyphNfc
          color: root.phase === "reading" ? root.accent : Theme.readableOn(root.surface, root.textOnSurface)
          font.family: Style.font.family
          font.pixelSize: Style.space(64)

          SequentialAnimation on opacity {
            running: root.phase === "reading"
            loops: Animation.Infinite
            onStopped: bigGlyph.opacity = 1
            NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
          }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          color: root.textOnSurface
          font.family: Style.font.family
          font.pixelSize: Style.space(17)
          font.weight: Font.Bold
          text: root.phase === "reading" ? "Hold a card to the back of the phone"
              : root.phase === "found" ? (root.tag.type || "Tag read")
              : root.phase === "timeout" ? "No card found"
              : root.phase === "error" ? "Could not read"
              : root.phase === "absent" ? "No NFC reader on this phone"
              : "Read an NFC tag or card"
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          visible: text !== ""
          color: root.phase === "error" ? root.danger : Theme.readableOn(root.surface, root.textOnSurface)
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
          font.weight: root.textWeight
          text: root.phase === "reading" ? "Flat against the back, and keep it still for a moment"
              : root.phase === "timeout" ? "Nothing answered within " + root.readSeconds + " seconds."
              : root.phase === "error" ? root.errorText
              : ""
        }

        // The result: one row per field the tag actually reported.
        Rectangle {
          width: parent.width
          visible: root.phase === "found"
          radius: root.radiusTile
          color: root.container
          height: resultColumn.implicitHeight + Style.space(16)

          Column {
            id: resultColumn
            x: Style.space(12)
            y: Style.space(8)
            width: parent.width - Style.space(24)
            spacing: Style.space(6)

            Repeater {
              model: root.rows
              Column {
                required property var modelData
                width: resultColumn.width
                visible: (root.tag[modelData.key] || "") !== ""
                spacing: Style.space(1)

                Text {
                  color: Theme.readableOn(root.container, root.textOnSurface)
                  opacity: 0.7
                  font.family: Style.font.family
                  font.pixelSize: Style.space(11)
                  font.weight: root.textWeight
                  text: modelData.label
                }
                TextEdit {
                  width: parent.width
                  readOnly: true
                  selectByMouse: true
                  wrapMode: TextEdit.WrapAnywhere
                  color: root.textOnSurface
                  font.family: modelData.key === "type" || modelData.key === "tech"
                               ? Style.font.family : "monospace"
                  font.pixelSize: Style.space(14)
                  font.weight: root.textWeight
                  text: root.tag[modelData.key] || ""
                }
              }
            }
          }
        }

        Item { width: 1; height: Style.space(4) }

        // The one button. It is Read, Read again, or Cancel while reading.
        Rectangle {
          id: action
          readonly property bool reading: root.phase === "reading"
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.phase !== "absent"
          width: Style.space(200)
          height: Style.space(52)
          radius: root.radiusTile
          color: action.reading ? (tap.pressed ? root.containerHigh : root.container)
               : tap.pressed ? Qt.darker(root.accent, 1.15) : root.accent

          Text {
            anchors.centerIn: parent
            color: action.reading ? root.textOnSurface : root.textOnAccent
            font.family: Style.font.family
            font.pixelSize: Style.space(16)
            font.weight: Font.Bold
            text: action.reading ? "Cancel"
                : (root.phase === "found" || root.phase === "timeout" || root.phase === "error")
                  ? "Read again" : "Read"
          }

          MouseArea {
            id: tap
            anchors.fill: parent
            onClicked: action.reading ? root.stopRead() : root.startRead()
          }
        }
      }
    }
  }
}
