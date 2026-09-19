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
// The first of them is wherever the phone is, looked up from its connection's
// address; the rest are the towns somebody typed.
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

  readonly property string pluginId: "moarchy.weather"
  readonly property bool opened: skyWindow.visible
  readonly property var appWindow: skyWindow

  property string returnTo: ""
  // `colours` and not `palette`: QQuickItem already has a `palette`, and
  // shadowing it makes a binding resolve to whichever the compiler picked.
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY
  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    root.applyHarness()
  }

  // --- what is known ----------------------------------------------------

  property var places: []
  property string currentId: ""
  property string units: "metric"
  // Whether to ask where the phone is, and the last answer: a place with a
  // `found` stamp, or null. Null until a lookup has answered and whenever
  // `locate` is off -- never a guess, and never a town kept after somebody
  // said not to look.
  property bool locate: true
  property var here: null
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

  property bool locating: false
  property string lost: ""
  property int lostCount: 0
  property real locateRetryAt: 0
  // No lookup until both files are read. The setting that says not to look is
  // in one and the last answer is in the other, and FileView reads them
  // asynchronously: a lookup started in between is either one this app was
  // told not to make or one it already has the answer to.
  property bool placesRead: false
  property bool cacheRead: false

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

  readonly property var place: root.currentId === Store.HERE
                               ? root.here : Store.find(root.places, root.currentId)
  // Keyed by the place's coordinates rather than by `currentId`, which for
  // the phone's own place is "here" wherever here happens to be.
  readonly property var entry: root.place ? (root.cache[root.place.id] || null) : null
  readonly property var forecast: root.entry ? root.entry.forecast : null
  readonly property real fetched: root.entry ? root.entry.fetched : 0
  readonly property int zoneOffset: root.forecast ? root.forecast.offset : 0
  // Finding where the phone is, when that is the place on screen, is part of
  // updating it: the forecast waits on the answer.
  readonly property bool busy: root.fetching
                               || (root.locating && root.currentId === Store.HERE)
  // Whether the weather screen has anything it could show: a town typed, or
  // a lookup that will name one. Without either, the places page is the only
  // page there is.
  readonly property bool somewhere: root.places.length > 0 || root.locate

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
  readonly property color accent: root.colours.accent

  function hueColor(name) {
    var hues = root.colours.hues || {}
    return hues[name] || root.colours.accent
  }

  function tempColour(celsius) {
    return root.hueColor(Forecast.band(celsius))
  }

  readonly property string card: Theme.mix(root.colours.foreground, root.colours.background, 0.06)
  readonly property string pressed: Theme.mix(root.colours.foreground, root.colours.background, 0.11)

  // --- what the header says ---------------------------------------------

  function freshnessText() {
    if (!root.place) return root.locating ? "Finding where you are…" : "Nowhere yet"
    if (root.busy) return "Updating…"
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
    return { places: root.places, current: root.currentId, units: root.units, locate: root.locate }
  }

  function apply(next) {
    root.places = next.places
    root.locate = next.locate
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

  function setLocate(on) {
    root.apply(Store.withLocate(root.placesState(), on))
    root.lost = ""
    root.lostCount = 0
    root.locateRetryAt = 0
    if (!on && root.here) {
      // Off is forgotten, not hidden: the town leaves memory now and the disk
      // at the next write, which serializeCache makes without it.
      root.here = null
      root.dirty = true
    }
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
    // Showing wherever the phone is, and about to ask where that is: the
    // forecast waits for the answer rather than fetching the last town's.
    if (root.currentId === Store.HERE && (root.locating || root.locateDue())) return false
    if (root.retryAt && root.nowSec < root.retryAt) return false
    if (root.fetched <= 0) return true
    return (root.nowSec - root.fetched) >= Forecast.refreshAfter()
  }

  // Only while the window is up. The files are watched, and the cache is
  // written as the window goes away -- so without this, the write's own
  // reload would ask the network a question with nothing on screen to show
  // the answer on.
  function maybeFetch() {
    if (!skyWindow.visible) return
    if (root.locateDue()) root.findHere(false)
    if (root.due()) root.fetch(false)
  }

  // The button and `omarchy-shell weather refresh`. For wherever the phone is,
  // that is two questions in order -- where, then the weather there -- so a
  // refresh after walking from one network onto another is of the town the
  // phone is in now.
  function refresh() {
    if (root.currentId === Store.HERE && root.locate && !root.offline) root.findHere(true)
    else root.fetch(true)
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
    // The town on screen may not be the one this answer is for: a lookup that
    // named a new one while this request was out found `fetching` true and
    // left the new town for whoever came next. This is next.
    Qt.callLater(root.maybeFetch)
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
    cacheFile.setText(Store.serializeCache(root.cache, root.places, root.here))
    root.dirty = false
  }

  // --- where the phone is -----------------------------------------------

  // Asked only when the answer would be on screen: the phone's own place is
  // the one being shown, or the places page is open with its row at the top.
  // Somebody reading Kyoto's week has not asked where they are.
  function locateDue() {
    if (root.offline || !root.locate || root.locating) return false
    if (!root.placesRead || !root.cacheRead) return false
    if (root.currentId !== Store.HERE && !root.showingPlaces) return false
    if (root.locateRetryAt && root.nowSec < root.locateRetryAt) return false
    if (!root.here) return true
    return (root.nowSec - root.here.found) >= Forecast.LOCATE_S
  }

  function findHere(manual) {
    if (root.offline || !root.locate) return
    if (root.locating) {
      if (manual) locator.manual = true
      return
    }
    root.locating = true
    locator.manual = !!manual
    locator.command = root.curl(Forecast.LOCATE)
    locator.running = true
  }

  function located(code, payload) {
    root.locating = false
    var manual = locator.manual
    // Switched off while the question was out: the answer is dropped unread.
    if (!root.locate) return

    if (code !== 0) {
      root.lostHere("No answer from GeoJS.", 0, manual)
      return
    }
    var answer = root.split(payload)
    if (answer.status === 429) {
      root.lostHere("GeoJS is rate-limiting this connection.", Forecast.RATE_LIMIT_S, manual)
      return
    }
    if (answer.status !== 200) {
      root.lostHere("GeoJS refused the request (" + answer.status + ").", 0, manual)
      return
    }
    var parsed = Forecast.parseLocation(answer.body)
    if (parsed.error) {
      root.lostHere(parsed.error, 0, manual)
      return
    }

    var found = parsed.place
    found.found = root.clockNow() / 1000
    root.lostCount = 0
    root.locateRetryAt = 0
    root.lost = ""
    // A town that moved has a new id, so no forecast in the cache and one
    // fetch due; one that did not keeps the forecast it had.
    root.here = found
    root.dirty = true
    root.thenTheWeather(manual)
  }

  function lostHere(message, retry, manual) {
    root.lostCount += 1
    var wait = retry || root.backoff[Math.min(root.lostCount - 1, root.backoff.length - 1)]
    root.locateRetryAt = root.clockNow() / 1000 + wait
    root.lost = message
    // The last town found is still the best answer there is, so it stays on
    // the screen, quietly, and its forecast still refreshes.
    if (manual && !root.here) root.say(message)
    root.thenTheWeather(manual)
  }

  // Where has been answered, or has not. Either way the weather is next, for
  // the town the last answer named.
  function thenTheWeather(manual) {
    if (manual && root.currentId === Store.HERE) root.fetch(true)
    else Qt.callLater(root.maybeFetch)
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
    id: locator
    property bool manual: false
    running: false
    stdout: StdioCollector { id: locateOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.located(code, locateOut.text) }
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
      root.locate = state.locate
      if (!root.locate) root.here = null
      root.currentId = state.current
      root.units = root.harnessUnits.length ? root.harnessUnits : state.units
      root.placesRead = true
      // Nowhere to show the weather of is the one state this app cannot draw,
      // so it opens on the page that fixes it. With the lookup on there is
      // always somewhere -- or there will be, in about a second.
      if (!root.places.length && !root.locate) root.showingPlaces = true
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
      // The same rule for the town: one found while the file was being read
      // is newer than the one in it.
      var disk = Store.parseHere(data)
      if (root.locate && disk && (!root.here || root.here.found < disk.found)) root.here = disk
      root.cacheRead = true
      Qt.callLater(root.maybeFetch)
    }
    onQuarantined: function (to) { root.say("The cached forecast was unreadable and was kept aside.") }
  }

  Chrome.ThemeFile { id: themeFile }

  onCurrentIdChanged: Qt.callLater(root.maybeFetch)
  // The places page has the phone's own place at the top of it.
  onShowingPlacesChanged: Qt.callLater(root.maybeFetch)

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
    function refresh(): string { root.refresh(); return "ok" }
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
        if (root.showingPlaces && root.somewhere) { root.showingPlaces = false; return }
        root.dismiss()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- the title ----------------------------------------------------

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12

          // The window's own background, the same colour as the status bar
          // above it. This used to be the top of a band washed in the
          // temperature's hue, and the shell does not draw an app under the
          // status bar -- so the wash stopped at its bottom edge in a hard
          // line across the top of the screen.
          Rectangle {
            anchors.fill: parent
            color: root.background
          }

          Chrome.AppBar {
            anchors.fill: parent
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.BackButton {
              colours: root.colours
              visible: root.showingPlaces && root.somewhere
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

                  // The pin says the name beside it was looked up rather than
                  // chosen, which is the difference between "Berlin" and "you
                  // are in Berlin".
                  Chrome.Icon {
                    id: pin
                    anchors.verticalCenter: nameText.verticalCenter
                    visible: !root.showingPlaces && root.currentId === Store.HERE && !!root.place
                    slot: 18
                    size: 14
                    color: root.ink
                    names: ["mark-location-symbolic"]
                  }

                  Chrome.TypedText {
                    id: nameText
                    width: Math.min(titleBlock.width - 22 - (pin.visible ? pin.width + 3 : 0),
                                    implicitWidth)
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
              colours: root.colours
              visible: !root.showingPlaces && !!root.place
              color: root.ink
              names: ["view-refresh-symbolic"]
              tooltip: root.busy ? "Updating the forecast" : "Refresh the forecast"
              spinning: root.busy
              onClicked: root.refresh()
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

              // The hero. On the window's own background, like the rest of the
              // screen: the temperature's colour is in the hour strip and the
              // week's bars, which is where it can be read against something.
              Item {
                width: parent.width
                height: 216

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
                      // The crescent is cut with the colour behind it.
                      behind: root.background
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.reading ? Forecast.temperature(root.reading.temp, root.units) : ""
                      // The theme's ink and not the temperature's colour: the
                      // hue is already on the screen -- in the hour strip and
                      // under it in every bar -- and sixty pixels of pale
                      // yellow on a light theme is the one place it would cost
                      // a reading.
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
                // several possible reasons it is. This is the screen a phone
                // shows on the first run of the app, and it was the last loose
                // sentence floating on a black rectangle in this repository.
                Chrome.EmptyState {
                  anchors.centerIn: parent
                  width: parent.width - Metrics.GUTTER * 2
                  visible: !root.reading
                  colours: root.colours
                  bodySize: root.bodySize
                  names: root.place
                         ? ["view-refresh-symbolic"]
                         : ["mark-location-symbolic", "view-pin-symbolic"]
                  title: {
                    if (root.place) return "No forecast yet"
                    if (root.locate && !root.lost && !root.offline) return "Finding where you are"
                    return "Nowhere yet"
                  }
                  detail: {
                    if (!root.place) {
                      if (root.offline) return "This run is offline."
                      if (!root.locate) return "Name a town on the places page and it opens here."
                      if (root.lost) return root.lost + " Name a town on the places page instead."
                      return "Asking GeoJS where this connection is."
                    }
                    if (root.trouble) return root.trouble
                    if (root.offline) return "This run is offline."
                    return "Asking Open-Meteo…"
                  }
                }
              }

              // --- the next twenty-four hours ---------------------------------

              Item {
                width: parent.width
                height: root.hours.length > 0 ? 124 : 0
                visible: root.hours.length > 0

                Rectangle {
                  anchors.fill: parent
                  anchors.leftMargin: Metrics.GUTTER
                  anchors.rightMargin: Metrics.GUTTER
                  anchors.bottomMargin: Metrics.GAP
                  radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
                  color: root.card

                  Flickable {
                    id: strip
                    anchors.fill: parent
                    anchors.margins: Metrics.GROUP_PAD
                    clip: true
                    contentWidth: hourRow.width
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                      id: hourRow
                      height: strip.height

                      Repeater {
                        model: root.hours

                        delegate: Item {
                          id: hour
                          required property var modelData

                          width: 52
                          height: hourRow.height

                          readonly property bool isNow: Forecast.isNow(hour.modelData.time, root.nowSec)

                          // The hour it is now is marked with the colour its
                          // label is drawn in as well as the pill behind it:
                          // roughly one man in twelve cannot tell this app's
                          // accent from the ink beside it.
                          Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 1
                            anchors.rightMargin: 1
                            radius: Metrics.inner(Metrics.radius(root.colours, Metrics.RADIUS_LG), Metrics.GROUP_PAD)
                            visible: hour.isNow
                            color: Theme.surface(root.colours, "raised")
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
                              behind: hour.isNow
                                      ? Theme.surface(root.colours, "raised") : root.card
                            }

                            Chrome.TypedText {
                              anchors.horizontalCenter: parent.horizontalCenter
                              role: "body"
                              text: Forecast.temperature(hour.modelData.temp, root.units)
                              color: root.tempColour(hour.modelData.temp)
                              bodySize: root.bodySize
                            }

                            // The chance of rain, and only when there is one
                            // worth printing: a column of "0%" down the strip
                            // is twenty-four numbers nobody reads.
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
              }

              // --- wind, damp, and the ends of the day ------------------------

              GridLayout {
                x: Metrics.GUTTER
                width: skyCol.width - Metrics.GUTTER * 2
                visible: root.tiles.length > 0
                columns: 2
                columnSpacing: Metrics.GAP
                rowSpacing: Metrics.GAP

                Repeater {
                  model: root.tiles

                  // Two across rather than four. Four columns of a label, a
                  // number and a note in 336px is four columns that all elide,
                  // and the notes ("NW", "in 4 h") were the first to go.
                  delegate: Chrome.Tile {
                    id: tile
                    required property var modelData
                    Layout.fillWidth: true
                    colours: root.colours
                    bodySize: root.bodySize
                    label: tile.modelData.label
                    value: tile.modelData.value
                    footnote: tile.modelData.note
                    valueColour: root.ink
                  }
                }
              }

              Item { width: 1; height: Metrics.GAP }

              // --- the week ---------------------------------------------------

              Chrome.Section {
                id: weekSection
                x: Metrics.GUTTER
                width: skyCol.width - Metrics.GUTTER * 2
                visible: root.week.length > 0
                colours: root.colours
                bodySize: root.bodySize
                title: "The week"
                pad: Metrics.GROUP_PAD
                radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
                cardSpacing: 0

                Repeater {
                  model: root.week

                  delegate: Item {
                    id: day
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: 46

                    readonly property var fraction: Forecast.bar(day.modelData, root.range)

                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: Metrics.GAP
                      anchors.rightMargin: Metrics.GAP
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
                        behind: root.card
                      }

                      Chrome.TypedText {
                        Layout.preferredWidth: 28
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
                          radius: Metrics.round(root.colours, height)
                          color: Theme.surface(root.colours, "raised")
                        }

                        Rectangle {
                          x: day.fraction.from * track.width
                          width: Math.max(6, (day.fraction.to - day.fraction.from) * track.width)
                          height: parent.height
                          radius: Metrics.round(root.colours, height)

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
            contentHeight: placesCol.implicitHeight + 32
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: placesCol
              x: Metrics.GUTTER
              y: Metrics.GAP
              width: placesView.width - Metrics.GUTTER * 2
              spacing: Metrics.GAP

              Chrome.TextField {
                Layout.fillWidth: true
                colours: root.colours
                level: "card"
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
              Chrome.Group {
                id: hitGroup
                Layout.fillWidth: true
                colours: root.colours
                visible: root.query.trim().length >= 2 && root.results.length > 0

                Repeater {
                  model: root.query.trim().length >= 2 ? root.results : []

                  delegate: Chrome.ListRow {
                    id: hit
                    required property var modelData
                    Layout.fillWidth: true
                    radius: hitGroup.innerRadius
                    minHeight: 58
                    colours: root.colours
                    bodySize: root.bodySize
                    title: hit.modelData.name
                    subtitle: Forecast.where(hit.modelData)
                    onClicked: root.addPlace(hit.modelData)
                  }
                }
              }

              Chrome.EmptyState {
                Layout.fillWidth: true
                Layout.topMargin: 12
                visible: root.query.trim().length >= 2 && !root.results.length
                colours: root.colours
                bodySize: root.bodySize
                names: ["system-search-symbolic"]
                title: root.finding ? "Looking…" : "Nothing found"
                detail: root.finding
                        ? "Asking the geocoder for “" + root.query.trim() + "”."
                        : (root.searched
                           ? "Nothing is called “" + root.query.trim() + "”."
                           : "")
              }

              // The first run: an empty list is not a state to leave a person
              // looking at without a sentence.
              Chrome.EmptyState {
                Layout.fillWidth: true
                Layout.topMargin: 12
                visible: !root.somewhere && root.query.trim().length < 2
                colours: root.colours
                bodySize: root.bodySize
                names: ["mark-location-symbolic"]
                title: "Nowhere yet"
                detail: "Type a town above — Vienna, Kyoto, Reykjavík — and tap it."
              }

              // One row of either list below. Shared because the two lists
              // are read as one -- the temperature and the clock line up down
              // the page -- and differ only in what the button at the end does.
              Component {
                id: placeRow

                Chrome.ListRow {
                  id: row
                  // A saved place, or `{ here: true }` for the phone's own row,
                  // whose town is `root.here` and may not be known yet.
                  required property var modelData
                  readonly property bool isHere: row.modelData.here === true
                  readonly property var shows: row.isHere ? root.here : row.modelData
                  readonly property string key: row.isHere ? Store.HERE : row.modelData.id
                  readonly property string cached: row.shows ? row.shows.id : ""
                  readonly property bool isCurrent: row.key === root.currentId

                  Layout.fillWidth: true
                  radius: Metrics.inner(Metrics.radius(root.colours, Metrics.RADIUS_LG),
                                        Metrics.GROUP_PAD)
                  minHeight: 58
                  colours: root.colours
                  bodySize: root.bodySize
                  selected: row.isCurrent && !!row.shows
                  title: row.shows
                         ? row.shows.name
                         : (root.locating ? "Finding where you are…" : "Not found yet")
                  subtitle: {
                    if (row.shows) return Forecast.where(row.shows)
                    if (root.offline) return "This run is offline."
                    return root.lost || "Asking GeoJS where this connection is."
                  }
                  onClicked: {
                    if (row.shows) root.selectPlace(row.key)
                    else root.findHere(true)
                  }

                  trailing: [
                    Sky {
                      anchors.verticalCenter: parent.verticalCenter
                      visible: root.glyphAt(row.cached).length > 0
                      width: 24
                      height: 24
                      kind: root.glyphAt(row.cached) || "cloud"
                      size: 24
                      ink: root.ink
                      accent: root.hueColor("blue")
                      spark: root.hueColor("yellow")
                      behind: row.selected
                              ? Theme.surface(root.colours, "raised") : root.card
                    },
                    Column {
                      anchors.verticalCenter: parent.verticalCenter
                      width: 52
                      spacing: 0

                      Chrome.TypedText {
                        width: parent.width
                        role: "body"
                        text: root.tempAt(row.cached)
                        color: root.ink
                        bodySize: root.bodySize
                        horizontalAlignment: Text.AlignRight
                      }

                      Chrome.TypedText {
                        width: parent.width
                        visible: text.length > 0
                        role: "caption"
                        text: root.clockAt(row.cached)
                        color: root.dim
                        bodySize: root.bodySize
                        horizontalAlignment: Text.AlignRight
                      }
                    },
                    // A town somebody typed can be removed. The phone's own
                    // place cannot -- the switch at the bottom of the page is
                    // how that goes -- so its button asks again instead.
                    Chrome.IconButton {
                      colours: root.colours
                      anchors.verticalCenter: parent.verticalCenter
                      slot: 36
                      color: root.dim
                      names: row.isHere ? ["view-refresh-symbolic"] : ["user-trash-symbolic"]
                      tooltip: row.isHere
                               ? "Look up where this connection is again"
                               : "Remove " + row.modelData.name
                      spinning: row.isHere && root.locating
                      onClicked: {
                        if (row.isHere) root.findHere(true)
                        else root.removePlace(row.modelData.id)
                      }
                    }
                  ]
                }
              }

              // --- where the phone is -----------------------------------------

              Chrome.Section {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.query.trim().length < 2 && root.locate
                colours: root.colours
                bodySize: root.bodySize
                title: "Where you are"
                pad: Metrics.GROUP_PAD
                radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
                cardSpacing: 0

                Repeater {
                  model: root.query.trim().length < 2 && root.locate ? [{ here: true }] : []
                  delegate: placeRow
                }
              }

              // --- the ones already chosen ------------------------------------

              Chrome.Section {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.query.trim().length < 2 && root.places.length > 0
                colours: root.colours
                bodySize: root.bodySize
                title: "Saved"
                pad: Metrics.GROUP_PAD
                radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
                cardSpacing: 0

                Repeater {
                  model: root.query.trim().length < 2 ? root.places : []
                  delegate: placeRow
                }
              }

              // --- degrees in which scale ------------------------------------

              Chrome.Card {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.query.trim().length < 2
                colours: root.colours

                RowLayout {
                  Layout.fillWidth: true
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

                    delegate: Chrome.Chip {
                      id: unitChip
                      required property var modelData
                      Layout.preferredWidth: 58
                      Layout.alignment: Qt.AlignVCenter
                      colours: root.colours
                      bodySize: root.bodySize
                      text: unitChip.modelData.label
                      on: root.units === unitChip.modelData.name
                      onClicked: root.setUnits(unitChip.modelData.name)

                      Accessible.name: unitChip.modelData.name === "metric"
                                       ? "Celsius" : "Fahrenheit"
                    }
                  }
                }
              }

              // The one thing this app asks about the phone, with who is asked
              // and how close the answer gets, beside the switch that stops it
              // -- which is where somebody would be looking for both.
              Chrome.Card {
                Layout.fillWidth: true
                visible: root.query.trim().length < 2
                colours: root.colours
                spacing: 0

                Chrome.Check {
                  Layout.fillWidth: true
                  // The box is centred in a 44px target, so its edge is 11px
                  // inside the card's padding. Pulled back by that, it lines up
                  // with the sentence under it rather than starting a column
                  // of its own.
                  Layout.leftMargin: -(Metrics.TARGET - Metrics.CHECK) / 2
                  colours: root.colours
                  text: "Show where I am"
                  checked: root.locate
                  foreground: root.ink
                  tickColor: Theme.inkOn(root.colours, root.accent)
                  accent: root.accent
                  dim: root.dim
                  bodySize: root.bodySize
                  onToggled: function (on) { root.setLocate(on) }
                }

                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "caption"
                  text: "Looked up from this connection’s address, by GeoJS. It finds a "
                        + "town, not a street — and on mobile data, not always yours."
                  color: root.dim
                  bodySize: root.bodySize
                  wrapMode: Text.WordWrap
                }
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
