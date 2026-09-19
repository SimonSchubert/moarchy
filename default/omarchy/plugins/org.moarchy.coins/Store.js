// The two files the GTK app already writes, in the same shape.
//
// ~/.local/share/moarchy-coins/favourites.json is the only thing in this app a
// person made; market.json is the last answer CoinGecko gave and is disposable
// by definition. A coin starred here is a coin starred there.
//
// Same schema, same keys, same one-space indent as store.py's
// `json.dump(indent=1)`, so either half can read what the other wrote and a
// phone with both installed loses nothing in either direction. Checked by
// handing Python a cache this file produced.
//
// Not byte-identical, and it is worth saying which way: Python writes a whole
// float as `77243.0` and JSON.stringify writes `77243`. Both readers take
// either -- store.py's guards are `isinstance(x, (int, float))` -- so this is a
// difference in the file and not in what it means. Anything that ever diffs the
// two files rather than parsing them would be measuring the wrong thing.
.pragma library

var SCHEMA = 1

// Two hundred is more coins than anybody watches and small enough that the file
// stays a file rather than a database.
var MAX_FAVOURITES = 200

var CURRENCY = "usd"

function parseFavourites(data) {
  var out = []
  if (!data) return out
  var raw = data.favourites
  if (!raw || raw.constructor !== Array) return out
  for (var i = 0; i < raw.length && out.length < MAX_FAVOURITES; i++) {
    var id = raw[i]
    // Duplicates would draw a coin twice on the starred page and toggle half
    // of it at a time.
    if (typeof id === "string" && id && out.indexOf(id) < 0) out.push(id)
  }
  return out
}

function serializeFavourites(favourites) {
  return JSON.stringify({ schema: SCHEMA, favourites: favourites || [] }, null, 1)
}

// One coin back out of our own cache, which is deliberately not the same reader
// as Market.parse: that one reads CoinGecko's shape and this reads ours, and
// folding them together would mean a change to the API's field names quietly
// rewriting what a cache written last week means.
function coinFrom(data) {
  if (!data || typeof data !== "object") return null
  var id = data.id
  if (typeof id !== "string" || !id) return null
  var price = typeof data.price === "number" && isFinite(data.price) ? data.price : null
  if (price === null || price <= 0) return null
  var rank = typeof data.rank === "number" && isFinite(data.rank) ? Math.round(data.rank) : 0
  var change = typeof data.change === "number" && isFinite(data.change) ? data.change : null
  var cap = typeof data.cap === "number" && isFinite(data.cap) ? data.cap : 0
  return {
    id: id,
    symbol: String(data.symbol || ""),
    name: String(data.name || id),
    rank: rank,
    price: price,
    change: change,
    cap: cap,
    // Additive, and safe for the other half: store.py's Coin.from_dict reads
    // the keys it names with .get() and ignores the rest, so a cache written
    // here still loads there. Kept so a cold start knows where to fetch a
    // missing logo without waiting for the next market refresh.
    image: typeof data.image === "string" ? data.image : ""
  }
}

function parseMarket(data) {
  var empty = { coins: [], fetched: 0, currency: CURRENCY }
  if (!data) return empty
  var records = data.coins
  if (!records || records.constructor !== Array) return empty
  var coins = []
  for (var i = 0; i < records.length; i++) {
    var coin = coinFrom(records[i])
    if (coin) coins.push(coin)
  }
  var currency = typeof data.currency === "string" ? data.currency.toLowerCase() : CURRENCY
  var fetched = typeof data.fetched === "number" && isFinite(data.fetched) ? data.fetched : 0
  return { coins: coins, fetched: fetched, currency: currency }
}

function serializeMarket(coins, fetched, currency) {
  var out = []
  for (var i = 0; i < coins.length; i++) {
    var c = coins[i]
    out.push({
      id: c.id, symbol: c.symbol, name: c.name, rank: c.rank,
      price: c.price, change: c.change === undefined ? null : c.change, cap: c.cap,
      image: c.image || ""
    })
  }
  return JSON.stringify({
    schema: SCHEMA,
    currency: currency || CURRENCY,
    fetched: fetched,
    coins: out
  }, null, 1)
}

// Star or unstar. `full` rather than a thrown error, because the only caller
// draws it as a line of text.
function toggle(favourites, id) {
  var list = (favourites || []).slice()
  var at = list.indexOf(id)
  if (at >= 0) {
    list.splice(at, 1)
    return { favourites: list, starred: false, full: false }
  }
  if (list.length >= MAX_FAVOURITES)
    return { favourites: favourites || [], starred: false, full: true }
  list.push(id)
  return { favourites: list, starred: true, full: false }
}

// Take a fetch, keeping at most one row per coin.
//
// The two requests can overlap -- the second asks for coins by name and the
// first may already have answered for one of them -- so the later record wins.
// A coin that came back from the second request keeps its real rank, so a
// starred coin that has fallen to 187th sorts to the end of the market page
// rather than into the middle of the top hundred.
function replace(existing, arriving) {
  var seen = {}
  var order = []
  for (var i = 0; i < arriving.length; i++) {
    var coin = arriving[i]
    if (seen[coin.id] === undefined) order.push(coin.id)
    seen[coin.id] = coin
  }
  var out = []
  for (var j = 0; j < order.length; j++) out.push(seen[order[j]])
  out.sort(function (a, b) { return a.rank - b.rank })
  return out
}
