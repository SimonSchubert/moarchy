// The half that reads somebody else's JSON, and the half that turns a number
// into the string on the screen.
//
// Worth more than a test of the drawing, because every answer here predates
// the app: a WMO code means what WMO 4677 says it means, 06:41 in Berlin is
// 04:41Z whatever the phone's own clock is set to, and a week's coldest and
// warmest are arithmetic. All of it runs without a display.
import QtQuick
import QtTest
import "../Forecast.js" as Forecast

TestCase {
  name: "Forecast"

  // Noon UTC on a Tuesday, and a place two hours ahead of it -- Berlin in
  // summer, which is the case the whole time half of this module exists for.
  readonly property real now: Date.UTC(2026, 8, 15, 12, 0, 0) / 1000
  readonly property int offset: 7200

  function hourly(startHour, count) {
    var time = [], temp = [], code = [], pop = [], day = []
    for (var i = 0; i < count; i++) {
      time.push(Date.UTC(2026, 8, 15, startHour + i, 0, 0) / 1000)
      temp.push(14 + i % 7)
      code.push(i % 3 === 0 ? 0 : 61)
      pop.push(i * 3)
      day.push(1)
    }
    return { time: time, temperature_2m: temp, weather_code: code,
             precipitation_probability: pop, is_day: day }
  }

  function daily(days) {
    var time = [], code = [], high = [], low = [], pop = [], up = [], down = []
    for (var i = 0; i < days; i++) {
      // Local midnight, as Open-Meteo sends it: the place's own day boundary
      // expressed in seconds, which is 22:00Z the evening before at +02:00.
      time.push(Date.UTC(2026, 8, 14 + i, 22, 0, 0) / 1000)
      code.push([0, 3, 61, 95, 71, 45, 2][i % 7])
      high.push(20 + i)
      low.push(9 + i)
      pop.push(i * 10)
      up.push(Date.UTC(2026, 8, 15 + i, 4, 41, 0) / 1000)
      down.push(Date.UTC(2026, 8, 15 + i, 17, 52, 0) / 1000)
    }
    return { time: time, weather_code: code, temperature_2m_max: high,
             temperature_2m_min: low, precipitation_probability_max: pop,
             sunrise: up, sunset: down }
  }

  function payload(extra) {
    var body = {
      utc_offset_seconds: offset,
      timezone_abbreviation: "CEST",
      current: {
        time: now, temperature_2m: 18.4, apparent_temperature: 17.1,
        relative_humidity_2m: 62, is_day: 1, precipitation: 0,
        weather_code: 2, wind_speed_10m: 12.6, wind_direction_10m: 315
      },
      hourly: hourly(6, 48),
      daily: daily(7)
    }
    for (var key in (extra || {})) body[key] = extra[key]
    return JSON.stringify(body)
  }

  // --- the wire ----------------------------------------------------------

  function test_an_ordinary_answer_becomes_a_forecast() {
    var parsed = Forecast.parseForecast(payload(), now)
    compare(parsed.error, "")
    compare(parsed.forecast.offset, offset)
    compare(parsed.forecast.current.temp, 18.4)
    compare(parsed.forecast.current.day, true)
    compare(parsed.forecast.daily.length, 7)
  }

  function test_hours_that_have_already_gone_are_not_kept() {
    // The series starts at 06:00 and it is noon, so the six hours before this
    // one are not in the answer at all.
    var parsed = Forecast.parseForecast(payload(), now)
    var first = parsed.forecast.hourly[0]
    compare(first.time, Date.UTC(2026, 8, 15, 11, 0, 0) / 1000)
  }

  function test_two_days_of_hours_and_no_more() {
    var parsed = Forecast.parseForecast(
      JSON.stringify({ utc_offset_seconds: 0, hourly: hourly(12, 168) }), now)
    compare(parsed.forecast.hourly.length, Forecast.KEEP_HOURS)
  }

  function test_a_row_with_a_hole_in_it_is_left_out_rather_than_fatal() {
    var whole = Forecast.parseForecast(payload(), now).forecast
    var body = JSON.parse(payload())
    // The ninth hour of the series is 14:00, which is inside the two days this
    // keeps; the third day loses its low.
    body.hourly.temperature_2m[8] = null
    body.daily.temperature_2m_min[2] = null
    var parsed = Forecast.parseForecast(JSON.stringify(body), now)
    compare(parsed.error, "")
    compare(parsed.forecast.daily.length, whole.daily.length - 1)
    compare(parsed.forecast.hourly.length, whole.hourly.length - 1)
    // The hour is gone; the ones on either side of it are not.
    for (var i = 0; i < parsed.forecast.hourly.length; i++)
      verify(parsed.forecast.hourly[i].temp !== null)
  }

  function test_a_probability_nobody_reported_stays_unreported() {
    var body = JSON.parse(payload())
    body.hourly.precipitation_probability = []
    var parsed = Forecast.parseForecast(JSON.stringify(body), now)
    compare(parsed.forecast.hourly[0].pop, null)
  }

  function test_rubbish_off_the_wire_is_a_sentence_and_not_a_crash() {
    verify(Forecast.parseForecast("<html>502</html>", now).error.length > 0)
    compare(Forecast.parseForecast("<html>502</html>", now).forecast, null)
    verify(Forecast.parseForecast("[1,2,3]", now).error.length > 0)
    verify(Forecast.parseForecast("{}", now).error.length > 0)
  }

  function test_open_meteos_own_error_is_repeated_rather_than_guessed_at() {
    var body = JSON.stringify({ error: true, reason: "Latitude must be in range" })
    compare(Forecast.parseForecast(body, now).error, "Latitude must be in range")
  }

  // --- where the phone is ------------------------------------------------

  // GeoJS's answer as it came back, trimmed of the address and the network it
  // belongs to. The coordinates are strings on the wire.
  function geojs(extra) {
    var body = {
      accuracy: 20, city: "Berlin", continent_code: "EU", country: "Germany",
      country_code: "DE", latitude: "52.4928", longitude: "13.4039",
      region: "State of Berlin", timezone: "Europe/Berlin"
    }
    for (var key in (extra || {})) body[key] = extra[key]
    return JSON.stringify(body)
  }

  function test_an_address_becomes_a_place_like_one_somebody_typed() {
    var parsed = Forecast.parseLocation(geojs())
    compare(parsed.error, "")
    compare(parsed.place.name, "Berlin")
    compare(parsed.place.admin, "State of Berlin")
    compare(parsed.place.country, "Germany")
    compare(parsed.place.lat, 52.4928)
    compare(parsed.place.lon, 13.4039)
    compare(parsed.place.id, "52.493,13.404")
  }

  function test_coordinates_are_read_whether_they_come_as_strings_or_numbers() {
    compare(Forecast.parseLocation(geojs({ latitude: -33.8688, longitude: 151.2093 })).place.id,
            "-33.869,151.209")
  }

  function test_an_empty_coordinate_is_not_the_equator() {
    // Number("") is 0, which is the failure that would put a phone in the sea.
    verify(Forecast.parseLocation(geojs({ latitude: "" })).error.length > 0)
    verify(Forecast.parseLocation(geojs({ longitude: "nil" })).error.length > 0)
    verify(Forecast.parseLocation(geojs({ latitude: "0", longitude: "0" })).error.length > 0)
    verify(Forecast.parseLocation(geojs({ latitude: "123" })).error.length > 0)
  }

  function test_a_country_without_a_town_is_not_a_place_to_forecast() {
    var parsed = Forecast.parseLocation(geojs({ city: "" }))
    compare(parsed.place, null)
    verify(parsed.error.length > 0)
  }

  function test_rubbish_from_the_lookup_is_a_sentence_and_not_a_crash() {
    verify(Forecast.parseLocation("<html>502</html>").error.length > 0)
    verify(Forecast.parseLocation("null").error.length > 0)
    verify(Forecast.parseLocation("{}").error.length > 0)
  }

  // --- the sky -----------------------------------------------------------

  function test_a_code_is_a_sentence_and_a_symbol() {
    compare(Forecast.describe(0), "Clear sky")
    compare(Forecast.describe(95), "Thunderstorm")
    compare(Forecast.glyph(0, true), "clear")
    compare(Forecast.glyph(3, true), "cloud")
    compare(Forecast.glyph(80, true), "showers")
  }

  function test_the_sun_does_not_come_out_at_night() {
    compare(Forecast.glyph(0, false), "clear-night")
    compare(Forecast.glyph(2, false), "partly-night")
    // Rain at night is rain. Only the three symbols with a sun in them have a
    // night half, and drawing a moon over a raincloud would say nothing.
    compare(Forecast.glyph(61, false), "rain")
    compare(Forecast.glyph(95, false), "storm")
  }

  function test_a_code_this_app_has_never_heard_of_says_nothing_rather_than_lying() {
    compare(Forecast.describe(404), "")
    compare(Forecast.glyph(404, true), "cloud")
  }

  function test_cold_is_blue_and_hot_is_red() {
    compare(Forecast.band(-4), "cyan")
    compare(Forecast.band(4), "blue")
    compare(Forecast.band(14), "green")
    compare(Forecast.band(21), "yellow")
    compare(Forecast.band(28), "orange")
    compare(Forecast.band(35), "red")
  }

  // --- the numbers -------------------------------------------------------

  function test_a_temperature_is_rounded_once_and_in_the_scale_asked_for() {
    compare(Forecast.temperature(18.4, "metric"), "18°")
    compare(Forecast.temperature(18.6, "metric"), "19°")
    compare(Forecast.temperature(0, "imperial"), "32°")
    compare(Forecast.temperature(100, "imperial"), "212°")
    compare(Forecast.temperature(null, "metric"), "—")
  }

  function test_wind_carries_its_unit_because_a_number_alone_is_two_answers() {
    compare(Forecast.windText(12.6, "metric"), "13 km/h")
    compare(Forecast.windText(16.1, "imperial"), "10 mph")
    compare(Forecast.compass(0), "N")
    compare(Forecast.compass(315), "NW")
    compare(Forecast.compass(360), "N")
    compare(Forecast.compass(-45), "NW")
    compare(Forecast.compass(null), "")
  }

  // --- the clock in the other place --------------------------------------

  function test_a_time_is_read_on_the_clock_of_the_place_it_belongs_to() {
    // 04:41Z is 06:41 in Berlin, and it must stay 06:41 on a phone in London.
    compare(Forecast.clock(Date.UTC(2026, 8, 15, 4, 41, 0) / 1000, offset), "06:41")
    compare(Forecast.clock(Date.UTC(2026, 8, 15, 23, 30, 0) / 1000, -25200), "16:30")
    compare(Forecast.clock(null, offset), "—")
  }

  function test_the_hour_it_is_there_is_labelled_now() {
    compare(Forecast.hourLabel(now, offset, now), "Now")
    compare(Forecast.hourLabel(now + 3600, offset, now), "15:00")
    // Half an hour past the hour is still that hour, which is the case a
    // straight comparison of hours gets wrong in India and Nepal.
    compare(Forecast.hourLabel(now, offset, now + 1800), "Now")
  }

  function test_today_is_called_today_and_the_rest_are_named() {
    compare(Forecast.dayLabel(Date.UTC(2026, 8, 14, 22, 0, 0) / 1000, offset, now), "Today")
    compare(Forecast.dayLabel(Date.UTC(2026, 8, 15, 22, 0, 0) / 1000, offset, now), "Wed")
  }

  function test_freshness_is_how_long_ago_rather_than_when() {
    compare(Forecast.freshness(30), "just now")
    compare(Forecast.freshness(240), "4 min ago")
    compare(Forecast.freshness(3600), "1 hour ago")
    compare(Forecast.freshness(90000), "yesterday")
  }

  // --- what the screen asks for ------------------------------------------

  function test_the_strip_starts_at_the_hour_it_is_now_not_the_next_one() {
    var forecast = Forecast.parseForecast(payload(), now).forecast
    // Twenty to one: the useful first column is one o'clock's hour, because
    // that is the hour it currently is.
    var hours = Forecast.nextHours(forecast, now + 2400, 24)
    compare(hours[0].time, now)
    compare(hours.length, 24)
  }

  function test_yesterday_is_not_in_the_week() {
    var forecast = Forecast.parseForecast(payload(), now).forecast
    var week = Forecast.days(forecast, now + 86400 * 2)
    compare(week.length, 5)
    compare(Forecast.dayLabel(week[0].time, offset, now + 86400 * 2), "Today")
  }

  function test_the_bars_are_measured_against_the_whole_week() {
    var week = [{ low: 5, high: 10 }, { low: 0, high: 20 }, { low: 10, high: 15 }]
    var range = Forecast.span(week)
    compare(range.low, 0)
    compare(range.high, 20)
    var bar = Forecast.bar(week[0], range)
    compare(bar.from, 0.25)
    compare(bar.to, 0.5)
  }

  function test_a_week_that_is_all_one_temperature_still_has_a_bar() {
    var range = Forecast.span([{ low: 12, high: 12 }])
    verify(range.high > range.low)
  }

  function test_the_current_block_is_a_quarter_hour_reading_not_an_hourly_one() {
    // Open-Meteo stamps `current` every fifteen minutes, so at ten to nine it
    // says 20:45 while the hour on screen starts at 20:00. Read as hours that
    // is a reading in the future, and the wind and the humidity -- which only
    // this block carries -- disappear off the screen.
    var body = JSON.parse(payload())
    body.current.time = now + 2700
    var forecast = Forecast.parseForecast(JSON.stringify(body), now).forecast
    var reading = Forecast.readingAt(forecast, now)
    compare(reading.humidity, 62)
    compare(reading.wind, 12.6)
  }

  function test_an_older_cache_still_answers_with_the_hour_it_is_in() {
    var forecast = Forecast.parseForecast(payload(), now).forecast
    // Three hours later the `current` block is stale, and the hourly series
    // it came with is not: that is what a cache read after a tunnel has.
    var reading = Forecast.readingAt(forecast, now + 3 * 3600)
    compare(reading.temp, forecast.hourly[4].temp)
    compare(reading.feels, null)
  }

  function test_the_tiles_leave_out_what_the_model_did_not_report() {
    var forecast = Forecast.parseForecast(payload(), now).forecast
    var tiles = Forecast.facts(forecast.current, forecast.daily[0], offset, "metric")
    compare(tiles.length, 4)
    compare(tiles[0].label, "Wind")
    compare(tiles[0].value, "13 km/h")
    compare(tiles[0].note, "NW")
    compare(tiles[3].value, "19:52")

    var thin = Forecast.facts({ temp: 10, wind: null, humidity: null }, null, offset, "metric")
    compare(thin.length, 0)
  }

  function test_feels_like_is_left_out_when_it_agrees_with_the_temperature() {
    var day = { high: 21, low: 9 }
    compare(Forecast.heroNote({ temp: 18.4, feels: 18.2 }, day, "metric"), "21° / 9°")
    verify(Forecast.heroNote({ temp: 18.4, feels: 14.0 }, day, "metric").indexOf("Feels like 14°") === 0)
  }

  // --- looking for a town ------------------------------------------------

  function test_a_search_comes_back_as_places() {
    var body = JSON.stringify({ results: [
      { id: 2950159, name: "Berlin", latitude: 52.52437, longitude: 13.41053,
        country: "Germany", admin1: "Berlin" },
      { name: "Berlin", latitude: 44.46867, longitude: -71.18508,
        country: "United States", admin1: "New Hampshire" }
    ]})
    var parsed = Forecast.parseSearch(body)
    compare(parsed.error, "")
    compare(parsed.places.length, 2)
    compare(parsed.places[0].id, "52.524,13.411")
    compare(parsed.places[1].id, "44.469,-71.185")
    compare(Forecast.where(parsed.places[1]), "New Hampshire, United States")
  }

  function test_a_row_with_no_coordinates_is_not_a_place() {
    var body = JSON.stringify({ results: [
      { name: "Nowhere" },
      { name: "", latitude: 1, longitude: 2 },
      { name: "Somewhere", latitude: 1, longitude: 2 }
    ]})
    compare(Forecast.parseSearch(body).places.length, 1)
  }

  function test_a_name_nothing_matches_is_an_empty_list_and_not_an_error() {
    var parsed = Forecast.parseSearch(JSON.stringify({ generationtime_ms: 0.2 }))
    compare(parsed.error, "")
    compare(parsed.places.length, 0)
  }

  function test_the_request_asks_for_seconds_rather_than_local_strings() {
    var url = Forecast.url(52.52437, 13.41053)
    verify(url.indexOf("latitude=52.5244") > 0)
    verify(url.indexOf("timeformat=unixtime") > 0)
    verify(url.indexOf("timezone=auto") > 0)
    verify(Forecast.searchUrl("São Paulo").indexOf("S%C3%A3o%20Paulo") > 0)
  }
}
