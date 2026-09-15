// Minesweeper: a portrait board, a latching flag, and a clock that stops.
//
// The QML half of apps/minesweeper. The file is the GTK app's own, and holds a
// level, a seed and every tap -- not a minefield. That only works because
// Random.js reproduces CPython's Mersenne Twister exactly, so a game begun in
// one half lays the same mines in the other.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Minesweeper.js" as M
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "org.moarchy.minesweeper"
  readonly property bool opened: fieldWindow.visible
  readonly property var appWindow: fieldWindow

  property string returnTo: ""
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY
  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    if ((Quickshell.env("MOARCHY_MINESWEEPER_MARKING") || "") !== "") root.marking = true
  }

  property string levelKey: Store.DEFAULT_LEVEL
  property int seed: 0
  property var game: null
  property real seconds: 0
  property bool recorded: false
  property var stats: ({})
  property bool loaded: false
  property bool showNewGame: false
  property int revision: 0

  // The flag is a mode, not a long press. A long press on a 28px cell is a
  // gamble about whether the finger moved, and the cost of guessing wrong is
  // the whole game -- so the mode latches and says so in the bar.
  property bool marking: false

  readonly property var level: M.levelFor(root.levelKey)
  readonly property bool over: {
    var r = root.revision
    return root.game ? M.isOver(root.game) : false
  }
  readonly property bool running: {
    var r = root.revision
    return !!root.game && M.started(root.game) && !root.over
  }

  readonly property color surface: colours.surface
  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
  readonly property color line: colours.line
  readonly property color accent: colours.accent

  readonly property string dataDir: Plugin.dataDir(
    "minesweeper", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_MINESWEEPER_DIR"))

  function hueColor(name) {
    var hues = root.colours.hues || {}
    return hues[name] || root.accent
  }

  // One colour per number, the way every minesweeper has had since 1990. The
  // number is the information; the colour only makes a screenful scannable.
  function countColour(n) {
    var names = ["", "blue", "green", "red", "magenta", "brown", "cyan", "yellow", "orange"]
    return root.hueColor(names[n] || "yellow")
  }

  function say(text) { toast.show(text) }

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
    } catch (e) {}
    fieldWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  function close() { root.showNewGame = false }

  function dismiss() {
    root.close()
    fieldWindow.hide()
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
    if (!root.game) return
    store.setText(Store.serialize({
      level: root.levelKey, seed: root.seed, seconds: root.seconds,
      finished: root.over, recorded: root.recorded,
      moves: root.game.moves, stats: root.stats
    }))
  }

  function newGame(levelKey) {
    root.levelKey = levelKey
    // A seed a person could read out. Seconds rather than milliseconds because
    // it goes in a file somebody might look at.
    root.seed = Math.floor(Date.now() / 1000)
    root.game = M.create(M.levelFor(levelKey), root.seed, [])
    root.seconds = 0
    root.recorded = false
    root.revision += 1
    root.showNewGame = false
    root.save()
  }

  function tap(cell) {
    if (!root.game || root.over) return
    var changed = root.marking ? M.mark(root.game, cell) : M.tap(root.game, cell)
    if (!changed) return
    root.revision += 1
    root.finishIfDone()
    root.save()
  }

  // A tap on an opened number clears around it, which is the move that makes
  // this playable on a 28px cell: once the flags are down, clearing the rest of
  // a number is one tap rather than five aimed ones.
  function chord(cell) {
    if (!root.game || root.over) return
    if (!M.clearAround(root.game, cell)) return
    root.revision += 1
    root.finishIfDone()
    root.save()
  }

  function finishIfDone() {
    if (!M.isOver(root.game) || root.recorded) return
    root.recorded = true
    if (M.won(root.game)) {
      var key = "best_" + root.levelKey
      var previous = root.stats[key]
      var mine = Math.floor(root.seconds)
      if (previous === undefined || mine < previous) {
        root.stats = Store.record(root.stats, key, mine)
        root.say("Cleared in " + mine + "s — your best.")
      } else {
        root.say("Cleared in " + mine + "s.")
      }
    } else {
      root.say("That one was a mine.")
    }
  }

  // The clock stops with the window. An app counting seconds in a pocket is
  // claiming somebody is still playing.
  Timer {
    interval: 1000
    repeat: true
    running: fieldWindow.visible && root.running
    onTriggered: root.seconds += 1
  }

  Process { id: ensureDir; running: false; command: ["mkdir", "-p", root.dataDir] }

  Chrome.JsonFile {
    id: store
    path: root.dataDir + "/minesweeper.json"
    onParsed: function (data) {
      var g = Store.parse(data)
      root.levelKey = g.level
      root.seed = g.seed
      root.seconds = g.seconds
      root.recorded = g.recorded
      root.stats = g.stats
      root.game = M.create(M.levelFor(g.level), g.seed, g.moves)
      root.revision += 1
    }
    onQuarantined: function (to) { root.say("The saved game was unreadable and was kept aside.") }
  }

  Chrome.ThemeFile { id: themeFile }

  IpcHandler {
    target: "minesweeper"
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
    function play(cell: string): string {
      var n = parseInt(cell, 10)
      if (isNaN(n)) return "not a cell"
      root.tap(n)
      return "ok"
    }
    function marking(on: string): string {
      root.marking = on === "1" || on === "true"
      return root.marking ? "on" : "off"
    }
    function status(): string {
      if (!root.game) return "no game"
      return (M.lost(root.game) ? "lost" : M.won(root.game) ? "won" : "playing") +
             " opened=" + M.openedCount(root.game) +
             " flags=" + M.flagCount(root.game) +
             " remaining=" + M.remaining(root.game)
    }
    function settled(): bool { return root.game !== null }
  }

  Chrome.AppWindow {
    id: fieldWindow
    shell: root.shell
    appName: "Minesweeper"
    pluginId: root.pluginId
    color: root.background

    onMapped: {
      Qt.callLater(root.ensureLoaded)
      if (!root.game) Qt.callLater(function () { store.reload() })
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
          title: "Minesweeper"
          subtitle: {
            var r = root.revision
            if (!root.game) return "—"
            if (M.lost(root.game)) return "Lost"
            if (M.won(root.game)) return "Cleared in " + Math.floor(root.seconds) + "s"
            return M.remaining(root.game) + " left · " + Math.floor(root.seconds) + "s"
          }
          foreground: root.textOnSurface
          dim: root.dim
          bodySize: root.bodySize

          trailing: Row {
            Chrome.IconButton {
              // The flag mode, latched. It is the one control on this screen
              // that changes what a tap means, so it says so by staying lit.
              color: root.marking ? root.hueColor("red") : root.textOnSurface
              names: root.marking ? ["view-pin-symbolic", "starred-symbolic"]
                                  : ["view-pin-symbolic", "non-starred-symbolic"]
              tooltip: root.marking ? "Flagging" : "Flag"
              onClicked: root.marking = !root.marking
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
            readonly property real cell: {
              var w = (parent.width - 12) / root.level.width
              var h = (parent.height - 12) / root.level.height
              return Math.max(18, Math.floor(Math.min(w, h)))
            }
            width: boardBox.cell * root.level.width
            height: boardBox.cell * root.level.height

            Grid {
              anchors.fill: parent
              columns: root.level.width
              Repeater {
                model: M.cellCount(root.level)
                delegate: Item {
                  id: square
                  required property int index
                  width: boardBox.cell
                  height: boardBox.cell

                  readonly property bool isOpen: {
                    var r = root.revision
                    return !!(root.game && root.game.opened[square.index])
                  }
                  readonly property bool isFlag: {
                    var r = root.revision
                    return !!(root.game && root.game.flags[square.index])
                  }
                  readonly property bool isMine: {
                    var r = root.revision
                    return !!(root.game && root.over && M.isMine(root.game, square.index))
                  }
                  readonly property int count: {
                    var r = root.revision
                    return (root.game && square.isOpen && M.started(root.game))
                           ? M.neighbourCount(root.game, square.index) : 0
                  }
                  readonly property bool boom: {
                    var r = root.revision
                    return !!root.game && root.game.boom === square.index
                  }

                  Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 3
                    color: square.boom ? root.hueColor("red")
                         : square.isOpen ? Theme.mix(root.colours.foreground, root.colours.background, 0.05)
                         : Theme.mix(root.colours.foreground, root.colours.background, 0.16)
                    Behavior on color { ColorAnimation { duration: 120 } }
                  }

                  // The number.
                  Chrome.TypedText {
                    anchors.centerIn: parent
                    visible: square.isOpen && square.count > 0 && !square.boom
                    role: "body"
                    text: String(square.count)
                    color: root.countColour(square.count)
                    bodySize: root.bodySize
                  }

                  // A flag: a shape, because a red square and a grey one are
                  // the same square to a lot of people.
                  Rectangle {
                    anchors.centerIn: parent
                    visible: square.isFlag && !square.isOpen
                    width: parent.width * 0.42
                    height: width
                    radius: 2
                    rotation: 45
                    color: root.hueColor("red")
                  }

                  // Where the mines were, once it is over.
                  Rectangle {
                    anchors.centerIn: parent
                    visible: square.isMine && !square.isFlag && !square.boom
                    width: parent.width * 0.38
                    height: width
                    radius: width / 2
                    color: root.textOnSurface
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: {
                      // A tap on a number clears around it; anywhere else it
                      // opens or flags.
                      if (square.isOpen && square.count > 0) root.chord(square.index)
                      else root.tap(square.index)
                    }
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
              model: M.LEVELS
              delegate: Item {
                required property var modelData
                width: parent.width
                height: 44

                Rectangle {
                  anchors.fill: parent
                  radius: Metrics.CARD_RADIUS
                  color: modelData.key === root.levelKey
                         ? Theme.mix(root.accent, root.colours.background, 0.25)
                         : "transparent"
                }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: 10
                  spacing: 10
                  Chrome.TypedText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 78
                    role: "body"; text: modelData.label
                    color: root.textOnSurface; bodySize: root.bodySize
                  }
                  Chrome.TypedText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 98
                    role: "caption"
                    text: modelData.width + "×" + modelData.height + ", " +
                          modelData.mines + " mines"
                    color: root.dim; bodySize: root.bodySize
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.newGame(modelData.key)
                }
              }
            }
          }
        }
      }
    }
  }
}
