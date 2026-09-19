// The two files, against what apps/coins/moarchy_coins/store.py actually wrote.
//
// The strings below were produced by running the Python Store, not by reading
// it. That is what makes this a check that a phone with both halves installed
// keeps its stars, rather than a check that this file agrees with itself.
import QtQuick
import QtTest
import "../Store.js" as Store

TestCase {
  name: "CoinsStore"

  // Straight out of store.py: json.dump(indent=1).
  readonly property string pyFavourites:
    '{\n "schema": 1,\n "favourites": [\n  "ethereum",\n  "bitcoin"\n ]\n}'

  readonly property string pyMarket:
    '{\n "schema": 1,\n "currency": "usd",\n "fetched": 1757930000.0,\n "coins": [\n' +
    '  {\n   "id": "bitcoin",\n   "symbol": "BTC",\n   "name": "Bitcoin",\n   "rank": 1,\n' +
    '   "price": 77243.0,\n   "change": 4.79,\n   "cap": 1551224442911.0\n  },\n' +
    '  {\n   "id": "zcash",\n   "symbol": "ZEC",\n   "name": "Zcash",\n   "rank": 9,\n' +
    '   "price": 180.0,\n   "change": null,\n   "cap": 17800000000.0\n  }\n ]\n}'

  function test_a_file_python_wrote_reads_here() {
    var favs = Store.parseFavourites(JSON.parse(pyFavourites))
    compare(favs.length, 2)
    // The order they were starred in, which is the ordering the page is drawn
    // in and the only one a person controls.
    compare(favs[0], "ethereum")
    compare(favs[1], "bitcoin")
  }

  function test_a_cache_python_wrote_reads_here() {
    var m = Store.parseMarket(JSON.parse(pyMarket))
    compare(m.coins.length, 2)
    compare(m.currency, "usd")
    compare(m.fetched, 1757930000)
    compare(m.coins[0].id, "bitcoin")
    compare(m.coins[0].price, 77243)
    compare(m.coins[0].change, 4.79)
    // A null change survives as null rather than becoming zero.
    compare(m.coins[1].change, null)
  }

  function test_what_we_write_is_the_same_document() {
    // Not byte-identical -- Python writes 77243.0 where JSON.stringify writes
    // 77243 -- so the check is that the parsed document matches, which is what
    // both readers actually consume.
    var mine = Store.serializeFavourites(["ethereum", "bitcoin"])
    compare(JSON.stringify(JSON.parse(mine)), JSON.stringify(JSON.parse(pyFavourites)))
    // The indent is still one space, so a person looking at the file on the
    // phone sees the same shape whichever half last wrote it.
    verify(mine.indexOf('\n "schema": 1,') === 0 || mine.indexOf('{\n "schema": 1') === 0)
  }

  function test_a_cache_we_write_round_trips() {
    var coins = [{ id: "bitcoin", symbol: "BTC", name: "Bitcoin", rank: 1,
                   price: 77243.0, change: 4.79, cap: 1551224442911.0,
                   image: "https://coin-images.coingecko.com/coins/images/1/small/bitcoin.png" },
                 { id: "zcash", symbol: "ZEC", name: "Zcash", rank: 9,
                   price: 180.0, change: null, cap: 17800000000.0, image: "" }]
    var back = Store.parseMarket(JSON.parse(Store.serializeMarket(coins, 1757930000, "usd")))
    compare(JSON.stringify(back.coins), JSON.stringify(coins))
    compare(back.fetched, 1757930000)
  }

  function test_a_python_cache_with_no_image_key_still_reads() {
    // The field is ours and newer than store.py, so every cache written before
    // it -- and every cache the GTK half writes today -- lacks it entirely.
    var m = Store.parseMarket(JSON.parse(pyMarket))
    compare(m.coins[0].image, "")
    // And what we write stays readable to the half that does not know the key:
    // store.py's Coin.from_dict names the keys it wants and ignores the rest.
    var written = JSON.parse(Store.serializeMarket(m.coins, 1, "usd"))
    compare(written.coins[0].id, "bitcoin")
    compare(written.schema, 1)
  }

  function test_an_absent_file_is_no_stars_rather_than_a_crash() {
    compare(Store.parseFavourites(null).length, 0)
    compare(Store.parseFavourites({}).length, 0)
    compare(Store.parseFavourites({ favourites: "bitcoin" }).length, 0)
    compare(Store.parseMarket(null).coins.length, 0)
    compare(Store.parseMarket({}).fetched, 0)
  }

  function test_duplicates_are_dropped_on_the_way_in() {
    // A duplicate would draw a coin twice on the starred page and toggle half
    // of it at a time.
    var favs = Store.parseFavourites({ favourites: ["a", "b", "a", "", null, "c"] })
    compare(favs.length, 3)
    compare(favs.join(","), "a,b,c")
  }

  function test_a_coin_with_no_price_is_dropped_from_the_cache() {
    var m = Store.parseMarket({ coins: [
      { id: "ok", symbol: "OK", name: "Ok", rank: 1, price: 2, change: 0, cap: 1 },
      { id: "nope", symbol: "NO", name: "No", rank: 2, price: 0, change: 0, cap: 1 },
      { id: "", symbol: "X", name: "X", rank: 3, price: 1, change: 0, cap: 1 },
      "not a coin"
    ] })
    compare(m.coins.length, 1)
    compare(m.coins[0].id, "ok")
  }

  function test_toggle_adds_and_removes() {
    var r1 = Store.toggle([], "bitcoin")
    compare(r1.starred, true)
    compare(r1.favourites.join(","), "bitcoin")
    var r2 = Store.toggle(r1.favourites, "bitcoin")
    compare(r2.starred, false)
    compare(r2.favourites.length, 0)
  }

  function test_toggle_does_not_mutate_what_it_was_given() {
    var before = ["a"]
    Store.toggle(before, "b")
    compare(before.length, 1)
  }

  function test_the_star_list_has_a_ceiling() {
    var full = []
    for (var i = 0; i < Store.MAX_FAVOURITES; i++) full.push("coin" + i)
    var r = Store.toggle(full, "one-more")
    compare(r.full, true)
    compare(r.favourites.length, Store.MAX_FAVOURITES)
  }

  function test_replace_keeps_one_row_per_coin_and_sorts_by_rank() {
    // The two requests overlap: the later record wins, and a starred coin that
    // has fallen to 187th sorts to the end rather than into the middle.
    var out = Store.replace([], [
      { id: "b", rank: 2, price: 1 },
      { id: "a", rank: 1, price: 1 },
      { id: "b", rank: 187, price: 9 },
      { id: "c", rank: 3, price: 1 }
    ])
    compare(out.length, 3)
    compare(out[0].id, "a")
    compare(out[1].id, "c")
    compare(out[2].id, "b")
    compare(out[2].rank, 187)
    compare(out[2].price, 9)
  }
}
