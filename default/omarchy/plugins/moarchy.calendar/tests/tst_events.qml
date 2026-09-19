// When a thing happens again, and what happens to a file somebody has edited.
import QtQuick
import QtTest
import "../Dates.js" as Dates
import "../Events.js" as Events

TestCase {
  name: "Events"

  function make(fields) {
    var ev = Events.blank("2026-09-15", 540, "blue", 1)
    for (var key in fields) ev[key] = fields[key]
    return ev
  }

  // --- recurrence ------------------------------------------------------------

  function test_something_once_happens_once() {
    var ev = make({ repeat: "none" })
    compare(Events.occursOn(ev, "2026-09-15"), true)
    compare(Events.occursOn(ev, "2026-09-16"), false)
    compare(Events.occursOn(ev, "2026-09-14"), false)
  }

  function test_nothing_happens_before_the_day_it_was_put_in() {
    var ev = make({ repeat: "daily" })
    compare(Events.occursOn(ev, "2026-09-14"), false)
    compare(Events.occursOn(ev, "2026-09-15"), true)
    compare(Events.occursOn(ev, "2030-01-01"), true)
  }

  function test_weekly_keeps_the_weekday() {
    var ev = make({ repeat: "weekly" })  // a Tuesday
    compare(Events.occursOn(ev, "2026-09-22"), true)
    compare(Events.occursOn(ev, "2026-09-23"), false)
    compare(Events.occursOn(ev, "2027-03-09"), true)
    compare(Dates.weekday("2027-03-09"), 2)
  }

  function test_monthly_on_the_thirty_first_skips_the_months_that_have_none() {
    // RFC 5545's rule for BYMONTHDAY: an instance that is not a date is
    // ignored. It is not moved to the 30th and it is not moved to the 1st,
    // because both of those are appointments on days nobody chose.
    var ev = make({ date: "2026-01-31", repeat: "monthly" })
    compare(Events.occursOn(ev, "2026-03-31"), true)
    compare(Events.occursOn(ev, "2026-02-28"), false)
    compare(Events.occursOn(ev, "2026-03-01"), false)
    compare(Events.occursOn(ev, "2026-04-30"), false)
  }

  function test_yearly_on_the_twenty_ninth_of_february_happens_in_leap_years() {
    var ev = make({ date: "2024-02-29", repeat: "yearly" })
    compare(Events.occursOn(ev, "2028-02-29"), true)
    compare(Events.occursOn(ev, "2026-02-28"), false)
    compare(Events.occursOn(ev, "2026-03-01"), false)
  }

  function test_a_birthday_is_the_same_date_every_year() {
    var ev = make({ date: "1984-06-07", repeat: "yearly" })
    compare(Events.occursOn(ev, "2026-06-07"), true)
    compare(Events.occursOn(ev, "2026-06-08"), false)
    compare(Events.occursOn(ev, "2026-07-07"), false)
  }

  function test_a_repeat_can_be_given_an_end_by_the_file() {
    var ev = make({ repeat: "daily", until: "2026-09-18" })
    compare(Events.occursOn(ev, "2026-09-18"), true)
    compare(Events.occursOn(ev, "2026-09-19"), false)
  }

  // --- a day, and a year --------------------------------------------------

  function test_a_day_is_all_day_first_then_by_the_clock() {
    var list = [
      make({ id: "b", title: "Standup", start: 540 }),
      make({ id: "a", title: "Bin day", allDay: true }),
      make({ id: "c", title: "Lunch", start: 720 })
    ]
    var day = Events.onDay(list, "2026-09-15")
    compare(day.length, 3)
    compare(day[0].title, "Bin day")
    compare(day[1].title, "Standup")
    compare(day[2].title, "Lunch")
  }

  function test_two_things_at_nine_keep_the_same_order_every_time() {
    var list = [make({ id: "1", title: "Zebra" }), make({ id: "2", title: "Aardvark" })]
    compare(Events.onDay(list, "2026-09-15")[0].title, "Aardvark")
    compare(Events.onDay(list.reverse(), "2026-09-15")[0].title, "Aardvark")
  }

  function test_the_dots_line_up_with_the_cells_and_stop_at_four() {
    var list = []
    for (var i = 0; i < 6; i++) list.push(make({ id: "e" + i, colour: "green" }))
    var cells = Dates.grid(2026, 9, 1)
    var dots = Events.marks(list, cells)
    compare(dots.length, cells.length)
    for (var c = 0; c < cells.length; c++) {
      if (cells[c].iso === "2026-09-15") compare(dots[c].length, Events.DOTS)
      else compare(dots[c].length, 0)
    }
  }

  function test_the_agenda_is_the_days_ahead_that_have_something_on_them() {
    var list = [
      make({ id: "a", date: "2026-09-15", title: "Today" }),
      make({ id: "b", date: "2026-09-18", title: "Friday" }),
      make({ id: "c", date: "2026-09-18", title: "Friday too", start: 600 }),
      make({ id: "d", date: "2026-08-01", title: "Long gone" })
    ]
    var ahead = Events.agenda(list, "2026-09-15", 400, 60)
    compare(ahead.length, 2)
    compare(ahead[0].iso, "2026-09-15")
    compare(ahead[1].iso, "2026-09-18")
    compare(ahead[1].items.length, 2)
  }

  function test_a_daily_event_does_not_fill_the_agenda_with_a_year_of_itself() {
    var ahead = Events.agenda([make({ repeat: "daily" })], "2026-09-15", 400, 60)
    compare(ahead.length, 60)
  }

  function test_a_birthday_eleven_months_out_is_still_ahead() {
    var ev = make({ date: "1984-06-07", repeat: "yearly", title: "Birthday" })
    var ahead = Events.agenda([ev], "2026-09-15", Events.HORIZON, Events.AGENDA_DAYS)
    compare(ahead.length, 1)
    compare(ahead[0].iso, "2027-06-07")
  }

  function test_the_next_time_it_happens_or_nothing_at_all() {
    compare(Events.nextOn(make({ repeat: "weekly" }), "2026-09-16", 400), "2026-09-22")
    compare(Events.nextOn(make({ repeat: "none" }), "2026-09-16", 400), "")
  }

  // --- a row from the file ---------------------------------------------------

  function test_a_row_that_cannot_be_put_on_a_day_is_refused() {
    compare(Events.normalise(null, 0, 0), null)
    compare(Events.normalise({ title: "No date" }, 0, 0), null)
    compare(Events.normalise({ date: "2026-02-30", title: "No such day" }, 0, 0), null)
    compare(Events.normalise([], 0, 0), null)
  }

  function test_a_file_may_write_the_time_either_way_round() {
    compare(Events.normalise({ date: "2026-09-15", start: "09:30" }, 0, 0).start, 570)
    compare(Events.normalise({ date: "2026-09-15", start: 570 }, 0, 0).start, 570)
    // And a nonsense time falls back rather than taking the event with it.
    compare(Events.normalise({ date: "2026-09-15", start: "elevenish" }, 0, 0).start, 9 * 60)
  }

  function test_an_event_with_no_end_is_a_moment_rather_than_an_hour() {
    // The app writes both times on every save, so a row with one is a row
    // somebody wrote by hand or a script sent through `add`. Guessing an hour
    // there turned an event saved as a moment into an hour-long one.
    var ev = Events.normalise({ date: "2026-09-15", title: "Parcel", start: "17:30" }, 0, 0)
    compare(ev.start, 1050)
    compare(ev.end, 1050)
    compare(Events.summary(ev), "17:30")
  }

  function test_an_event_cannot_end_before_it_starts() {
    var ev = Events.normalise({ date: "2026-09-15", start: "14:00", end: "09:00" }, 0, 0)
    compare(ev.start, 840)
    compare(ev.end, 840)
    // A moment is allowed: one time and no length.
    var moment = Events.normalise({ date: "2026-09-15", start: "14:00", end: "14:00" }, 0, 0)
    compare(moment.end, 840)
  }

  function test_a_nameless_row_is_drawn_rather_than_dropped() {
    compare(Events.normalise({ date: "2026-09-15" }, 0, 0).title, "Untitled")
    compare(Events.normalise({ date: "2026-09-15", title: "  Dentist " }, 0, 0).title, "Dentist")
  }

  function test_a_colour_or_a_repeat_this_app_has_never_heard_of_falls_back() {
    var ev = Events.normalise({ date: "2026-09-15", colour: "puce", repeat: "fortnightly" }, 0, 0)
    compare(ev.colour, "blue")
    compare(ev.repeat, "none")
    // An `until` before the day it starts is not an end, it is a typo.
    compare(Events.normalise({ date: "2026-09-15", repeat: "daily", until: "2026-09-01" }, 0, 0).until, "")
  }

  // --- saying it, and keeping it ---------------------------------------------

  function test_a_repeat_is_described_in_the_words_it_was_chosen_with() {
    compare(Events.describeRepeat(make({ repeat: "none" })), "")
    compare(Events.describeRepeat(make({ repeat: "daily" })), "Every day")
    compare(Events.describeRepeat(make({ repeat: "weekly" })), "Every Tuesday")
    compare(Events.describeRepeat(make({ repeat: "monthly" })), "Every month on the 15th")
    compare(Events.describeRepeat(make({ date: "2026-09-01", repeat: "monthly" })),
            "Every month on the 1st")
    compare(Events.describeRepeat(make({ repeat: "yearly" })), "Every 15 September")
    compare(Events.describeRepeat(make({ repeat: "daily", until: "2026-12-24" })),
            "Every day, until Thu 24 Dec")
  }

  function test_the_ordinals_english_gets_wrong_first() {
    compare(Events.ordinal(1), "1st")
    compare(Events.ordinal(2), "2nd")
    compare(Events.ordinal(3), "3rd")
    compare(Events.ordinal(4), "4th")
    compare(Events.ordinal(11), "11th")
    compare(Events.ordinal(12), "12th")
    compare(Events.ordinal(13), "13th")
    compare(Events.ordinal(21), "21st")
    compare(Events.ordinal(31), "31st")
  }

  function test_the_line_under_the_name_is_when_and_where() {
    compare(Events.line(make({ start: 540, end: 600 })), "09:00 – 10:00")
    compare(Events.line(make({ allDay: true })), "All day")
    compare(Events.line(make({ start: 540, end: 600, where: "Kitchen" })), "09:00 – 10:00 · Kitchen")
  }

  function test_the_list_is_replaced_rather_than_pushed_at() {
    var one = make({ id: "a", title: "One" })
    var list = Events.withEvent([], one)
    compare(list.length, 1)

    var edited = Events.copy(one)
    edited.title = "One, edited"
    var again = Events.withEvent(list, edited)
    compare(again.length, 1)
    compare(again[0].title, "One, edited")
    // The old array is untouched, which is what makes a binding notice.
    compare(list[0].title, "One")

    compare(Events.without(again, "a").length, 0)
    compare(Events.find(again, "a").title, "One, edited")
    compare(Events.find(again, "nope"), null)
  }

  function test_a_new_event_takes_the_colour_that_is_used_least() {
    compare(Events.nextColour([]), "blue")
    compare(Events.nextColour([make({ colour: "blue" })]), "green")
    var most = []
    for (var i = 0; i < Events.COLOURS.length; i++)
      if (Events.COLOURS[i] !== "orange") most.push(make({ id: "e" + i, colour: Events.COLOURS[i] }))
    compare(Events.nextColour(most), "orange")
  }

  function test_two_events_added_in_the_same_millisecond_are_two_events() {
    var a = Events.blank("2026-09-15", 540, "blue", 1758000000000)
    var b = Events.blank("2026-09-15", 540, "blue", 1758000000000)
    verify(a.id !== b.id)
  }
}
