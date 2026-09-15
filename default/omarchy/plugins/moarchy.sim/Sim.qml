// The SIM PIN, on a keypad.
//
// docs/gestures.md K10: the fourth shell app, after Settings, Wi-Fi and
// Bluetooth, and it earns that the same way they do -- it is a screen you sit
// in and answer, not a sheet you dismiss.
//
// Why a keypad of its own rather than a text field and the on-screen keyboard,
// which is what Wi-Fi does for a passphrase:
//
//   A PIN is digits, four to eight of them, and the OSK opens on letters. Every
//   entry would start with a mode switch, on the one screen where a wrong
//   keystroke is not free.
//
//   The OSK takes the bottom of the screen with an exclusive zone. On a
//   passphrase that is fine; here it would cover the attempts-left count, which
//   is the single most important thing on this screen.
//
//   Ten big targets beat twenty-six small ones held in one hand.
//
// The counter is why this screen exists at all, and why it is loud. Three wrong
// PINs and the SIM wants a PUK that is on a plastic card somebody threw away in
// 2019. `moarchy-sim` refuses malformed input before the modem can count it;
// this draws what that refusal is protecting.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui
import "../moarchy.common/Theme.js" as Theme
import "../moarchy.common" as Shared

Item {
  id: root

  // Injected by the host, the same set every moarchy overlay takes.
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.sim"

  // Read off the window, never assigned -- moarchy.common/AppWindow.qml says
  // why that direction and not the other.
  readonly property bool opened: simWindow.visible
  readonly property var appWindow: simWindow

  // Where Back goes, set by whoever summoned this screen.
  property string returnTo: ""

  readonly property color surface: Color.popups.background
  readonly property color textOnSurface: Color.popups.text
  readonly property color container: Util.alpha(Color.popups.text, 0.08)
  readonly property color containerHigh: Util.alpha(Color.popups.text, 0.14)
  readonly property color accent: Color.accent
  readonly property color textOnAccent: Color.background
  readonly property color danger: "#e5534b"

  // ---------------------------------------------------------------- state
  // Straight out of `moarchy-sim status`, which is the only thing that talks to
  // ModemManager. Keeping the parsing in one place means this file never has an
  // opinion about mmcli's output format, and the shell-side behaviour can be
  // exercised over ssh without a running shell.
  property bool present: false
  property string modemState: ""
  property string lock: "none"
  property int retries: -1
  property string operator: ""

  property string pin: ""
  property string errorText: ""
  property bool busy: false

  readonly property bool locked: root.present && root.lock === "sim-pin"
  readonly property bool pukRequired: root.present && root.lock === "sim-puk"

  // The card's third line, and the window title's second half.
  readonly property string pageTitle: {
    if (!root.present) return "No modem"
    if (root.pukRequired) return "PUK required"
    if (root.locked) return root.retries >= 0 ? root.retries + " left" : "Locked"
    if (root.operator !== "") return root.operator
    return "Unlocked"
  }

  function refresh() { statusProbe.running = true }

  // The two the host calls, and the reason `summon` answered "ok" while
  // nothing appeared: a plugin that declares an overlay is still only reachable
  // through these. Same shape as moarchy.bluetooth's, including standing the
  // sheets down first -- opening a screen underneath the shade is how you get a
  // keypad you cannot see but can still type into.
  function open(payloadJson) {
    if (root.shell && typeof root.shell.isPluginOpen === "function") {
      if (root.shell.isPluginOpen("moarchy.shade")) root.shell.hide("moarchy.shade")
      if (root.shell.isPluginOpen("moarchy.drawer")) root.shell.hide("moarchy.drawer")
    }
    simWindow.show()
    root.returnTo = ""
    root.pin = ""
    root.errorText = ""
    root.refresh()
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload && payload.returnTo) root.returnTo = String(payload.returnTo)
    } catch (e) {
      // A malformed payload is not worth refusing to open over.
    }
  }

  function close() { simWindow.hide() }

  function press(digit) {
    if (root.busy || !root.locked) return
    if (root.pin.length >= 8) return
    root.errorText = ""
    root.pin += digit
  }

  function backspace() {
    if (root.busy) return
    root.errorText = ""
    root.pin = root.pin.slice(0, -1)
  }

  function submit() {
    if (root.busy || !root.locked) return
    if (root.pin.length < 4) { root.errorText = "A PIN is at least 4 digits"; return }
    root.busy = true
    unlockProc.command = ["moarchy-sim", "unlock", root.pin]
    unlockProc.running = true
  }

  Process {
    id: statusProbe
    command: ["moarchy-sim", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var present = false, st = "", lk = "none", rt = -1, op = ""
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var eq = lines[i].indexOf("=")
          if (eq < 0) continue
          var k = lines[i].slice(0, eq)
          var v = lines[i].slice(eq + 1)
          if (k === "present") present = (v === "yes")
          else if (k === "state") st = v
          else if (k === "lock") lk = v
          else if (k === "retries") rt = parseInt(v, 10)
          else if (k === "operator") op = v
        }
        root.present = present
        root.modemState = st
        root.lock = lk
        root.retries = isFinite(rt) ? rt : -1
        root.operator = op

        // Close on success rather than sitting there congratulating itself. The
        // screen exists to answer one question; once answered there is nothing
        // on it worth a tap.
        if (root.opened && present && lk === "none" && st !== "" && st !== "locked")
          simWindow.hide()
      }
    }
  }

  Process {
    id: unlockProc
    stdout: StdioCollector {}
    stderr: StdioCollector {
      onStreamFinished: root.errorText = String(text || "").trim()
    }
    // No exit code is read, and that is deliberate. The modem owns both the
    // lock and the counter, so "did that work" is a question for
    // `moarchy-sim status` -- and the status handler above closes this screen
    // when the answer is yes. An exit code here would be a second source of
    // truth for the same fact, and the one that goes stale.
    onExited: {
      root.busy = false
      root.pin = ""
      root.refresh()
    }
  }

  // Polled while open only. A locked SIM is a steady state and there is no
  // signal to subscribe to, but polling it for the life of the session -- the
  // mistake the bar's cellular widget calls out -- is pure waste.
  Timer {
    running: root.opened
    interval: 3000
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Shared.AppWindow {
    id: simWindow

    shell: root.shell
    appName: "SIM"
    pageTitle: root.pageTitle
    pluginId: root.pluginId
    // U+F0BD9, md-sim-alert. The literal rune, not a "\u" escape: JavaScript's
    // \u takes exactly four hex digits, so a five-digit codepoint silently
    // becomes two characters.
    glyph: "󰯙"
    color: root.surface

    onMapped: root.refresh()
    onUnmapped: {
      root.pin = ""
      root.errorText = ""
    }

    Rectangle {
      anchors.fill: parent
      color: root.surface

      Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(24), Style.space(300))
        spacing: Style.space(10)

        // ------------------------------------------------------ what is asked
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          color: root.textOnSurface
          font.pixelSize: Style.space(17)
          font.bold: true
          text: !root.present ? "No modem"
              : root.pukRequired ? "This SIM needs its PUK"
              : root.locked ? "Enter your SIM PIN"
              : "SIM unlocked"
        }

        // The number this screen is really about. Red once one wrong answer
        // would cost the PUK, because at that point it is the whole message.
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: root.locked && root.retries >= 0
          color: root.retries <= 1 ? root.danger : Theme.readableOn(root.surface, root.textOnSurface)
          font.pixelSize: Style.space(13)
          font.bold: root.retries <= 1
          text: root.retries === 1
              ? "1 attempt left — the next wrong PIN locks the SIM"
              : root.retries + " attempts left"
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: root.pukRequired
          wrapMode: Text.WordWrap
          color: root.danger
          font.pixelSize: Style.space(13)
          text: "A PIN will not help now. The PUK came with the SIM; entering it is not something this screen does yet."
        }

        // ------------------------------------------------------------- digits
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.locked
          spacing: Style.space(9)
          height: Style.space(22)

          Repeater {
            model: Math.max(4, root.pin.length)
            Rectangle {
              width: Style.space(11)
              height: Style.space(11)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: index < root.pin.length ? root.accent : root.containerHigh
            }
          }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: root.errorText !== ""
          wrapMode: Text.WordWrap
          color: root.danger
          font.pixelSize: Style.space(12)
          text: root.errorText
        }

        Item { width: 1; height: Style.space(4) }

        // ------------------------------------------------------------- keypad
        Grid {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.locked
          columns: 3
          spacing: Style.space(10)

          Repeater {
            // 1-9, then backspace, 0, OK. The two controls flank the zero
            // rather than sitting in a row of their own, so the whole pad is
            // one thumb's reach and the shapes stay square.
            model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "OK"]

            Rectangle {
              id: key
              required property int index
              required property string modelData

              readonly property bool isOk: modelData === "OK"
              readonly property bool isBack: modelData === "⌫"
              readonly property bool enabledKey:
                !root.busy && (key.isBack ? root.pin.length > 0
                             : key.isOk ? root.pin.length >= 4
                             : true)

              width: Style.space(64)
              height: Style.space(52)
              radius: Style.space(12)
              opacity: key.enabledKey ? 1 : 0.35
              color: key.isOk ? root.accent
                   : tap.pressed ? root.containerHigh
                   : root.container

              Text {
                anchors.centerIn: parent
                text: key.modelData
                color: key.isOk ? root.textOnAccent : root.textOnSurface
                font.pixelSize: key.isOk || key.isBack ? Style.space(16) : Style.space(21)
                font.bold: key.isOk
              }

              MouseArea {
                id: tap
                anchors.fill: parent
                enabled: key.enabledKey
                onClicked: {
                  if (key.isOk) root.submit()
                  else if (key.isBack) root.backspace()
                  else root.press(key.modelData)
                }
              }
            }
          }
        }
      }
    }
  }
}
