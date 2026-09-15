// Habits, in the shell: a tap a day, a streak, and how strong that makes it.
//
// The QML half of apps/habits. The file is the GTK app's own
// (~/.local/share/moarchy-habits/habits.json), so a day ticked here is ticked
// there. Chrome comes from shared/qs_ui, vendored into this plugin as ui/.
//
// A habit is kept on a local calendar day, so "today" is read off the phone's
// clock and then carried as a bare ISO label -- the same reason habits.py
// ignores timezones entirely.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Habits.js" as Habits
import "Game.js" as Game

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "org.moarchy.habits"
  readonly property bool opened: habitWindow.visible
  readonly property var appWindow: habitWindow

  property string returnTo: ""
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY
  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    root.applyHarness()
  }

  property var habits: []
  property var achievements: ({})
  property bool loaded: false

  // "list", "detail", "achievements"
  property string page: "list"
  property string openId: ""
  property string today: Habits.todayFrom(Date.now(), Quickshell.env("MOARCHY_HABITS_TODAY"))

  // Bumped on every write so the bindings that walk a habit's history -- the
  // streak, the score, the strip -- recompute. The habit objects are mutated
  // in place (habits.py does the same, for the same reason: a new object per
  // tick is a new object per tick), so nothing else would tell QML to look.
  property int revision: 0

  readonly property color surface: colours.surface
  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
  readonly property color line: colours.line
  readonly property color accent: colours.accent

  readonly property var shownHabits: {
    var r = root.revision
    return r >= 0 ? Habits.active(root.habits) : []
  }
  readonly property var current: {
    var r = root.revision
    for (var i = 0; i < root.habits.length; i++)
      if (root.habits[i].id === root.openId) return root.habits[i]
    return null
  }

  readonly property string dataDir: Plugin.dataDir(
    "habits", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_HABITS_DIR"))

  // --- the harness ------------------------------------------------------

  // The same variables apps/habits/shots.sh sets, so that list ports across
  // unchanged: _OPEN names a habit, _PAGE names a screen, _TODAY pins the day
  // so two shots taken either side of midnight agree.
  function applyHarness() {
    var page = Quickshell.env("MOARCHY_HABITS_PAGE") || ""
    if (page === "achievements") root.page = "achievements"
    if ((Quickshell.env("MOARCHY_HABITS_NEW") || "") !== "") root.page = "editor"
  }

  function applyOpenHarness() {
    var want = Quickshell.env("MOARCHY_HABITS_OPEN") || ""
    if (!want.length) return
    for (var i = 0; i < root.habits.length; i++)
      if (root.habits[i].name === want || root.habits[i].id === want) {
        root.openId = root.habits[i].id
        root.page = "detail"
        return
      }
  }

  // --- colours ----------------------------------------------------------

  function hueColor(name) {
    var hues = root.colours.hues || {}
    return hues[name] || root.accent
  }

  // The fill of one mark, at a step from 0 (untouched) to STEPS. Step 0 is a
  // wash of the theme's own foreground rather than the habit's colour, so an
  // untouched day reads as absent rather than as a pale version of done.
  function markColour(habit, day) {
    var step = Habits.stepFor(habit, day)
    if (step === 0) return Theme.mix(root.colours.foreground, root.colours.background, 0.10)
    return Theme.mix(root.hueColor(habit.colour), root.colours.background,
                     Habits.rampAt(root.colours.dark, step))
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
    habitWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  function close() {
    root.page = "list"
    root.openId = ""
  }

  function dismiss() {
    root.close()
    habitWindow.hide()
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

  // --- writing ----------------------------------------------------------

  function save() {
    store.setText(Habits.serialize(root.habits, root.achievements))
  }

  function tick(habit, day) {
    // Tomorrow is not a day anybody has done anything on yet.
    if (day > root.today) return
    var before = Habits.streak(habit, root.today)
    Habits.toggle(habit, day)
    var after = Habits.streak(habit, root.today)
    root.revision += 1

    var crossed = Habits.milestoneCrossed(before, after)
    if (crossed) root.say(crossed + " days of " + (habit.name || "this") + ".")

    root.award()
    root.save()
  }

  function award() {
    var fresh = Game.newlyEarned(root.habits, root.achievements, root.today)
    if (!fresh.length) return
    var earned = ({})
    for (var k in root.achievements) earned[k] = root.achievements[k]
    for (var i = 0; i < fresh.length; i++) earned[fresh[i]] = root.today
    root.achievements = earned
    // One line, not ten: a pile of achievements arriving at once is a pile of
    // toasts nobody reads.
    var first = Game.describe(fresh[0])
    root.say(fresh.length === 1 ? first.name + " — " + first.blurb
                                : fresh.length + " achievements earned.")
  }

  // --- plumbing ---------------------------------------------------------

  // The day can change under a window that is left open overnight.
  Timer {
    interval: 60000
    repeat: true
    running: habitWindow.visible
    onTriggered: {
      var now = Habits.todayFrom(Date.now(), Quickshell.env("MOARCHY_HABITS_TODAY"))
      if (now !== root.today) { root.today = now; root.revision += 1 }
    }
  }

  Process { id: ensureDir; running: false; command: ["mkdir", "-p", root.dataDir] }

  Chrome.JsonFile {
    id: store
    path: root.dataDir + "/habits.json"
    onParsed: function (data) {
      var got = Habits.parse(data)
      root.habits = got.habits
      root.achievements = got.achievements
      root.revision += 1
      Qt.callLater(root.applyOpenHarness)
    }
    onQuarantined: function (to) {
      root.say("The habits file was unreadable and was kept aside.")
    }
  }

  Chrome.ThemeFile { id: themeFile }

  IpcHandler {
    target: "habits"
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
    function screen(name: string): string {
      root.page = (name === "achievements" || name === "detail") ? name : "list"
      return root.page
    }
    function settled(): bool { return root.loaded }
  }

  // --- the window -------------------------------------------------------

  Chrome.AppWindow {
    id: habitWindow
    shell: root.shell
    appName: "Habits"
    pageTitle: root.page === "achievements" ? "Achievements"
               : (root.current ? root.current.name : "")
    pluginId: root.pluginId
    color: root.background

    onMapped: {
      Qt.callLater(root.ensureLoaded)
      // Nothing yet, and this plugin stays loaded for the life of the shell:
      // a file created after the first open -- by the GTK half, or by a
      // restore -- is never noticed, because a FileView watching a path that
      // does not exist is not told when it appears.
      if (!root.habits.length) Qt.callLater(function () { store.reload() })
    }

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true
      Keys.onEscapePressed: {
        if (root.page !== "list") { root.close(); return }
        root.dismiss()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12
          title: root.page === "achievements" ? "Achievements"
                 : (root.page === "detail" && root.current ? root.current.name : "Habits")
          subtitle: {
            var r = root.revision
            if (root.page === "achievements") {
              var have = 0
              for (var k in root.achievements) have += 1
              return have + " of " + Game.keys().length + " earned"
            }
            if (root.page === "detail" && root.current)
              return Habits.streak(root.current, root.today) + " day streak"
            var p = Habits.todayProgress(root.habits, root.today)
            return p.due ? p.done + " of " + p.due + " today" : "No habits yet"
          }
          foreground: root.textOnSurface
          dim: root.dim
          bodySize: root.bodySize

          leading: Chrome.BackButton {
            visible: root.page !== "list"
            color: root.textOnSurface
            onClicked: root.close()
          }

          trailing: Row {
            Chrome.IconButton {
              visible: root.page === "list"
              color: root.textOnSurface
              names: ["starred-symbolic"]
              tooltip: "Achievements"
              onClicked: root.page = "achievements"
            }
          }
        }

        // --- the list ----------------------------------------------------

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          Flickable {
            anchors.fill: parent
            visible: root.page === "list"
            clip: true
            contentWidth: width
            contentHeight: listCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: listCol
              width: parent.width

              // The five days the strip offers, oldest on the left, today on
              // the right where a thumb rests.
              Row {
                width: parent.width
                height: 26
                Item { width: 12; height: 1 }
                Item {
                  width: listCol.width - 12 - (Habits.STRIP_DAYS * 44) - 4
                  height: 1
                }
                Repeater {
                  model: Habits.recentDays(Habits.STRIP_DAYS, root.today)
                  delegate: Item {
                    required property var modelData
                    width: 44
                    height: 26
                    Chrome.TypedText {
                      anchors.centerIn: parent
                      role: "overline"
                      // The day of the month: a weekday letter repeats every
                      // seven and gives no purchase on where you are.
                      text: modelData.slice(8)
                      color: modelData === root.today ? root.accent : root.dim
                      bodySize: root.bodySize
                    }
                  }
                }
              }

              Repeater {
                model: root.shownHabits

                delegate: Item {
                  id: habitRow
                  required property var modelData
                  readonly property var habit: habitRow.modelData
                  width: listCol.width
                  height: 64

                  MouseArea {
                    anchors.fill: parent
                    onClicked: { root.openId = habitRow.habit.id; root.page = "detail" }
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 4
                    spacing: 6

                    Column {
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignVCenter
                      spacing: 1

                      Chrome.TypedText {
                        width: parent.width
                        role: "body"
                        text: habitRow.habit.name || "Untitled"
                        color: root.textOnSurface
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }
                      Chrome.TypedText {
                        width: parent.width
                        role: "caption"
                        text: {
                          var r = root.revision
                          var run = Habits.streak(habitRow.habit, root.today)
                          var strength = Math.round(Habits.score(habitRow.habit, root.today) * 100)
                          return (run ? run + " day streak · " : "") + strength + "%"
                        }
                        color: root.dim
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }
                    }

                    // Five 44px targets: the smallest thing a thumb hits
                    // reliably, and what fits beside a readable name at 360px.
                    Repeater {
                      model: Habits.recentDays(Habits.STRIP_DAYS, root.today)

                      delegate: Item {
                        id: cell
                        required property var modelData
                        readonly property string day: cell.modelData
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                          anchors.centerIn: parent
                          width: 30
                          height: 30
                          radius: 9
                          color: {
                            var r = root.revision
                            return root.markColour(habitRow.habit, cell.day)
                          }
                          border.width: Habits.stepFor(habitRow.habit, cell.day) === 0 ? 1 : 0
                          border.color: root.line
                          scale: markTap.pressed ? 0.88 : 1.0
                          Behavior on scale { NumberAnimation { duration: 90 } }
                        }

                        MouseArea {
                          id: markTap
                          anchors.fill: parent
                          onClicked: root.tick(habitRow.habit, cell.day)
                        }
                      }
                    }
                  }

                  Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: root.line
                  }
                }
              }
            }
          }

          // --- one habit -------------------------------------------------

          Flickable {
            anchors.fill: parent
            visible: root.page === "detail" && !!root.current
            clip: true
            contentWidth: width
            contentHeight: detailCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: detailCol
              width: parent.width
              leftPadding: 16
              rightPadding: 16
              topPadding: 8
              spacing: 10

              Chrome.TypedText {
                width: detailCol.width - 32
                visible: text.length > 0
                role: "body"
                text: root.current ? root.current.question : ""
                color: root.dim
                bodySize: root.bodySize
                wrapMode: Text.WordWrap
              }

              Grid {
                columns: 2
                spacing: 8
                Repeater {
                  model: {
                    var r = root.revision
                    var h = root.current
                    if (!h) return []
                    return [
                      { label: "Streak", value: Habits.streak(h, root.today) + " days" },
                      { label: "Best", value: Habits.bestStreak(h, root.today) + " days" },
                      { label: "Strength", value: Math.round(Habits.score(h, root.today) * 100) + "%" },
                      { label: "Kept", value: Habits.keptDays(h) + " days" },
                      { label: "Total", value: Habits.total(h) + (h.unit ? " " + h.unit : "") },
                      { label: "Points", value: String(Game.habitPoints(h)) }
                    ]
                  }
                  delegate: Rectangle {
                    required property var modelData
                    width: (detailCol.width - 40) / 2
                    height: 56
                    radius: Metrics.CARD_RADIUS
                    color: Theme.mix(root.colours.foreground, root.colours.background, 0.06)

                    Column {
                      anchors.centerIn: parent
                      spacing: 2
                      Chrome.TypedText {
                        role: "overline"
                        text: modelData.label
                        color: root.dim
                        bodySize: root.bodySize
                      }
                      Chrome.TypedText {
                        role: "body"
                        text: modelData.value
                        color: root.textOnSurface
                        bodySize: root.bodySize
                      }
                    }
                  }
                }
              }

              Chrome.TypedText {
                width: detailCol.width - 32
                role: "caption"
                text: {
                  var r = root.revision
                  var h = root.current
                  if (!h) return ""
                  var next = Habits.nextMilestone(h, root.today)
                  return next ? next.away + " days to " + next.target
                              : "Every milestone passed."
                }
                color: root.dim
                bodySize: root.bodySize
              }

              // Sixteen weeks, read rather than tapped.
              Column {
                spacing: 3
                Chrome.TypedText {
                  role: "overline"
                  text: "Last sixteen weeks"
                  color: root.dim
                  bodySize: root.bodySize
                }
                Repeater {
                  model: 7
                  delegate: Row {
                    id: weekRow
                    required property int index
                    spacing: 3
                    Repeater {
                      model: 16
                      delegate: Rectangle {
                        id: weekCell
                        required property int index
                        // By id and not `parent.parent.index`: a Row's parent
                        // is a QQuickItem with no index on it, so reaching
                        // through it resolved to undefined and put every mark
                        // in this grid on the wrong day. qmllint said so.
                        readonly property string day: {
                          var back = (15 - weekCell.index) * 7 + (6 - weekRow.index)
                          return Habits.addDays(root.today, -back)
                        }
                        width: 15
                        height: 15
                        radius: 4
                        color: {
                          var r = root.revision
                          return root.current ? root.markColour(root.current, weekCell.day) : "transparent"
                        }
                      }
                    }
                  }
                }
              }

              Item { width: 1; height: 12 }
            }
          }

          // --- the ten ---------------------------------------------------

          Flickable {
            anchors.fill: parent
            visible: root.page === "achievements"
            clip: true
            contentWidth: width
            contentHeight: achCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: achCol
              width: parent.width

              Repeater {
                model: Game.ACHIEVEMENTS

                delegate: Item {
                  required property var modelData
                  readonly property string key: modelData[0]
                  readonly property bool earned: root.achievements[key] !== undefined
                  width: achCol.width
                  height: 64

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    Rectangle {
                      Layout.preferredWidth: 36
                      Layout.preferredHeight: 36
                      Layout.alignment: Qt.AlignVCenter
                      radius: 18
                      color: earned ? Theme.mix(root.hueColor("yellow"), root.colours.background, 0.28)
                                    : Theme.mix(root.colours.foreground, root.colours.background, 0.10)

                      Chrome.Icon {
                        anchors.centerIn: parent
                        names: earned ? ["starred-symbolic"] : ["non-starred-symbolic", "starred-symbolic"]
                        color: earned ? root.hueColor("yellow") : root.dim
                        size: Metrics.ICON_INK
                      }
                    }

                    Column {
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignVCenter
                      spacing: 1
                      Chrome.TypedText {
                        width: parent.width
                        role: "body"
                        text: modelData[1]
                        color: earned ? root.textOnSurface : root.dim
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }
                      Chrome.TypedText {
                        width: parent.width
                        role: "caption"
                        // Earned once and never lost, so the date it was earned
                        // is worth more than the condition once it is behind you.
                        text: earned ? "Earned " + root.achievements[key] : modelData[2]
                        color: root.dim
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }
                    }
                  }

                  Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: root.line
                  }
                }
              }
            }
          }

          Chrome.TypedText {
            anchors.centerIn: parent
            width: parent.width - 48
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: root.page === "list" && root.shownHabits.length === 0
            role: "body"
            text: "No habits yet. Add one in the GTK app and it appears here."
            color: root.dim
            bodySize: root.bodySize
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
      }
    }
  }
}
