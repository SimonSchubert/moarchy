// The start page (docs/home.md HM7, HM8).
//
// Omalauncher's `00-start` in this phone's terms: the time large, the date and
// the weather now, the next calendar event, and the battery. A face is the
// whole page between the status bar and the strip and draws on the wallpaper
// with no background of its own (HM7); the information sits in boxes wearing
// home's frame (HM10) so it stays readable on any wallpaper.
//
// The date, the weather and the next event are the `today` and `calendar`
// widgets, not a second copy of either: whatever those tiles decide about a
// stale forecast or an all-day event, this page says the same.
//
// It is loaded by URL rather than imported, and that is HM7's doing. This file
// is meant to be copied to `~/.config/omarchy/faces/` and edited, and a copy
// there that said `import "../../moarchy.common/widgets"` would resolve to a
// directory that does not exist and fail to load whole. So nothing in it is
// relative to where it sits: the widgets and the frame come from
// `host.widgetUrl(id)` and `host.frameUrl`. Module imports (qs.Commons,
// Quickshell) are the shell's and resolve from anywhere.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons

Item {
  id: face

  // Home sets both, the way the shell injects into a plugin (HM7).
  property var host: null
  property var shell: null

  // Omalauncher's faces doc: wider than tall is a phone on its side or an
  // unfolded one, and gets two columns.
  readonly property bool wide: face.width > face.height
  readonly property int gap: Style.space(6)

  // --- where the widgets are ---------------------------------------------

  // Asked of the host, never worked out from where this file is: a copy in
  // ~/.config/omarchy/faces/ has no package beside it, and home knows where the
  // package it was loaded from is -- the installed one or a plugin override.
  readonly property string frameUrl: face.host ? face.host.frameUrl : ""

  // A widget is handed the host and the shell as it is built, not bound after:
  // every widget reads `host.textOnSurface` and friends in its first bindings,
  // and a Loader that set them in onLoaded would log a TypeError per binding
  // first. The same reason WidgetColumn uses setSource().
  function fill(slot, id) {
    if (!face.host) return
    slot.setSource(face.host.widgetUrl(id), { host: face.host, shell: face.shell })
  }
  function fillAll() {
    face.fill(todaySlot, "today")
    face.fill(calendarSlot, "calendar")
  }
  Component.onCompleted: face.fillAll()
  onHostChanged: face.fillAll()
  onShellChanged: {
    if (todaySlot.item) todaySlot.item.shell = face.shell
    if (calendarSlot.item) calendarSlot.item.shell = face.shell
  }

  // --- the time ----------------------------------------------------------

  // Woken on the minute, not every second: the face shows no seconds. Re-armed
  // to the next boundary each time, so a minute that drifted (or a phone that
  // slept through ten of them) is right again at the first tick.
  property date now: new Date()
  Timer {
    id: tick
    interval: 60000 - (Date.now() % 60000) + 50
    running: true
    repeat: false
    onTriggered: {
      face.now = new Date()
      tick.interval = 60000 - (Date.now() % 60000) + 50
      tick.restart()
    }
  }

  // Twelve or twenty-four hours: the Clock app's choice when somebody has made
  // one, and the locale's until then -- the same rule Clock.qml resolves, read
  // from the same file, so the face and the app never show two formats. Read
  // directly rather than through moarchy.clock/Store.js for HM7's reason
  // above: it is one boolean, and the import would tie a copied face to the
  // package's layout.
  property var clockChoice: null
  readonly property bool hour24: typeof face.clockChoice === "boolean"
    ? face.clockChoice
    : String(Qt.locale().timeFormat(Locale.ShortFormat)).toLowerCase().indexOf("a") < 0

  FileView {
    id: clockFile
    path: {
      var override = Quickshell.env("MOARCHY_CLOCK_DIR")
      if (override && override.length) return override + "/clock.json"
      var xdg = Quickshell.env("XDG_DATA_HOME")
      var base = (xdg && xdg.length) ? xdg : (Quickshell.env("HOME") + "/.local/share")
      return base + "/moarchy-clock/clock.json"
    }
    watchChanges: true
    printErrors: false
    onLoaded: {
      var settings = null
      try {
        settings = JSON.parse(clockFile.text()).settings
      } catch (e) {
        settings = null
      }
      face.clockChoice = settings && typeof settings.hour24 === "boolean" ? settings.hour24 : null
    }
    onLoadFailed: face.clockChoice = null
    onFileChanged: Qt.callLater(function () { clockFile.reload() })
  }

  readonly property string hours: face.hour24
    ? Qt.formatTime(face.now, "HH")
    : String(face.now.getHours() % 12 || 12)
  readonly property string minutes: Qt.formatTime(face.now, "mm")
  readonly property string meridiem: face.hour24 ? "" : (face.now.getHours() < 12 ? "am" : "pm")
  readonly property string greeting: {
    var h = face.now.getHours()
    if (h < 5) return "good night"
    if (h < 12) return "good morning"
    if (h < 18) return "good afternoon"
    return "good evening"
  }

  // --- the battery -------------------------------------------------------

  // UPower's aggregate, the one the bar reads (moarchy.bar), so the two never
  // disagree by a percent.
  readonly property var battery: UPower.displayDevice
  readonly property bool batteryPresent: !!face.battery && face.battery.isPresent
  readonly property string batteryText: {
    if (!face.batteryPresent) return ""
    var pct = Math.round(Number(face.battery.percentage || 0) * 100) + "%"
    if (face.battery.state === UPowerDeviceState.FullyCharged) return pct + " · full"
    return pct + (UPower.onBattery ? " · on battery" : " · charging")
  }

  // --- drawing -----------------------------------------------------------

  // Home's frame is HomeFrame.qml, loaded from beside the kit the same way the
  // widgets are, not drawn again here: one component decides what a frame is
  // (HM10, HM10a), and HM10's check holds moarchy.home/ to the single border
  // width that file sets. Contents declared inside a Box are drawn
  // over the frame, inset by its `inset` so a square corner clears a round one.
  component Box: Item {
    id: box
    property var host: null
    property string frameUrl: ""
    readonly property int inset: frame.item ? frame.item.inset : 0
    function load() {
      if (!box.host || !box.frameUrl.length) return
      if (frame.item && String(frame.source) === box.frameUrl) {
        frame.item.host = box.host
        return
      }
      frame.setSource(box.frameUrl, { host: box.host })
    }
    onHostChanged: box.load()
    onFrameUrlChanged: box.load()
    Component.onCompleted: box.load()
    Loader { id: frame; anchors.fill: parent }
  }

  // Portrait: one column, top down. Wide: the time on the left, the rest on
  // the right, each column as tall as the page.
  Item {
    id: page
    anchors.fill: parent
    anchors.margins: Style.space(12)

    readonly property real columnWidth: face.wide ? (page.width - face.gap) / 2 : page.width

    Box {
      id: clockBox
      host: face.host
      frameUrl: face.frameUrl
      x: 0
      y: 0
      width: page.columnWidth
      height: face.wide ? page.height : clockColumn.implicitHeight + Style.space(16) * 2

      Column {
        id: clockColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: face.greeting
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.weight: face.host ? face.host.textWeight : Font.Normal
          color: face.host ? face.host.accent : "transparent"
          elide: Text.ElideRight
        }

        // The colon in the accent, as Omalauncher's start face has it. Fit to
        // the width, so a narrow column on its side shrinks the time rather
        // than cutting it.
        Row {
          spacing: Style.space(6)
          Text {
            id: timeText
            width: Math.min(implicitWidth, clockColumn.width - meridiemText.width - Style.space(6))
            textFormat: Text.StyledText
            text: face.hours + "<font color=\"" + (face.host ? face.host.accent : "") + "\">:</font>"
                  + face.minutes
            font.family: Style.font.family
            font.pixelSize: Style.font.display * 3
            font.weight: face.host ? face.host.textWeight : Font.Normal
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Style.font.display
            color: face.host ? face.host.textOnSurface : "transparent"
          }
          Text {
            id: meridiemText
            anchors.baseline: timeText.baseline
            text: face.meridiem
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: face.host ? face.host.textWeight : Font.Normal
            color: face.host ? face.host.subdued : "transparent"
          }
        }

        Text {
          width: parent.width
          visible: face.batteryPresent
          text: "battery " + face.batteryText
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: face.host ? face.host.textWeight : Font.Normal
          color: face.host ? face.host.subdued : "transparent"
          elide: Text.ElideRight
        }
      }
    }

    // The date and the weather: the `today` widget, at whatever the page has
    // room for. Capped, because a tile stretched to half a screen would put
    // three days of weather a thumb's length apart.
    Box {
      id: todayBox
      host: face.host
      frameUrl: face.frameUrl
      x: face.wide ? page.columnWidth + face.gap : 0
      y: face.wide ? 0 : clockBox.height + face.gap
      width: page.columnWidth
      height: {
        var room = face.wide
          ? page.height - (calendarBox.wanted ? calendarBox.height + face.gap : 0)
          : page.height - clockBox.height - face.gap
            - (calendarBox.wanted ? calendarBox.height + face.gap : 0)
        return Math.max(0, Math.min(room, Style.space(240)))
      }

      Loader {
        id: todaySlot
        anchors.fill: parent
        anchors.margins: todayBox.inset
      }
    }

    // The next event, only while there is one: the widget's own `available`
    // (W6), so an empty diary leaves no empty box.
    Box {
      id: calendarBox
      host: face.host
      frameUrl: face.frameUrl
      readonly property bool wanted: calendarSlot.status === Loader.Ready
                                     && !!calendarSlot.item && calendarSlot.item.available
      visible: calendarBox.wanted
      x: todayBox.x
      y: todayBox.y + todayBox.height + face.gap
      width: page.columnWidth
      height: calendarSlot.item ? calendarSlot.item.implicitHeight
                                  + calendarSlot.anchors.margins * 2 : 0

      Loader {
        id: calendarSlot
        anchors.fill: parent
        anchors.margins: calendarBox.inset
      }
    }
  }
}
