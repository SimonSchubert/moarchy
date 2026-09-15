// Weather, in the shell: one place, one screen, seven days.
//
// The screen is a single column and it is in the order the question is asked.
// What is it doing now, at the top, in the biggest type on the phone. What is
// it doing for the rest of today, as a strip of hours under it. What is it
// doing this week, as seven rows with a bar each. Nothing is behind a tab,
// because a weather app is opened, read and closed -- often without the thumb
// ever arriving -- and a tab bar would spend a fourteenth of a phone's screen
// on a page nobody visits twice.
//
// The places live on their own page, reached by the place name in the title
// bar, which carries a chevron to say so. That is the whole of the navigation.
//
// Nothing here is a port: the GTK half of this repository has no weather app.
// It was written for the shell first, which means summoning it is a window
// becoming visible rather than a process starting -- and the last forecast is
// already in memory, so the answer is on screen before the radio is asked.

// Bound because every list on this screen is a Repeater whose delegate reads
// the palette, the units and the clock off `root`.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Forecast.js" as Forecast
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "org.moarchy.weather"
  readonly property bool opened: skyWindow.visible
  readonly property var appWindow: skyWindow

  property string returnTo: ""
  // `colours` and not `palette`: QQuickItem already has a `palette`, and
  // shadowing it makes a binding resolve to whichever the compiler picked.
  readonly property var colours: themeFile.colours
  readonly property int radiusCard: uiFile.radiusCard
  readonly property int radiusTile: uiFile.radiusTile
  property int bodySize: Metrics.BODY
  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    root.applyHarness()
  }

  // --- what is known ----------------------------------------------------

  property var places: []
  property string currentId: ""
  property string units: "metric"
  // placeId -> { fetched, forecast }. One entry per place, so switching towns
  // draws the last thing known about the new one rather than a blank screen.
  property var cache: ({})

  property double now: Date.now()
  property bool loaded: false
  property bool offline: false
  property string harnessUnits: ""
  // The clock, pinned. Zero everywhere except under the screenshot harness,
  // which pins it for the GTK apps' reason: a picture taken at nine in the
  // evening and one taken at noon disagree about the sky, for reasons that
  // have nothing to do with the app.
  property real pinnedNow: 0

  property bool showingPlaces: false
  property string query: ""
  property var results: []
  property bool finding: false
  property bool searched: false

  property bool fetching: false
  property string trouble: ""
  property int failures: 0
  property real retryAt: 0
  property bool dirty: false

  readonly property var backoff: [60, 150, 300, 600]

  readonly property real nowSec: root.now / 1000

  // The clock the forecast is read against, rounded down to the hour.
  //
  // `now` moves every half minute so that "4 min ago" in the header stays
  // true. Everything else on this screen -- which hours are in the strip,
  // which day is today, which reading is current -- changes on the hour, and
  // binding those to `now` would rebuild twenty-four delegates twice a minute
  // to draw exactly what was already there.
  readonly property real hourStart: Math.floor(root.nowSec / 3600) * 3600

  readonly property var place: Store.find(root.places, root.currentId)
  readonly property var entry: root.cache[root.currentId] || null
  readonly property var forecast: root.entry ? root.entry.forecast : null
  readonly property real fetched: root.entry ? root.entry.fetched : 0
  readonly property int zoneOffset: root.forecast ? root.forecast.offset : 0

  readonly property var reading: Forecast.readingAt(root.forecast, root.hourStart)
  readonly property var hours: Forecast.nextHours(root.forecast, root.hourStart, Forecast.STRIP_HOURS)
  readonly property var week: Forecast.days(root.forecast, root.hourStart)
  readonly property var todayRow: Forecast.today(root.forecast, root.hourStart)
  readonly property var range: Forecast.span(root.week)
  readonly property var tiles: Forecast.facts(root.reading, root.todayRow, root.zoneOffset, root.units)

  readonly property string dataDir: Plugin.dataDir(
    "weather", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_WEATHER_DIR"))

  // --- colour -----------------------------------------------------------

  readonly property color background: root.colours.background
  readonly property color ink: root.colours.foreground
  readonly property color dim: root.colours.dim
  readonly property color line: root.colours.line
  readonly property color accent: root.colours.accent

  function hueColor(name) {
    var hues = root.colours.hues || {}
    return hues[name] || root.colours.accent
  }

  function tempColour(celsius) {
    return root.hueColor(Forecast.band(celsius))
  }

  // The band behind the hero, mixed from the hue of the temperature it is
  // behind: a cold morning is a blue screen and a hot afternoon an orange one,
  // in whatever blue and orange the theme names. Weaker at night, because the
  // same wash that reads as daylight at 22% reads as a fault at midnight.
  // Not `readonly`, though nothing but the binding below ever writes it: a
  // Behavior is an interceptor on writes, and Quickshell refuses to attach one
  // to a read-only property -- with an error that names the property and not
  // the reason.
  property color wash: {
    if (!root.reading) return Theme.mix(root.colours.foreground, root.colours.background, 0.05)
    var hue = root.hueColor(Forecast.band(root.reading.temp))
    return Theme.mix(hue, root.colours.background, root.reading.day ? 0.22 : 0.13)
  }

  // Switching town, or the sun going down, moves this colour across the top of
  // the screen. A quarter of a second of it reads as the screen catching up; a
  // jump reads as a redraw.
  Behavior on wash { ColorAnimation { duration: 240 } }

  readonly property string card: Theme.mix(root.colours.foreground, root.colours.background, 0.06)
  readonly property string pressed: Theme.mix(root.colours.foreground, root.colours.background, 0.11)

  // --- what the header says ---------------------------------------------

  function freshnessText() {
    if (!root.places.length) return "Nowhere yet"
    if (root.fetching) return "Updating…"
    if (root.fetched <= 0) return root.trouble ? root.trouble : "No forecast yet"
    var age = Math.max(0, root.nowSec - root.fetched)
    if (root.failures) return "Not updating · " + Forecast.freshness(age)
    return "Updated " + Forecast.freshness(age)
  }

  function say(text) { toast.show(text) }

  // The current temperature at a place other than the one on screen, for the
  // places list. Whatever is in the cache, or nothing -- never a fetch: a list
  // of twelve towns that fetches twelve forecasts to draw itself is a data
  // bill for a screen somebody is passing through.
  function tempAt(id) {
    var entry = root.cache[id]
    if (!entry) return ""
    var reading = Forecast.readingAt(entry.forecast, root.hourStart)
    return reading ? Forecast.temperature(reading.temp, root.units) : ""
  }

  // The clock where that place is. A list of four towns on one screen is the
  // one place the hour is genuinely ambiguous -- every time in this app is the
  // forecast's own, and this is where that stops being a claim in a README.
  function clockAt(id) {
    var entry = root.cache[id]
    if (!entry) return ""
    return Forecast.clock(root.nowSec, entry.forecast.offset)
  }

  function glyphAt(id) {
    var entry = root.cache[id]
    if (!entry) return ""
    var reading = Forecast.readingAt(entry.forecast, root.hourStart)
    return reading ? Forecast.glyph(reading.code, reading.day) : ""
  }

  // --- the harness ------------------------------------------------------

  // The variables a screenshot run sets. _OFFLINE is the one that matters:
  // with it the window draws the forecast in the cache and never opens a
  // socket, which is why two pictures taken a minute apart agree.
  function clockNow() {
    return root.pinnedNow > 0 ? root.pinnedNow * 1000 : Date.now()
  }

  function applyHarness() {
    root.offline = (Quickshell.env("MOARCHY_WEATHER_OFFLINE") || "") !== ""
    var pinned = parseInt(Quickshell.env("MOARCHY_WEATHER_NOW") || "0", 10)
    root.pinnedNow = pinned > 0 ? pinned : 0
    root.now = root.clockNow()
    var units = Quickshell.env("MOARCHY_WEATHER_UNITS") || ""
    root.harnessUnits = units.length ? Store.units(units) : ""
    if ((Quickshell.env("MOARCHY_WEATHER_PAGE") || "") === "places") root.showingPlaces = true
    // The same variable apps/coins' shots.sh sets, and for the same reason:
    // the search is the one screen a harness cannot reach on its own. A
    // headless compositor has no pointer, so nothing can tap the field --
    // which is how this path went unphotographed until somebody tried.
    var search = Quickshell.env("MOARCHY_WEATHER_SEARCH") || ""
    if (search.length) {
      root.showingPlaces = true
      root.query = search
      Qt.callLater(root.runSearch)
    }
  }

  // --- the shell's plugin contract --------------------------------------

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
    } catch (e) {}
    skyWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  function close() {
    root.showingPlaces = false
  }

  function dismiss() {
    root.close()
    skyWindow.hide()
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
    placesFile.reload()
    cacheFile.reload()
    root.loaded = true
  }

  // --- the places -------------------------------------------------------

  // `placesState` and not `state`: QQuickItem already has a `state`, and a
  // function that shadows it makes the property-override warning real -- the
  // linter names it, and this is the one collision here that could quietly
  // resolve to the wrong thing.
  function placesState() {
    return { places: root.places, current: root.currentId, units: root.units }
  }

  function apply(next) {
    root.places = next.places
    root.currentId = next.current
    root.units = next.units
    placesFile.setText(Store.serializePlaces(next))
  }

  function addPlace(place) {
    var result = Store.add(root.placesState(), place)
    if (result.full) {
      root.say(Store.MAX_PLACES + " places is as many as this app keeps.")
      return
    }
    root.apply(result.state)
    root.query = ""
    root.results = []
    root.searched = false
    root.showingPlaces = false
    if (!result.added) root.say(place.name + " is already on the list.")
  }

  function removePlace(id) {
    root.apply(Store.remove(root.placesState(), id))
    // The entry stays in memory until the file is next written, which is when
    // it is dropped: serializeCache only writes the places that still exist.
    root.dirty = true
  }

  function selectPlace(id) {
    root.apply(Store.select(root.placesState(), id))
    root.showingPlaces = false
  }

  function setUnits(name) {
    root.apply(Store.withUnits(root.placesState(), name))
  }

  // --- the network ------------------------------------------------------

  function curl(url) {
    return ["curl", "-sS", "--max-time", String(Forecast.TIMEOUT),
            "-H", "User-Agent: " + Forecast.AGENT,
            "-H", "Accept: application/json",
            "-w", "\n%{http_code}", url]
  }

  // The status code curl was asked to write on the last line, and the body
  // without it.
  function split(payload) {
    var text = String(payload || "")
    var cut = text.lastIndexOf("\n")
    return {
      status: cut >= 0 ? parseInt(text.slice(cut + 1).trim(), 10) : 0,
      body: cut >= 0 ? text.slice(0, cut) : text
    }
  }

  function due() {
    if (root.offline || root.fetching || !root.place) return false
    if (root.retryAt && root.nowSec < root.retryAt) return false
    if (root.fetched <= 0) return true
    return (root.nowSec - root.fetched) >= Forecast.refreshAfter()
  }

  function maybeFetch() {
    if (root.due()) root.fetch(false)
  }

  function fetch(manual) {
    if (root.fetching) return
    if (!root.place) return
    if (root.offline) {
      if (manual) root.say("This run is offline.")
      return
    }
    root.fetching = true
    fetcher.manual = !!manual
    // Which place the answer belongs to, remembered at the moment of asking.
    // Somebody switching towns while a request is in flight would otherwise
    // file Reykjavik's weather under Cairo.
    fetcher.want = root.place.id
    fetcher.command = root.curl(Forecast.url(root.place.lat, root.place.lon))
    fetcher.running = true
  }

  function arrived(code, payload) {
    root.fetching = false
    var manual = fetcher.manual
    var want = fetcher.want

    if (code !== 0) {
      root.failed("No answer from Open-Meteo.", 0, manual)
      return
    }

    var answer = root.split(payload)
    if (answer.status === 429) {
      root.failed("Open-Meteo is rate-limiting this connection.", Forecast.RATE_LIMIT_S, manual)
      return
    }
    if (answer.status >= 500) {
      root.failed("Open-Meteo is having trouble.", 0, manual)
      return
    }
    if (answer.status !== 200) {
      root.failed("Open-Meteo refused the request (" + answer.status + ").", 0, manual)
      return
    }

    var parsed = Forecast.parseForecast(answer.body, root.nowSec)
    if (parsed.error) {
      root.failed(parsed.error, 0, manual)
      return
    }

    root.failures = 0
    root.retryAt = 0
    root.trouble = ""
    root.cache = Store.put(root.cache, want, parsed.forecast, root.clockNow() / 1000)
    root.dirty = true
  }

  function failed(message, retry, manual) {
    root.failures += 1
    var wait = retry || root.backoff[Math.min(root.failures - 1, root.backoff.length - 1)]
    root.retryAt = root.clockNow() / 1000 + wait
    root.trouble = message
    // A forecast from twenty minutes ago is worth something and a blank screen
    // is worth nothing, so whatever is on the screen stays on it.
    if (manual || !root.forecast) root.say(message)
  }

  function saveCache() {
    if (!root.dirty) return
    cacheFile.setText(Store.serializeCache(root.cache, root.places))
    root.dirty = false
  }

  // --- searching for a town ---------------------------------------------

  function runSearch() {
    var needle = root.query.trim()
    if (needle.length < 2) {
      root.results = []
      root.searched = false
      return
    }
    if (root.offline) {
      root.say("This run is offline.")
      return
    }
    // One request at a time: waiting another beat is cheaper than killing a
    // curl that is about to answer the question being retyped.
    if (root.finding) { debounce.restart(); return }
    root.finding = true
    finder.command = root.curl(Forecast.searchUrl(needle))
    finder.running = true
  }

  function found(code, payload) {
    root.finding = false
    root.searched = true
    if (code !== 0) {
      root.say("No answer from Open-Meteo.")
      return
    }
    var answer = root.split(payload)
    if (answer.status !== 200) {
      root.say("Open-Meteo refused the search (" + answer.status + ").")
      return
    }
    var parsed = Forecast.parseSearch(answer.body)
    if (parsed.error) {
      root.say(parsed.error)
      return
    }
    root.results = parsed.places
  }

  // --- plumbing ---------------------------------------------------------

  // Half a minute, not a second. The only thing on this screen that changes
  // between ticks is the age in the header, and a clock that wakes a phone's
  // processor sixty times more often than it has anything to say is the kind
  // of thing that shows up in a battery graph rather than on the screen.
  Timer {
    id: tick
    interval: 30000
    repeat: true
    running: skyWindow.visible
    onTriggered: {
      root.now = root.clockNow()
      root.maybeFetch()
    }
  }

  Timer {
    id: debounce
    interval: 350
    onTriggered: root.runSearch()
  }

  Process {
    id: ensureDir
    running: false
    command: ["mkdir", "-p", root.dataDir]
  }

  Process {
    id: fetcher
    property bool manual: false
    property string want: ""
    running: false
    stdout: StdioCollector { id: fetchOut; waitForEnd: true }
    // The disable is Quickshell's gap, not ours: `exited` carries a
    // QProcess::ExitStatus, and that enum is not in the type information the
    // module ships, so the linter cannot resolve a parameter this handler does
    // not even read.
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.arrived(code, fetchOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: finder
    running: false
    stdout: StdioCollector { id: findOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.found(code, findOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Chrome.JsonFile {
    id: placesFile
    path: root.dataDir + "/places.json"

    onParsed: function (data) {
      var state = Store.parsePlaces(data)
      root.places = state.places
      root.currentId = state.current
      root.units = root.harnessUnits.length ? root.harnessUnits : state.units
      // Nowhere to show the weather of is the one state this app cannot draw,
      // so it opens on the page that fixes it.
      if (!root.places.length) root.showingPlaces = true
      Qt.callLater(root.maybeFetch)
    }
    onQuarantined: function (to) { root.say("The places file was unreadable and was kept aside.") }
  }

  Chrome.JsonFile {
    id: cacheFile
    path: root.dataDir + "/forecast.json"

    onParsed: function (data) {
      var cached = Store.parseCache(data)
      var merged = root.cache
      // Only where nothing fresher has already arrived: a fetch that answered
      // while the file was being read must not be undone by it.
      for (var id in cached) {
        var mine = merged[id]
        if (mine && mine.fetched >= cached[id].fetched) continue
        merged = Store.put(merged, id, cached[id].forecast, cached[id].fetched)
      }
      root.cache = merged
      Qt.callLater(root.maybeFetch)
    }
    onQuarantined: function (to) { root.say("The cached forecast was unreadable and was kept aside.") }
  }

  Chrome.ThemeFile { id: themeFile }
  Chrome.UiFile { id: uiFile }

  onCurrentIdChanged: Qt.callLater(root.maybeFetch)

  IpcHandler {
    target: "weather"
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
    function refresh(): string { root.fetch(true); return "ok" }
    function place(): string { return root.place ? root.place.name : "" }
    function temperature(): string {
      return root.reading ? Forecast.temperature(root.reading.temp, root.units) : ""
    }
  }

  // --- the window -------------------------------------------------------

  Chrome.AppWindow {
    id: skyWindow
    shell: root.shell
    appName: "Weather"
    pageTitle: root.showingPlaces ? "Places" : (root.place ? root.place.name : "")
    pluginId: root.pluginId
    color: root.background

    onMapped: {
      root.now = root.clockNow()
      Qt.callLater(root.ensureLoaded)
      Qt.callLater(root.maybeFetch)
    }
    // The cache is written when the window leaves the screen, which on this
    // phone is the event immediately before the app is reclaimed. Not per
    // fetch: that is a write onto flash every quarter of an hour for a file
    // whose entire purpose is the next cold start.
    onUnmapped: root.saveCache()

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true
      Keys.onEscapePressed: {
        if (root.showingPlaces && root.places.length) { root.showingPlaces = false; return }
        root.dismiss()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- the title ----------------------------------------------------

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12

          // The bar is the top of the band rather than a strip above it. The
          // hero scrolls away under it and the colour stays, which is what
          // makes the sky look like one piece.
          Rectangle {
            anchors.fill: parent
            color: root.showingPlaces ? root.background : root.wash
          }

          Chrome.AppBar {
            anchors.fill: parent
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.BackButton {
              visible: root.showingPlaces && root.places.length > 0
              color: root.ink
              onClicked: root.showingPlaces = false
            }

            // The place name is the way to the places page, and the chevron is
            // what says so. A title that is also a button needs to look like one
            // or it is a title with a secret.
            center: Item {
              anchors.fill: parent

              Column {
                id: titleBlock
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 0

                // The chevron sits against the name rather than at the end of
                // the bar, so what it belongs to is not a guess.
                Row {
                  spacing: 3

                  Chrome.TypedText {
                    id: nameText
                    width: Math.min(titleBlock.width - 22, implicitWidth)
                    role: "subtitle"
                    text: root.showingPlaces ? "Places" : (root.place ? root.place.name : "Weather")
                    color: root.ink
                    bodySize: root.bodySize
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }

                  Chrome.Icon {
                    anchors.verticalCenter: nameText.verticalCenter
                    visible: !root.showingPlaces
                    slot: 18
                    size: 14
                    color: root.dim
                    names: ["pan-down-symbolic"]
                  }
                }

                Chrome.TypedText {
                  width: titleBlock.width
                  visible: !root.showingPlaces
                  role: "caption"
                  text: root.freshnessText()
                  color: root.dim
                  bodySize: root.bodySize
                  elide: Text.ElideRight
                  maximumLineCount: 1
                }
              }

              MouseArea {
                anchors.fill: parent
                enabled: !root.showingPlaces
                onClicked: root.showingPlaces = true
              }
            }

            trailing: Chrome.IconButton {
              visible: !root.showingPlaces && !!root.place
              color: root.ink
              names: ["view-refresh-symbolic"]
              tooltip: root.fetching ? "Updating the forecast" : "Refresh the forecast"
              spinning: root.fetching
              onClicked: root.fetch(true)
            }
          }
        }

        // --- the weather --------------------------------------------------

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          Flickable {
            id: sky
            anchors.fill: parent
            visible: !root.showingPlaces
            clip: true
            contentWidth: width
            contentHeight: skyCol.height
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: skyCol
              width: sky.width

              // The band. Its colour is the temperature's, which is the one
              // piece of this screen somebody reads without looking at it.
              Rectangle {
                width: parent.width
                height: 216

                gradient: Gradient {
                  GradientStop { position: 0.0; color: root.wash }
                  GradientStop { position: 0.62; color: root.wash }
                  GradientStop { position: 1.0; color: root.background }
                }

                Column {
                  anchors.centerIn: parent
                  width: parent.width
                  spacing: 2
                  visible: !!root.reading

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6

                    Sky {
                      anchors.verticalCenter: parent.verticalCenter
                      kind: root.reading ? Forecast.glyph(root.reading.code, root.reading.day) : "cloud"
                      size: 84
                      ink: root.ink
                      accent: root.hueColor("blue")
                      spark: root.hueColor("yellow")
                      // The crescent is cut with the colour behind it, and
                      // here that is the band rather than the window.
                      behind: root.wash
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.reading ? Forecast.temperature(root.reading.temp, root.units) : ""
                      // The theme's ink and not the temperature's colour: the
                      // hue is already on the screen -- behind this number, in
                      // the band, and under it in every bar -- and sixty pixels
                      // of pale yellow on a light theme is the one place it
                      // would cost a reading.
                      color: root.ink
                      font.family: Metrics.FONT
                      font.pixelSize: Math.round(root.bodySize * 3.6)
                      font.weight: Font.Light
                    }
                  }

                  Chrome.TypedText {
                    width: parent.width
                    role: "subtitle"
                    text: root.reading ? Forecast.describe(root.reading.code) : ""
                    color: root.ink
                    bodySize: root.bodySize
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Chrome.TypedText {
                    width: parent.width
                    visible: text.length > 0
                    role: "caption"
                    text: Forecast.heroNote(root.reading, root.todayRow, root.units)
                    color: root.dim
                    bodySize: root.bodySize
                    horizontalAlignment: Text.AlignHCenter
                  }
                }

                // Nothing known yet: the one sentence that says which of the
                // several possible reasons it is.
                Column {
                  anchors.centerIn: parent
                  width: parent.width - 64
                  spacing: 6
                  visible: !root.reading

                  Chrome.TypedText {
                    width: parent.width
                    role: "subtitle"
                    text: root.places.length ? "No forecast yet" : "Nowhere yet"
                    color: root.ink
                    bodySize: root.bodySize
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Chrome.TypedText {
                    width: parent.width
                    role: "caption"
                    text: {
                      if (!root.places.length) return "Name a town on the places page and it opens here."
                      if (root.trouble) return root.trouble
                      if (root.offline) return "This run is offline."
                      return "Asking Open-Meteo…"
                    }
                    color: root.dim
                    bodySize: root.bodySize
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                  }
                }
              }

              // --- the next twenty-four hours ---------------------------------

              Item {
                width: parent.width
                height: 112
                visible: root.hours.length > 0

                Flickable {
                  id: strip
                  anchors.fill: parent
                  clip: true
                  contentWidth: hourRow.width
                  contentHeight: height
                  flickableDirection: Flickable.HorizontalFlick
                  boundsBehavior: Flickable.StopAtBounds

                  Row {
                    id: hourRow
                    height: strip.height
                    leftPadding: 10
                    rightPadding: 10

                    Repeater {
                      model: root.hours

                      delegate: Item {
                        id: hour
                        required property var modelData

                        width: 54
                        height: hourRow.height

                        readonly property bool isNow: Forecast.isNow(hour.modelData.time, root.nowSec)

                        // The hour it is now is marked with the colour its
                        // label is drawn in as well as the pill behind it:
                        // roughly one man in twelve cannot tell this app's
                        // accent from the ink beside it.
                        Rectangle {
                          anchors.fill: parent
                          anchors.topMargin: 6
                          anchors.bottomMargin: 6
                          anchors.leftMargin: 3
                          anchors.rightMargin: 3
                          radius: 14
                          visible: hour.isNow
                          color: root.card
                        }

                        Column {
                          anchors.centerIn: parent
                          spacing: 3

                          Chrome.TypedText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            role: "caption"
                            text: Forecast.hourLabel(hour.modelData.time, root.zoneOffset, root.nowSec)
                            color: hour.isNow ? root.ink : root.dim
                            bodySize: root.bodySize
                          }

                          Sky {
                            anchors.horizontalCenter: parent.horizontalCenter
                            kind: Forecast.glyph(hour.modelData.code, hour.modelData.day)
                            size: 26
                            ink: root.ink
                            accent: root.hueColor("blue")
                            spark: root.hueColor("yellow")
                            behind: root.background
                          }

                          Chrome.TypedText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            role: "body"
                            text: Forecast.temperature(hour.modelData.temp, root.units)
                            color: root.tempColour(hour.modelData.temp)
                            bodySize: root.bodySize
                          }

                          // The chance of rain, and only when there is one
                          // worth printing: a column of "0%" down the strip is
                          // twenty-four numbers nobody reads.
                          Chrome.TypedText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: Math.round(root.bodySize * 0.9)
                            role: "overline"
                            text: (hour.modelData.pop !== null && hour.modelData.pop >= 10)
                                  ? Forecast.percent(hour.modelData.pop) : ""
                            color: root.hueColor("blue")
                            bodySize: root.bodySize
                          }
                        }
                      }
                    }
                  }
                }
              }

              // --- wind, damp, and the ends of the day ------------------------

              Item {
                width: parent.width
                height: root.tiles.length ? 82 : 0
                visible: root.tiles.length > 0

                Rectangle {
                  anchors.fill: parent
                  anchors.leftMargin: 12
                  anchors.rightMargin: 12
                  anchors.topMargin: 2
                  anchors.bottomMargin: 12
                  radius: root.radiusCard
                  color: root.card

                  RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    Repeater {
                      model: root.tiles

                      // An Item around the Column, and not the Column itself.
                      // Four columns that each size themselves to their own
                      // children, in a layout that is meanwhile sizing them,
                      // is a circle -- and the way it fails is that the first
                      // tile takes the whole card and the other three are
                      // drawn a pixel wide.
                      delegate: Item {
                        id: tile
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true

                        Column {
                          anchors.centerIn: parent
                          width: parent.width
                          spacing: 1

                          Chrome.TypedText {
                            width: parent.width
                            role: "overline"
                            text: tile.modelData.label
                            color: root.dim
                            bodySize: root.bodySize
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                          }

                          Chrome.TypedText {
                            width: parent.width
                            role: "body"
                            text: tile.modelData.value
                            color: root.ink
                            bodySize: root.bodySize
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                          }

                          Chrome.TypedText {
                            width: parent.width
                            visible: text.length > 0
                            role: "caption"
                            text: tile.modelData.note
                            color: root.dim
                            bodySize: root.bodySize
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                          }
                        }
                      }
                    }
                  }
                }
              }

              // --- the week ---------------------------------------------------

              Chrome.TypedText {
                x: 16
                visible: root.week.length > 0
                role: "overline"
                text: "THE WEEK"
                color: root.dim
                bodySize: root.bodySize
                bottomPadding: 4
              }

              Repeater {
                model: root.week

                delegate: Item {
                  id: day
                  required property var modelData

                  width: skyCol.width
                  height: 46

                  readonly property var fraction: Forecast.bar(day.modelData, root.range)

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8

                    Chrome.TypedText {
                      // Enough for "Today", which is the widest of the eight
                      // words that can be here and the one that matters.
                      Layout.preferredWidth: 52
                      Layout.alignment: Qt.AlignVCenter
                      role: "body"
                      text: Forecast.dayLabel(day.modelData.time, root.zoneOffset, root.nowSec)
                      color: root.ink
                      bodySize: root.bodySize
                      elide: Text.ElideRight
                    }

                    Sky {
                      Layout.preferredWidth: 26
                      Layout.preferredHeight: 26
                      Layout.alignment: Qt.AlignVCenter
                      kind: Forecast.glyph(day.modelData.code, true)
                      size: 26
                      ink: root.ink
                      accent: root.hueColor("blue")
                      spark: root.hueColor("yellow")
                      behind: root.background
                    }

                    Chrome.TypedText {
                      Layout.preferredWidth: 30
                      Layout.alignment: Qt.AlignVCenter
                      role: "caption"
                      text: (day.modelData.pop !== null && day.modelData.pop >= 10)
                            ? Forecast.percent(day.modelData.pop) : ""
                      color: root.hueColor("blue")
                      bodySize: root.bodySize
                    }

                    Chrome.TypedText {
                      Layout.preferredWidth: 28
                      Layout.alignment: Qt.AlignVCenter
                      role: "body"
                      text: Forecast.temperature(day.modelData.low, root.units)
                      color: root.dim
                      bodySize: root.bodySize
                      horizontalAlignment: Text.AlignRight
                    }

                    // The week on one scale. A bar further to the right is a
                    // warmer day than the row above it, which is only true
                    // because every row is measured against the same coldest
                    // and warmest -- and it is decoration: both ends of it
                    // carry their own number.
                    Item {
                      id: track
                      Layout.fillWidth: true
                      Layout.preferredHeight: 6
                      Layout.alignment: Qt.AlignVCenter

                      Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: root.line
                      }

                      Rectangle {
                        x: day.fraction.from * track.width
                        width: Math.max(6, (day.fraction.to - day.fraction.from) * track.width)
                        height: parent.height
                        radius: height / 2

                        gradient: Gradient {
                          orientation: Gradient.Horizontal
                          GradientStop { position: 0.0; color: root.tempColour(day.modelData.low) }
                          GradientStop { position: 1.0; color: root.tempColour(day.modelData.high) }
                        }
                      }
                    }

                    Chrome.TypedText {
                      Layout.preferredWidth: 30
                      Layout.alignment: Qt.AlignVCenter
                      role: "body"
                      text: Forecast.temperature(day.modelData.high, root.units)
                      color: root.ink
                      bodySize: root.bodySize
                      horizontalAlignment: Text.AlignRight
                    }
                  }
                }
              }

              Item {
                width: parent.width
                height: 16
              }
            }
          }

          // --- the places ---------------------------------------------------

          Flickable {
            id: placesView
            anchors.fill: parent
            visible: root.showingPlaces
            clip: true
            contentWidth: width
            contentHeight: placesCol.height
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: placesCol
              width: placesView.width
              topPadding: 8
              bottomPadding: 24

              Chrome.TextField {
                x: 12
                width: parent.width - 24
                color: root.card
                bodySize: root.bodySize
                leadingNames: ["system-search-symbolic", "edit-find-symbolic"]
                trailingNames: root.query.length > 0 ? ["edit-clear-symbolic"] : []
                trailingClickable: true
                placeholderText: "Town or city"
                foreground: root.ink
                accent: root.accent
                iconColor: root.dim
                text: root.query
                onTextChanged: {
                  root.query = text
                  root.searched = false
                  if (root.query.trim().length < 2) root.results = []
                  else debounce.restart()
                }
                onAccepted: { debounce.stop(); root.runSearch() }
                onTrailingClicked: { root.query = ""; root.results = [] }
              }

              // What the geocoder found. Tapping one adds it and shows it,
              // which is the whole of "adding a place" -- there is no second
              // step and nothing to confirm.
              Repeater {
                model: root.query.trim().length >= 2 ? root.results : []

                delegate: Item {
                  id: hit
                  required property var modelData

                  width: placesCol.width
                  height: 62

                  Rectangle {
                    anchors.fill: parent
                    color: hitTap.pressed ? root.pressed : "transparent"
                  }

                  MouseArea {
                    id: hitTap
                    anchors.fill: parent
                    onClicked: root.addPlace(hit.modelData)
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 1

                    Chrome.TypedText {
                      width: parent.width
                      role: "body"
                      text: hit.modelData.name
                      color: root.ink
                      bodySize: root.bodySize
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }

                    Chrome.TypedText {
                      width: parent.width
                      visible: text.length > 0
                      role: "caption"
                      text: Forecast.where(hit.modelData)
                      color: root.dim
                      bodySize: root.bodySize
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: root.line
                  }
                }
              }

              Chrome.TypedText {
                width: parent.width - 48
                x: 24
                topPadding: 20
                visible: root.query.trim().length >= 2 && !root.results.length
                role: "caption"
                text: {
                  if (root.finding) return "Looking…"
                  if (!root.searched) return ""
                  return "Nothing is called “" + root.query.trim() + "”."
                }
                color: root.dim
                bodySize: root.bodySize
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }

              // The first run: an empty list is not a state to leave a person
              // looking at without a sentence.
              Column {
                width: parent.width - 48
                x: 24
                topPadding: 28
                bottomPadding: 12
                spacing: 6
                visible: !root.places.length && root.query.trim().length < 2

                Chrome.TypedText {
                  width: parent.width
                  role: "subtitle"
                  text: "Nowhere yet"
                  color: root.ink
                  bodySize: root.bodySize
                  horizontalAlignment: Text.AlignHCenter
                }

                Chrome.TypedText {
                  width: parent.width
                  role: "caption"
                  text: "Type a town above — Vienna, Kyoto, Reykjavík — and tap it."
                  color: root.dim
                  bodySize: root.bodySize
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                }
              }

              // --- the ones already chosen ------------------------------------

              Chrome.TypedText {
                x: 16
                topPadding: 14
                bottomPadding: 4
                visible: root.query.trim().length < 2 && root.places.length > 0
                role: "overline"
                text: "SAVED"
                color: root.dim
                bodySize: root.bodySize
              }

              Repeater {
                model: root.query.trim().length < 2 ? root.places : []

                delegate: Item {
                  id: saved
                  required property var modelData

                  width: placesCol.width
                  height: 60

                  readonly property bool isCurrent: saved.modelData.id === root.currentId

                  Rectangle {
                    anchors.fill: parent
                    color: savedTap.pressed ? root.pressed
                         : (saved.isCurrent ? root.card : "transparent")
                  }

                  MouseArea {
                    id: savedTap
                    anchors.fill: parent
                    onClicked: root.selectPlace(saved.modelData.id)
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 4
                    spacing: 8

                    Column {
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignVCenter
                      spacing: 1

                      Chrome.TypedText {
                        width: parent.width
                        role: "body"
                        text: saved.modelData.name
                        color: root.ink
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }

                      Chrome.TypedText {
                        width: parent.width
                        visible: text.length > 0
                        role: "caption"
                        text: Forecast.where(saved.modelData)
                        color: root.dim
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }
                    }

                    Sky {
                      Layout.preferredWidth: 24
                      Layout.preferredHeight: 24
                      Layout.alignment: Qt.AlignVCenter
                      visible: root.glyphAt(saved.modelData.id).length > 0
                      kind: root.glyphAt(saved.modelData.id) || "cloud"
                      size: 24
                      ink: root.ink
                      accent: root.hueColor("blue")
                      spark: root.hueColor("yellow")
                      behind: saved.isCurrent ? root.card : root.background
                    }

                    Column {
                      Layout.preferredWidth: 52
                      Layout.alignment: Qt.AlignVCenter
                      spacing: 0

                      Chrome.TypedText {
                        width: parent.width
                        role: "body"
                        text: root.tempAt(saved.modelData.id)
                        color: root.ink
                        bodySize: root.bodySize
                        horizontalAlignment: Text.AlignRight
                      }

                      Chrome.TypedText {
                        width: parent.width
                        visible: text.length > 0
                        role: "caption"
                        text: root.clockAt(saved.modelData.id)
                        color: root.dim
                        bodySize: root.bodySize
                        horizontalAlignment: Text.AlignRight
                      }
                    }

                    Chrome.IconButton {
                      Layout.alignment: Qt.AlignVCenter
                      color: root.dim
                      names: ["user-trash-symbolic"]
                      tooltip: "Remove " + saved.modelData.name
                      onClicked: root.removePlace(saved.modelData.id)
                    }
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: root.line
                  }
                }
              }

              // --- degrees in which scale ------------------------------------

              Item {
                width: parent.width
                height: 64
                visible: root.query.trim().length < 2

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: 16
                  anchors.rightMargin: 16
                  spacing: 8

                  Chrome.TypedText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    role: "body"
                    text: "Units"
                    color: root.ink
                    bodySize: root.bodySize
                  }

                  Repeater {
                    model: [{ name: "metric", label: "°C" }, { name: "imperial", label: "°F" }]

                    delegate: Chrome.Pill {
                      id: pill
                      required property var modelData

                      readonly property bool on: root.units === pill.modelData.name

                      Layout.preferredWidth: 58
                      Layout.preferredHeight: Metrics.TARGET - 6
                      Layout.alignment: Qt.AlignVCenter
                      text: pill.modelData.label
                      color: pill.on ? Theme.mix(root.colours.accent, root.colours.background, 0.22)
                                     : root.card
                      ink: pill.on ? root.accent : root.dim
                      bodySize: root.bodySize
                      onClicked: root.setUnits(pill.modelData.name)

                      Accessible.role: Accessible.RadioButton
                      Accessible.name: pill.modelData.name === "metric" ? "Celsius" : "Fahrenheit"
                      Accessible.checked: pill.on
                    }
                  }
                }
              }

              // The one thing this app will not do, said once, where somebody
              // would be looking for it.
              Chrome.TypedText {
                x: 16
                width: parent.width - 32
                topPadding: 4
                visible: root.query.trim().length < 2
                role: "caption"
                text: "Nothing here asks where the phone is. A place is on this "
                      + "list because you typed it."
                color: root.dim
                bodySize: root.bodySize
                wrapMode: Text.WordWrap
              }
            }
          }

          // --- a sentence, not a spinner ------------------------------------

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
