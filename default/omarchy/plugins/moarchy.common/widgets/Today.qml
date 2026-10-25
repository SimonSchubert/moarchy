// The date, the weather now and the next three days (docs/home.md HM14).
//
// Omalauncher's `today` tile: the day of the month large with the weekday and
// month beside it, then the sky now, then three days. A home tile, so the host
// hands it both its width and its height (HM9) and draws the frame round it
// (HM10); this draws no card of its own and lays itself out to whatever
// rectangle it is given, dropping the days and then the weather before it
// would overflow.
//
// The weather half is a view of the Weather app's own cache, never a fetch
// (HM14, W49's rule for the calendar). It reads the two files that app writes,
// `places.json` (which place is on screen, which units) and `forecast.json`
// (the last answer), through that plugin's `Store.js` and `Forecast.js` -- so
// which place is "current", how stale a reading may be and what a WMO code is
// called are decided in one place, and this tile shows what the app would.
// A forecast with no app behind it to refresh it would be a number that slowly
// stops being true. If the Weather plugin is not installed this widget fails
// to load and the host shows its frame with the error (HM13); the date with no
// weather beside it is a smaller loss than a second weather client.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui
import ".." as Shared
import "../../moarchy.weather/Store.js" as WeatherStore
import "../../moarchy.weather/Forecast.js" as Forecast

Item {
  id: widget

  property var host: null
  property var shell: null
  property bool preview: false

  // W6. Always: there is always a date, and a tile that vanished whenever the
  // cache was empty would move the user's grid about (HM12 keeps the gap, but
  // an empty frame says less than a date does).
  readonly property bool available: true

  implicitHeight: Style.space(230)

  // The app's directory, worked out the way the app works it out. Weather.qml
  // calls `Plugin.dataDir("weather", HOME, XDG_DATA_HOME, MOARCHY_WEATHER_DIR)`
  // from its vendored `ui/` kit, which the PKGBUILD copies in at build time and
  // which is therefore not beside this file to import. So the rule is written
  // out once more, as Calendar.qml writes its own, override included: the
  // screenshot harness points the app somewhere else, and a tile reading a
  // different directory from the app it is a view of would disagree with it.
  readonly property string dataDir: {
    var override = Quickshell.env("MOARCHY_WEATHER_DIR")
    if (override && override.length) return override
    var xdg = Quickshell.env("XDG_DATA_HOME")
    var base = (xdg && xdg.length) ? xdg : (Quickshell.env("HOME") + "/.local/share")
    return base + "/moarchy-weather"
  }

  // --- the clock ----------------------------------------------------------

  // Re-read once a minute and assigned only when it moves, which is
  // Calendar.qml's arrangement: the date changes at midnight and the reading
  // on the hour, so every binding below re-evaluates 25 times a day and the
  // timer costs one comparison the rest of the time. A per-second clock would
  // repaint a tile that shows no seconds. A phone woken from suspend catches
  // up within the minute.
  property real hourStart: widget.hourOf(Date.now())
  property string dayKey: widget.dayOf(new Date())

  function hourOf(ms) { return Math.floor(ms / 3600000) * 3600 }
  function dayOf(d) { return d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate() }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      var ms = Date.now()
      var hour = widget.hourOf(ms)
      if (hour !== widget.hourStart) widget.hourStart = hour
      var day = widget.dayOf(new Date(ms))
      if (day !== widget.dayKey) widget.dayKey = day
    }
  }

  // Read off `dayKey` so the three strings below change at midnight with it.
  readonly property var today: { widget.dayKey; return new Date() }
  readonly property string dayNumber: String(widget.today.getDate())
  readonly property string weekday: Qt.formatDate(widget.today, "dddd").toLowerCase()
  readonly property string monthYear: Qt.formatDate(widget.today, "MMMM yyyy").toLowerCase()

  // --- the app's two files ------------------------------------------------

  property var placesState: WeatherStore.parsePlaces(null)
  property var cache: ({})
  property var here: null

  FileView {
    id: placesFile
    // No path in a preview: W26, a preview runs nothing and reads nothing.
    path: widget.preview ? "" : widget.dataDir + "/places.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        widget.placesState = WeatherStore.parsePlaces(JSON.parse(placesFile.text()))
      } catch (e) {
        widget.placesState = WeatherStore.parsePlaces(null)
      }
    }
    onLoadFailed: widget.placesState = WeatherStore.parsePlaces(null)
    onFileChanged: Qt.callLater(function () { placesFile.reload() })
  }

  FileView {
    id: cacheFile
    path: widget.preview ? "" : widget.dataDir + "/forecast.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var data = JSON.parse(cacheFile.text())
        widget.cache = WeatherStore.parseCache(data)
        widget.here = WeatherStore.parseHere(data)
      } catch (e) {
        widget.cache = {}
        widget.here = null
      }
    }
    onLoadFailed: { widget.cache = {}; widget.here = null }
    onFileChanged: Qt.callLater(function () { cacheFile.reload() })
  }

  // The place the app has on screen, resolved by the app's rule: `here` is
  // whatever the last lookup found, and is keyed by its coordinates.
  readonly property var place: {
    var s = widget.placesState
    if (s.current === WeatherStore.HERE) return s.locate ? widget.here : null
    return WeatherStore.find(s.places, s.current)
  }
  readonly property var forecast: {
    if (!widget.place) return null
    var entry = widget.cache[widget.place.id]
    return entry ? entry.forecast : null
  }
  readonly property string units: widget.placesState.units

  // Only a reading that is about this hour. `readingAt` falls back to the last
  // `current` it has when the series has run out, which the app can show under
  // an "Updated 3 days ago" header and a tile with no header cannot: a stale
  // 14° here would read as today's.
  readonly property var reading: {
    var r = Forecast.readingAt(widget.forecast, widget.hourStart)
    if (!r || Math.abs(r.time - widget.hourStart) >= 2 * 3600) return null
    return r
  }
  readonly property var todayRow: widget.reading
    ? Forecast.today(widget.forecast, widget.hourStart) : null

  // The days after today. `Forecast.days` already drops the ones before it.
  readonly property var nextDays: {
    if (!widget.reading) return []
    var all = Forecast.days(widget.forecast, widget.hourStart)
    var offset = widget.forecast.offset || 0
    var out = []
    for (var i = 0; i < all.length && out.length < 3; i++) {
      if (Forecast.sameDay(all[i].time, widget.hourStart, offset)) continue
      out.push(all[i])
    }
    return out
  }

  // Forecast.glyph() names a picture for the app's own Sky.qml; this is the
  // same twelve pictures as Nerd Font Material glyphs. Every codepoint read
  // out of glyphnames.json by name and checked against JetBrainsMono Nerd
  // Font's cmap -- not copied from a neighbour (control-center.md S29).
  readonly property var glyphs: ({
    "clear":              "󰖙",  // md-weather_sunny
    "clear-night":        "󰖔",  // md-weather_night
    "mostly-clear":       "󰖕",  // md-weather_partly_cloudy
    "mostly-clear-night": "󰼱",  // md-weather_night_partly_cloudy
    "partly":             "󰖕",  // md-weather_partly_cloudy
    "partly-night":       "󰼱",  // md-weather_night_partly_cloudy
    "cloud":              "󰖐",  // md-weather_cloudy
    "fog":                "󰖑",  // md-weather_fog
    "drizzle":            "󰖗",  // md-weather_rainy
    "rain":               "󰖖",  // md-weather_pouring
    "showers":            "󰼳",  // md-weather_partly_rainy
    "sleet":              "󰙿",  // md-weather_snowy_rainy
    "snow":               "󰖘",  // md-weather_snowy
    "storm":              "󰙾"   // md-weather_lightning_rainy
  })
  function glyphFor(code, day) {
    return widget.glyphs[Forecast.glyph(code, day)] || widget.glyphs["cloud"]
  }

  // W26. Canned, and shaped like the real thing so the card in Settings is
  // the size it will be on home.
  readonly property bool hasWeather: widget.preview || widget.reading !== null
  readonly property string nowGlyph: widget.preview ? widget.glyphs["clear"]
    : (widget.reading ? widget.glyphFor(widget.reading.code, widget.reading.day) : "")
  readonly property string nowTemp: widget.preview ? "14°"
    : (widget.reading ? Forecast.temperature(widget.reading.temp, widget.units) : "")
  readonly property string nowWord: widget.preview ? "clear sky"
    : (widget.reading ? Forecast.describe(widget.reading.code).toLowerCase() : "")
  readonly property string nowRange: widget.preview ? "↑16° ↓7°"
    : (widget.todayRow ? "↑" + Forecast.temperature(widget.todayRow.high, widget.units)
                         + " ↓" + Forecast.temperature(widget.todayRow.low, widget.units) : "")
  readonly property var dayRows: {
    if (widget.preview) return [
      { name: "mon", glyph: widget.glyphs["cloud"], range: "16° 5°" },
      { name: "tue", glyph: widget.glyphs["drizzle"], range: "10° 9°" },
      { name: "wed", glyph: widget.glyphs["partly"], range: "12° 6°" }
    ]
    var offset = widget.forecast ? (widget.forecast.offset || 0) : 0
    var out = []
    for (var i = 0; i < widget.nextDays.length; i++) {
      var d = widget.nextDays[i]
      out.push({
        // No `now` handed in, so it never says "Today": these are all later.
        name: Forecast.dayLabel(d.time, offset).toLowerCase(),
        glyph: widget.glyphFor(d.code, true),
        range: Forecast.temperature(d.high, widget.units) + " "
               + Forecast.temperature(d.low, widget.units)
      })
    }
    return out
  }

  // --- drawing ------------------------------------------------------------

  // Over everything and under the content (docs/style.md H8). On home the frame
  // is the host's, so the veil is the only fill this tile ever paints.
  Shared.PressVeil {
    anchors.fill: parent
    radius: widget.host ? widget.host.radiusCard : 0
    ink: widget.host.textOnSurface
    on: tileArea.pressed && !widget.host.sheetDragging
  }

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: Style.space(10)

    // What fits, decided from the parts' implicit heights and never from a
    // child's `visible`, which is inherited and reads false while home is down
    // (qml-visible-is-inherited). The days go first, then the weather: the date
    // is the one thing a 3x2 tile still has room for.
    readonly property int gap: Style.space(8)
    readonly property real dateNeed: dateRow.implicitHeight
    readonly property real nowNeed: content.gap * 2 + 1 + nowBlock.implicitHeight
    readonly property real daysNeed: content.gap * 2 + 1 + daysRow.implicitHeight
    readonly property bool showNow: widget.hasWeather
                                    && content.height >= content.dateNeed + content.nowNeed
    readonly property bool showDays: content.showNow && widget.dayRows.length > 0
      && content.height >= content.dateNeed + content.nowNeed + content.daysNeed

    // The date, top left: the number as large as the tile, the rest beside it.
    Row {
      id: dateRow
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(10)

      Text {
        id: dayNumberText
        text: widget.dayNumber
        font.family: Style.font.family
        font.pixelSize: Style.font.display * 2
        font.weight: widget.host.textWeight
        color: widget.host.textOnSurface
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: dateRow.width - dayNumberText.width - dateRow.spacing
        Text {
          width: parent.width
          text: widget.weekday
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.weight: widget.host.textWeight
          color: widget.host.accent
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: widget.monthYear
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: widget.host.textWeight
          color: widget.host.subdued
          elide: Text.ElideRight
        }
      }
    }

    // The weather now, centred in whatever the date and the days leave.
    Rectangle {
      id: ruleNow
      visible: content.showNow
      anchors.top: dateRow.bottom
      anchors.topMargin: content.gap
      width: parent.width
      height: 1
      color: widget.host.subdued
      opacity: 0.35
    }

    Row {
      id: nowBlock
      visible: content.showNow
      anchors.left: parent.left
      anchors.right: parent.right
      // Halfway between the rule above it and the rule below (or the bottom).
      y: {
        var top = ruleNow.y + 1 + content.gap
        var bottom = content.showDays ? ruleDays.y - content.gap : content.height
        return top + Math.max(0, (bottom - top - nowBlock.height) / 2)
      }
      spacing: Style.space(6)

      Text {
        id: nowGlyphText
        anchors.verticalCenter: parent.verticalCenter
        text: widget.nowGlyph
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        color: widget.host.textOnSurface
      }
      Text {
        id: nowTempText
        anchors.verticalCenter: parent.verticalCenter
        text: widget.nowTemp
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        font.weight: widget.host.textWeight
        color: widget.host.accent
      }
      // Right-aligned against the tile's edge, as Omalauncher's is.
      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, nowBlock.width - nowGlyphText.width - nowTempText.width
                           - nowBlock.spacing * 2)
        Text {
          width: parent.width
          text: widget.nowWord
          horizontalAlignment: Text.AlignRight
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: widget.host.textWeight
          color: widget.host.textOnSurface
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: widget.nowRange
          horizontalAlignment: Text.AlignRight
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: widget.host.textWeight
          color: widget.host.subdued
          elide: Text.ElideRight
        }
      }
    }

    // The next three days, along the bottom.
    Rectangle {
      id: ruleDays
      visible: content.showDays
      anchors.bottom: daysRow.top
      anchors.bottomMargin: content.gap
      width: parent.width
      height: 1
      color: widget.host.subdued
      opacity: 0.35
    }

    Row {
      id: daysRow
      visible: content.showDays
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom

      Repeater {
        model: widget.dayRows
        delegate: Column {
          required property var modelData
          width: daysRow.width / Math.max(1, widget.dayRows.length)

          Text {
            width: parent.width
            text: modelData.name
            horizontalAlignment: Text.AlignHCenter
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: widget.host.textWeight
            color: widget.host.subdued
            elide: Text.ElideRight
          }
          Ui.OpticalGlyph {
            anchors.horizontalCenter: parent.horizontalCenter
            width: widget.host.glyphSlot
            height: widget.host.glyphSlot
            text: modelData.glyph
            fontFamily: Style.font.family
            fontSize: Style.font.iconLarge
            color: widget.host.textOnSurface
          }
          // A cold week is "-12° -20°", which is wider than a 3-cell column
          // has: it shrinks to fit before it elides.
          Text {
            width: parent.width
            text: modelData.range
            horizontalAlignment: Text.AlignHCenter
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: widget.host.textWeight
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Math.round(Style.font.caption * 0.8)
            color: widget.host.textOnSurface
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // The whole tile opens the Weather app: the next three days are the
  // question a glance raises. Through the host (W5), so home can close what it
  // must on the way. A drag that starts here still turns home's page (HM14b).
  Shared.SheetDragArea {
    id: tileArea
    sheet: widget.host.sheet
    anchors.fill: parent
    onClicked: if (!widget.preview && !widget.host.sheetWasDrag)
      widget.host.openScreen("moarchy.weather")
  }
}
