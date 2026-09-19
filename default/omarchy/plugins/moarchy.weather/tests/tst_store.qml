// The two files: the places somebody chose, and the week behind them.
//
// Both are read as objects, because the kit's JsonFile has already told an
// absent file from a broken one. What is tested here is the other half: a file
// somebody has edited by hand, and the rules about a list of places that the
// screen would otherwise have to know.
import QtQuick
import QtTest
import "../Store.js" as Store

TestCase {
  name: "Store"

  function berlin() {
    return { id: "52.524,13.411", name: "Berlin", admin: "Berlin",
             country: "Germany", lat: 52.524, lon: 13.411 }
  }

  function cairo() {
    return { id: "30.044,31.236", name: "Cairo", admin: "Cairo",
             country: "Egypt", lat: 30.044, lon: 31.236 }
  }

  // Off unless a test says otherwise, so the rules about a list of typed towns
  // are tested as they were before there was anything else on the list.
  function state(places, current, units, locate) {
    return { places: places, current: current, units: units || "metric", locate: !!locate }
  }

  function roundTrip(s) {
    return Store.parsePlaces(JSON.parse(Store.serializePlaces(s)))
  }

  // --- the places --------------------------------------------------------

  function test_places_go_out_and_come_back() {
    var back = roundTrip(state([berlin(), cairo()], cairo().id, "imperial"))
    compare(back.places.length, 2)
    compare(back.places[1].name, "Cairo")
    compare(back.places[1].lat, 30.044)
    compare(back.current, cairo().id)
    compare(back.units, "imperial")
  }

  function test_nothing_at_all_is_an_empty_list_rather_than_a_failure() {
    compare(Store.parsePlaces(null).places.length, 0)
    compare(Store.parsePlaces({}).units, "metric")
    compare(Store.parsePlaces({ places: "Berlin" }).places.length, 0)
  }

  function test_a_file_somebody_has_edited_cannot_put_anything_but_a_place_on_screen() {
    var data = { places: [
      { id: "1,1", name: 12, lat: 1, lon: 1 },
      { id: "2,2", name: "No latitude" },
      { id: "3,3", name: "Off the globe", lat: 191, lon: 0 },
      { name: "No id", lat: 4, lon: 4 },
      { id: "5,5", name: "  Padded  ", lat: 5, lon: 5 }
    ]}
    var back = Store.parsePlaces(data)
    compare(back.places.length, 1)
    compare(back.places[0].name, "Padded")
  }

  function test_a_scale_this_app_does_not_have_is_the_one_it_does() {
    compare(Store.parsePlaces({ units: "kelvin" }).units, "metric")
    compare(Store.parsePlaces({ units: "IMPERIAL" }).units, "imperial")
  }

  function test_the_same_place_twice_is_one_row() {
    var back = Store.parsePlaces({ places: [berlin(), berlin()] })
    compare(back.places.length, 1)
  }

  function test_a_current_naming_nowhere_falls_back_to_the_first_place() {
    // What removing a place in an editor leaves behind.
    var back = Store.parsePlaces({ places: [berlin(), cairo()], current: "0,0", locate: false })
    compare(back.current, berlin().id)
    compare(Store.parsePlaces({ current: "0,0", locate: false }).current, "")
  }

  // --- where the phone is ------------------------------------------------

  function test_a_first_run_shows_where_the_phone_is() {
    var fresh = Store.parsePlaces(null)
    compare(fresh.locate, true)
    compare(fresh.current, Store.HERE)
  }

  function test_a_file_from_before_the_lookup_keeps_its_town_and_gains_the_lookup() {
    var back = Store.parsePlaces({ places: [berlin(), cairo()], current: cairo().id })
    compare(back.locate, true)
    compare(back.current, cairo().id)
  }

  function test_a_current_naming_nowhere_falls_back_to_the_top_which_is_here() {
    compare(Store.parsePlaces({ places: [berlin()], current: "0,0" }).current, Store.HERE)
  }

  function test_only_false_switches_the_lookup_off() {
    compare(Store.parsePlaces({ locate: false }).locate, false)
    compare(Store.parsePlaces({ locate: 0 }).locate, true)
    compare(Store.parsePlaces({ locate: "no" }).locate, true)
  }

  function test_here_is_not_somewhere_the_file_can_point_once_the_lookup_is_off() {
    var back = Store.parsePlaces({ places: [berlin()], current: Store.HERE, locate: false })
    compare(back.current, berlin().id)
  }

  function test_the_switch_goes_out_and_comes_back() {
    var back = roundTrip(state([berlin()], Store.HERE, "metric", true))
    compare(back.locate, true)
    compare(back.current, Store.HERE)
    compare(roundTrip(state([berlin()], berlin().id)).locate, false)
  }

  function test_switching_the_lookup_on_shows_it() {
    var next = Store.withLocate(state([berlin()], berlin().id), true)
    compare(next.locate, true)
    compare(next.current, Store.HERE)
  }

  function test_switching_it_off_while_it_is_on_screen_moves_to_the_first_town() {
    var next = Store.withLocate(state([berlin(), cairo()], Store.HERE, "metric", true), false)
    compare(next.locate, false)
    compare(next.current, berlin().id)
    compare(Store.withLocate(state([], Store.HERE, "metric", true), false).current, "")
  }

  function test_switching_it_off_while_a_town_is_on_screen_leaves_the_town() {
    var next = Store.withLocate(state([berlin(), cairo()], cairo().id, "metric", true), false)
    compare(next.current, cairo().id)
  }

  function test_here_can_be_chosen_only_while_it_is_being_looked_up() {
    compare(Store.select(state([berlin()], berlin().id, "metric", true), Store.HERE).current, Store.HERE)
    compare(Store.select(state([berlin()], berlin().id), Store.HERE).current, berlin().id)
  }

  function test_removing_the_last_town_falls_back_to_here() {
    var next = Store.remove(state([berlin()], berlin().id, "metric", true), berlin().id)
    compare(next.current, Store.HERE)
    compare(next.locate, true)
  }

  function test_every_change_to_the_list_keeps_the_switch_where_it_was() {
    var on = state([berlin()], Store.HERE, "metric", true)
    compare(Store.add(on, cairo()).state.locate, true)
    compare(Store.select(on, berlin().id).locate, true)
    compare(Store.withUnits(on, "imperial").locate, true)
  }

  function test_adding_a_place_shows_it() {
    var result = Store.add(state([berlin()], berlin().id), cairo())
    compare(result.added, true)
    compare(result.state.places.length, 2)
    compare(result.state.current, cairo().id)
  }

  function test_adding_a_place_that_is_already_there_shows_it_rather_than_refusing() {
    var result = Store.add(state([berlin(), cairo()], cairo().id), berlin())
    compare(result.added, false)
    compare(result.full, false)
    compare(result.state.places.length, 2)
    compare(result.state.current, berlin().id)
  }

  function test_there_is_a_ceiling_and_it_says_so() {
    var places = []
    for (var i = 0; i < Store.MAX_PLACES; i++)
      places.push({ id: i + ",0", name: "Place " + i, lat: i, lon: 0 })
    var result = Store.add(state(places, places[0].id), cairo())
    compare(result.full, true)
    compare(result.state.places.length, Store.MAX_PLACES)
  }

  function test_a_file_longer_than_the_ceiling_is_read_up_to_it() {
    var places = []
    for (var i = 0; i < Store.MAX_PLACES + 5; i++)
      places.push({ id: i + ",0", name: "Place " + i, lat: i, lon: 0 })
    compare(Store.parsePlaces({ places: places }).places.length, Store.MAX_PLACES)
  }

  function test_removing_the_place_on_screen_moves_to_its_neighbour() {
    var oslo = { id: "59.913,10.739", name: "Oslo", lat: 59.913, lon: 10.739 }
    var next = Store.remove(state([berlin(), cairo(), oslo], cairo().id), cairo().id)
    compare(next.places.length, 2)
    // The row that was under the thumb, not the top of the list.
    compare(next.current, oslo.id)
  }

  function test_removing_the_last_place_leaves_nowhere() {
    var next = Store.remove(state([berlin()], berlin().id), berlin().id)
    compare(next.places.length, 0)
    compare(next.current, "")
  }

  function test_removing_a_place_that_is_not_shown_does_not_move_the_screen() {
    var next = Store.remove(state([berlin(), cairo()], berlin().id), cairo().id)
    compare(next.current, berlin().id)
  }

  function test_choosing_a_place_that_is_not_on_the_list_changes_nothing() {
    var next = Store.select(state([berlin()], berlin().id), "0,0")
    compare(next.current, berlin().id)
  }

  // --- the cache ---------------------------------------------------------

  function forecast() {
    return {
      offset: 7200,
      current: { time: 1789567200, temp: 18.4, feels: 17.1, humidity: 62,
                 precip: 0, code: 2, wind: 12.6, from: 315, day: true },
      hourly: [{ time: 1789567200, temp: 18.4, code: 2, pop: 10, day: true }],
      daily: [{ time: 1789531200, code: 2, high: 21, low: 9, pop: 20,
                sunrise: 1789533660, sunset: 1789580320 }]
    }
  }

  function test_a_forecast_goes_out_and_comes_back() {
    var entries = Store.put({}, berlin().id, forecast(), 1789567300)
    var back = Store.parseCache(JSON.parse(Store.serializeCache(entries, [berlin()])))
    compare(back[berlin().id].fetched, 1789567300)
    compare(back[berlin().id].forecast.current.temp, 18.4)
    compare(back[berlin().id].forecast.daily[0].high, 21)
    compare(back[berlin().id].forecast.offset, 7200)
  }

  function test_a_place_that_is_gone_does_not_leave_its_week_behind() {
    var entries = Store.put({}, berlin().id, forecast(), 1)
    entries = Store.put(entries, cairo().id, forecast(), 1)
    var written = JSON.parse(Store.serializeCache(entries, [cairo()]))
    compare(written.forecasts[berlin().id], undefined)
    verify(!!written.forecasts[cairo().id])
  }

  function located() {
    return { id: "52.493,13.404", name: "Berlin", admin: "State of Berlin",
             country: "Germany", lat: 52.4928, lon: 13.4039, found: 1789567000 }
  }

  function test_the_town_the_lookup_found_goes_out_and_comes_back_with_its_week() {
    var here = located()
    var entries = Store.put({}, here.id, forecast(), 1789567300)
    var written = JSON.parse(Store.serializeCache(entries, [cairo()], here))
    var back = Store.parseHere(written)
    compare(back.name, "Berlin")
    compare(back.lat, 52.4928)
    compare(back.found, 1789567000)
    verify(!!Store.parseCache(written)[here.id])
  }

  function test_no_lookup_leaves_no_town_and_no_week_in_the_file() {
    // What switching the lookup off writes: the same entries, and no `here`.
    var here = located()
    var entries = Store.put({}, here.id, forecast(), 1)
    var written = JSON.parse(Store.serializeCache(entries, [cairo()], null))
    compare(written.here, undefined)
    compare(written.forecasts[here.id], undefined)
    compare(Store.parseHere(written), null)
  }

  function test_a_found_town_somebody_has_edited_is_read_as_strictly_as_a_typed_one() {
    compare(Store.parseHere(null), null)
    compare(Store.parseHere({ here: { id: "1,1", name: "Nowhere", lat: 91, lon: 0 } }), null)
    compare(Store.parseHere({ here: { id: "1,1", name: "Undated", lat: 1, lon: 1 } }).found, 0)
  }

  function test_a_cache_that_is_not_one_is_empty_rather_than_fatal() {
    compare(Object.keys(Store.parseCache(null)).length, 0)
    compare(Object.keys(Store.parseCache({ forecasts: 12 })).length, 0)
    compare(Object.keys(Store.parseCache({ forecasts: { "1,1": {} } })).length, 0)
  }

  function test_a_forecast_off_the_disk_is_read_as_strictly_as_one_off_the_wire() {
    var broken = {
      offset: "two hours",
      current: { time: 1789567200, temp: "warm" },
      hourly: [{ time: 1789567200, temp: 18.4, code: 2, pop: null, day: true },
               { time: 1789570800, temp: null, code: 2 }],
      daily: [{ time: 1789531200, high: 21 }]
    }
    var back = Store.parseCache({ forecasts: { "1,1": { fetched: 5, forecast: broken } } })
    var kept = back["1,1"].forecast
    // A temperature that is a word is not a temperature, and a day with no low
    // cannot be drawn as a bar.
    compare(kept.current, null)
    compare(kept.hourly.length, 1)
    compare(kept.daily.length, 0)
    compare(kept.offset, 0)
  }

  function test_a_forecast_with_nothing_readable_in_it_is_not_kept_at_all() {
    var back = Store.parseCache({ forecasts: {
      "1,1": { fetched: 5, forecast: { offset: 0, hourly: [], daily: [] } }
    }})
    compare(Object.keys(back).length, 0)
  }
}
