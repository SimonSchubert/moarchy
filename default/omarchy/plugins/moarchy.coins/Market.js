// The market: what CoinGecko says, and what a phone can do with it.
//
// The port of apps/coins/moarchy_coins/market.py, and the same split it makes:
// nothing here touches QML, so the half of this app that can be wrong --
// parsing somebody else's JSON, and turning a number into the string a person
// reads -- is testable with no display, exactly as the Python half was.
//
// The numbers are the interesting part and they are ported literally rather
// than approximated: a price is grouped and rounded the same way, a cap gets
// the same three significant figures, and a change always carries its sign
// because roughly one man in twelve cannot tell this app's green from its red.
.pragma library

var API = "https://api.coingecko.com/api/v3/coins/markets"

// Who is asking. An app that names itself is one whose traffic can be
// recognised and blocked on its own rather than with every other keyless
// caller.
var AGENT = "moarchy-coins/0.1.1 (+https://github.com/SimonSchubert/moarchy-apps)"

var TIMEOUT = 12
var TOP = 100
var PER_PAGE_MAX = 250
var CURRENCY = "usd"

// CoinGecko's keyless limit is a handful of calls a minute per address, so a
// minute or two is the difference between being let back in and being refused
// again.
var RATE_LIMIT_S = 120

// A minute is the interval a coin tracker is worth having at.
var REFRESH_S = 60

// Larger than any list this app asks for, so an unranked coin sorts to the end
// rather than into the middle, and small enough to stay three digits in the
// disc it is drawn in.
var UNRANKED = 999

// An em dash rather than "0" or "n/a": a missing 24-hour change and a flat one
// are different facts, and a column of zeroes would be a lie told in the same
// typeface as the truth.
var DASH = "—"

var BIG = 10000
var SMALL = 0.01
var FIGURES = 4
var MAX_PLACES = 10

var SIGNS = {
  usd: "$", eur: "€", gbp: "£", jpy: "¥", cny: "¥",
  inr: "₹", krw: "₩", rub: "₽", btc: "₿"
}

var UNITS = [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "K"]]

// --- numbers as somebody reads them --------------------------------------

// Python's format spec does the thousands separator with `,`; V4 has no such
// spec and Intl is not worth depending on inside a shell, so the grouping is
// done by hand on the integer side only.
function group(digits) {
  var out = ""
  var n = String(digits)
  for (var i = 0; i < n.length; i++) {
    if (i > 0 && (n.length - i) % 3 === 0) out += ","
    out += n[i]
  }
  return out
}

function fixed(value, places) {
  var s = value.toFixed(places)
  var dot = s.indexOf(".")
  var whole = dot < 0 ? s : s.slice(0, dot)
  var rest = dot < 0 ? "" : s.slice(dot)
  return group(whole) + rest
}

function sign(currency) {
  var code = String(currency || CURRENCY).toLowerCase()
  return SIGNS[code] !== undefined ? SIGNS[code] : code.toUpperCase() + " "
}

// A price with as many decimals as it has significant digits, near zero. A coin
// at 0.0000132 has four figures worth reading and they all sit past the fourth
// decimal place, so a fixed two -- or a fixed eight -- is either a row of
// zeroes or a row of noise.
function places(value) {
  if (value >= BIG) return fixed(value, 0)
  if (value >= 1) return fixed(value, 2)
  if (value >= SMALL) return value.toFixed(4)
  var leading = Math.floor(-Math.log(value) / Math.LN10)
  return value.toFixed(Math.min(leading + FIGURES, MAX_PLACES))
}

function money(value, currency) {
  if (value === null || value === undefined || !(value > 0)) return DASH
  return sign(currency) + places(value)
}

// A market cap: three significant figures and a letter. $1.55 T rather than
// $1,551,224,442,911, which is twenty characters of a 360px row spent on digits
// that change every second and mean nothing individually.
function compact(value, currency) {
  if (value === null || value === undefined || !(value > 0)) return DASH
  for (var i = 0; i < UNITS.length; i++) {
    var scale = UNITS[i][0], suffix = UNITS[i][1]
    if (value >= scale) {
      var scaled = value / scale
      var dp = scaled < 10 ? 2 : (scaled < 100 ? 1 : 0)
      return sign(currency) + scaled.toFixed(dp) + " " + suffix
    }
  }
  return sign(currency) + fixed(value, 0)
}

// Always signed. The colour says up or down too, and the colour is the half a
// person sees first -- but for anyone who cannot tell them apart the sign is
// the answer.
function percent(value) {
  if (value === null || value === undefined) return DASH
  var s = Math.abs(value).toFixed(2)
  return (value < 0 ? "-" : "+") + s + "%"
}

function direction(value) {
  if (value === null || value === undefined) return "flat"
  // Under half a hundredth rounds to +0.00%, and a plus sign in green over a
  // number that is not moving is a claim the figure beside it does not make.
  if (value >= 0.005) return "up"
  if (value <= -0.005) return "down"
  return "flat"
}

// A clock that has gone backwards -- a phone that has just picked up NTP after
// being off for a week -- reads as "just now" rather than as a negative number.
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

// --- CoinGecko's shape ----------------------------------------------------

// `typeof true === "boolean"`, so a bool cannot arrive here as 1 and be drawn
// as a dollar the way Python's isinstance(True, int) would have allowed.
function number(value) {
  if (typeof value !== "number" || !isFinite(value)) return null
  return value
}

// In an ordered answer the rank is where the coin sat in it, and
// `market_cap_rank` is ignored: that field disagrees with the ordering it
// arrives in, and drawn faithfully it gives a list numbered 8, 9, 9, 10, which
// reads as a broken app rather than as a quirk of somebody else's field.
function parse(record, position, ordered) {
  if (!record || typeof record !== "object") return null
  var id = record.id
  var price = number(record.current_price)
  if (typeof id !== "string" || !id || price === null || price <= 0) return null
  var rank
  if (ordered === false) {
    var reported = number(record.market_cap_rank)
    rank = reported && reported > 0 ? Math.round(reported) : UNRANKED
  } else {
    rank = position
  }
  return {
    id: id,
    symbol: String(record.symbol || "").slice(0, 8).toUpperCase(),
    name: String(record.name || id),
    rank: rank,
    price: price,
    change: number(record.price_change_percentage_24h),
    cap: number(record.market_cap) || 0,
    image: iconUrl(record.image)
  }
}

function parseMarkets(text, ordered) {
  var payload
  try {
    payload = JSON.parse(String(text || ""))
  } catch (e) {
    return { error: "CoinGecko sent something this app cannot read.", coins: [] }
  }
  if (!payload || payload.constructor !== Array)
    return { error: "CoinGecko sent something that is not a list of coins.", coins: [] }
  var coins = []
  for (var i = 0; i < payload.length; i++) {
    var coin = parse(payload[i], i + 1, ordered)
    if (coin) coins.push(coin)
  }
  // Every row unusable is not "a quiet market": it is the shape of the answer
  // having changed, and saying so beats drawing an empty list.
  if (!coins.length && payload.length)
    return { error: "CoinGecko sent coins in a shape this app cannot read.", coins: [] }
  return { error: "", coins: coins }
}

function url(currency, count, ids) {
  var per = Math.max(1, Math.min(count || TOP, PER_PAGE_MAX))
  var q = "vs_currency=" + encodeURIComponent(String(currency || CURRENCY).toLowerCase())
        + "&order=market_cap_desc"
        + "&per_page=" + per
        + "&page=1"
        // No sparkline: 168 hourly prices per coin, seven times the size of the
        // whole rest of the answer, for a chart this app does not draw.
        + "&sparkline=false"
        + "&price_change_percentage=24h"
        + "&locale=en"
  if (ids && ids.length) q += "&ids=" + encodeURIComponent(ids.join(","))
  return API + "?" + q
}

// The front of the symbol, or the front of any word in the name. Not a
// substring anywhere: "itc" matching Bitcoin means a search box that fills with
// coincidences. Any *word*, because "cash" has to find Bitcoin Cash and "inu"
// has to find Shiba Inu.
function matches(coin, query) {
  var text = String(query || "").trim().toLowerCase()
  if (!text) return true
  if (String(coin.symbol || "").toLowerCase().indexOf(text) === 0) return true
  var words = String(coin.name || "").toLowerCase().split(/\s+/)
  for (var i = 0; i < words.length; i++)
    if (words[i].indexOf(text) === 0) return true
  return false
}

function filter(coins, query) {
  var out = []
  for (var i = 0; i < coins.length; i++)
    if (matches(coins[i], query)) out.push(coins[i])
  return out
}

// The starred coins, in the order they were starred -- not in rank order, which
// is the obvious alternative and is wrong on a phone: a watchlist sorted by
// market cap reorders itself under a thumb halfway down it.
//
// A star with no price behind it is left out rather than drawn as a row of
// dashes, which lasts exactly as long as it takes the next fetch to ask for it
// by name.
function starred(coins, favourites, query) {
  var known = {}
  for (var i = 0; i < coins.length; i++) known[coins[i].id] = coins[i]
  var out = []
  for (var j = 0; j < favourites.length; j++) {
    var coin = known[favourites[j]]
    if (coin && matches(coin, query)) out.push(coin)
  }
  return out
}

// Starred coins the last answer did not cover, which is what the second request
// exists for: a coin can only be starred from the top hundred, but it can fall
// out of it afterwards, and a watchlist quietly showing last week's price is
// worse than one that says it cannot.
function missing(coins, favourites) {
  var known = {}
  for (var i = 0; i < coins.length; i++) known[coins[i].id] = true
  var out = []
  for (var j = 0; j < favourites.length; j++)
    if (!known[favourites[j]]) out.push(favourites[j])
  return out
}

// --- the coin's own logo --------------------------------------------------

// theme.py argued against logos on three grounds: a hundred requests to a CDN,
// each one telling that CDN which coins somebody watches, for pictures 24px
// wide. Two of the three have answers and the measurements are why:
//
//   * The URL arrives in the market answer already, so finding it costs no
//     request at all -- market.py simply dropped the field.
//   * `small` is 50x50 and about 2.5 kB, so the whole top hundred is ~245 kB
//     once and then never again. `large`, which is what the API hands over, is
//     12 kB each and 1.2 MB the set -- which is the version of this that
//     deserved to be refused.
//   * Every coin in the list is fetched, not the starred ones: asking for all
//     hundred says exactly what asking for the top hundred already said, while
//     asking for four would name the four. The privacy objection argues for
//     fetching *more*, not less.
//
// What stays true is the last one: at 36 points a logo is a smudge for many
// coins. So the disc is not replaced, it is what shows until a file is there --
// and on a phone that has never been online, it is all there ever is.
var ICON_SIZE = "small"

// The API hands over the 250px one. The path segment is the size, so this is a
// rewrite rather than a second request to discover a smaller variant.
function iconUrl(url) {
  var s = String(url || "")
  if (!s) return ""
  if (s.indexOf("/large/") < 0) return s
  return s.replace("/large/", "/" + ICON_SIZE + "/")
}

// The file a coin's logo is cached at. Keyed by id and not by the URL's own
// name, because the id is what the row already has and what the cache file
// already carries -- and because two coins can ship a `logo.png`.
function iconFile(coinId) {
  return String(coinId).replace(/[^A-Za-z0-9._-]/g, "_") + ".png"
}

// --- the disc a coin wears ------------------------------------------------

// The eight hue roles a theme names, as the eight discs a coin can wear. All of
// them rather than a chosen few: with a hundred rows on the page the point is
// that two coins next to each other are unlikely to match, and dropping the
// awkward hues would make that likelier rather than the list prettier.
var BADGE_HUES = ["blue", "cyan", "magenta", "orange", "green", "yellow", "brown", "red"]

// How much of the hue goes into the disc. Solid enough to tell eight of them
// apart at arm's length, pale enough that the theme's own text colour reads on
// top of it in both a light theme and a dark one.
var BADGE_TINT = 0.28

var CRC_TABLE = null

function crcTable() {
  if (CRC_TABLE) return CRC_TABLE
  var table = []
  for (var n = 0; n < 256; n++) {
    var c = n
    for (var k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1)
    table[n] = c >>> 0
  }
  CRC_TABLE = table
  return table
}

// zlib.crc32 of the UTF-8 bytes, which is what theme.py uses -- and it uses it
// rather than a hash because Python's hash() is salted per process and would
// give a coin a different colour on every launch, turning the one property this
// is for ("my coin is the blue one") into noise. Ported rather than replaced so
// a phone with both halves installed draws one coin one colour.
function crc32(text) {
  var table = crcTable()
  var crc = 0xFFFFFFFF
  var s = String(text)
  for (var i = 0; i < s.length; i++) {
    var code = s.charCodeAt(i)
    // UTF-8, by hand: the ids are ASCII today, but "shiba-inu" is not a promise
    // and a multibyte id must hash to what Python's .encode("utf-8") hashes to.
    var bytes
    if (code < 0x80) bytes = [code]
    else if (code < 0x800) bytes = [0xC0 | (code >> 6), 0x80 | (code & 0x3F)]
    else bytes = [0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F)]
    for (var b = 0; b < bytes.length; b++)
      crc = table[(crc ^ bytes[b]) & 0xFF] ^ (crc >>> 8)
  }
  return (crc ^ 0xFFFFFFFF) >>> 0
}

function badgeHue(coinId) {
  return BADGE_HUES[crc32(coinId) % BADGE_HUES.length]
}
