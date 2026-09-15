// Noughts and crosses: the game solved at startup, then told to err.
//
// The QML half of apps/tictactoe. The file is the GTK app's own, so a game left
// in one is the game found in the other -- the move list is what is stored.
//
// The solver runs on this thread and not in a worker, which is the opposite of
// Reversi and right for the opposite reason: the whole game is 5478 positions
// and solving it once takes a moment, where a reversi search is millions of
// nodes every move. It is warmed on the first idle frame so that cost is paid
// while somebody is looking at an empty board.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Tictactoe.js" as T
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "org.moarchy.tictactoe"
  readonly property bool opened: gameWindow.visible
  readonly property var appWindow: gameWindow

  property string returnTo: ""
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY
  Component.onCompleted: root.bodySize = Metrics.shellBody(root)

  property var moves: []
  property string level: Store.DEFAULT_LEVEL
  property int mark: T.CROSS
  property var series: ({})
  property var stats: ({})
  property bool loaded: false
  property bool recorded: false
  property bool showNewGame: false
  property int revision: 0
  property bool thinking: false

  readonly property var position: {
    var r = root.revision
    return T.replay(root.moves)
  }
  readonly property bool humanTurn: root.position.turn === root.mark
  readonly property bool over: {
    var r = root.revision
    return T.isOver(root.position)
  }
  readonly property var winningLine: {
    var r = root.revision
    return T.winningLine(root.position)
  }

  readonly property color surface: colours.surface
  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
  readonly property color line: colours.line
  readonly property color accent: colours.accent

  readonly property string dataDir: Plugin.dataDir(
    "tictactoe", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_TICTACTOE_DIR"))

  function hueColor(name) {
    var hues = root.colours.hues || {}
    return hues[name] || root.accent
  }

  // The two marks differ in shape first and colour second: a cross and a ring
  // are told apart by anyone, where two hues are not.
  function markColour(m) {
    return m === T.CROSS ? root.hueColor("blue") : root.hueColor("orange")
  }

  function say(text) { toast.show(text) }

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
    } catch (e) {}
    gameWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  function close() { root.showNewGame = false }

  function dismiss() {
    root.close()
    gameWindow.hide()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  function ensureLoaded() {
    if (root.loaded) return
    ensureDir.running = true
    store.reload()
    root.loaded = true
    // The tenth of a second the table costs, spent while somebody is looking at
    // an empty board rather than while they wait for a reply to their first tap.
    Qt.callLater(function () { T.warm() })
  }

  function save() {
    store.setText(Store.serialize({
      mode: "solo", level: root.level, mark: root.mark,
      finished: root.over, recorded: root.recorded,
      moves: root.moves, series: root.series, stats: root.stats
    }))
  }

  function tap(cell) {
    if (root.thinking || !root.humanTurn || root.over) return
    if (!T.isLegal(root.position, cell)) return
    root.commit(cell)
  }

  function commit(cell) {
    var next = root.moves.slice()
    next.push(cell)
    root.moves = next
    root.revision += 1
    root.settle()
  }

  function settle() {
    if (T.isOver(root.position)) { root.finish(); root.save(); return }
    root.save()
    if (!root.humanTurn) reply.restart()
  }

  function finish() {
    if (root.recorded) return
    root.recorded = true
    var w = T.winner(root.position)
    var outcome = w === null ? "drawn" : (w === root.mark ? "won" : "lost")
    root.stats = Store.record(root.stats, outcome)
    root.say(w === null ? "A draw." : (w === root.mark ? "You win." : "You lose."))
  }

  function ponder() {
    if (root.over || root.humanTurn) return
    root.thinking = true
    var cell = T.choose(root.position, T.levelFor(root.level), null, null)
    root.thinking = false
    if (cell < 0) return
    root.commit(cell)
  }

  function newGame(level, mark) {
    root.level = level
    root.mark = mark
    root.moves = []
    root.recorded = false
    root.revision += 1
    root.showNewGame = false
    root.save()
    if (!root.humanTurn) reply.restart()
  }

  function undo() {
    if (root.thinking || !root.moves.length) return
    // Back to the person's own last move: undoing one ply would hand the turn
    // straight back to the computer, which reads as the undo having done
    // nothing.
    var next = root.moves.slice()
    while (next.length) {
      next.pop()
      if (T.replay(next).turn === root.mark) break
    }
    root.moves = next
    root.recorded = false
    root.revision += 1
    root.save()
  }

  // A beat before the computer answers. Instant is unsettling on a board this
  // small -- it reads as the app having moved before you did.
  Timer { id: reply; interval: 420; onTriggered: root.ponder() }

  Process { id: ensureDir; running: false; command: ["mkdir", "-p", root.dataDir] }

  Chrome.JsonFile {
    id: store
    path: root.dataDir + "/tictactoe.json"
    onParsed: function (data) {
      var g = Store.parse(data)
      root.level = g.level
      root.mark = g.mark
      root.series = g.series
      root.stats = g.stats
      root.recorded = g.recorded
      root.moves = g.moves
      root.revision += 1
      if (!root.over && !root.humanTurn) reply.restart()
    }
    onQuarantined: function (to) { root.say("The saved game was unreadable and was kept aside.") }
  }

  Chrome.ThemeFile { id: themeFile }

  IpcHandler {
    target: "tictactoe"
    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
    function play(square: string): string {
      var cell = parseInt(square, 10)
      if (isNaN(cell)) return "not a square"
      root.tap(cell)
      return "ok"
    }
    function board(): string {
      var out = ""
      for (var i = 0; i < T.CELLS; i++) {
        if ((root.position.x >> i) & 1) out += "x"
        else if ((root.position.o >> i) & 1) out += "o"
        else out += "."
      }
      return out
    }
    function settled(): bool { return !root.thinking && !reply.running }
  }

  Chrome.AppWindow {
    id: gameWindow
    shell: root.shell
    appName: "Noughts and crosses"
    pluginId: root.pluginId
    color: root.background

    onMapped: {
      Qt.callLater(root.ensureLoaded)
      if (!root.moves.length) Qt.callLater(function () { store.reload() })
    }

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true
      Keys.onEscapePressed: {
        if (root.showNewGame) { root.showNewGame = false; return }
        root.dismiss()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12
          title: "Noughts and crosses"
          subtitle: {
            var r = root.revision
            if (root.over) {
              var w = T.winner(root.position)
              return w === null ? "A draw"
                   : (w === root.mark ? "You win" : T.NAMES[w] + " wins")
            }
            return root.humanTurn ? "Your turn, " + T.NAMES[root.mark]
                                  : T.NAMES[root.position.turn] + " to play"
          }
          foreground: root.textOnSurface
          dim: root.dim
          bodySize: root.bodySize

          trailing: Row {
            Chrome.IconButton {
              color: root.textOnSurface
              names: ["edit-undo-symbolic", "go-previous-symbolic"]
              tooltip: "Undo"
              onClicked: root.undo()
            }
            Chrome.IconButton {
              color: root.textOnSurface
              names: ["view-refresh-symbolic"]
              tooltip: "New game"
              onClicked: root.showNewGame = true
            }
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          Item {
            id: boardBox
            anchors.centerIn: parent
            readonly property int side: {
              var room = Math.min(parent.width - 24, parent.height - 24)
              return Math.max(3, Math.floor(room / 3) * 3)
            }
            width: side
            height: side

            Grid {
              anchors.fill: parent
              columns: 3
              Repeater {
                model: 9
                delegate: Item {
                  id: square
                  required property int index
                  width: boardBox.side / 3
                  height: boardBox.side / 3

                  readonly property int owner: {
                    var r = root.revision
                    if ((root.position.x >> square.index) & 1) return T.CROSS
                    if ((root.position.o >> square.index) & 1) return T.NOUGHT
                    return -1
                  }
                  readonly property bool inLine: {
                    var r = root.revision
                    return root.winningLine.indexOf(square.index) >= 0
                  }

                  Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: Metrics.CARD_RADIUS
                    color: square.inLine
                           ? Theme.mix(root.accent, root.colours.background, 0.22)
                           : Theme.mix(root.colours.foreground, root.colours.background, 0.07)
                    Behavior on color { ColorAnimation { duration: 200 } }
                  }

                  // A ring for O, two strokes for X. Shape before colour: the
                  // two are told apart by anyone, where two hues are not.
                  Rectangle {
                    anchors.centerIn: parent
                    visible: square.owner === T.NOUGHT
                    width: parent.width * 0.5
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: Math.max(3, parent.width * 0.09)
                    border.color: root.markColour(T.NOUGHT)
                    scale: square.owner === T.NOUGHT ? 1 : 0
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                  }

                  Item {
                    anchors.centerIn: parent
                    visible: square.owner === T.CROSS
                    width: parent.width * 0.48
                    height: width
                    scale: square.owner === T.CROSS ? 1 : 0
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                    Repeater {
                      model: [45, -45]
                      delegate: Rectangle {
                        required property var modelData
                        anchors.centerIn: parent
                        width: parent.width * 1.28
                        height: Math.max(3, parent.width * 0.18)
                        radius: height / 2
                        color: root.markColour(T.CROSS)
                        rotation: modelData
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.tap(square.index)
                  }
                }
              }
            }
          }

          Chrome.Toast {
            id: toast
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            colours: root.colours
            bodySize: root.bodySize
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: root.showNewGame ? 176 : 0
          visible: root.showNewGame
          color: Theme.mix(root.colours.foreground, root.colours.background, 0.06)

          Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Chrome.TypedText {
              role: "overline"; text: "NEW GAME"
              color: root.dim; bodySize: root.bodySize
            }

            Repeater {
              model: T.LEVELS
              delegate: Item {
                required property var modelData
                width: parent.width
                height: 44

                Rectangle {
                  anchors.fill: parent
                  radius: Metrics.CARD_RADIUS
                  color: modelData.key === root.level
                         ? Theme.mix(root.accent, root.colours.background, 0.25)
                         : "transparent"
                }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: 10
                  spacing: 10
                  Chrome.TypedText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 62
                    role: "body"; text: modelData.label
                    color: root.textOnSurface; bodySize: root.bodySize
                  }
                  Chrome.TypedText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 82
                    role: "caption"; text: modelData.blurb
                    color: root.dim; bodySize: root.bodySize
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.newGame(modelData.key, root.mark)
                }
              }
            }
          }
        }
      }
    }
  }
}
