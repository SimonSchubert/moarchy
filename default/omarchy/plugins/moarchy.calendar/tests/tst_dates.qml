// The arithmetic, against dates a person would write down.
//
// Worth more here than in most of these plugins, because what is being tested
// has a right answer that predates the app: the 29th of February exists in
// 2024 and not in 2026 whatever this code thinks, and a wrong answer is not a
// layout bug, it is somebody missing a dentist.
import QtQuick
import QtTest
import "../Dates.js" as Dates

TestCase {
  name: "Dates"

  function test_day_zero_is_the_epoch_and_it_was_a_thursday() {
    compare(Dates.daysFromCivil(1970, 1, 1), 0)
    compare(Dates.fromDayNumber(0), "1970-01-01")
    compare(Dates.weekday("1970-01-01"), 4)
  }

  function test_the_conversion_goes_both_ways_for_every_day_of_four_years() {
    // Across a leap year and a century that is not one, which is where the
    // two clever lines in civilFromDays earn their keep.
    var at = Dates.daysFromCivil(1999, 1, 1)
    var stop = Dates.daysFromCivil(2003, 1, 1)
    for (; at < stop; at++) {
      var c = Dates.civilFromDays(at)
      compare(Dates.daysFromCivil(c.y, c.m, c.d), at)
    }
  }

  function test_a_century_is_not_a_leap_year_unless_it_is_a_fourth_one() {
    compare(Dates.isLeap(1900), false)
    compare(Dates.isLeap(2000), true)
    compare(Dates.isLeap(2024), true)
    compare(Dates.isLeap(2026), false)
    compare(Dates.daysInMonth(2024, 2), 29)
    compare(Dates.daysInMonth(2026, 2), 28)
  }

  function test_a_day_the_calendar_does_not_have_is_not_a_day() {
    compare(Dates.isDay("2026-09-15"), true)
    compare(Dates.isDay("2026-02-30"), false)
    compare(Dates.isDay("2024-02-29"), true)
    compare(Dates.isDay("2026-13-01"), false)
    compare(Dates.isDay("15/09/2026"), false)
    compare(Dates.isDay(""), false)
    compare(Dates.isDay(null), false)
  }

  function test_adding_days_walks_over_the_ends_of_things() {
    compare(Dates.addDays("2026-09-15", 1), "2026-09-16")
    compare(Dates.addDays("2026-09-30", 1), "2026-10-01")
    compare(Dates.addDays("2026-12-31", 1), "2027-01-01")
    compare(Dates.addDays("2027-01-01", -1), "2026-12-31")
    compare(Dates.addDays("2024-02-28", 1), "2024-02-29")
    compare(Dates.addDays("2026-02-28", 1), "2026-03-01")
    compare(Dates.between("2026-09-15", "2026-09-22"), 7)
  }

  function test_the_fifteenth_of_september_2026_was_a_tuesday() {
    compare(Dates.weekday("2026-09-15"), 2)
    compare(Dates.dayLabel("2026-09-15"), "Tuesday 15 September")
    compare(Dates.fullDayLabel("2026-09-15"), "Tuesday 15 September 2026")
    compare(Dates.shortDayLabel("2026-09-15"), "Tue 15 Sep")
    compare(Dates.monthLabel(2026, 9), "September 2026")
  }

  function test_a_month_is_one_number_that_still_adds_up_over_december() {
    var december = Dates.monthOfDay("2026-12-31")
    compare(Dates.yearOf(december + 1), 2027)
    compare(Dates.monthOf(december + 1), 1)
    compare(Dates.firstOfMonth(december + 1), "2027-01-01")
  }

  function test_a_grid_is_six_rows_whatever_the_month_needs() {
    // February 2026 has 28 days and starts on a Sunday: four rows of days and
    // two of the month after. The height does not change, which is the point.
    var february = Dates.grid(2026, 2, 1)
    compare(february.length, 42)
    var september = Dates.grid(2026, 9, 1)
    compare(september.length, 42)

    var inSeptember = 0
    for (var i = 0; i < september.length; i++) if (september[i].inMonth) inSeptember++
    compare(inSeptember, 30)
  }

  function test_a_grid_starts_on_the_day_the_phone_starts_a_week_on() {
    var monday = Dates.grid(2026, 9, 1)
    compare(Dates.weekday(monday[0].iso), 1)
    // 1 September 2026 is a Tuesday, so a week beginning on Monday shows the
    // 31st of August in the corner.
    compare(monday[0].iso, "2026-08-31")

    var sunday = Dates.grid(2026, 9, 0)
    compare(Dates.weekday(sunday[0].iso), 0)
    compare(sunday[0].iso, "2026-08-30")
  }

  function test_the_weekday_row_is_labelled_in_the_same_order() {
    compare(Dates.weekdayLabels(1, "short").join(" "), "Mon Tue Wed Thu Fri Sat Sun")
    compare(Dates.weekdayLabels(0, "short").join(" "), "Sun Mon Tue Wed Thu Fri Sat")
    compare(Dates.weekdayLabels(1, "initial").join(""), "MTWTFSS")
  }

  function test_the_thirty_first_swiped_into_february_is_its_last_day() {
    var february = Dates.monthOfDay("2026-02-01")
    compare(Dates.sameDayIn(february, "2026-01-31"), "2026-02-28")
    compare(Dates.sameDayIn(february, "2026-01-15"), "2026-02-15")
    // And into a February that has one.
    compare(Dates.sameDayIn(Dates.monthOfDay("2024-02-01"), "2024-01-31"), "2024-02-29")
  }

  function test_three_words_that_save_working_out_the_date() {
    compare(Dates.relative("2026-09-15", "2026-09-15"), "Today")
    compare(Dates.relative("2026-09-16", "2026-09-15"), "Tomorrow")
    compare(Dates.relative("2026-09-14", "2026-09-15"), "Yesterday")
    compare(Dates.relative("2026-09-18", "2026-09-15"), "")
    compare(Dates.headline("2026-09-18", "2026-09-15"), "Friday 18 September")
  }

  function test_today_is_read_off_the_phones_clock_in_local_time() {
    // The bug this is about: `new Date("2026-09-15")` is UTC midnight, and
    // .getDate() on it is the 14th anywhere west of Greenwich. Ours goes
    // through the local fields, so noon local is today whatever the offset.
    var noon = new Date(2026, 8, 15, 12, 0, 0).getTime()
    compare(Dates.todayFrom(noon, ""), "2026-09-15")
    // Late evening, where a UTC reading would already be tomorrow in Berlin.
    var evening = new Date(2026, 8, 15, 23, 30, 0).getTime()
    compare(Dates.todayFrom(evening, ""), "2026-09-15")
    compare(Dates.todayFrom(noon, "2001-01-01"), "2001-01-01")
    compare(Dates.todayFrom(noon, "not a day"), "2026-09-15")
  }

  function test_a_new_event_today_starts_at_the_next_half_hour() {
    compare(Dates.nextHalfHour(new Date(2026, 8, 15, 9, 1, 0).getTime()), 9 * 60 + 30)
    compare(Dates.nextHalfHour(new Date(2026, 8, 15, 9, 30, 0).getTime()), 10 * 60)
    compare(Dates.nextHalfHour(new Date(2026, 8, 15, 9, 0, 0).getTime()), 9 * 60 + 30)
    // Never past the end of the day.
    var late = Dates.nextHalfHour(new Date(2026, 8, 15, 23, 45, 0).getTime())
    verify(late < Dates.MINUTES)
  }

  // --- what somebody typed ---------------------------------------------------

  function test_every_way_a_person_writes_half_past_nine() {
    var ways = ["9:30", "930", "0930", "09:30", "9.30", "9h30", "9 30", "9:30 pm"]
    var wanted = [570, 570, 570, 570, 570, 570, 570, 1290]
    for (var i = 0; i < ways.length; i++)
      compare(Dates.parseTime(ways[i]), wanted[i], ways[i])
  }

  function test_a_bare_hour_is_the_hour() {
    compare(Dates.parseTime("9"), 540)
    compare(Dates.parseTime("09"), 540)
    compare(Dates.parseTime("21"), 1260)
    compare(Dates.parseTime("100"), 60)
    compare(Dates.parseTime("1200"), 720)
  }

  function test_noon_and_midnight_are_the_two_a_twelve_hour_clock_gets_wrong() {
    compare(Dates.parseTime("12am"), 0)
    compare(Dates.parseTime("12pm"), 720)
    compare(Dates.parseTime("12:30am"), 30)
    compare(Dates.parseTime("1pm"), 780)
  }

  function test_what_is_not_a_time_is_refused_rather_than_guessed_at() {
    var rubbish = ["", "abc", "25:00", "9:75", "24", "2400", "-1", "9:", ":30", "13pm", "0pm"]
    for (var i = 0; i < rubbish.length; i++)
      compare(Dates.parseTime(rubbish[i]), -1, rubbish[i])
  }

  function test_a_time_is_shown_on_the_clock_the_rest_of_the_phone_is_on() {
    compare(Dates.formatTime(570), "09:30")
    compare(Dates.formatTime(0), "00:00")
    compare(Dates.formatTime(1290), "21:30")
    compare(Dates.formatTime(-1), "")
    compare(Dates.formatSpan(540, 600), "09:00 – 10:00")
    // An event with no length is a moment, and says so with one time.
    compare(Dates.formatSpan(540, 540), "09:00")
  }

  function test_how_long_it_is_reads_as_a_length_rather_than_as_a_sum() {
    compare(Dates.formatLength(0), "")
    compare(Dates.formatLength(20), "20 min")
    compare(Dates.formatLength(60), "1 hour")
    compare(Dates.formatLength(90), "1 hour 30 min")
    compare(Dates.formatLength(120), "2 hours")
  }
}
