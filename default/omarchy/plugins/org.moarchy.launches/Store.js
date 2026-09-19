// The two files the GTK app already writes, in the same shape.
//
// ~/.local/share/moarchy-launches/favourites.json is the only thing in this
// app a person made; upcoming.json is the last answer Launch Library gave and
// is disposable by definition. A star tapped here is a star over there.
.pragma library

var SCHEMA = 1
var MAX_FAVOURITES = 200

function pad2(n) { return n < 10 ? "0" + n : String(n) }

function iso(ms) {
  if (!ms) return null
  var d = new Date(ms)
  return d.getUTCFullYear() + "-" + pad2(d.getUTCMonth() + 1) + "-" + pad2(d.getUTCDate())
         + "T" + pad2(d.getUTCHours()) + ":" + pad2(d.getUTCMinutes()) + ":" + pad2(d.getUTCSeconds()) + "Z"
}

function stamp(value) {
  if (typeof value !== "string" || !value.trim()) return 0
  var ms = Date.parse(value.trim())
  return isNaN(ms) ? 0 : ms
}

function parseFavourites(text) {
  var out = []
  if (!text || !String(text).trim()) return out
  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return out
  }
  var raw = data && data.favourites
  if (!raw || raw.length === undefined) return out
  for (var i = 0; i < raw.length && out.length < MAX_FAVOURITES; i++) {
    var id = raw[i]
    if (typeof id === "string" && id && out.indexOf(id) < 0) out.push(id)
  }
  return out
}

function serializeFavourites(favourites) {
  return JSON.stringify({ schema: SCHEMA, favourites: favourites || [] }, null, 1)
}

function launchFrom(data) {
  if (!data || typeof data !== "object") return null
  var net = stamp(data.net)
  if (typeof data.id !== "string" || !data.id || !net) return null
  return {
    id: data.id,
    name: String(data.name || data.id),
    vehicle: String(data.vehicle || ""),
    agency: String(data.agency || ""),
    status_id: Math.round(Number(data.status_id) || 0),
    status: String(data.status || ""),
    net: net,
    precision: String(data.precision || ""),
    window_start: stamp(data.window_start),
    window_end: stamp(data.window_end),
    pad: String(data.pad || ""),
    location: String(data.location || ""),
    orbit: String(data.orbit || ""),
    mission_type: String(data.mission_type || ""),
    probability: (typeof data.probability === "number") ? data.probability : null,
    weather: String(data.weather || ""),
    hold: String(data.hold || ""),
    description: String(data.description || "")
  }
}

function launchTo(item) {
  return {
    id: item.id,
    name: item.name,
    vehicle: item.vehicle,
    agency: item.agency,
    status_id: item.status_id,
    status: item.status,
    net: iso(item.net),
    precision: item.precision,
    window_start: iso(item.window_start),
    window_end: iso(item.window_end),
    pad: item.pad,
    location: item.location,
    orbit: item.orbit,
    mission_type: item.mission_type,
    probability: item.probability,
    weather: item.weather,
    hold: item.hold,
    description: item.description
  }
}

// Returns { launches: [...], fetched: <epoch seconds> }.
function parseUpcoming(text) {
  var empty = { launches: [], fetched: 0 }
  if (!text || !String(text).trim()) return empty
  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return empty
  }
  if (!data || !data.launches || data.launches.length === undefined) return empty
  var out = []
  for (var i = 0; i < data.launches.length; i++) {
    var item = launchFrom(data.launches[i])
    if (item) out.push(item)
  }
  return {
    launches: out,
    fetched: (typeof data.fetched === "number") ? data.fetched : 0
  }
}

function serializeUpcoming(launches, fetched) {
  var out = []
  for (var i = 0; i < (launches || []).length; i++) out.push(launchTo(launches[i]))
  return JSON.stringify({ schema: SCHEMA, fetched: fetched || 0, launches: out }, null, 1)
}

// Keeps at most one row per launch, in arrival order — which is NET order,
// because that is how the endpoint sorts.
function dedupe(launches) {
  var seen = {}
  var out = []
  for (var i = 0; i < (launches || []).length; i++) {
    var item = launches[i]
    if (seen[item.id]) continue
    seen[item.id] = true
    out.push(item)
  }
  return out
}

function toggle(favourites, id) {
  var out = []
  var found = false
  for (var i = 0; i < (favourites || []).length; i++) {
    if (favourites[i] === id) { found = true; continue }
    out.push(favourites[i])
  }
  if (found) return { favourites: out, starred: false, full: false }
  if (out.length >= MAX_FAVOURITES) return { favourites: out, starred: false, full: true }
  out.push(id)
  return { favourites: out, starred: true, full: false }
}
