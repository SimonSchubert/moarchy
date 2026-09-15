// A calendar for a phone: the month, the day under it, and what is next.
//
// Three screens and no more. **The month** is a grid you swipe through with
// the day's events underneath it, so tapping the 14th answers "what is on the
// 14th" without going anywhere. **The agenda** is the same events as one list
// from today forward, which is the other question a calendar is opened for.
// **The editor** is one screen per event, reached by the plus or by tapping
// something that already exists.
//
// The date picker in the editor is the same Month.qml the first screen draws
// three of. A picker that does not look like the calendar it came from is two
// things to learn instead of one, and the phone has room for neither.
//
// Nothing here is a port. The GTK half of this repository has no calendar and
// is not going to grow one: this was written for the shell, where a plugin is
// an Item the host already holds, so summoning it is `visible = true` on a
// window that exists rather than four seconds of starting a process. A
// calendar is opened for six seconds, several times a day, usually while
// somebody is being asked "does Thursday work?".
// Bound because the delegates are the whole screen. The month pager, the
// day's list, the agenda and the editor's chips all read `root` from inside
// a component boundary, and saying so is what turns forty lines of qmllint
// info into a promise the compiler can keep.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Dates.js" as Dates
import "Events.js" as Events
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "org.moarchy.calendar"
  readonly property bool opened: dayWindow.visible
  readonly property var appWindow: dayWindow

  property string returnTo: ""
  // `colours` and not `palette`: QQuickItem already has a `palette`, and
  // shadowing it makes a binding resolve to whichever the compiler picked.
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY

  // Which day a week starts on is the phone's business, not this app's. Qt
  // reads it off the system locale -- Monday here, Sunday in the United
  // States, Saturday in much of the Gulf -- and it is the one thing on this
  // screen that would be *wrong* rather than merely foreign if it were
  // hardcoded. The day names stay English, because the rest of the app is.
  property int weekStart: 1

  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    root.weekStart = root.firstDayOfWeek()
    root.applyHarness()
  }

  // MOARCHY_CALENDAR_WEEK_START=1 pins it, for the screenshot harness and for
  // anybody whose machine is set to a country they do not live in. A container
  // has no generated locales at all, so Qt answers Sunday there whatever LANG
  // says -- and a set of pictures where one week starts on Sunday and the next
  // on Monday is a set of pictures of the machine rather than of the app.
  function firstDayOfWeek() {
    var pinned = parseInt(Quickshell.env("MOARCHY_CALENDAR_WEEK_START") || "", 10)
    if (isFinite(pinned) && pinned >= 0 && pinned <= 6) return pinned
    var first = Qt.locale().firstDayOfWeek
    return (typeof first === "number" && first >= 0 && first <= 6) ? first : 1
  }

  // --- what is known --------------------------------------------------------

  property var events: []
  // Rows of the file this app could not read. Carried so they can be written
  // back untouched; see Store.js.
  property var strays: []
  property bool loaded: false

  // Bumped whenever the list changes, so the bindings that ask Events.js a
  // question about a day -- the dots, the panel, the agenda -- recompute.
  property int revision: 0

  property string today: Dates.todayFrom(Date.now(), Quickshell.env("MOARCHY_CALENDAR_TODAY"))
  property string selected: root.today
  property int shownMonth: Dates.monthOfDay(root.today)

  // "month" | "agenda" | "editor"
  property string page: "month"
  // Which of the two the editor came from, and therefore goes back to.
  property string returnPage: "month"

  // The event being edited, or null. A copy, always: nothing in `events`
  // changes until Save is pressed, which is what makes Back a cancel.
  property var draft: null
  property bool draftIsNew: false
  property bool pickingDate: false
  property int editorMonth: 0
  // The bin asks twice. There is no undo in a file with one version of
  // itself, so the second tap is the undo.
  property bool armed: false

  readonly property int shellFurniture: root.shell ? 60 : 0

  readonly property string dataDir: Plugin.dataDir(
    "calendar", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_CALENDAR_DIR"))

  // The pager's model. A century and a half of months, which is 1800 numbers
  // and three live delegates: a ListView builds what is on screen, so the
  // range costs nothing and nobody ever reaches the end of it.
  readonly property int firstMonth: Dates.monthIndex(1950, 1)
  readonly property int monthCount: 12 * 150

  readonly property var selectedEvents: {
    var r = root.revision
    return Events.onDay(root.events, root.selected)
  }

  readonly property var agenda: {
    var r = root.revision
    return Events.agenda(root.events, root.today, Events.HORIZON, Events.AGENDA_DAYS)
  }

  // --- colour ---------------------------------------------------------------

  readonly property color background: root.colours.background
  readonly property color ink: root.colours.foreground
  readonly property color dim: root.colours.dim
  readonly property color line: root.colours.line
  readonly property color accent: root.colours.accent
  readonly property string danger: (root.colours.hues && root.colours.hues.red) || "#e01b24"

  function shade(colour) {
    var c = Theme.rgb(String(colour))
    return (c[0] * 299 + c[1] * 587 + c[2] * 114) / 255000.0
  }

  // What can be read on top of the accent. Not always the background: on a
  // light theme that is white, and white on a pale accent is a date nobody
  // can find.
  readonly property string accentInk: {
    var level = root.shade(root.colours.accent)
    return Math.abs(level - root.shade(root.colours.background))
         > Math.abs(level - root.shade(root.colours.foreground))
      ? root.colours.background : root.colours.foreground
  }

  function hue(name) { return Events.hue(root.colours, name) }

  // An event's own colour, at the strength a card is washed in. Mixed from
  // the theme's background so that the same event is a pale tint on a light
  // theme and a dark one on a dark theme, rather than the same grey on both.
  function wash(name, amount) {
    return Theme.mix(root.hue(name), root.colours.background, amount)
  }

  function surface(amount) {
    return Theme.mix(root.colours.foreground, root.colours.background, amount)
  }

  function say(text) { toast.show(text) }

  // --- moving about ---------------------------------------------------------

  function showMonth(index) {
    root.shownMonth = index
    // Before the pager has a width there is nothing to move; it reads
    // `shownMonth` when it settles.
    if (pager.settled && pager.currentIndex !== index - root.firstMonth)
      pager.currentIndex = index - root.firstMonth
  }

  function selectDay(iso) {
    if (!Dates.isDay(iso)) return
    root.selected = iso
    root.showMonth(Dates.monthOfDay(iso))
  }

  function goToday() {
    root.selectDay(root.today)
    root.page = "month"
  }

  function stepMonth(by) {
    var next = root.shownMonth + by
    root.selected = Dates.sameDayIn(next, root.selected)
    root.showMonth(next)
  }

  // --- the editor -----------------------------------------------------------

  function startNew() {
    var day = root.page === "agenda" ? root.today : root.selected
    var at = day === root.today ? Dates.nextHalfHour(Date.now()) : -1
    root.openEditor(Events.blank(day, at, Events.nextColour(root.events), Date.now()), true)
    // The keyboard, at the field the event is named in. It is the one thing
    // anybody does first, and the form is at the top of the screen, so the
    // keyboard covers what is under it rather than what is being typed into.
    Qt.callLater(function () { titleField.focusInput() })
  }

  function startEdit(ev) {
    root.openEditor(Events.copy(ev), false)
  }

  function openEditor(ev, isNew) {
    root.returnPage = root.page === "editor" ? root.returnPage : root.page
    root.draft = ev
    root.draftIsNew = !!isNew
    root.armed = false
    root.pickingDate = false
    root.editorMonth = Dates.monthOfDay(ev.date)
    titleField.text = ev.title
    whereField.text = ev.where
    startField.text = Dates.formatTime(ev.start)
    endField.text = Dates.formatTime(ev.end)
    root.page = "editor"
  }

  function closeEditor() {
    root.draft = null
    root.armed = false
    root.pickingDate = false
    root.page = root.returnPage
  }

  // Every control in the editor writes straight into the draft, so there is
  // one answer to "what is being edited" and Save has nothing to collect.
  function change(field, value) {
    if (!root.draft) return
    var d = Events.copy(root.draft)
    d[field] = value
    root.draft = d
  }

  function setDate(iso) {
    if (!Dates.isDay(iso)) return
    root.change("date", iso)
    root.pickingDate = false
  }

  // Moving the start moves the end with it, keeping the length -- which is
  // what every calendar does and what nobody has ever had to be told. The end
  // is only ever pinned by typing into the end field.
  function commitStart() {
    if (!root.draft) return
    var at = Dates.parseTime(startField.text)
    if (at < 0) {
      root.say("\"" + startField.text + "\" is not a time.")
      startField.text = Dates.formatTime(root.draft.start)
      return
    }
    var length = Math.max(0, root.draft.end - root.draft.start)
    var d = Events.copy(root.draft)
    d.start = at
    d.end = Math.min(at + length, Dates.MINUTES - 1)
    root.draft = d
    startField.text = Dates.formatTime(d.start)
    endField.text = Dates.formatTime(d.end)
  }

  function commitEnd() {
    if (!root.draft) return
    var at = Dates.parseTime(endField.text)
    if (at < 0) {
      root.say("\"" + endField.text + "\" is not a time.")
      endField.text = Dates.formatTime(root.draft.end)
      return
    }
    if (at < root.draft.start) root.say("An event cannot end before it starts.")
    root.change("end", Math.max(at, root.draft.start))
    endField.text = Dates.formatTime(root.draft.end)
  }

  function commitDraft() {
    if (!root.draft) return
    // Both fields, whether or not Enter was ever pressed in them: a time
    // typed and then saved with the button is a time somebody meant.
    root.commitStart()
    root.commitEnd()

    var title = String(titleField.text || "").trim()
    if (!title.length) {
      root.say("An event needs a name.")
      titleField.focusInput()
      return
    }

    var d = Events.copy(root.draft)
    d.title = title
    d.where = String(whereField.text || "").trim()
    root.events = Events.withEvent(root.events, d)
    root.revision += 1
    root.selected = d.date
    root.showMonth(Dates.monthOfDay(d.date))
    root.draft = null
    root.page = root.returnPage
    root.save()
  }

  function deleteDraft() {
    if (!root.draft) return
    if (!root.armed) {
      root.armed = true
      disarm.restart()
      root.say("Tap the bin again to delete this.")
      return
    }
    root.events = Events.without(root.events, root.draft.id)
    root.revision += 1
    root.closeEditor()
    root.save()
    root.say("Deleted.")
  }

  Timer {
    id: disarm
    interval: 3000
    onTriggered: root.armed = false
  }

  // --- the shell's end of it ------------------------------------------------

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
      if (Dates.isDay(payload.day)) root.selectDay(payload.day)
    } catch (e) {}
    dayWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  function close() {
    if (root.page === "editor") root.closeEditor()
  }

  function dismiss() {
    root.close()
    dayWindow.hide()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  function back() {
    if (root.page === "editor") { root.closeEditor(); return }
    if (root.page === "agenda") { root.page = "month"; return }
    root.dismiss()
  }

  function ensureLoaded() {
    if (root.loaded) return
    ensureDir.running = true
    store.reload()
    root.loaded = true
  }

  function save() {
    store.setText(Store.serialize(root.events, root.strays))
  }

  // --- the harness ----------------------------------------------------------

  function applyHarness() {
    var day = Quickshell.env("MOARCHY_CALENDAR_DAY") || ""
    if (Dates.isDay(day)) {
      root.selected = day
      root.shownMonth = Dates.monthOfDay(day)
    }
    var page = Quickshell.env("MOARCHY_CALENDAR_PAGE") || ""
    if (page === "agenda") root.page = "agenda"
  }

  // After the file is in, because a new event picks the colour that is used
  // least and that cannot be known before the events are.
  function applyLoadedHarness() {
    if ((Quickshell.env("MOARCHY_CALENDAR_NEW") || "") !== "") root.startNew()
    else if ((Quickshell.env("MOARCHY_CALENDAR_EDIT") || "") !== "") {
      var want = Quickshell.env("MOARCHY_CALENDAR_EDIT")
      var list = Events.onDay(root.events, root.selected)
      for (var i = 0; i < list.length; i++)
        if (list[i].title === want || list[i].id === want) {
          root.startEdit(list[i])
          // The date picker is opened by a tap, and the harness has no finger.
          if ((Quickshell.env("MOARCHY_CALENDAR_PICKING") || "") !== "") root.pickingDate = true
          return
        }
    }
  }

  // --- plumbing -------------------------------------------------------------

  // Midnight happens to a window that was left open. The day it is decides
  // which date is ringed and where the agenda starts, so it is checked rather
  // than read once at startup.
  Timer {
    interval: 60000
    repeat: true
    running: dayWindow.visible
    onTriggered: {
      var now = Dates.todayFrom(Date.now(), Quickshell.env("MOARCHY_CALENDAR_TODAY"))
      if (now !== root.today) { root.today = now; root.revision += 1 }
    }
  }

  Process { id: ensureDir; running: false; command: ["mkdir", "-p", root.dataDir] }

  Chrome.JsonFile {
    id: store
    path: root.dataDir + "/calendar.json"

    // Re-read on every change, including this app's own writes: re-reading our
    // own save restores the state we were already in, and re-reading somebody
    // else's -- a `jq` from a script, the same file synced onto the phone --
    // puts it on screen without a restart. The calculator needs a read-once
    // guard because its state moves on between the write and the read; nothing
    // here does.
    onParsed: function (data) {
      var state = Store.parse(data)
      root.events = state.events
      root.strays = state.strays
      root.revision += 1
      if (!root.harnessed) { root.harnessed = true; Qt.callLater(root.applyLoadedHarness) }
    }
    onQuarantined: function (to) {
      root.say("The calendar file was unreadable and was kept aside.")
    }
  }

  property bool harnessed: false

  Chrome.ThemeFile { id: themeFile }

  IpcHandler {
    target: "calendar"

    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      else dayWindow.show()
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }

    function today(): string { return root.today }

    // What is on a day, as the screen would say it. Quickshell's IPC insists
    // on every declared argument, so the way to ask about the day the app is
    // showing is `on ""` rather than `on`.
    function on(day: string): string {
      var iso = Dates.isDay(day) ? day : root.selected
      var list = Events.onDay(root.events, iso)
      var out = []
      for (var i = 0; i < list.length; i++)
        out.push(Events.summary(list[i]) + "  " + list[i].title)
      return out.length ? out.join("\n") : "nothing on " + Dates.fullDayLabel(iso)
    }

    function show(day: string): string {
      if (!Dates.isDay(day)) return "not a day: " + day
      root.selectDay(day)
      root.page = "month"
      return root.selected
    }

    // One event, from a script. The only way into the file that is not a
    // thumb, and the reason a build that finishes at four can put itself in
    // somebody's calendar.
    function add(json: string): string {
      var raw
      try { raw = JSON.parse(String(json || "")) } catch (e) { return "not JSON: " + e }
      var ev = Events.normalise(raw, 0, Date.now())
      if (ev === null) return "an event needs a date, as \"date\": \"YYYY-MM-DD\""
      root.events = Events.withEvent(root.events, ev)
      root.revision += 1
      root.save()
      return ev.id
    }

    function remove(id: string): string {
      if (!Events.find(root.events, id)) return "no such event: " + id
      root.events = Events.without(root.events, String(id))
      root.revision += 1
      root.save()
      return "ok"
    }
  }

  // --- the window -----------------------------------------------------------

  Chrome.AppWindow {
    id: dayWindow
    shell: root.shell
    appName: "Calendar"
    pluginId: root.pluginId
    color: root.background
    pageTitle: root.page === "editor"
              ? (root.draftIsNew ? "New event" : "Event")
              : (root.page === "agenda" ? "Agenda"
                 : Dates.monthLabel(Dates.yearOf(root.shownMonth), Dates.monthOf(root.shownMonth)))

    onMapped: Qt.callLater(root.ensureLoaded)

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true

      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true; return }
        if (root.page !== "month") return
        if (event.key === Qt.Key_Left) { root.stepMonth(-1); event.accepted = true }
        else if (event.key === Qt.Key_Right) { root.stepMonth(1); event.accepted = true }
        else if (event.key === Qt.Key_Home) { root.goToday(); event.accepted = true }
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- the bar ----------------------------------------------------------

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12

          // The month, with the two months either side of it one tap away.
          // The swipe is the quick way and the arrows are the certain one; a
          // phone wants both, because one of them is done while walking.
          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "month"
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.IconButton {
              names: ["pan-start-symbolic", "go-previous-symbolic"]
              color: root.ink
              tooltip: "The month before"
              onClicked: root.stepMonth(-1)
            }

            center: Item {
              anchors.fill: parent

              Row {
                anchors.centerIn: parent
                spacing: 8

                Chrome.TypedText {
                  anchors.verticalCenter: parent.verticalCenter
                  role: "subtitle"
                  text: Dates.monthLabel(Dates.yearOf(root.shownMonth), Dates.monthOf(root.shownMonth))
                  color: root.ink
                  bodySize: root.bodySize
                }

                // Only when it would do something. A control that is always
                // there and usually does nothing stops being read.
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.shownMonth !== Dates.monthOfDay(root.today)
                  width: todayLabel.implicitWidth + 18
                  height: 26
                  radius: 13
                  color: Theme.alpha(root.accent, 0.16)

                  Text {
                    id: todayLabel
                    anchors.centerIn: parent
                    text: "Today"
                    color: root.accent
                    font.family: Metrics.FONT
                    font.pixelSize: Metrics.typeSize(root.bodySize, "caption")
                    font.weight: Font.DemiBold
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: root.goToday()
              }
            }

            trailing: Chrome.IconButton {
              names: ["pan-end-symbolic"]
              color: root.ink
              tooltip: "The month after"
              onClicked: root.stepMonth(1)
            }
          }

          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "agenda"
            title: "Agenda"
            subtitle: root.agenda.length ? "From " + Dates.shortDayLabel(root.today) : ""
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize
          }

          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "editor"
            title: root.draftIsNew ? "New event" : "Event"
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.BackButton {
              color: root.ink
              onClicked: root.closeEditor()
            }

            trailing: [
              Chrome.IconButton {
                visible: !root.draftIsNew
                names: ["user-trash-symbolic", "edit-delete-symbolic"]
                color: root.armed ? root.danger : root.ink
                tooltip: "Delete this event"
                onClicked: root.deleteDraft()
              },
              Chrome.IconButton {
                names: ["object-select-symbolic"]
                color: root.accent
                tooltip: "Save"
                onClicked: root.commitDraft()
              }
            ]
          }
        }

        // --- the three screens -------------------------------------------------

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          // ========== the month ==========

          Item {
            anchors.fill: parent
            visible: root.page === "month"

            Item {
              id: pagerFrame
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              height: 26 + Dates.ROWS * Math.round(root.bodySize * 2.9)

              ListView {
                id: pager
                anchors.fill: parent
                orientation: ListView.Horizontal
                snapMode: ListView.SnapOneItem
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: 0
                preferredHighlightEnd: width
                highlightMoveDuration: 220
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                // A month either side is built before it is needed, so a swipe
                // slides a grid that is already drawn rather than one being
                // laid out under the thumb.
                cacheBuffer: 2 * Math.max(1, width)

                // **Nothing is built until the window is on screen.**
                //
                // The shell keeps this plugin loaded -- `keepLoaded` in the
                // manifest -- so the whole app is instantiated while the shell
                // is starting, hours before anybody taps Calendar. Without
                // this line the pager lays itself out in that window, and then
                // jumps the nine hundred months from the start of its model to
                // this one, instantiating and throwing away a grid per month
                // on the way. On a phone that is a core at 99% during startup,
                // and the shell never finishes starting: no bar, no drawer, no
                // IPC, wallpaper only. A plugin the shell holds open has to
                // cost nothing until it is opened.
                readonly property bool live: dayWindow.visible && pager.width > 0
                model: pager.live ? root.monthCount : 0

                // The view opens on a month rather than on the first one in
                // its model, and it takes a second go to say so: a ListView
                // with no width enforces its range against nothing and puts
                // `currentIndex` back to 0, which is January 1950 with the
                // selection dragged there after it.
                property bool settled: false
                // Bounded, because the one thing this file must never do
                // again is spin. Ten turns of the event loop is far more than
                // a view needs to accept an index, and if it has not by then
                // the month on screen is wrong, which is a bug somebody can
                // see rather than a phone that will not start.
                property int attempts: 0

                onLiveChanged: {
                  if (!pager.live) { pager.settled = false; pager.attempts = 0; return }
                  Qt.callLater(pager.settle)
                }
                // The model arrives one turn after `live`, and an index set
                // against an empty view does not stick.
                onCountChanged: if (!pager.settled) Qt.callLater(pager.settle)

                function settle(): void {
                  if (pager.settled || !pager.live || pager.count <= 0) return
                  if (pager.attempts++ > 10) return
                  var want = root.shownMonth - root.firstMonth
                  // Without the duration, because this is a jump of hundreds
                  // of months: animated, it scrolls through every one of them
                  // and builds the grid for each.
                  var moved = pager.highlightMoveDuration
                  pager.highlightMoveDuration = 0
                  pager.currentIndex = want
                  pager.positionViewAtIndex(want, ListView.SnapPosition)
                  pager.highlightMoveDuration = moved
                  if (pager.currentIndex === want) pager.settled = true
                  else Qt.callLater(pager.settle)
                }

                onCurrentIndexChanged: {
                  if (!pager.settled) return
                  var index = pager.currentIndex + root.firstMonth
                  if (index === root.shownMonth) return
                  root.shownMonth = index
                  // The selection follows the swipe, to the same day of the
                  // new month. Leaving it behind would put the list under the
                  // grid on a day the grid is not showing.
                  if (Dates.monthOfDay(root.selected) !== index)
                    root.selected = Dates.sameDayIn(index, root.selected)
                }

                delegate: Month {
                  required property int index

                  width: pager.width
                  height: pager.height
                  year: Dates.yearOf(root.firstMonth + index)
                  month: Dates.monthOf(root.firstMonth + index)
                  weekStart: root.weekStart
                  today: root.today
                  selected: root.selected
                  events: root.events
                  revision: root.revision
                  colours: root.colours
                  accentInk: root.accentInk
                  bodySize: root.bodySize
                  onPicked: function (iso) { root.selectDay(iso) }
                }
              }
            }

            Rectangle {
              id: divider
              anchors.top: pagerFrame.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              height: 1
              color: root.line
            }

            // --- the day itself ---

            Item {
              anchors.top: divider.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom

              Item {
                id: dayHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: Metrics.TARGET

                Chrome.TypedText {
                  id: dayName
                  anchors.left: parent.left
                  anchors.leftMargin: 16
                  anchors.verticalCenter: parent.verticalCenter
                  role: "subtitle"
                  text: Dates.headline(root.selected, root.today)
                  color: root.selected === root.today ? root.accent : root.ink
                  bodySize: root.bodySize
                }

                Chrome.TypedText {
                  anchors.left: dayName.right
                  anchors.leftMargin: 8
                  anchors.right: parent.right
                  anchors.rightMargin: 16
                  anchors.baseline: dayName.baseline
                  role: "caption"
                  text: Dates.relative(root.selected, root.today).length
                        ? Dates.dayLabel(root.selected) : ""
                  color: root.dim
                  bodySize: root.bodySize
                  elide: Text.ElideRight
                }
              }

              Flickable {
                anchors.top: dayHeader.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                contentWidth: width
                contentHeight: dayList.height + 12
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                Column {
                  id: dayList
                  width: parent.width
                  spacing: 8
                  leftPadding: 12
                  rightPadding: 12

                  Repeater {
                    model: dayWindow.visible ? root.selectedEvents : []

                    delegate: EventRow {
                      required property var modelData

                      width: dayList.width - 24
                      entry: modelData
                      colours: root.colours
                      bodySize: root.bodySize
                      onClicked: root.startEdit(modelData)
                    }
                  }

                  // Nothing on. Not a blank half-screen: the empty state is
                  // most of what a new calendar is, and it is the only place
                  // to say where events come from.
                  Column {
                    width: dayList.width - 24
                    spacing: 4
                    visible: root.selectedEvents.length === 0
                    topPadding: 18

                    Chrome.TypedText {
                      width: parent.width
                      role: "body"
                      text: root.selected === root.today ? "Nothing today."
                                                         : "Nothing on " + Dates.dayLabel(root.selected) + "."
                      color: root.dim
                      bodySize: root.bodySize
                      horizontalAlignment: Text.AlignHCenter
                    }

                    Chrome.TypedText {
                      width: parent.width
                      role: "caption"
                      text: root.events.length ? "" : "The plus puts something in the day."
                      color: Theme.mix(root.colours.dim, root.colours.background, 0.6)
                      bodySize: root.bodySize
                      horizontalAlignment: Text.AlignHCenter
                    }
                  }
                }
              }
            }
          }

          // ========== the agenda ==========

          Flickable {
            anchors.fill: parent
            visible: root.page === "agenda"
            clip: true
            contentWidth: width
            contentHeight: agendaCol.height + 24
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: agendaCol
              width: parent.width
              spacing: 0
              topPadding: 4

              Repeater {
                // Same reason as the pager: four hundred days are walked to
                // build this, and not one of them matters until the window is
                // up. See the note there.
                model: dayWindow.visible ? root.agenda : []

                delegate: Item {
                  id: group
                  required property var modelData
                  required property int index

                  readonly property bool newMonth: group.index === 0
                    || Dates.monthOfDay(group.modelData.iso)
                       !== Dates.monthOfDay(root.agenda[group.index - 1].iso)
                  readonly property bool isToday: group.modelData.iso === root.today

                  width: agendaCol.width
                  height: rows.height + 20 + (group.newMonth ? monthMark.height + 10 : 0)

                  // A month's name, once, where the month turns. A year of
                  // days otherwise reads as one long list with no landmarks
                  // in it.
                  Chrome.TypedText {
                    id: monthMark
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    visible: group.newMonth
                    role: "overline"
                    text: Dates.MONTHS[Dates.monthOf(Dates.monthOfDay(group.modelData.iso)) - 1].toUpperCase()
                    color: root.dim
                    bodySize: root.bodySize
                  }

                  Column {
                    id: rail
                    anchors.top: group.newMonth ? monthMark.bottom : parent.top
                    anchors.topMargin: group.newMonth ? 10 : 8
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    width: 46
                    spacing: -2

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: Dates.DAYS_SHORT[Dates.weekday(group.modelData.iso)]
                      color: group.isToday ? root.accent : root.dim
                      font.family: Metrics.FONT
                      font.pixelSize: Metrics.typeSize(root.bodySize, "caption")
                      font.weight: Font.DemiBold
                    }

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: Dates.parts(group.modelData.iso).d
                      color: group.isToday ? root.accent : root.ink
                      font.family: Metrics.FONT
                      font.pixelSize: Metrics.typeSize(root.bodySize, "title")
                      font.weight: group.isToday ? Font.DemiBold : Font.Normal
                    }
                  }

                  Column {
                    id: rows
                    anchors.top: rail.top
                    anchors.left: rail.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    spacing: 6

                    Repeater {
                      model: group.modelData.items

                      delegate: EventRow {
                        required property var modelData

                        width: rows.width
                        entry: modelData
                        colours: root.colours
                        bodySize: root.bodySize
                        onClicked: {
                          root.selected = group.modelData.iso
                          root.startEdit(modelData)
                        }
                      }
                    }
                  }
                }
              }

              Column {
                width: agendaCol.width - 48
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                topPadding: 40
                visible: root.agenda.length === 0

                Chrome.TypedText {
                  width: parent.width
                  role: "subtitle"
                  text: "Nothing ahead"
                  color: root.ink
                  bodySize: root.bodySize
                  horizontalAlignment: Text.AlignHCenter
                }

                Chrome.TypedText {
                  width: parent.width
                  role: "caption"
                  text: root.events.length
                        ? "Nothing in the next year, anyway."
                        : "The plus puts something in the day."
                  color: root.dim
                  bodySize: root.bodySize
                  horizontalAlignment: Text.AlignHCenter
                }
              }
            }
          }

          // ========== the editor ==========

          Flickable {
            anchors.fill: parent
            visible: root.page === "editor"
            clip: true
            contentWidth: width
            contentHeight: form.height + 24
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: form
              width: parent.width
              spacing: 12
              topPadding: 10
              leftPadding: 16
              rightPadding: 16

              Chrome.TextField {
                id: titleField
                width: form.width - 32
                placeholderText: "What is it?"
                foreground: root.ink
                accent: root.accent
                iconColor: root.dim
                placeholderColor: root.dim
                bodySize: root.bodySize
                color: root.surface(0.09)
                onTextChanged: root.change("title", text)
                onAccepted: whereField.focusInput()
              }

              Chrome.TextField {
                id: whereField
                width: form.width - 32
                placeholderText: "Where"
                leadingNames: ["mark-location-symbolic", "view-pin-symbolic"]
                foreground: root.ink
                accent: root.accent
                iconColor: root.dim
                placeholderColor: root.dim
                bodySize: root.bodySize
                color: root.surface(0.09)
                onTextChanged: root.change("where", text)
              }

              // --- when ---

              Chrome.TypedText {
                role: "overline"
                text: "WHEN"
                color: root.dim
                bodySize: root.bodySize
                topPadding: 6
              }

              // The date, and the same grid as the first screen behind it.
              Rectangle {
                id: dateRow
                width: form.width - 32
                height: Metrics.TARGET + 6
                radius: Metrics.CARD_RADIUS
                color: root.pickingDate ? Theme.alpha(root.accent, 0.14) : root.surface(0.09)
                Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }

                Chrome.Icon {
                  id: dateGlyph
                  anchors.left: parent.left
                  anchors.leftMargin: 6
                  anchors.verticalCenter: parent.verticalCenter
                  slot: 32
                  size: 16
                  color: root.pickingDate ? root.accent : root.dim
                  names: ["x-office-calendar-symbolic", "appointment-new-symbolic"]
                }

                Chrome.TypedText {
                  anchors.left: dateGlyph.right
                  anchors.leftMargin: 4
                  anchors.right: dateChevron.left
                  anchors.verticalCenter: parent.verticalCenter
                  role: "body"
                  text: root.draft ? Dates.fullDayLabel(root.draft.date) : ""
                  color: root.ink
                  bodySize: root.bodySize
                  elide: Text.ElideRight
                }

                Chrome.Icon {
                  id: dateChevron
                  anchors.right: parent.right
                  anchors.rightMargin: 4
                  anchors.verticalCenter: parent.verticalCenter
                  slot: 28
                  size: 14
                  color: root.dim
                  names: root.pickingDate ? ["pan-up-symbolic", "pan-down-symbolic"] : ["pan-down-symbolic"]
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    if (root.draft) root.editorMonth = Dates.monthOfDay(root.draft.date)
                    root.pickingDate = !root.pickingDate
                  }
                }
              }

              Rectangle {
                width: form.width - 32
                height: root.pickingDate ? pickerCol.height + 12 : 0
                clip: true
                radius: Metrics.CARD_RADIUS
                color: root.surface(0.06)
                visible: height > 0
                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                Column {
                  id: pickerCol
                  width: parent.width
                  spacing: 2
                  topPadding: 6

                  Item {
                    width: parent.width
                    height: Metrics.TARGET

                    Chrome.IconButton {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      names: ["pan-start-symbolic", "go-previous-symbolic"]
                      color: root.ink
                      tooltip: "The month before"
                      onClicked: root.editorMonth -= 1
                    }

                    Chrome.TypedText {
                      anchors.centerIn: parent
                      role: "body"
                      text: Dates.monthLabel(Dates.yearOf(root.editorMonth), Dates.monthOf(root.editorMonth))
                      color: root.ink
                      bodySize: root.bodySize
                    }

                    Chrome.IconButton {
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      names: ["pan-end-symbolic"]
                      color: root.ink
                      tooltip: "The month after"
                      onClicked: root.editorMonth += 1
                    }
                  }

                  Month {
                    width: pickerCol.width
                    height: 20 + Dates.ROWS * Math.round(root.bodySize * 2.3)
                    compact: true
                    year: Dates.yearOf(root.editorMonth)
                    month: Dates.monthOf(root.editorMonth)
                    weekStart: root.weekStart
                    today: root.today
                    selected: root.draft ? root.draft.date : ""
                    colours: root.colours
                    accentInk: root.accentInk
                    bodySize: root.bodySize
                    onPicked: function (iso) { root.setDate(iso) }
                  }
                }
              }

              Chrome.Check {
                text: "All day"
                checked: root.draft ? root.draft.allDay : false
                foreground: root.ink
                tickColor: root.accentInk
                accent: root.accent
                dim: root.dim
                bodySize: root.bodySize
                onToggled: function (on) { root.change("allDay", on) }
              }

              Row {
                width: form.width - 32
                spacing: 10
                visible: !!root.draft && !root.draft.allDay

                Chrome.TextField {
                  id: startField
                  width: (parent.width - 10) / 2
                  placeholderText: "Start"
                  leadingNames: ["alarm-symbolic"]
                  foreground: root.ink
                  accent: root.accent
                  iconColor: root.dim
                  placeholderColor: root.dim
                  bodySize: root.bodySize
                  color: root.surface(0.09)
                  onAccepted: root.commitStart()
                }

                Chrome.TextField {
                  id: endField
                  width: (parent.width - 10) / 2
                  placeholderText: "End"
                  foreground: root.ink
                  accent: root.accent
                  iconColor: root.dim
                  placeholderColor: root.dim
                  bodySize: root.bodySize
                  color: root.surface(0.09)
                  onAccepted: root.commitEnd()
                }
              }

              // How long it is, worked out rather than asked for. It is also
              // the only sign that "930" was understood as half past nine.
              Chrome.TypedText {
                width: form.width - 32
                visible: !!root.draft && !root.draft.allDay && text.length > 0
                role: "caption"
                text: root.draft ? Dates.formatLength(root.draft.end - root.draft.start) : ""
                color: root.dim
                bodySize: root.bodySize
              }

              // --- how often ---

              Chrome.TypedText {
                role: "overline"
                text: "REPEATS"
                color: root.dim
                bodySize: root.bodySize
                topPadding: 6
              }

              Flow {
                width: form.width - 32
                spacing: 8

                Repeater {
                  model: Events.REPEATS

                  delegate: Rectangle {
                    id: chip
                    required property var modelData

                    readonly property bool on: !!root.draft && root.draft.repeat === chip.modelData.key

                    width: chipLabel.implicitWidth + 26
                    height: 36
                    radius: 18
                    color: chip.on ? Theme.alpha(root.accent, 0.18) : root.surface(0.08)
                    border.width: chip.on ? 1 : 0
                    border.color: root.accent
                    Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }

                    Text {
                      id: chipLabel
                      anchors.centerIn: parent
                      text: chip.modelData.label
                      color: chip.on ? root.accent : root.ink
                      font.family: Metrics.FONT
                      font.pixelSize: Metrics.typeSize(root.bodySize, "caption")
                      font.weight: chip.on ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.change("repeat", chip.modelData.key)
                    }
                  }
                }
              }

              Chrome.TypedText {
                width: form.width - 32
                visible: text.length > 0
                role: "caption"
                text: root.draft ? Events.describeRepeat(root.draft) : ""
                color: root.dim
                bodySize: root.bodySize
              }

              // --- what colour ---

              Chrome.TypedText {
                role: "overline"
                text: "COLOUR"
                color: root.dim
                bodySize: root.bodySize
                topPadding: 6
              }

              Row {
                width: form.width - 32
                spacing: (form.width - 32 - Events.COLOURS.length * 30) / (Events.COLOURS.length - 1)

                Repeater {
                  model: Events.COLOURS

                  delegate: Rectangle {
                    id: swatch
                    required property string modelData

                    readonly property bool on: !!root.draft && root.draft.colour === swatch.modelData

                    width: 30
                    height: 30
                    radius: 15
                    color: root.hue(swatch.modelData)
                    border.width: swatch.on ? 3 : 0
                    border.color: root.background

                    // The ring is drawn outside the swatch rather than on it,
                    // so that a chosen colour is still the whole colour.
                    Rectangle {
                      anchors.centerIn: parent
                      width: parent.width + 8
                      height: parent.height + 8
                      radius: width / 2
                      color: "transparent"
                      border.width: swatch.on ? 2 : 0
                      border.color: root.ink
                      z: -1
                    }

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: swatch.modelData
                    Accessible.checked: swatch.on

                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.change("colour", swatch.modelData)
                    }
                  }
                }
              }

              Item { width: 1; height: 8 + root.shellFurniture }
            }
          }
        }

        // --- the two screens, along the bottom ---------------------------------

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: root.page === "editor" ? 0 : 1
          visible: root.page !== "editor"
          color: root.line
        }

        Chrome.BottomNav {
          id: bottomNav
          Layout.fillWidth: true
          Layout.preferredHeight: root.page === "editor" ? 0 : Metrics.BOTTOM_NAV
          visible: root.page !== "editor"
          color: root.background
          dim: root.dim
          accent: root.accent
          bodySize: root.bodySize
          currentIndex: root.page === "agenda" ? 1 : 0
          onActivated: function (i) { root.page = i === 1 ? "agenda" : "month" }

          Chrome.BottomNavItem {
            text: "Month"
            names: ["x-office-calendar-symbolic", "view-grid-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }

          Chrome.BottomNavItem {
            text: "Agenda"
            names: ["view-list-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
        }

        // The shell keeps the bottom of the screen for the gesture bar and
        // moarchy-keyboard's toggle, both of which are layer surfaces that
        // draw over an app and take the taps that land on them. The tab bar
        // cannot be under them: the calculator measured the strip at 60px and
        // reserved it, and a switcher nobody can press is worse than a key.
        //
        // Only inside the shell, where `shell` is not null. On a laptop there
        // is no furniture down there and a reserved strip would be a bug.
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: root.page === "editor" ? 0 : root.shellFurniture
        }
      }

      Chrome.Fab {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 16 + Metrics.BOTTOM_NAV + root.shellFurniture
        visible: root.page !== "editor"
        accent: root.accent
        foreground: root.accentInk
        names: ["appointment-new-symbolic", "list-add-symbolic"]
        tooltip: "A new event"
        onClicked: root.startNew()
      }

      Chrome.Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12 + (root.page === "editor" ? 0 : Metrics.BOTTOM_NAV)
                              + root.shellFurniture
        colours: root.colours
        bodySize: root.bodySize
      }
    }
  }
}
