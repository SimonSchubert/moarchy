// The two files: the places somebody chose, and the last answer about them.
//
// `places.json` is the only thing in this app a person made -- a handful of
// towns, which of them is on screen, and whether they want degrees Celsius. It
// is small, hand-editable and worth keeping. `forecast.json` is disposable by
// definition: it exists so that opening the app in a tunnel shows this
// morning's forecast rather than a spinner, and every byte of it can be
// fetched again.
//
// Both are read as objects rather than as text, because the kit's JsonFile has
// already told a file that is absent from a file that is broken and moved the
// broken one aside. What is left for this module is the other half of the same
// job: a file somebody has edited by hand must not be able to put anything on
// screen that is not a string or a number.
.pragma library

var SCHEMA = 1

// Twelve places is more than anybody watches and few enough that the cache
// beside it stays a few tens of kilobytes.
var MAX_PLACES = 12

var UNITS = ["metric", "imperial"]

function str(value) {
  return typeof value === "string" ? value.trim() : ""
}

function num(value) {
  if (typeof value !== "number" || !isFinite(value)) return null
  return value
}

function units(value) {
  var name = str(value).toLowerCase()
  return UNITS.indexOf(name) >= 0 ? name : "metric"
}

// --- the places ----------------------------------------------------------

function placeFrom(data) {
  if (!data || typeof data !== "object") return null
  var name = str(data.name)
  var lat = num(data.lat)
  var lon = num(data.lon)
  var id = str(data.id)
  if (!name || lat === null || lon === null || !id) return null
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null
  return {
    id: id,
    name: name,
    admin: str(data.admin),
    country: str(data.country),
    lat: lat,
    lon: lon
  }
}

function placeTo(place) {
  return {
    id: place.id, name: place.name, admin: place.admin,
    country: place.country, lat: place.lat, lon: place.lon
  }
}

// Returns { places: [...], current: "<id>", units: "metric" }.
function parsePlaces(data) {
  var empty = { places: [], current: "", units: "metric" }
  if (!data || typeof data !== "object") return empty
  var raw = data.places
  if (!raw || raw.length === undefined) raw = []

  var out = []
  var seen = {}
  for (var i = 0; i < raw.length && out.length < MAX_PLACES; i++) {
    var place = placeFrom(raw[i])
    if (!place || seen[place.id]) continue
    seen[place.id] = true
    out.push(place)
  }

  // A `current` naming a place that is not in the list is the ordinary result
  // of removing one in an editor, and the first place is a better answer than
  // an empty screen.
  var current = str(data.current)
  if (!seen[current]) current = out.length ? out[0].id : ""

  return { places: out, current: current, units: units(data.units) }
}

function serializePlaces(state) {
  var out = []
  for (var i = 0; i < (state.places || []).length; i++) out.push(placeTo(state.places[i]))
  return JSON.stringify({
    schema: SCHEMA,
    units: units(state.units),
    current: str(state.current),
    places: out
  }, null, 1)
}

function find(places, id) {
  for (var i = 0; i < (places || []).length; i++)
    if (places[i].id === id) return places[i]
  return null
}

function has(places, id) {
  return !!find(places, id)
}

// Adding a place that is already there is not an error and not a duplicate: it
// is somebody searching for the town they are already watching, and what they
// meant was "show me that one".
function add(state, place) {
  if (!place) return { state: state, added: false, full: false }
  if (has(state.places, place.id))
    return { state: select(state, place.id), added: false, full: false }
  if (state.places.length >= MAX_PLACES)
    return { state: state, added: false, full: true }
  var places = state.places.slice()
  places.push(place)
  return {
    state: { places: places, current: place.id, units: state.units },
    added: true,
    full: false
  }
}

// Removing the place being shown moves to its neighbour rather than to the
// top: the row under your thumb is the one you were looking at next.
function remove(state, id) {
  var places = []
  var index = -1
  for (var i = 0; i < state.places.length; i++) {
    if (state.places[i].id === id) { index = i; continue }
    places.push(state.places[i])
  }
  if (index < 0) return state
  var current = state.current
  if (current === id)
    current = places.length ? places[Math.min(index, places.length - 1)].id : ""
  return { places: places, current: current, units: state.units }
}

function select(state, id) {
  if (!has(state.places, id)) return state
  return { places: state.places, current: id, units: state.units }
}

function withUnits(state, name) {
  return { places: state.places, current: state.current, units: units(name) }
}

// --- the cache -----------------------------------------------------------

// One entry per place, keyed by the same coordinate id the places file uses.
// Returns { "<id>": { fetched: <epoch seconds>, forecast: {...} } }.
function parseCache(data) {
  var out = {}
  if (!data || typeof data !== "object") return out
  var raw = data.forecasts
  if (!raw || typeof raw !== "object") return out
  for (var id in raw) {
    var entry = raw[id]
    if (!entry || typeof entry !== "object") continue
    var forecast = forecastFrom(entry.forecast)
    if (!forecast) continue
    out[id] = { fetched: num(entry.fetched) || 0, forecast: forecast }
  }
  return out
}

// Written for the places that still exist, and only for them: a town removed
// from the list should not leave its week behind in a file.
function serializeCache(entries, places) {
  var out = {}
  for (var i = 0; i < (places || []).length; i++) {
    var id = places[i].id
    var entry = entries[id]
    if (entry && entry.forecast) out[id] = { fetched: entry.fetched || 0, forecast: entry.forecast }
  }
  return JSON.stringify({ schema: SCHEMA, forecasts: out }, null, 1)
}

function put(entries, id, forecast, fetched) {
  var out = {}
  for (var key in entries) out[key] = entries[key]
  out[id] = { fetched: fetched || 0, forecast: forecast }
  return out
}

// A forecast off the disk is read exactly as strictly as one off the wire.
// It is the same JSON, one restart later, and the arithmetic that draws a
// range bar cannot tell the difference between a missing number and a nought.
function forecastFrom(data) {
  if (!data || typeof data !== "object") return null
  var hourly = []
  var raw = data.hourly
  if (raw && raw.length !== undefined) {
    for (var i = 0; i < raw.length; i++) {
      var hour = hourFrom(raw[i])
      if (hour) hourly.push(hour)
    }
  }
  var daily = []
  raw = data.daily
  if (raw && raw.length !== undefined) {
    for (var j = 0; j < raw.length; j++) {
      var day = dayFrom(raw[j])
      if (day) daily.push(day)
    }
  }
  var current = currentFrom(data.current)
  if (!current && !hourly.length) return null
  return {
    offset: Math.round(num(data.offset) || 0),
    current: current,
    hourly: hourly,
    daily: daily
  }
}

function currentFrom(data) {
  if (!data || typeof data !== "object") return null
  var time = num(data.time)
  var temp = num(data.temp)
  if (time === null || temp === null) return null
  return {
    time: Math.round(time), temp: temp,
    feels: num(data.feels), humidity: num(data.humidity),
    precip: num(data.precip), code: Math.round(num(data.code) || 0),
    wind: num(data.wind), from: num(data.from),
    day: data.day !== false
  }
}

function hourFrom(data) {
  if (!data || typeof data !== "object") return null
  var time = num(data.time)
  var temp = num(data.temp)
  if (time === null || temp === null) return null
  return {
    time: Math.round(time), temp: temp,
    code: Math.round(num(data.code) || 0),
    pop: num(data.pop), day: data.day !== false
  }
}

function dayFrom(data) {
  if (!data || typeof data !== "object") return null
  var time = num(data.time)
  var high = num(data.high)
  var low = num(data.low)
  if (time === null || high === null || low === null) return null
  return {
    time: Math.round(time), code: Math.round(num(data.code) || 0),
    high: high, low: low, pop: num(data.pop),
    sunrise: num(data.sunrise), sunset: num(data.sunset)
  }
}
