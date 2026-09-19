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

  readonly property string pluginId: "moarchy.habits"
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

  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
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
    // An unkept day is a filled square one step up the ramp, not an outlined
    // one. The outline was a 1px border that disappeared on a phone in
    // daylight and left a hole in the grid.
    if (step === 0) return Theme.surface(root.colours, "raised")
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
            colours: root.colours
            visible: root.page !== "list"
            color: root.textOnSurface
            onClicked: root.close()
          }

          trailing: Row {
            Chrome.IconButton {
              colours: root.colours
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
            id: listPage
            anchors.fill: parent
            visible: root.page === "list"
            clip: true
            contentWidth: width
            contentHeight: listCol.implicitHeight + Metrics.GUTTER * 2
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: listCol
              x: Metrics.GUTTER
              y: Metrics.GUTTER
              width: listPage.width - Metrics.GUTTER * 2
              spacing: Metrics.LABEL_GAP

              // The five days the strip offers, oldest on the left, today on
              // the right where a thumb rests. It is a heading for the columns
              // under it, so it sits outside the box and lines up with them.
              Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 20

                Row {
                  anchors.right: parent.right
                  anchors.rightMargin: Metrics.GROUP_PAD + Metrics.GAP
                  anchors.verticalCenter: parent.verticalCenter

                  Repeater {
                    model: Habits.recentDays(Habits.STRIP_DAYS, root.today)
                    delegate: Item {
                      required property var modelData
                      width: Metrics.TARGET
                      height: 20
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
              }

              // One box, one row per habit. The name gets the whole width and
              // the five marks the line under it: at 360px a name and five
              // 44px targets on one line leaves 80px for the name, which is
              // not a name, it is an ellipsis.
              Chrome.Group {
                id: habitGroup
                Layout.fillWidth: true
                colours: root.colours
                visible: root.shownHabits.length > 0

                Repeater {
                  model: root.shownHabits

                  delegate: Item {
                    id: habitRow
                    required property var modelData
                    readonly property var habit: habitRow.modelData
                    Layout.fillWidth: true
                    implicitHeight: 86

                    Rectangle {
                      anchors.fill: parent
                      radius: habitGroup.innerRadius
                      color: Theme.surface(root.colours, "pressed")
                      visible: openTap.pressed
                    }

                    // Declared before the content so the five mark targets,
                    // which are children of it, sit on top and get their taps.
                    // A row handler declared last would swallow every one.
                    MouseArea {
                      id: openTap
                      anchors.fill: parent
                      onClicked: { root.openId = habitRow.habit.id; root.page = "detail" }
                    }

                    ColumnLayout {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Metrics.GAP
                      anchors.rightMargin: Metrics.GAP
                      spacing: 1

                      Chrome.TypedText {
                        Layout.fillWidth: true
                        role: "body"
                        text: habitRow.habit.name || "Untitled"
                        color: root.textOnSurface
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }

                      Chrome.TypedText {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 3
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

                      // Five 44px targets: the smallest thing a thumb hits
                      // reliably, and now on a line of their own they keep it.
                      Row {
                        Layout.alignment: Qt.AlignRight

                        Repeater {
                          model: Habits.recentDays(Habits.STRIP_DAYS, root.today)

                          delegate: Item {
                            id: cell
                            required property var modelData
                            readonly property string day: cell.modelData
                            width: Metrics.TARGET
                            height: 34

                            Rectangle {
                              anchors.centerIn: parent
                              width: 30
                              height: 30
                              radius: Metrics.radius(root.colours, Metrics.RADIUS_SM)
                              color: {
                                var r = root.revision
                                return root.markColour(habitRow.habit, cell.day)
                              }
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
                    }
                  }
                }
              }
            }
          }

          // --- one habit -------------------------------------------------

          Flickable {
            id: detailPage
            anchors.fill: parent
            visible: root.page === "detail" && !!root.current
            clip: true
            contentWidth: width
            contentHeight: detailCol.implicitHeight + Metrics.GUTTER * 2
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: detailCol
              x: Metrics.GUTTER
              y: Metrics.GUTTER
              width: detailPage.width - Metrics.GUTTER * 2
              spacing: Metrics.GAP

              Chrome.Card {
                Layout.fillWidth: true
                visible: String(root.current ? root.current.question : "").length > 0
                colours: root.colours

                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "body"
                  text: root.current ? root.current.question : ""
                  color: root.textOnSurface
                  bodySize: root.bodySize
                  wrapMode: Text.WordWrap
                }
              }

              GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Metrics.GAP
                rowSpacing: Metrics.GAP

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
                  delegate: Chrome.Tile {
                    id: statTile
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 62
                    colours: root.colours
                    bodySize: root.bodySize
                    label: statTile.modelData.label
                    value: statTile.modelData.value
                    valueColour: root.textOnSurface
                  }
                }
              }

              Chrome.Card {
                Layout.fillWidth: true
                colours: root.colours
                tint: root.current ? root.hueColor(root.current.colour) : "transparent"
                level: "well"

                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "body"
                  text: {
                    var r = root.revision
                    var h = root.current
                    if (!h) return ""
                    var next = Habits.nextMilestone(h, root.today)
                    return next ? next.away + " days to " + next.target
                                : "Every milestone passed."
                  }
                  color: root.textOnSurface
                  bodySize: root.bodySize
                  horizontalAlignment: Text.AlignHCenter
                }
              }

              // Sixteen weeks, read rather than tapped.
              Chrome.Section {
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                title: "Last sixteen weeks"
                cardSpacing: 3

                Repeater {
                  model: 7
                  delegate: Row {
                    id: weekRow
                    required property int index
                    Layout.alignment: Qt.AlignHCenter
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
                        radius: Metrics.radius(root.colours, Metrics.RADIUS_XXS)
                        color: {
                          var r = root.revision
                          return root.current ? root.markColour(root.current, weekCell.day) : "transparent"
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // --- the ten ---------------------------------------------------

          Flickable {
            id: achPage
            anchors.fill: parent
            visible: root.page === "achievements"
            clip: true
            contentWidth: width
            contentHeight: achCol.implicitHeight + Metrics.GUTTER * 2
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: achCol
              x: Metrics.GUTTER
              y: Metrics.GUTTER
              width: achPage.width - Metrics.GUTTER * 2
              spacing: 0

              Chrome.Group {
                id: achGroup
                Layout.fillWidth: true
                colours: root.colours

                Repeater {
                  model: Game.ACHIEVEMENTS

                  delegate: Chrome.ListRow {
                    id: ach
                    required property var modelData
                    readonly property string key: ach.modelData[0]
                    readonly property bool earned: root.achievements[ach.key] !== undefined
                    Layout.fillWidth: true
                    minHeight: 64
                    radius: achGroup.innerRadius
                    colours: root.colours
                    bodySize: root.bodySize
                    interactive: false
                    title: ach.modelData[1]
                    titleColour: ach.earned ? root.textOnSurface : root.dim
                    // Earned once and never lost, so the date it was earned is
                    // worth more than the condition once it is behind you.
                    subtitle: ach.earned ? "Earned " + root.achievements[ach.key]
                                         : ach.modelData[2]

                    leading: Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      width: 36
                      height: 36
                      radius: Metrics.round(root.colours, width)
                      color: ach.earned
                             ? Theme.tint(root.colours, root.hueColor("yellow"), "raised")
                             : Theme.surface(root.colours, "raised")

                      Chrome.Icon {
                        anchors.centerIn: parent
                        names: ach.earned
                               ? ["starred-symbolic"]
                               : ["non-starred-symbolic", "starred-symbolic"]
                        color: ach.earned ? root.hueColor("yellow") : root.dim
                        size: Metrics.ICON_INK
                      }
                    }
                  }
                }
              }
            }
          }

          Chrome.EmptyState {
            anchors.centerIn: parent
            width: parent.width - Metrics.GUTTER * 2
            visible: root.page === "list" && root.shownHabits.length === 0
            colours: root.colours
            bodySize: root.bodySize
            names: ["object-select-symbolic"]
            title: "No habits yet"
            detail: "Add one in the GTK app and it appears here, with today already on the strip."
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
