// Upcoming launches: what Launch Library says, and what a phone reads.
//
// The port of moarchy_launches/launches.py. Nothing here touches QML, which
// keeps the half that can be wrong — somebody else's JSON, and a NET turned
// into a string a person reads — separate from the screen that draws it.
.pragma library

var API = "https://ll.thespacedevs.com/2.2.0/launch/upcoming/"
var AGENT = "moarchy-launches/0.1.0 (+https://github.com/SimonSchubert/moarchy-apps)"
var TIMEOUT = 12
var LIMIT = 20

// How old the cache may get before the window asks again, and how that
// shortens when something is about to fly — Launch Library's own advice.
var REFRESH_S = 15 * 60
var NEAR_S = 60 * 60
var IMMINENT_S = 10 * 60
var NEAR_REFRESH_S = 5 * 60
var IMMINENT_REFRESH_S = 2 * 60
var RATE_LIMIT_S = 240

var STATUS_GO = 1
var STATUS_TBD = 2
var STATUS_SUCCESS = 3
var STATUS_FAILURE = 4
var STATUS_HOLD = 5
var STATUS_IN_FLIGHT = 6
var STATUS_PARTIAL = 7
var STATUS_TBC = 8

var TERMINAL = [STATUS_SUCCESS, STATUS_FAILURE, STATUS_PARTIAL]
var UNCERTAIN = [STATUS_TBD, STATUS_TBC]
var LIVE = [STATUS_GO, STATUS_HOLD, STATUS_IN_FLIGHT]

// The disc is 36px. "In Flight" and "Partial Failure" do not fit, so the
// badge carries a short mark and the detail page carries the real words.
// Colour is never the only signal: roughly one man in twelve cannot tell
// this app's green from its red.
var DISC = {
  1: "GO", 2: "TBD", 3: "OK", 4: "NO", 5: "HLD", 6: "FLY", 7: "PRT", 8: "TBC"
}

var STATUS_HUE = {
  1: "green", 2: "yellow", 3: "green", 4: "red",
  5: "yellow", 6: "cyan", 7: "orange", 8: "yellow"
}

var FINE = ["SEC", "MIN"]
var HOUR = ["HR"]
var MONTH = ["M", "MONTH"]
var QUARTER = ["Q1", "Q2", "Q3", "Q4"]
var YEAR = ["Y", "YEAR"]

var DASH = "—"
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function has(list, value) {
  for (var i = 0; i < list.length; i++) if (list[i] === value) return true
  return false
}

function url(count) {
  return API + "?limit=" + Math.max(1, Math.min(count || LIMIT, 100))
}

// --- reading the wire ----------------------------------------------------

function text(value) {
  return typeof value === "string" ? value.trim() : ""
}

function number(value) {
  if (typeof value !== "number" || !isFinite(value)) return null
  return value
}

function probability(value) {
  var n = number(value)
  // Launch Library uses -1 for "we have not been told".
  if (n === null || n < 0) return null
  return Math.round(n)
}

function stamp(value) {
  if (typeof value !== "string" || !value.trim()) return 0
  var ms = Date.parse(value.trim())
  return isNaN(ms) ? 0 : ms
}

function parse(record) {
  if (!record || typeof record !== "object") return null
  var id = record.id
  if (typeof id !== "string" || !id) return null
  var net = stamp(record.net)
  if (!net) return null

  var statusObj = (record.status && typeof record.status === "object") ? record.status : {}
  var statusId = Math.round(number(statusObj.id) || 0)
  var status = text(statusObj.abbrev) || DISC[statusId] || DASH

  var precision = ""
  if (record.net_precision && typeof record.net_precision === "object")
    precision = text(record.net_precision.abbrev)
  else
    precision = text(record.net_precision)

  var named = names(record)
  var place = pad(record)
  var job = mission(record)

  return {
    id: id,
    name: named.name || id,
    vehicle: named.vehicle,
    agency: agency(record),
    status_id: statusId,
    status: status,
    net: net,
    precision: precision,
    window_start: stamp(record.window_start),
    window_end: stamp(record.window_end),
    pad: place.pad,
    location: place.location,
    orbit: job.orbit,
    mission_type: job.type,
    probability: probability(record.probability),
    weather: text(record.weather_concerns),
    hold: text(record.holdreason),
    description: job.description
  }
}

function names(record) {
  var name = ""
  if (record.mission && typeof record.mission === "object")
    name = text(record.mission.name)
  else
    name = text(record.mission)

  var vehicle = ""
  if (record.rocket && typeof record.rocket === "object") {
    var config = record.rocket.configuration
    if (config && typeof config === "object")
      vehicle = text(config.full_name) || text(config.name)
  }

  var raw = text(record.name)
  if (raw.indexOf(" | ") >= 0) {
    var parts = raw.split(" | ")
    vehicle = vehicle || parts[0].trim()
    name = name || parts.slice(1).join(" | ").trim()
  } else if (!name) {
    name = raw
  }
  return { name: name, vehicle: vehicle }
}

function agency(record) {
  var lsp = record.launch_service_provider
  if (lsp && typeof lsp === "object") return text(lsp.name)
  return text(record.lsp_name)
}

function pad(record) {
  var p = record.pad
  if (p && typeof p === "object") {
    var where = ""
    if (p.location && typeof p.location === "object") where = text(p.location.name)
    return { pad: text(p.name), location: where }
  }
  return { pad: text(p), location: text(record.location) }
}

function mission(record) {
  var m = record.mission
  if (m && typeof m === "object") {
    var orbit = ""
    if (m.orbit && typeof m.orbit === "object")
      orbit = text(m.orbit.abbrev) || text(m.orbit.name)
    else
      orbit = text(m.orbit)
    return { orbit: orbit, type: text(m.type), description: text(m.description) }
  }
  return { orbit: text(record.orbit), type: text(record.mission_type), description: "" }
}

// Returns { launches: [...], error: "" }. Rows that cannot be read are left
// out rather than fatal: a list of twenty that refuses to draw because the
// eighth has a null in it is the failure mode to design against.
function parseUpcoming(body) {
  var payload
  try {
    payload = JSON.parse(body)
  } catch (e) {
    return { launches: [], error: "Launch Library sent something that is not JSON." }
  }
  if (!payload || !payload.results || payload.results.length === undefined)
    return { launches: [], error: "Launch Library sent something that is not a list of launches." }

  var out = []
  for (var i = 0; i < payload.results.length; i++) {
    var item = parse(payload.results[i])
    if (item) out.push(item)
  }
  if (!out.length && payload.results.length)
    return { launches: [], error: "Launch Library sent launches in a shape this app cannot read." }
  return { launches: out, error: "" }
}

// --- searching -----------------------------------------------------------

// The front of any word in the mission, vehicle, agency, pad or location.
// Not a substring anywhere: "ace" matching SpaceX means a search box that
// fills with coincidences.
function matches(item, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return true
  var hay = [item.name, item.vehicle, item.agency, item.pad, item.location].join(" ")
  var words = hay.toLowerCase().split(/\s+/)
  for (var i = 0; i < words.length; i++) {
    var word = words[i].replace(/^[.,;:()[\]{}\/|-]+|[.,;:()[\]{}\/|-]+$/g, "")
    if (word && word.indexOf(needle) === 0) return true
  }
  return false
}

function filter(list, query) {
  var out = []
  for (var i = 0; i < (list || []).length; i++)
    if (matches(list[i], query)) out.push(list[i])
  return out
}

// Starred launches in the order they were starred, not by NET: a watchlist
// sorted by countdown reorders itself under a thumb halfway down it.
function starred(list, favourites, query) {
  var known = {}
  for (var i = 0; i < (list || []).length; i++) known[list[i].id] = list[i]
  var out = []
  for (var k = 0; k < (favourites || []).length; k++) {
    var item = known[favourites[k]]
    if (item && matches(item, query)) out.push(item)
  }
  return out
}

function find(list, id) {
  for (var i = 0; i < (list || []).length; i++)
    if (list[i].id === id) return list[i]
  return null
}

// --- numbers as somebody reads them --------------------------------------

function disc(item) {
  if (!item) return DASH
  return DISC[item.status_id] || (item.status ? item.status.slice(0, 4).toUpperCase() : DASH)
}

function hue(item) {
  return (item && STATUS_HUE[item.status_id]) || "blue"
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

function countdown(net, now) {
  var seconds = Math.round((net - now) / 1000)
  var sign = seconds >= 0 ? "-" : "+"
  var left = Math.abs(seconds)
  var days = Math.floor(left / 86400)
  left -= days * 86400
  var hours = Math.floor(left / 3600)
  left -= hours * 3600
  var minutes = Math.floor(left / 60)
  var secs = left - minutes * 60
  if (days) return "T" + sign + days + "d " + pad2(hours) + "h"
  return "T" + sign + pad2(hours) + ":" + pad2(minutes) + ":" + pad2(secs)
}

function wall(net, precision) {
  var d = new Date(net)
  var mark = String(precision || "").toUpperCase()
  if (has(YEAR, mark)) return String(d.getFullYear())
  if (has(QUARTER, mark)) return "Q" + (Math.floor(d.getMonth() / 3) + 1) + " " + d.getFullYear()
  if (has(MONTH, mark)) return MONTHS[d.getMonth()] + " " + d.getFullYear()
  if (has(HOUR, mark))
    return pad2(d.getDate()) + " " + MONTHS[d.getMonth()] + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  return pad2(d.getDate()) + " " + MONTHS[d.getMonth()]
}

function freshness(seconds) {
  if (seconds < 60) return "just now"
  if (seconds < 3600) return Math.floor(seconds / 60) + " min ago"
  if (seconds < 86400) {
    var hours = Math.floor(seconds / 3600)
    return hours === 1 ? "1 hour ago" : hours + " hours ago"
  }
  var days = Math.floor(seconds / 86400)
  return days === 1 ? "yesterday" : days + " days ago"
}

function headline(item, now) {
  if (!item) return ""
  if (has(TERMINAL, item.status_id))
    return freshness(Math.max(0, (now - item.net) / 1000))
  if (has(UNCERTAIN, item.status_id) || !has(FINE, String(item.precision).toUpperCase())) {
    var precision = has(FINE, String(item.precision).toUpperCase()) ? "HR" : item.precision
    return wall(item.net, precision)
  }
  return countdown(item.net, now)
}

// "soon" | "late" | "wait" | "dim" — which ink the countdown is drawn in.
function tone(item, now) {
  if (!item) return "dim"
  if (has(UNCERTAIN, item.status_id)) return "wait"
  if (has(TERMINAL, item.status_id)) return "dim"
  var remaining = (item.net - now) / 1000
  if (remaining < 0 && item.status_id === STATUS_GO) return "late"
  if (remaining >= 0 && remaining < 3600 && item.status_id === STATUS_GO) return "soon"
  return "dim"
}

function windowText(item) {
  if (!item || (!item.window_start && !item.window_end)) return ""
  var start = item.window_start || item.net
  var end = item.window_end || start
  var a = new Date(start)
  var left = pad2(a.getDate()) + " " + MONTHS[a.getMonth()] + " " + pad2(a.getHours()) + ":" + pad2(a.getMinutes())
  if (end <= start) return left
  var b = new Date(end)
  if (a.toDateString() === b.toDateString())
    return left + " – " + pad2(b.getHours()) + ":" + pad2(b.getMinutes())
  return left + " – " + pad2(b.getDate()) + " " + MONTHS[b.getMonth()] + " " + pad2(b.getHours()) + ":" + pad2(b.getMinutes())
}

function note(item) {
  if (!item) return ""
  var parts = []
  if (item.vehicle) parts.push(item.vehicle)
  if (item.agency) parts.push(item.agency)
  return parts.join(" · ")
}

function facts(item) {
  if (!item) return []
  var out = []
  function add(label, value) { if (value) out.push({ label: label, value: value }) }
  add("Status", item.status || DASH)
  add("Vehicle", item.vehicle)
  add("Agency", item.agency)
  add("Pad", item.pad)
  add("Location", item.location)
  var orbit = []
  if (item.orbit) orbit.push(item.orbit)
  if (item.mission_type) orbit.push(item.mission_type)
  add("Orbit", orbit.join(" · "))
  add("Window", windowText(item))
  if (item.probability !== null && item.probability !== undefined)
    add("Probability", item.probability + "%")
  add("Weather", item.weather)
  add("Hold", item.hold)
  return out
}

// How old the cache may be before the next fetch, in seconds.
function refreshAfter(list, now) {
  var wait = REFRESH_S
  for (var i = 0; i < (list || []).length; i++) {
    var item = list[i]
    if (!has(LIVE, item.status_id)) continue
    var remaining = (item.net - now) / 1000
    if (remaining >= 0 && remaining <= IMMINENT_S) wait = Math.min(wait, IMMINENT_REFRESH_S)
    else if (remaining >= 0 && remaining <= NEAR_S) wait = Math.min(wait, NEAR_REFRESH_S)
  }
  return wait
}
