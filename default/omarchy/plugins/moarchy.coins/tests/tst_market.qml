// The numbers, against the strings apps/coins/moarchy_coins/market.py produces.
//
// Every expectation below was taken by running the Python functions rather than
// by reading them, because that is the only way this is a parity test and not a
// second opinion. A price grouped differently, or a cap rounded to a different
// figure, is the kind of difference nobody sees until the two halves disagree
// on a phone.
import QtQuick
import QtTest
import "../Market.js" as Market

TestCase {
  name: "CoinsMarket"

  function test_money_data() {
    return [
      { tag: "big",        value: 77243.0,   text: "$77,243" },
      { tag: "just under", value: 9999.99,   text: "$9,999.99" },
      { tag: "round",      value: 2500.0,    text: "$2,500.00" },
      { tag: "one",        value: 1.0,       text: "$1.00" },
      { tag: "under one",  value: 0.9999,    text: "$0.9999" },
      { tag: "half",       value: 0.5,       text: "$0.5000" },
      { tag: "at SMALL",   value: 0.01,      text: "$0.0100" },
      { tag: "below",      value: 0.0099,    text: "$0.009900" },
      { tag: "tiny",       value: 0.0000132, text: "$0.00001320" },
      { tag: "millions",   value: 1234567.0, text: "$1,234,567" },
      { tag: "clamped",    value: 5e-10,     text: "$0.0000000005" }
    ]
  }
  function test_money(row) { compare(Market.money(row.value, "usd"), row.text) }

  function test_compact_data() {
    return [
      { tag: "trillions",   value: 1551224442911.0, text: "$1.55 T" },
      { tag: "billions 1dp", value: 9900000000.0,   text: "$9.90 B" },
      { tag: "billions 2sf", value: 55500000000.0,  text: "$55.5 B" },
      { tag: "billions 3sf", value: 155000000000.0, text: "$155 B" },
      { tag: "millions",     value: 999400000.0,    text: "$999 M" },
      { tag: "thousands",    value: 12345.0,        text: "$12.3 K" }
    ]
  }
  function test_compact(row) { compare(Market.compact(row.value, "usd"), row.text) }

  function test_percent_data() {
    return [
      { tag: "up",      value: 4.79,   text: "+4.79%", way: "up" },
      { tag: "down",    value: -3.19,  text: "-3.19%", way: "down" },
      { tag: "zero",    value: 0.0,    text: "+0.00%", way: "flat" },
      // Under half a hundredth rounds to +0.00%, and a plus sign in green over
      // a number that is not moving is a claim the figure does not make.
      { tag: "barely up",   value: 0.004,  text: "+0.00%", way: "flat" },
      { tag: "barely down", value: -0.004, text: "-0.00%", way: "flat" },
      { tag: "rounds up",   value: 12.345, text: "+12.35%", way: "up" }
    ]
  }
  function test_percent(row) {
    compare(Market.percent(row.value), row.text)
    compare(Market.direction(row.value), row.way)
  }

  function test_a_missing_number_is_a_dash_not_a_zero() {
    // A missing 24-hour change and a flat one are different facts.
    compare(Market.percent(null), "—")
    compare(Market.direction(null), "flat")
    compare(Market.money(null, "usd"), "—")
    compare(Market.money(0, "usd"), "—")
    compare(Market.money(-1, "usd"), "—")
    compare(Market.compact(null, "usd"), "—")
    compare(Market.compact(0, "usd"), "—")
  }

  function test_freshness_data() {
    return [
      { tag: "0",      s: 0,      text: "just now" },
      { tag: "59",     s: 59,     text: "just now" },
      { tag: "60",     s: 60,     text: "1 min ago" },
      { tag: "3599",   s: 3599,   text: "59 min ago" },
      { tag: "3600",   s: 3600,   text: "1 hour ago" },
      { tag: "7200",   s: 7200,   text: "2 hours ago" },
      { tag: "86399",  s: 86399,  text: "23 hours ago" },
      { tag: "86400",  s: 86400,  text: "yesterday" },
      { tag: "172800", s: 172800, text: "2 days ago" }
    ]
  }
  function test_freshness(row) { compare(Market.freshness(row.s), row.text) }

  function test_sign_data() {
    return [
      { tag: "usd", code: "usd", text: "$" },
      { tag: "eur", code: "eur", text: "€" },
      { tag: "btc", code: "btc", text: "₿" },
      // A currency nobody wrote a symbol for reads as its code rather than
      // silently becoming dollars.
      { tag: "sek", code: "sek", text: "SEK " },
      { tag: "empty", code: "", text: "$" }
    ]
  }
  function test_sign(row) { compare(Market.sign(row.code), row.text) }

  // --- CoinGecko's shape --------------------------------------------------

  readonly property string payload: '[
    {"id":"bitcoin","symbol":"btc","name":"Bitcoin","current_price":77243.0,
     "market_cap":1551224442911,"price_change_percentage_24h":4.79,"market_cap_rank":1},
    {"id":"ethereum","symbol":"eth","name":"Ethereum","current_price":2500.0,
     "market_cap":300000000000,"price_change_percentage_24h":-3.19,"market_cap_rank":9},
    {"id":"zcash","symbol":"zec","name":"Zcash","current_price":180.0,
     "market_cap":17800000000,"price_change_percentage_24h":null,"market_cap_rank":9},
    {"id":"dead","symbol":"dead","name":"Delisted","current_price":null,"market_cap":0}
  ]'

  function test_the_position_is_the_rank_not_the_reported_field() {
    // market_cap_rank disagrees with the ordering it arrives in -- two coins
    // both carrying 9 -- and drawn faithfully that is a list numbered 1, 9, 9,
    // which reads as a broken app rather than as a quirk of somebody's field.
    var got = Market.parseMarkets(payload, true)
    compare(got.error, "")
    compare(got.coins.length, 3)
    compare(got.coins[0].rank, 1)
    compare(got.coins[1].rank, 2)
    compare(got.coins[2].rank, 3)
  }

  function test_a_coin_with_no_price_is_not_a_row() {
    // Every column on the right of the screen is derived from the price.
    var got = Market.parseMarkets(payload, true)
    for (var i = 0; i < got.coins.length; i++) verify(got.coins[i].id !== "dead")
  }

  function test_an_unordered_answer_keeps_each_coins_own_rank() {
    // The second request asks for coins by name, so its positions mean nothing.
    var got = Market.parseMarkets(payload, false)
    compare(got.coins[0].rank, 1)
    compare(got.coins[1].rank, 9)
    compare(got.coins[2].rank, 9)
  }

  function test_an_unranked_coin_sorts_to_the_end() {
    var got = Market.parseMarkets('[{"id":"new","symbol":"new","name":"New","current_price":1.0}]', false)
    compare(got.coins[0].rank, Market.UNRANKED)
  }

  function test_the_symbol_is_upper_case_and_bounded() {
    var got = Market.parseMarkets(payload, true)
    compare(got.coins[0].symbol, "BTC")
    var long = Market.parseMarkets('[{"id":"x","symbol":"abcdefghijkl","name":"X","current_price":1}]', true)
    compare(long.coins[0].symbol.length, 8)
  }

  function test_a_null_change_stays_null_rather_than_becoming_zero() {
    var got = Market.parseMarkets(payload, true)
    compare(got.coins[2].change, null)
    compare(Market.percent(got.coins[2].change), "—")
  }

  function test_a_bool_where_a_price_belongs_is_not_a_dollar() {
    // isinstance(True, int) is True in Python, which is why market.py guards
    // this; typeof true is "boolean" here, and the guard is kept anyway.
    var got = Market.parseMarkets('[{"id":"x","symbol":"x","name":"X","current_price":true}]', true)
    compare(got.coins.length, 0)
    verify(got.error !== "")
  }

  function test_rubbish_is_an_error_not_an_exception() {
    compare(Market.parseMarkets("not json", true).error !== "", true)
    compare(Market.parseMarkets('{"coins":[]}', true).error !== "", true)
    // An empty market is an empty list, not an error.
    compare(Market.parseMarkets("[]", true).error, "")
  }

  // --- search --------------------------------------------------------------

  readonly property var coins: [
    { id: "bitcoin", symbol: "BTC", name: "Bitcoin", rank: 1, price: 1, change: 0, cap: 1 },
    { id: "bitcoin-cash", symbol: "BCH", name: "Bitcoin Cash", rank: 2, price: 1, change: 0, cap: 1 },
    { id: "shiba-inu", symbol: "SHIB", name: "Shiba Inu", rank: 3, price: 1, change: 0, cap: 1 },
    { id: "ethereum", symbol: "ETH", name: "Ethereum", rank: 4, price: 1, change: 0, cap: 1 }
  ]

  function test_search_matches_the_front_of_a_word_not_a_substring() {
    compare(Market.filter(coins, "bit").length, 2)
    // "cash" has to find Bitcoin Cash and "inu" has to find Shiba Inu.
    compare(Market.filter(coins, "cash")[0].id, "bitcoin-cash")
    compare(Market.filter(coins, "inu")[0].id, "shiba-inu")
    // "itc" matching Bitcoin would be a search box full of coincidences.
    compare(Market.filter(coins, "itc").length, 0)
    compare(Market.filter(coins, "eth")[0].id, "ethereum")
    compare(Market.filter(coins, "").length, 4)
  }

  function test_starred_keeps_the_order_they_were_starred_in() {
    // Not rank order: a watchlist sorted by cap reorders itself under a thumb.
    var got = Market.starred(coins, ["ethereum", "bitcoin"], "")
    compare(got.length, 2)
    compare(got[0].id, "ethereum")
    compare(got[1].id, "bitcoin")
  }

  function test_a_star_with_no_price_behind_it_is_left_out() {
    var got = Market.starred(coins, ["ethereum", "gone"], "")
    compare(got.length, 1)
    compare(Market.missing(coins, ["ethereum", "gone"]).length, 1)
    compare(Market.missing(coins, ["ethereum", "gone"])[0], "gone")
  }

  function test_the_url_asks_for_no_sparkline() {
    var u = Market.url("usd", 100)
    verify(u.indexOf("sparkline=false") > 0)
    verify(u.indexOf("per_page=100") > 0)
    verify(u.indexOf("order=market_cap_desc") > 0)
    // 168 hourly prices per coin for a chart this app does not draw.
    verify(u.indexOf("sparkline=true") < 0)
  }

  function test_the_url_clamps_what_it_asks_for() {
    verify(Market.url("usd", 9999).indexOf("per_page=250") > 0)
    verify(Market.url("usd", 0).indexOf("per_page=1") > 0)
  }

  function test_by_ids_names_them() {
    var u = Market.url("usd", 2, ["bitcoin", "ethereum"])
    verify(u.indexOf("ids=bitcoin%2Cethereum") > 0)
  }

  // --- the disc -----------------------------------------------------------

  function test_badge_hue_matches_pythons_crc32_data() {
    // Taken from moarchy_coins.theme.badge_hue, which is zlib.crc32 % 8. If
    // these drift, one coin is two colours on a phone with both halves on it.
    return [
      { tag: "bitcoin",     id: "bitcoin",     hue: "brown" },
      { tag: "ethereum",    id: "ethereum",    hue: "brown" },
      { tag: "tether",      id: "tether",      hue: "blue" },
      { tag: "ripple",      id: "ripple",      hue: "yellow" },
      { tag: "solana",      id: "solana",      hue: "orange" },
      { tag: "dogecoin",    id: "dogecoin",    hue: "magenta" },
      { tag: "monero",      id: "monero",      hue: "yellow" },
      { tag: "chainlink",   id: "chainlink",   hue: "orange" },
      { tag: "usd-coin",    id: "usd-coin",    hue: "orange" },
      { tag: "binancecoin", id: "binancecoin", hue: "green" }
    ]
  }
  function test_badge_hue_matches_pythons_crc32(row) {
    compare(Market.badgeHue(row.id), row.hue)
  }

  function test_crc32_is_the_real_one() {
    // The standard check value, so a broken table fails here rather than as
    // eight coins quietly wearing the wrong colour.
    compare(Market.crc32("123456789"), 3421780262)
    compare(Market.crc32(""), 0)
  }

  // --- the logo -----------------------------------------------------------

  function test_the_large_variant_is_rewritten_to_small() {
    // The API hands over the 250px one at 12 kB. The path segment is the size,
    // so this is a rewrite rather than a second request to find a smaller one.
    compare(Market.iconUrl("https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png?1696501400"),
            "https://coin-images.coingecko.com/coins/images/1/small/bitcoin.png?1696501400")
  }

  function test_a_url_that_is_not_the_large_variant_is_left_alone() {
    compare(Market.iconUrl("https://example.invalid/x.png"), "https://example.invalid/x.png")
    compare(Market.iconUrl(""), "")
    compare(Market.iconUrl(null), "")
  }

  function test_parse_keeps_the_logo_the_answer_already_carried() {
    var got = Market.parseMarkets('[{"id":"bitcoin","symbol":"btc","name":"Bitcoin",' +
      '"current_price":1,"market_cap":1,' +
      '"image":"https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png"}]', true)
    compare(got.coins[0].image,
            "https://coin-images.coingecko.com/coins/images/1/small/bitcoin.png")
  }

  function test_a_coin_with_no_image_is_still_a_coin() {
    var got = Market.parseMarkets('[{"id":"x","symbol":"x","name":"X","current_price":1}]', true)
    compare(got.coins.length, 1)
    compare(got.coins[0].image, "")
  }

  function test_the_cache_filename_cannot_escape_its_directory() {
    // The id comes off the wire, and it is about to be concatenated into a
    // path handed to curl -o.
    compare(Market.iconFile("bitcoin"), "bitcoin.png")
    compare(Market.iconFile("bitcoin-cash"), "bitcoin-cash.png")
    compare(Market.iconFile("../../etc/passwd"), ".._.._etc_passwd.png")
    compare(Market.iconFile("a/b"), "a_b.png")
    compare(Market.iconFile("a b"), "a_b.png")
  }
}
