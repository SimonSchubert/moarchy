// The next upcoming event (docs/widgets.md §H).
//
// A view of the Calendar app's own file, not a second calendar. It reads
// `~/.local/share/moarchy-calendar/calendar.json` through that plugin's
// `Store.js` and `Events.js`, so a recurrence rule, an all-day event and the
// way a span is worded are decided in one place and this shows whatever the
// app would have shown.
//
// Importing across plugin directories is what couples this to `moarchy.calendar`
// (docs/refactor.md E1 settled that the import works). The alternative was a
// second parser for the same file, which is the duplication E7 exists to stop,
// and it would have drifted the first time a repeat rule was added. If the
// Calendar plugin is not installed this widget fails to load, the column logs
// its id and leaves the row empty (W12) -- which is the right outcome: a "next
// event" with no calendar behind it has nothing to say.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui
import ".." as Shared
import "../../moarchy.calendar/Store.js" as Store
import "../../moarchy.calendar/Events.js" as Events
import "../../moarchy.calendar/Dates.js" as Dates

Item {
  id: widget

  property var host: null
  property var shell: null
  property bool preview: false

  implicitHeight: Style.space(56)

  // W6. Nothing in the diary is nothing to draw. A card reading "No events" is
  // a row the user has to look at to learn there is nothing -- the absent row
  // says it without being read.
  readonly property bool available: widget.preview || widget.next !== null

  property var events: []

  readonly property string dataDir: {
    var xdg = Quickshell.env("XDG_DATA_HOME")
    var base = (xdg && xdg.length) ? xdg : (Quickshell.env("HOME") + "/.local/share")
    return base + "/moarchy-calendar"
  }

  // Ticks over the day boundary and no faster. The next event does not change
  // between minutes in any way this card shows -- it prints a span, never a
  // countdown -- so a per-minute timer would repaint the same two strings
  // 1,440 times a day on an A53.
  property string today: Dates.todayFrom(Date.now(),
                                        Quickshell.env("MOARCHY_CALENDAR_TODAY"))
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      var now = Dates.todayFrom(Date.now(),
                                Quickshell.env("MOARCHY_CALENDAR_TODAY"))
      if (now !== widget.today) widget.today = now
    }
  }

  FileView {
    id: file
    path: widget.dataDir + "/calendar.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        widget.events = Store.parse(JSON.parse(file.text())).events
      } catch (e) {
        widget.events = []
      }
    }
    onLoadFailed: widget.events = []
    onFileChanged: Qt.callLater(function () { file.reload() })
  }

  // The first thing on the first day that has anything, today included. Today
  // included and not "strictly later": an event at 09:00 is still the next
  // thing at 08:55, and a card that skipped to tomorrow at one minute past
  // would be wrong for the whole of the day it was about.
  readonly property var next: {
    if (widget.preview) return null
    var days = Events.agenda(widget.events, widget.today, Events.HORIZON, 1)
    if (!days.length || !days[0].items.length) return null
    return { iso: days[0].iso, ev: days[0].items[0] }
  }

  readonly property string title:
    widget.preview ? "Standup"
    : (widget.next ? String(widget.next.ev.title || "Untitled") : "")

  // The day first when it is not today, then whatever the app says the time
  // is -- "All day", or the span, plus a place if there is one.
  readonly property string detail: {
    if (widget.preview) return "Today · 09:30 – 09:45"
    if (!widget.next) return ""
    var said = Events.line(widget.next.ev)
    if (widget.next.iso === widget.today) return said
    // "Tomorrow", "Friday" -- the app's own wording, so the card and the
    // agenda behind it never say the same day two ways.
    return Dates.headline(widget.next.iso, widget.today) + " · " + said
  }

  Rectangle {
    anchors.fill: parent
    radius: widget.host.radiusCard
    color: widget.host.container

    // Over the fill and under the content (docs/style.md H8).
    Shared.PressVeil {
      anchors.fill: parent
      radius: parent.radius
      ink: widget.host.textOnSurface
      on: cardArea.pressed && !widget.host.sheetDragging
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(14)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(12)

      // md-calendar_clock, read out of the font's cmap and not off a chart:
      // the Material range is JetBrainsMono Nerd Font's and is not where a
      // neighbouring comment would put it (control-center.md S29).
      Ui.OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        width: widget.host.glyphSlot
        height: widget.host.glyphSlot
        text: "󰃰"
        fontFamily: Style.font.family
        fontSize: Style.font.iconLarge
        color: widget.host.textOnSurface
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - widget.host.glyphSlot - Style.space(12)

        Text {
          width: parent.width
          text: widget.title
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.weight: widget.host.textWeight
          color: widget.host.textOnSurface
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: widget.detail
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: widget.host.textWeight
          color: widget.host.subdued
          elide: Text.ElideRight
        }
      }
    }

    // The whole card opens the Calendar, which is what a glance at "the next
    // thing" makes you want next. Through the host (W5), so the control center
    // closes on the way and a host that must not open an app can refuse.
    Shared.SheetDragArea {
      id: cardArea
      sheet: widget.host.sheet
      anchors.fill: parent
      onClicked: if (!widget.preview && !widget.host.sheetWasDrag)
        widget.host.openScreen("moarchy.calendar")
    }
  }
}
