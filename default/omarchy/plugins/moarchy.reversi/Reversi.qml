// Reversi, in the shell: a board drawn for 360px, an opponent on a clock.
//
// The QML half of apps/reversi. The file is the GTK app's own
// (~/.local/share/moarchy-reversi/reversi.json), so a game left in one is the
// game found in the other -- the move list is what is stored, and both halves
// replay it the same way.
//
// The board is sixty-four Items rather than one drawn surface, which is the
// opposite of what widgets.py argues for and right for the opposite reason.
// That file defends one DrawingArea against sixty-four GTK widgets: sixty-four
// style contexts to resolve, sixty-four nodes to lay out. None of that exists
// here. A Rectangle is one scene-graph node, sixty-four of the same material
// batch into one draw call, and a frame in which nothing changed submits
// nothing at all. What it buys is that the square drawn and the square tapped
// are the same object, so they cannot disagree.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Bits.js" as Bits
import "Reversi.js" as Reversi
import "Ai.js" as Ai
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.reversi"
  readonly property bool opened: boardWindow.visible
  readonly property var appWindow: boardWindow

  property string returnTo: ""
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY
  Component.onCompleted: root.bodySize = Metrics.shellBody(root)

  // The game is the move list; everything else is derived from it.
  property var moves: []
  property string level: Store.DEFAULT_LEVEL
  property int human: Reversi.DARK
  property var stats: ({})
  property bool loaded: false
  property bool showNewGame: false

  // Bumped for every change, because `moves` is replaced rather than mutated
  // but `position` is derived by a function call that QML must be told to redo.
  property int revision: 0

  property bool thinking: false
  // A new game started mid-search gets an answer it throws away: WorkerScript
  // cannot be interrupted, so the reply carries the generation it was asked
  // under and a stale one is dropped.
  property int generation: 0

  readonly property var position: {
    var r = root.revision
    return Reversi.replay(root.moves).position
  }
  readonly property var legalNow: {
    var r = root.revision
    return Reversi.moves(root.position)
  }
  readonly property bool humanTurn: root.position.turn === root.human
  readonly property bool over: {
    var r = root.revision
    return Reversi.isOver(root.position)
  }

  readonly property color surface: colours.surface
  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
  readonly property color line: colours.line
  readonly property color accent: colours.accent

  readonly property string dataDir: Plugin.dataDir(
    "reversi", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_REVERSI_DIR"))

  function hueColor(name) {
    var hues = root.colours.hues || {}
    return hues[name] || root.accent
  }

  // The board's colours, ported from theme.py's board_colours().
  //
  // The discs stay dark and light rather than becoming two of the theme's hues,
  // and they stay that way in a light theme too. A pair of hues looks good in a
  // screenshot and fails in daylight, for the eight percent of men who cannot
  // tell the popular pair apart, and at 43px. Dark against light survives all
  // three -- so a disc takes a *tint* from the theme and not its identity.
  //
  // Getting this backwards is not a subtle bug: the first cut drew Dark as the
  // theme's foreground, which on a dark theme is a light disc called Dark.
  readonly property color feltColour: Theme.mix(root.hueColor("green"),
                                                root.colours.background,
                                                root.colours.dark ? 0.34 : 0.58)
  // A control center of the felt rather than of the window: grid lines have to stay
  // darker than the board in both directions.
  readonly property color feltLine: Theme.mix(root.feltColour, "#000000", 0.70)
  readonly property color darkDisc: Theme.mix(root.colours.background, "#0d0d10", 0.22)
  readonly property color lightDisc: Theme.mix(root.colours.foreground, "#f4f3f1", 0.14)
  readonly property color darkRim: Theme.mix("#ffffff", root.darkDisc, 0.20)
  readonly property color lightRim: Theme.mix("#000000", root.lightDisc, 0.14)

  function discColour(colour) {
    return colour === Reversi.DARK ? root.darkDisc : root.lightDisc
  }

  function rimColour(colour) {
    return colour === Reversi.DARK ? root.darkRim : root.lightRim
  }

  function say(text) { toast.show(text) }

  // --- the shell's plugin contract --------------------------------------

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
    } catch (e) {}
    boardWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  function close() { root.showNewGame = false }

  function dismiss() {
    root.close()
    boardWindow.hide()
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
  }

  function save() {
    store.setText(Store.serialize({
      mode: "computer", level: root.level, human: root.human,
      finished: root.over, moves: root.moves, stats: root.stats
    }))
  }

  // --- playing ----------------------------------------------------------

  function tap(cell) {
    if (root.thinking || !root.humanTurn || root.over) return
    if (!Reversi.isLegal(root.position, cell)) return
    root.commit(cell)
  }

  function commit(cell) {
    var next = root.moves.slice()
    next.push(cell)
    root.moves = next
    root.revision += 1
    root.settle()
  }

  // After every move: a forced pass is taken for whoever it falls on, the
  // result is recorded once, and the computer is asked if it is its turn.
  function settle() {
    if (Reversi.isOver(root.position)) {
      root.finish()
      root.save()
      return
    }
    if (Reversi.mustPass(root.position)) {
      root.say(Reversi.NAMES[root.position.turn] + " has no move.")
      root.commit(Reversi.PASS)
      return
    }
    root.save()
    if (!root.humanTurn) Qt.callLater(root.ponder)
  }

  function finish() {
    var winner = Reversi.winner(root.position)
    var outcome = winner === null ? "drawn" : (winner === root.human ? "won" : "lost")
    root.stats = Store.record(root.stats, outcome)
    var counts = Reversi.counts(root.position)
    root.say(winner === null ? "A draw, " + counts[0] + "-" + counts[1]
             : Reversi.NAMES[winner] + " wins " +
               Math.max(counts[0], counts[1]) + "-" + Math.min(counts[0], counts[1]))
  }

  function ponder() {
    if (root.thinking || root.over || root.humanTurn) return
    root.thinking = true
    root.generation += 1
    if (!root.brain) brainLoader.active = true
    if (!root.brain) { root.thinking = false; return }
    root.brain.sendMessage({
      position: root.position,
      level: root.level,
      generation: root.generation
    })
  }

  function thought(reply) {
    // A different game now: the answer is for a board nobody is looking at.
    if (reply.generation !== root.generation) return
    root.thinking = false
    if (reply.trouble) root.say("The opponent stumbled; playing on.")
    if (reply.cell === Reversi.PASS) { root.commit(Reversi.PASS); return }
    if (!Reversi.isLegal(root.position, reply.cell)) {
      // Never seen, and guarded anyway: a board nobody can play on is worse
      // than a weak move.
      var legal = Reversi.legal(root.position)
      if (!legal.length) { root.commit(Reversi.PASS); return }
      root.commit(legal[0])
      return
    }
    root.commit(reply.cell)
  }

  function newGame(level, human) {
    root.generation += 1   // orphan any search in flight
    root.thinking = false
    root.level = level
    root.human = human
    root.moves = []
    root.revision += 1
    root.showNewGame = false
    root.save()
    if (!root.humanTurn) Qt.callLater(root.ponder)
  }

  function undo() {
    if (root.thinking || !root.moves.length) return
    // Back to the human's own last move, not one ply: undoing into the
    // computer's turn would have it move again immediately, which reads as the
    // undo having done nothing.
    var next = root.moves.slice()
    while (next.length) {
      next.pop()
      var p = Reversi.replay(next).position
      if (p.turn === root.human && !Reversi.mustPass(p)) break
    }
    root.moves = next
    root.revision += 1
    root.save()
  }

  // --- plumbing ---------------------------------------------------------

  Process { id: ensureDir; running: false; command: ["mkdir", "-p", root.dataDir] }

  // The search, behind a Loader so that it can be taken down before the
  // process is.
  //
  // A WorkerScript is a thread. Tearing the QML engine down while one exists
  // -- even an idle one that has already answered -- takes the process with
  // it: "QEventLoop: Cannot be used without QCoreApplication", a crash report,
  // and an exit code nobody wanted. Unloading the Loader joins the thread
  // first, which is the difference between quitting and crashing on the way
  // out. `shutdown()` is what every exit path calls.
  Loader {
    id: brainLoader
    active: true
    sourceComponent: WorkerScript {
      source: "search.js"
      onMessage: function (reply) { root.thought(reply) }
    }
  }

  // `Loader.item` is a QObject, and a QObject has no sendMessage on it as far
  // as the linter is concerned. Naming the type here is what keeps the call
  // site checkable rather than resolved at run time and hoped for.
  readonly property WorkerScript brain: brainLoader.item as WorkerScript

  function shutdown() {
    root.thinking = false
    brainLoader.active = false
  }

  Chrome.JsonFile {
    id: store
    path: root.dataDir + "/reversi.json"
    onParsed: function (data) {
      var g = Store.parse(data)
      root.level = g.level
      root.human = g.human
      root.stats = g.stats
      root.moves = g.moves
      root.revision += 1
      if (!root.over && !root.humanTurn) Qt.callLater(root.ponder)
    }
    onQuarantined: function (to) { root.say("The saved game was unreadable and was kept aside.") }
  }

  Chrome.ThemeFile { id: themeFile }

  IpcHandler {
    target: "reversi"
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
    // The harness's half: a square by name, so a screenshot script that says
    // "play d3" cannot photograph the wrong move.
    function play(square: string): string {
      for (var i = 0; i < Reversi.CELLS; i++)
        if (Reversi.notation(i) === square) { root.tap(i); return "ok" }
      return "no such square"
    }
    function board(): string {
      return Bits.toHex(root.position.dark) + ":" + Bits.toHex(root.position.light)
    }
    function score(): string { return Reversi.counts(root.position).join("-") }
    function settled(): bool { return !root.thinking }
  }

  // --- the window -------------------------------------------------------

  Chrome.AppWindow {
    id: boardWindow
    shell: root.shell
    appName: "Reversi"
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
          title: "Reversi"
          subtitle: {
            var r = root.revision
            if (root.over) {
              var w = Reversi.winner(root.position)
              return w === null ? "Drawn" : Reversi.NAMES[w] + " wins"
            }
            if (root.thinking) return "Thinking…"
            return root.humanTurn ? "Your move" : Reversi.NAMES[root.position.turn] + " to play"
          }
          foreground: root.textOnSurface
          dim: root.dim
          bodySize: root.bodySize

          trailing: Row {
            Chrome.IconButton {
              colours: root.colours
              color: root.textOnSurface
              names: ["edit-undo-symbolic", "go-previous-symbolic"]
              tooltip: "Undo"
              onClicked: root.undo()
            }
            Chrome.IconButton {
              colours: root.colours
              color: root.textOnSurface
              names: ["view-refresh-symbolic"]
              tooltip: "New game"
              spinning: root.thinking
              onClicked: root.showNewGame = true
            }
          }
        }

        // --- the score ---------------------------------------------------

        Row {
          Layout.fillWidth: true
          Layout.preferredHeight: 44
          Repeater {
            model: [Reversi.DARK, Reversi.LIGHT]
            delegate: Row {
              required property var modelData
              width: boardWindow.width / 2
              height: 44
              spacing: 8
              leftPadding: 16

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                radius: 11
                color: root.discColour(modelData)
                border.width: 1
                border.color: root.rimColour(modelData)
              }
              Chrome.TypedText {
                anchors.verticalCenter: parent.verticalCenter
                role: "title"
                text: {
                  var r = root.revision
                  return String(Reversi.count(root.position, modelData))
                }
                color: root.position.turn === modelData && !root.over
                       ? root.accent : root.textOnSurface
                bodySize: root.bodySize
              }
              Chrome.TypedText {
                anchors.verticalCenter: parent.verticalCenter
                role: "caption"
                text: modelData === root.human ? "you" : ""
                color: root.dim
                bodySize: root.bodySize
              }
            }
          }
        }

        // --- the board ---------------------------------------------------

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          Item {
            id: boardBox
            anchors.centerIn: parent
            // Square, and a multiple of eight so every cell is a whole number
            // of pixels: a board 361 wide has seven cells of 45 and one of 46.
            readonly property int side: {
              var room = Math.min(parent.width - 16, parent.height - 16)
              return Math.max(8, Math.floor(room / 8) * 8)
            }
            width: side
            height: side

            Rectangle {
              anchors.fill: parent
              radius: Metrics.radius(root.colours, Metrics.CARD_RADIUS)
              color: root.feltColour
            }

            Grid {
              anchors.fill: parent
              columns: 8
              // Row 8 is drawn first: a1 is the bottom-left square, the way
              // reversi.py numbers it and the way a board is printed.
              Repeater {
                model: 64
                delegate: Item {
                  id: square
                  required property int index
                  readonly property int cell: (7 - Math.floor(index / 8)) * 8 + (index % 8)
                  width: boardBox.side / 8
                  height: boardBox.side / 8

                  readonly property int owner: {
                    var r = root.revision
                    if (Bits.test(root.position.dark, square.cell)) return Reversi.DARK
                    if (Bits.test(root.position.light, square.cell)) return Reversi.LIGHT
                    return -1
                  }
                  readonly property bool playable: {
                    var r = root.revision
                    return root.humanTurn && !root.thinking && !root.over
                           && Bits.test(root.legalNow, square.cell)
                  }

                  Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1
                    border.color: root.feltLine
                  }

                  // The disc. A scale animation rather than a redrawn frame:
                  // the flip is one property over 180ms, and the scene graph
                  // does the rest.
                  Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.78
                    height: width
                    radius: width / 2
                    visible: square.owner >= 0
                    color: square.owner >= 0 ? root.discColour(square.owner) : "transparent"
                    border.width: 1
                    border.color: square.owner >= 0 ? root.rimColour(square.owner) : "transparent"
                    Behavior on color { ColorAnimation { duration: 180 } }
                    scale: square.owner >= 0 ? 1 : 0
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                  }

                  // Where you may play, as a ring: a filled dot would read as a
                  // disc already there.
                  Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.3
                    height: width
                    radius: width / 2
                    visible: square.playable
                    color: "transparent"
                    border.width: 2
                    border.color: root.feltLine
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.tap(square.cell)
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

        // --- new game ------------------------------------------------------

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
              model: Ai.LEVELS
              delegate: Item {
                required property var modelData
                width: parent.width
                height: 44

                Rectangle {
                  anchors.fill: parent
                  radius: Metrics.radius(root.colours, Metrics.CARD_RADIUS)
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
                    width: 72
                    role: "body"; text: modelData.name
                    color: root.textOnSurface; bodySize: root.bodySize
                  }
                  Chrome.TypedText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 92
                    role: "caption"; text: modelData.blurb
                    color: root.dim; bodySize: root.bodySize
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.newGame(modelData.key, root.human)
                }
              }
            }
          }
        }
      }
    }
  }
}
