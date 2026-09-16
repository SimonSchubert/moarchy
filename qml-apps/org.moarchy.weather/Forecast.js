// The weather: what Open-Meteo says, and what a phone reads.
//
// Nothing here touches QML, which keeps the half that can be wrong -- somebody
// else's JSON, a WMO code turned into a word, a temperature turned into a
// string -- separate from the screen that draws it. It is also the half with a
// right answer that predates the app, which is what makes the tests worth
// writing.
.pragma library

var API = "https://api.open-meteo.com/v1/forecast"
var GEOCODE = "https://geocoding-api.open-meteo.com/v1/search"
// Where this connection is, by its address. GeoJS because it is HTTPS without
// a key or an account, and names the country in words -- ipinfo, asked the
// same question, answers "DE", and the places list would need a table of
// countries to say Germany.
var LOCATE = "https://get.geojs.io/v1/ip/geo.json"
var AGENT = "moarchy-weather/0.1.0 (+https://github.com/SimonSchubert/moarchy-apps)"
var TIMEOUT = 12

// Seven days is what the daily list shows; 48 hours is what is kept of the
// hourly one, which is twice what the strip draws and is there so that a phone
// woken at midnight still has tomorrow in the cache.
var DAYS = 7
var KEEP_HOURS = 48
var STRIP_HOURS = 24

// Weather is not a share price. Fifteen minutes is finer than the models
// themselves update -- ICON and GFS publish hourly -- and the number is about
// the clock on screen rather than about the forecast behind it.
var REFRESH_S = 15 * 60
var RATE_LIMIT_S = 600

// An address changes when the phone changes network, which is not something a
// weather app can be told about. So it is asked again on the forecast's own
// clock: a train out of one town and a café's wifi in the next is a new answer
// within a quarter of an hour of opening the app.
var LOCATE_S = 15 * 60

var MAX_RESULTS = 8

var CURRENT = ["temperature_2m", "apparent_temperature", "relative_humidity_2m",
               "is_day", "precipitation", "weather_code",
               "wind_speed_10m", "wind_direction_10m"]
var HOURLY = ["temperature_2m", "weather_code", "precipitation_probability", "is_day"]
var DAILY = ["weather_code", "temperature_2m_max", "temperature_2m_min",
             "precipitation_probability_max", "sunrise", "sunset"]

var DASH = "—"
var DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
// Sixteen points rather than eight: "WNW" is three characters, fits the tile,
// and is the difference between a wind off the sea and a wind off the hill.
var COMPASS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
               "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

// --- the wire ------------------------------------------------------------

// `timeformat=unixtime` is the one request parameter here that is load-bearing.
// With Open-Meteo's default, every time in the answer is a naive local string
// -- "2026-09-15T14:00" -- with the offset reported separately, and a phone in
// Berlin reading a forecast for Denver has to reconstruct which of the two
// clocks each string is on. As seconds it is arithmetic: the wire is UTC, the
// offset comes with it, and the local wall clock is `t + offset` read in UTC.
function url(lat, lon) {
  return API
    + "?latitude=" + fixed(lat, 4)
    + "&longitude=" + fixed(lon, 4)
    + "&current=" + CURRENT.join(",")
    + "&hourly=" + HOURLY.join(",")
    + "&daily=" + DAILY.join(",")
    + "&timezone=auto&timeformat=unixtime&forecast_days=" + DAYS
}

function searchUrl(query) {
  return GEOCODE + "?name=" + encodeURIComponent(String(query || "").trim())
    + "&count=" + MAX_RESULTS + "&language=en&format=json"
}

function fixed(value, places) {
  var n = Number(value)
  if (!isFinite(n)) return "0"
  return n.toFixed(places)
}

function num(value) {
  if (typeof value !== "number" || !isFinite(value)) return null
  return value
}

function text(value) {
  return typeof value === "string" ? value.trim() : ""
}

// --- what the sky is doing -----------------------------------------------

// WMO 4677, as Open-Meteo sends it. The first of each pair is what the header
// says; the second is which glyph Sky.qml draws, and several codes share one --
// there is no drawing that tells light drizzle from drizzle at 22px, and
// pretending otherwise is a symbol that says nothing precisely.
var CODES = {
  0: ["Clear sky", "clear"],
  1: ["Mainly clear", "mostly-clear"],
  2: ["Partly cloudy", "partly"],
  3: ["Overcast", "cloud"],
  45: ["Fog", "fog"],
  48: ["Freezing fog", "fog"],
  51: ["Light drizzle", "drizzle"],
  53: ["Drizzle", "drizzle"],
  55: ["Heavy drizzle", "drizzle"],
  56: ["Freezing drizzle", "sleet"],
  57: ["Freezing drizzle", "sleet"],
  61: ["Light rain", "rain"],
  63: ["Rain", "rain"],
  65: ["Heavy rain", "rain"],
  66: ["Freezing rain", "sleet"],
  67: ["Freezing rain", "sleet"],
  71: ["Light snow", "snow"],
  73: ["Snow", "snow"],
  75: ["Heavy snow", "snow"],
  77: ["Snow grains", "snow"],
  80: ["Light showers", "showers"],
  81: ["Showers", "showers"],
  82: ["Heavy showers", "showers"],
  85: ["Snow showers", "snow"],
  86: ["Heavy snow showers", "snow"],
  95: ["Thunderstorm", "storm"],
  96: ["Thunderstorm with hail", "storm"],
  99: ["Thunderstorm with hail", "storm"]
}

// The three glyphs that have a night half. Rain at night is rain; a sun at
// night is a mistake, and it is the one people notice.
var NIGHTABLE = { "clear": 1, "mostly-clear": 1, "partly": 1 }

function describe(code) {
  var row = CODES[Math.round(Number(code))]
  // A code this app has never heard of leaves the sentence out rather than
  // inventing one. The temperature beside it is still true.
  return row ? row[0] : ""
}

function glyph(code, day) {
  var row = CODES[Math.round(Number(code))]
  var kind = row ? row[1] : "cloud"
  if (day === false && NIGHTABLE[kind]) return kind + "-night"
  return kind
}

// Which hue a temperature is drawn in. Cold is the theme's blue and hot is its
// red, through the two in between, and every one of them is a hue the palette
// names -- so a theme with a warm blue gets a warm cold end and still looks
// like itself. Decoration only: both ends of a range bar carry their number.
function band(celsius) {
  var c = Number(celsius)
  if (!isFinite(c)) return "blue"
  if (c < 0) return "cyan"
  if (c < 10) return "blue"
  if (c < 18) return "green"
  if (c < 25) return "yellow"
  if (c < 32) return "orange"
  return "red"
}

// --- reading the answer --------------------------------------------------

// Returns { forecast: {...}, error: "" }. `now` is in seconds, and is what the
// hourly series is trimmed against: a forecast is 168 hours long and a phone
// needs the next two days of it, not the week.
function parseForecast(body, now) {
  var payload
  try {
    payload = JSON.parse(body)
  } catch (e) {
    return { forecast: null, error: "Open-Meteo sent something that is not JSON." }
  }
  if (!payload || typeof payload !== "object")
    return { forecast: null, error: "Open-Meteo sent something that is not a forecast." }
  if (payload.error)
    return { forecast: null, error: text(payload.reason) || "Open-Meteo refused the request." }

  var current = readCurrent(payload.current)
  var hourly = readHourly(payload.hourly, now)
  var daily = readDaily(payload.daily)
  if (!current && !hourly.length)
    return { forecast: null, error: "Open-Meteo sent a forecast in a shape this app cannot read." }

  return {
    forecast: {
      offset: Math.round(num(payload.utc_offset_seconds) || 0),
      current: current,
      hourly: hourly,
      daily: daily
    },
    error: ""
  }
}

function readCurrent(data) {
  if (!data || typeof data !== "object") return null
  var when = num(data.time)
  var temp = num(data.temperature_2m)
  if (when === null || temp === null) return null
  return {
    time: Math.round(when),
    temp: temp,
    feels: num(data.apparent_temperature),
    humidity: num(data.relative_humidity_2m),
    precip: num(data.precipitation),
    code: Math.round(num(data.weather_code) || 0),
    wind: num(data.wind_speed_10m),
    from: num(data.wind_direction_10m),
    // The wire says 1 or 0. Anything else is treated as day, which is the
    // failure that draws a sun in daylight rather than a moon at noon.
    day: num(data.is_day) !== 0
  }
}

function readHourly(data, now) {
  var out = []
  if (!data || !data.time || data.time.length === undefined) return out
  var from = Math.round(Number(now) || 0) - 3600
  for (var i = 0; i < data.time.length && out.length < KEEP_HOURS; i++) {
    var when = num(data.time[i])
    var temp = num(series(data.temperature_2m, i))
    if (when === null || temp === null) continue
    if (when < from) continue
    out.push({
      time: Math.round(when),
      temp: temp,
      code: Math.round(num(series(data.weather_code, i)) || 0),
      pop: num(series(data.precipitation_probability, i)),
      day: num(series(data.is_day, i)) !== 0
    })
  }
  return out
}

function readDaily(data) {
  var out = []
  if (!data || !data.time || data.time.length === undefined) return out
  for (var i = 0; i < data.time.length; i++) {
    var when = num(data.time[i])
    var high = num(series(data.temperature_2m_max, i))
    var low = num(series(data.temperature_2m_min, i))
    if (when === null || high === null || low === null) continue
    out.push({
      time: Math.round(when),
      code: Math.round(num(series(data.weather_code, i)) || 0),
      high: high,
      low: low,
      pop: num(series(data.precipitation_probability_max, i)),
      sunrise: num(series(data.sunrise, i)),
      sunset: num(series(data.sunset, i))
    })
  }
  return out
}

// Open-Meteo sends parallel arrays rather than a list of objects, so a series
// that is missing entirely is `undefined` and one that is short is a row with
// no value. Both come back null here and are handled as "not told".
function series(list, i) {
  if (!list || list.length === undefined || i >= list.length) return null
  return list[i]
}

// Returns { places: [...], error: "" }. A geocoding answer with no `results`
// at all is what Open-Meteo sends for a name nothing matches -- an empty list,
// not an error.
function parseSearch(body) {
  var payload
  try {
    payload = JSON.parse(body)
  } catch (e) {
    return { places: [], error: "Open-Meteo sent something that is not JSON." }
  }
  if (!payload || typeof payload !== "object")
    return { places: [], error: "Open-Meteo sent something that is not a list of places." }
  var raw = payload.results
  if (!raw || raw.length === undefined) return { places: [], error: "" }

  var out = []
  for (var i = 0; i < raw.length; i++) {
    var place = readPlace(raw[i])
    if (place) out.push(place)
  }
  return { places: out, error: "" }
}

function readPlace(record) {
  if (!record || typeof record !== "object") return null
  var name = text(record.name)
  var lat = num(record.latitude)
  var lon = num(record.longitude)
  if (!name || lat === null || lon === null) return null
  return {
    id: placeId(lat, lon),
    name: name,
    admin: text(record.admin1),
    country: text(record.country),
    lat: lat,
    lon: lon
  }
}

// Three decimal places is about a hundred metres, which is closer than any
// weather model resolves and far enough apart that two towns of the same name
// are two rows. It is also why the id is coordinates rather than the geoname
// number: a place typed in from a map has no geoname number, and the cache is
// keyed on this.
function placeId(lat, lon) {
  return fixed(lat, 3) + "," + fixed(lon, 3)
}

// --- where the phone is --------------------------------------------------

// Returns { place: {...}, error: "" }. The place is the same shape a search
// result is, so everything downstream of it -- the id, the cache, `where()` --
// cannot tell a town that was typed from one that was looked up.
function parseLocation(body) {
  var payload
  try {
    payload = JSON.parse(body)
  } catch (e) {
    return { place: null, error: "GeoJS sent something that is not JSON." }
  }
  if (!payload || typeof payload !== "object")
    return { place: null, error: "GeoJS sent something that is not a place." }

  var lat = coordinate(payload.latitude, 90)
  var lon = coordinate(payload.longitude, 180)
  // Nought and nought is where a lookup that knows nothing puts a phone: the
  // Gulf of Guinea, whose weather is nobody's.
  if (lat === null || lon === null || (lat === 0 && lon === 0))
    return { place: null, error: "GeoJS could not tell where this connection is." }
  // An address that resolves to a country and no town is that country's
  // middle, and the forecast for the middle of Germany is not a forecast for
  // anybody in it.
  var name = text(payload.city)
  if (!name)
    return { place: null, error: "GeoJS knows the country but not the town." }

  return {
    place: {
      id: placeId(lat, lon),
      name: name,
      admin: text(payload.region),
      country: text(payload.country),
      lat: lat,
      lon: lon
    },
    error: ""
  }
}

// GeoJS sends coordinates as strings. `Number("")` is nought rather than a
// failure, which is the one conversion here that would quietly put a phone on
// the equator, so an empty string is refused before it gets that far.
function coordinate(value, limit) {
  var n = typeof value === "string" && value.trim().length ? Number(value) : num(value)
  if (n === null || !isFinite(n) || Math.abs(n) > limit) return null
  return n
}

// --- the numbers as somebody reads them ----------------------------------

function toF(celsius) { return celsius * 9 / 5 + 32 }
function toMph(kmh) { return kmh * 0.621371 }

function degrees(celsius, units) {
  var c = num(celsius)
  if (c === null) return null
  return Math.round(units === "imperial" ? toF(c) : c)
}

// "18°" and not "18 °C": the unit is on the screen once, in the tile that says
// which it is, and a forecast is forty temperatures.
function temperature(celsius, units) {
  var d = degrees(celsius, units)
  return d === null ? DASH : d + "°"
}

function windText(kmh, units) {
  var v = num(kmh)
  if (v === null) return DASH
  return units === "imperial"
    ? Math.round(toMph(v)) + " mph"
    : Math.round(v) + " km/h"
}

function compass(degreesFrom) {
  var d = num(degreesFrom)
  if (d === null) return ""
  var i = Math.round(((d % 360) + 360) % 360 / 22.5) % 16
  return COMPASS[i]
}

function percent(value) {
  var v = num(value)
  return v === null ? "" : Math.round(v) + "%"
}

function pad2(n) { return n < 10 ? "0" + n : String(n) }

// The place's clock, not the phone's. Both times are read with the UTC
// accessors on purpose: `t + offset` is already the local wall clock, and
// asking a Date for its local hours would apply the phone's own offset a
// second time.
function clock(seconds, offset) {
  var t = num(seconds)
  if (t === null) return DASH
  var d = new Date((t + (Number(offset) || 0)) * 1000)
  return pad2(d.getUTCHours()) + ":" + pad2(d.getUTCMinutes())
}

function hourLabel(seconds, offset, now) {
  var t = num(seconds)
  if (t === null) return DASH
  if (now !== undefined && isNow(t, now)) return "Now"
  var d = new Date((t + (Number(offset) || 0)) * 1000)
  return pad2(d.getUTCHours()) + ":00"
}

// The hour a moment falls in. Not `sameHour`: India is half an hour off UTC
// and Nepal three quarters, so the series there is on the half hour and two
// readings an hour apart can share a UTC hour. An hour-long window either side
// of a reading is the question actually being asked.
function isNow(seconds, now) {
  var t = Number(now) || 0
  return t >= seconds && t < seconds + 3600
}

function dayLabel(seconds, offset, now) {
  var t = num(seconds)
  if (t === null) return DASH
  if (now !== undefined && sameDay(t, now, offset)) return "Today"
  var d = new Date((t + (Number(offset) || 0)) * 1000)
  return DAY_NAMES[d.getUTCDay()]
}

function sameDay(a, b, offset) {
  return Math.floor((a + (Number(offset) || 0)) / 86400)
       === Math.floor((b + (Number(offset) || 0)) / 86400)
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

// --- what the screen asks for --------------------------------------------

// The hours from the one we are in, forward. Not the hours after now: at 14:40
// the useful first column is 14:00, because that is the hour it currently is.
function nextHours(forecast, now, count) {
  if (!forecast || !forecast.hourly) return []
  var out = []
  var floor = Math.floor((Number(now) || 0) / 3600) * 3600
  for (var i = 0; i < forecast.hourly.length; i++) {
    var hour = forecast.hourly[i]
    if (hour.time < floor) continue
    out.push(hour)
    if (out.length >= (count || STRIP_HOURS)) break
  }
  return out
}

function days(forecast, now) {
  if (!forecast || !forecast.daily) return []
  var out = []
  var offset = forecast.offset || 0
  // `time` in the daily series is local midnight, so shifting by the offset
  // and dividing gives the day number the place itself would use. A day before
  // today is dropped, which is what keeps a cache read at 01:00 from opening
  // on yesterday.
  var todayIndex = Math.floor(((Number(now) || 0) + offset) / 86400)
  for (var i = 0; i < forecast.daily.length; i++) {
    var day = forecast.daily[i]
    if (Math.floor((day.time + offset) / 86400) < todayIndex) continue
    out.push(day)
  }
  return out
}

function today(forecast, now) {
  if (!forecast || !forecast.daily) return null
  for (var i = 0; i < forecast.daily.length; i++)
    if (sameDay(forecast.daily[i].time, now, forecast.offset || 0)) return forecast.daily[i]
  return forecast.daily.length ? forecast.daily[0] : null
}

// The week's coldest and warmest, which is what every row's bar is measured
// against. One scale for the list, so a bar that is further right is a warmer
// day -- per-row scaling would draw every day the same and mean nothing.
function span(list) {
  var low = null, high = null
  for (var i = 0; i < (list || []).length; i++) {
    if (low === null || list[i].low < low) low = list[i].low
    if (high === null || list[i].high > high) high = list[i].high
  }
  if (low === null) return { low: 0, high: 1 }
  // A week with one temperature in it would divide by nothing.
  if (high - low < 1) high = low + 1
  return { low: low, high: high }
}

// Where a day's range sits in the week's, as two fractions of the bar.
function bar(day, range) {
  var width = range.high - range.low
  var from = (day.low - range.low) / width
  var to = (day.high - range.low) / width
  return { from: Math.max(0, Math.min(1, from)), to: Math.max(0, Math.min(1, to)) }
}

// What it is doing now: the `current` block while it still describes this
// hour, and the hourly series after that. The fallback is what lets a forecast
// fetched before a tunnel still say something true on the other side of it --
// at the cost of the three things only `current` carries, which is why the
// tiles under the hero come and go with it.
//
// Within an hour either way, rather than in the same hour. Open-Meteo's
// `current` is a fifteen-minute observation -- `"interval": 900` -- so at ten
// to nine it is stamped 20:45 and the hour being drawn starts at 20:00.
// Comparing the two as hours puts the reading in the future and quietly drops
// to the series, which has no wind, no humidity and no apparent temperature in
// it. Found against the live API; the fixture had it on the hour.
function readingAt(forecast, now) {
  if (!forecast) return null
  var t = Number(now) || 0
  if (forecast.current && Math.abs(forecast.current.time - t) < 3600) return forecast.current
  var hours = forecast.hourly || []
  for (var i = 0; i < hours.length; i++) {
    if (!isNow(hours[i].time, t)) continue
    return {
      time: hours[i].time, temp: hours[i].temp, feels: null, humidity: null,
      precip: null, code: hours[i].code, wind: null, from: null, day: hours[i].day
    }
  }
  // Older than the series it came with: the last thing known, which the header
  // is already saying the age of.
  return forecast.current || null
}

// How old the cache may be before the next fetch, in seconds.
function refreshAfter() {
  return REFRESH_S
}

// --- the tiles under the hero --------------------------------------------

// Wind, humidity and the two ends of the day, in the order somebody asks for
// them. A reading with nothing in a field leaves the tile out rather than
// printing a dash: four tiles of "—" is a row that says the app is broken,
// where three tiles says the model did not report the fourth.
function facts(reading, day, offset, units) {
  var out = []
  if (reading && reading.wind !== null && reading.wind !== undefined)
    out.push({ label: "Wind", value: windText(reading.wind, units), note: compass(reading.from) })
  if (reading && reading.humidity !== null && reading.humidity !== undefined)
    out.push({ label: "Humidity", value: percent(reading.humidity), note: "" })
  if (day && day.sunrise !== null && day.sunrise !== undefined)
    out.push({ label: "Sunrise", value: clock(day.sunrise, offset), note: "" })
  if (day && day.sunset !== null && day.sunset !== undefined)
    out.push({ label: "Sunset", value: clock(day.sunset, offset), note: "" })
  return out
}

// The line under the condition: what it feels like, and the day's two ends.
// "Feels like" is left out when it agrees with the temperature to the degree,
// which is most of the time and is a line saying nothing.
function heroNote(reading, day, units) {
  var parts = []
  if (reading && reading.feels !== null && reading.feels !== undefined
      && degrees(reading.feels, units) !== degrees(reading.temp, units))
    parts.push("Feels like " + temperature(reading.feels, units))
  if (day) parts.push(temperature(day.high, units) + " / " + temperature(day.low, units))
  return parts.join("  ·  ")
}

// Where a place is, in the one line a list row has for it. The country on its
// own for a capital, the region as well when there is one, because half the
// answers to "Springfield" are in the same country as each other.
function where(place) {
  if (!place) return ""
  var parts = []
  if (place.admin && place.admin !== place.name) parts.push(place.admin)
  if (place.country) parts.push(place.country)
  return parts.join(", ")
}
