// The one file, and what it does with a file somebody has edited.
//
// The kit's JsonFile has already told an absent file from a broken one and
// moved the broken one aside, so what is left for this module is the other
// half of the same job: a document that parses cleanly can still hold a row
// with no hour on it, and the next save must not be what destroys it.
import QtQuick
import QtTest
import "../Store.js" as Store
import "../Alarms.js" as Alarms
import "../Watch.js" as Watch

TestCase {
  name: "Store"

  function rows(list, watch, timer, settings) {
    return {
      alarms: list || [],
      stopwatch: watch || {},
      timer: timer || {},
      settings: settings || {}
    }
  }

  function roundTrip(state) {
    return Store.parse(JSON.parse(Store.serialize(state)))
  }

  function blankState() {
    return {
      alarms: [], strays: [],
      watch: Watch.blankWatch(), timer: Watch.blankTimer(),
      settings: Store.defaults()
    }
  }

  // --- nothing at all -----------------------------------------------------

  function test_no_file_is_an_empty_app_rather_than_a_failure() {
    var out = Store.parse(null)
    compare(out.alarms.length, 0)
    compare(out.strays.length, 0)
    compare(out.watch.running, false)
    compare(out.timer.total, 0)
    compare(out.settings.hour24, null)
    compare(out.settings.silent, false)
  }

  function test_rubbish_where_a_list_should_be_is_no_list() {
    compare(Store.parse({ alarms: "07:00" }).alarms.length, 0)
    compare(Store.parse({ alarms: 7 }).alarms.length, 0)
    compare(Store.parse(12).alarms.length, 0)
  }

  // --- the alarms ---------------------------------------------------------

  function test_alarms_go_out_and_come_back() {
    var state = blankState()
    var one = Alarms.blank(6, 40)
    one.id = "a"
    one.label = "Work"
    one.days = [1, 2, 3, 4, 5]
    var two = Alarms.blank(22, 30)
    two.id = "b"
    two.enabled = false
    state.alarms = [one, two]
    state.settings = { hour24: true, silent: true }

    var back = roundTrip(state)
    compare(back.alarms.length, 2)
    compare(back.alarms[0].hour, 6)
    compare(back.alarms[0].label, "Work")
    compare(JSON.stringify(back.alarms[0].days), "[1,2,3,4,5]")
    compare(back.alarms[1].enabled, false)
    compare(back.settings.hour24, true)
    compare(back.settings.silent, true)
  }

  function test_the_file_is_written_in_the_order_the_screen_shows_it() {
    var state = blankState()
    var late = Alarms.blank(22, 30); late.id = "c"
    var early = Alarms.blank(6, 40); early.id = "a"
    var mid = Alarms.blank(6, 45); mid.id = "b"
    state.alarms = [late, early, mid]
    var back = roundTrip(state)
    compare(back.alarms[0].id, "a")
    compare(back.alarms[1].id, "b")
    compare(back.alarms[2].id, "c")
  }

  function test_a_row_that_cannot_be_read_is_kept_rather_than_dropped() {
    var parsed = Store.parse(rows([
      { hour: 6, minute: 40, id: "good" },
      { minute: 40, note: "no hour" },
      { hour: 99, minute: 0 }
    ]))
    compare(parsed.alarms.length, 1)
    compare(parsed.strays.length, 2)
    // ...and it is still there after a save, which is the whole point.
    var written = JSON.parse(Store.serialize({
      alarms: parsed.alarms, strays: parsed.strays,
      watch: parsed.watch, timer: parsed.timer, settings: parsed.settings
    }))
    compare(written.alarms.length, 3)
    compare(written.alarms[1].note, "no hour")
  }

  function test_two_rows_with_one_id_do_not_become_one_alarm() {
    var parsed = Store.parse(rows([
      { hour: 6, minute: 40, id: "same" },
      { hour: 7, minute: 40, id: "same" }
    ]))
    compare(parsed.alarms.length, 2)
    verify(parsed.alarms[0].id !== parsed.alarms[1].id)
  }

  function test_the_bookkeeping_fields_are_absent_when_there_is_none() {
    var state = blankState()
    var one = Alarms.blank(6, 40); one.id = "a"
    state.alarms = [one]
    var written = JSON.parse(Store.serialize(state))
    compare(written.alarms[0].fired, undefined)
    compare(written.alarms[0].snoozed, undefined)
    one.fired = 1789466976000
    state.alarms = [one]
    compare(JSON.parse(Store.serialize(state)).alarms[0].fired, 1789466976000)
  }

  function test_more_alarms_than_the_app_keeps_are_not_all_read() {
    var many = []
    for (var i = 0; i < Alarms.MAX + 6; i++)
      many.push({ hour: 7, minute: 0, id: "a" + i })
    compare(Store.parse(rows(many)).alarms.length, Alarms.MAX)
  }

  function test_put_replaces_by_id_and_drop_removes_by_id() {
    var one = Alarms.blank(6, 40); one.id = "a"
    var two = Alarms.blank(7, 40); two.id = "b"
    var list = Store.put(Store.put([], one), two)
    compare(list.length, 2)
    var changed = Alarms.clone(one)
    changed.minute = 45
    list = Store.put(list, changed)
    compare(list.length, 2)
    compare(list[0].minute, 45)
    compare(Store.drop(list, "a").length, 1)
    compare(Store.drop(list, "nope").length, 2)
  }

  // --- the stopwatch and the timer ----------------------------------------

  function test_a_stopwatch_survives_the_app_being_reclaimed() {
    var state = blankState()
    state.watch = Watch.lapWatch(Watch.startWatch(Watch.blankWatch(), 1000), 5000)
    var back = roundTrip(state)
    compare(back.watch.running, true)
    compare(back.watch.since, 1000)
    compare(JSON.stringify(back.watch.laps), "[4000]")
  }

  function test_a_watch_that_says_it_runs_with_no_start_stops_where_it_stood() {
    var back = Store.parse(rows([], { running: true, accrued: 5000 }))
    compare(back.watch.running, false)
    compare(Watch.elapsed(back.watch, 999999), 5000)
  }

  function test_laps_that_do_not_climb_are_not_laps() {
    var back = Store.parse(rows([], { laps: [5000, 3000, 9000, 9000, -1] }))
    compare(JSON.stringify(back.watch.laps), "[5000,9000]")
  }

  function test_a_timer_survives_and_one_with_no_total_does_not_exist() {
    var state = blankState()
    state.timer = Watch.startTimer(300000, 1000)
    var back = roundTrip(state)
    compare(back.timer.total, 300000)
    compare(back.timer.endsAt, 301000)
    compare(Store.parse(rows([], {}, { running: true, endsAt: 500 })).timer.total, 0)
    compare(Store.parse(rows([], {}, { running: true, total: 300000 })).timer.running, false)
  }

  // --- the settings -------------------------------------------------------

  function test_nobody_has_chosen_a_clock_until_somebody_has() {
    // Absent rather than false, so that the app can fall back to the phone's
    // own locale instead of this file quietly choosing twelve hours.
    compare(Store.parse(rows([], {}, {}, {})).settings.hour24, null)
    compare(Store.parse(rows([], {}, {}, { hour24: false })).settings.hour24, false)
    compare(Store.parse(rows([], {}, {}, { hour24: "yes" })).settings.hour24, null)
    var state = blankState()
    compare(JSON.parse(Store.serialize(state)).settings.hour24, undefined)
    state.settings = { hour24: false, silent: false }
    compare(JSON.parse(Store.serialize(state)).settings.hour24, false)
  }

  function test_the_schema_number_is_written() {
    compare(JSON.parse(Store.serialize(blankState())).schema, Store.SCHEMA)
  }
}
