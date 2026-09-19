// The file: what goes out, what comes back, and what is kept even though this
// app cannot read it.
import QtQuick
import QtTest
import "../Dates.js" as Dates
import "../Events.js" as Events
import "../Store.js" as Store

TestCase {
  name: "Store"

  function roundTrip(events, strays) {
    return Store.parse(JSON.parse(Store.serialize(events, strays)))
  }

  function test_an_event_goes_out_and_comes_back() {
    var ev = Events.blank("2026-09-15", 570, "green", 1)
    ev.title = "Dentist"
    ev.where = "Charlottenstraße"
    ev.end = 630
    ev.repeat = "yearly"

    var back = roundTrip([ev], [])
    compare(back.events.length, 1)
    var got = back.events[0]
    compare(got.title, "Dentist")
    compare(got.where, "Charlottenstraße")
    compare(got.date, "2026-09-15")
    compare(got.start, 570)
    compare(got.end, 630)
    compare(got.repeat, "yearly")
    compare(got.colour, "green")
    compare(got.id, ev.id)
  }

  function test_a_time_is_written_as_a_person_would_read_it() {
    var ev = Events.blank("2026-09-15", 570, "blue", 1)
    ev.title = "Standup"
    var raw = JSON.parse(Store.serialize([ev], []))
    compare(raw.schema, Store.SCHEMA)
    compare(raw.events[0].start, "09:30")
    compare(raw.events[0].end, "10:30")
    compare(raw.events[0].colour, "blue")
  }

  function test_what_is_empty_is_left_out_of_the_file() {
    var ev = Events.blank("2026-09-15", 540, "blue", 1)
    ev.title = "Plain"
    var row = JSON.parse(Store.serialize([ev], [])).events[0]
    compare(row.where, undefined)
    compare(row.until, undefined)
    compare(row.repeat, undefined)
    compare(row.allDay, undefined)

    ev.allDay = true
    var allDay = JSON.parse(Store.serialize([ev], [])).events[0]
    compare(allDay.allDay, true)
    // An all-day event has no times to write down.
    compare(allDay.start, undefined)
  }

  function test_a_moment_comes_back_a_moment() {
    var ev = Events.blank("2026-09-15", 1050, "yellow", 1)
    ev.title = "Pick up the parcel"
    ev.end = ev.start

    var row = JSON.parse(Store.serialize([ev], [])).events[0]
    compare(row.start, "17:30")
    compare(row.end, "17:30")
    compare(roundTrip([ev], []).events[0].end, 1050)
  }

  function test_the_file_is_written_in_the_order_it_would_be_read_in() {
    var late = Events.blank("2026-10-01", 540, "blue", 1); late.title = "Late"
    var early = Events.blank("2026-09-15", 540, "blue", 2); early.title = "Early"
    var earlier = Events.blank("2026-09-15", 480, "blue", 3); earlier.title = "Earlier"

    var rows = JSON.parse(Store.serialize([late, early, earlier], [])).events
    compare(rows[0].title, "Earlier")
    compare(rows[1].title, "Early")
    compare(rows[2].title, "Late")
  }

  function test_a_row_this_app_cannot_read_is_kept_rather_than_destroyed() {
    // FileView refuses to overwrite a file that will not parse. It cannot
    // guard a *row*: this file parses, and the next save would have written it
    // back without the second event in it.
    var stray = { id: "x", title: "From somewhere else", starts: "next Tuesday" }
    var ev = Events.blank("2026-09-15", 540, "blue", 1)
    ev.title = "Ours"

    var back = Store.parse({ schema: 1, events: [ev, stray] })
    compare(back.events.length, 1)
    compare(back.strays.length, 1)

    var written = JSON.parse(Store.serialize(back.events, back.strays))
    compare(written.events.length, 2)
    compare(written.events[1].starts, "next Tuesday")
  }

  function test_two_rows_with_one_id_become_two_events() {
    // What a copied and pasted file looks like, and the shape that makes
    // deleting one event delete two.
    var row = { id: "same", title: "Twice", date: "2026-09-15", start: "09:00" }
    var back = Store.parse({ schema: 1, events: [row, row] })
    compare(back.events.length, 2)
    verify(back.events[0].id !== back.events[1].id)
  }

  function test_nothing_at_all_is_an_empty_calendar_rather_than_a_failure() {
    compare(Store.parse(null).events.length, 0)
    compare(Store.parse({}).events.length, 0)
    compare(Store.parse({ events: "yesterday" }).events.length, 0)
    compare(Store.parse({ events: [] }).strays.length, 0)
  }
}
