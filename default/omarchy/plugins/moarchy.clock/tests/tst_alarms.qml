// When an alarm goes off, which is the one thing in this app that cannot be
// checked by looking at it.
//
// Every case here is a morning somebody would otherwise have to wait for:
// does a weekday alarm skip Sunday, does one set for 23:55 at midnight ring in
// five minutes or in a day, does an alarm that came due while the phone was
// off still ring, and does one that came due three hours ago stay quiet.
//
// The clock these run against is the container's, which is UTC. Nothing here
// asserts an absolute epoch for that reason: the assertions are about the
// *local* hour, weekday and ordering of what comes back, which are the things
// the app actually uses and the things that stay true in Berlin.
import QtQuick
import QtTest
import "../Alarms.js" as Alarms

TestCase {
  name: "Alarms"

  // A fixed instant to reason from: Tuesday, 10:09 local, whatever local is.
  function tuesdayMorning() {
    var d = new Date(2026, 8, 15, 10, 9, 36, 0)
    return d.getTime()
  }

  function at(hour, minute, days, extra) {
    var alarm = Alarms.blank(hour, minute)
    alarm.id = "t"
    alarm.days = days || []
    if (extra) for (var key in extra) alarm[key] = extra[key]
    return alarm
  }

  function hourOf(ms) { return new Date(ms).getHours() }
  function minuteOf(ms) { return new Date(ms).getMinutes() }
  function dayOf(ms) { return new Date(ms).getDay() }

  // --- reading a row -------------------------------------------------------

  function test_a_row_without_a_time_on_it_is_not_an_alarm() {
    compare(Alarms.normalise(null, 1), null)
    compare(Alarms.normalise({}, 1), null)
    compare(Alarms.normalise({ hour: 7 }, 1), null)
    compare(Alarms.normalise({ hour: 24, minute: 0 }, 1), null)
    compare(Alarms.normalise({ hour: 7, minute: 60 }, 1), null)
    compare(Alarms.normalise({ hour: -1, minute: 0 }, 1), null)
    compare(Alarms.normalise({ hour: "7", minute: 0 }, 1), null)
  }

  function test_a_row_gets_an_id_of_its_own_when_it_has_none() {
    var alarm = Alarms.normalise({ hour: 7, minute: 0 }, 3)
    verify(alarm.id.length > 0)
    compare(alarm.enabled, true)
    compare(alarm.days.length, 0)
    compare(alarm.fired, 0)
  }

  function test_days_are_sorted_deduplicated_and_kept_in_range() {
    var alarm = Alarms.normalise({ hour: 7, minute: 0, days: [5, 1, 1, 9, -2, 0] }, 1)
    compare(JSON.stringify(alarm.days), "[0,1,5]")
  }

  function test_off_is_written_down_and_nothing_else_is_assumed() {
    compare(Alarms.normalise({ hour: 7, minute: 0, enabled: false }, 1).enabled, false)
    // Anything that is not the boolean false is an alarm that is on, because a
    // file with no `enabled` in it is the ordinary case.
    compare(Alarms.normalise({ hour: 7, minute: 0, enabled: "no" }, 1).enabled, true)
  }

  // --- the next one --------------------------------------------------------

  function test_later_today_is_today() {
    var now = tuesdayMorning()
    var when = Alarms.nextFire(at(13, 0), now)
    compare(hourOf(when), 13)
    compare(minuteOf(when), 0)
    compare(dayOf(when), 2)
    compare(Alarms.whichDay(when, now), "today")
  }

  function test_earlier_today_is_tomorrow() {
    var now = tuesdayMorning()
    var when = Alarms.nextFire(at(6, 40), now)
    compare(hourOf(when), 6)
    compare(dayOf(when), 3)
    compare(Alarms.whichDay(when, now), "tomorrow")
  }

  function test_a_weekday_alarm_on_a_friday_evening_waits_for_monday() {
    // Friday 18 September 2026, 20:00 local.
    var friday = new Date(2026, 8, 18, 20, 0, 0, 0).getTime()
    var when = Alarms.nextFire(at(6, 40, [1, 2, 3, 4, 5]), friday)
    compare(dayOf(when), 1)
    compare(hourOf(when), 6)
  }

  function test_five_to_midnight_at_midnight_is_five_minutes_away() {
    var midnight = new Date(2026, 8, 15, 0, 0, 0, 0).getTime()
    var when = Alarms.nextFire(at(0, 5), midnight)
    compare(when - midnight, 5 * 60000)
    compare(Alarms.whichDay(when, midnight), "today")
  }

  function test_an_alarm_that_is_off_never_goes_off() {
    var now = tuesdayMorning()
    compare(Alarms.nextFire(at(13, 0, [], { enabled: false }), now), 0)
    compare(Alarms.due(at(9, 0, [], { enabled: false }), now), 0)
  }

  function test_a_day_number_that_is_not_a_day_becomes_a_one_off() {
    // This is why the app has no "never" state to draw. A file can name day 7,
    // or -1, or "Tuesday"; normalise() drops every one of them, and a day list
    // that comes out empty means "once" rather than "not any day" -- so an
    // alarm that is switched on always has a next time, and every screen can
    // say what it is.
    var alarm = at(7, 0)
    alarm.days = [7, -1, "Tuesday"]
    var read = Alarms.normalise(alarm, 1)
    compare(read.days.length, 0)
    compare(Alarms.repeatLabel(read.days), "Once")
    verify(Alarms.nextFire(read, tuesdayMorning()) > 0)
  }

  function test_an_alarm_that_is_on_always_has_a_next_time() {
    // The claim the screens rely on, over every shape a day list can take.
    var now = tuesdayMorning()
    var shapes = [[], [0], [6], [2], [1, 2, 3, 4, 5], [0, 6], [0, 1, 2, 3, 4, 5, 6]]
    for (var i = 0; i < shapes.length; i++) {
      for (var hour = 0; hour < 24; hour += 7) {
        var alarm = at(hour, 30, shapes[i])
        var when = Alarms.nextFire(alarm, now)
        verify(when > now)
        compare(hourOf(when), hour)
        compare(minuteOf(when), 30)
        if (shapes[i].length) verify(shapes[i].indexOf(dayOf(when)) >= 0)
      }
    }
  }

  function test_the_soonest_of_several_is_the_one_reported() {
    var now = tuesdayMorning()
    var a = at(13, 0); a.id = "one"
    var b = at(11, 30); b.id = "two"
    var c = at(6, 0, [], { enabled: false }); c.id = "three"
    var best = Alarms.soonest([a, b, c], now)
    compare(best.alarm.id, "two")
    compare(hourOf(best.at), 11)
  }

  function test_nothing_armed_is_nothing_reported() {
    compare(Alarms.soonest([], tuesdayMorning()), null)
    compare(Alarms.soonest([at(7, 0, [], { enabled: false })], tuesdayMorning()), null)
  }

  // --- what is due ---------------------------------------------------------

  function test_an_alarm_is_due_the_moment_it_arrives() {
    var alarm = at(10, 0)
    var now = new Date(2026, 8, 15, 10, 0, 0, 0).getTime()
    compare(Alarms.due(alarm, now), Alarms.before(alarm, now))
    compare(hourOf(Alarms.due(alarm, now)), 10)
  }

  function test_a_minute_before_it_is_not_due() {
    var alarm = at(10, 0)
    var now = new Date(2026, 8, 15, 9, 59, 0, 0).getTime()
    // Yesterday's ten o'clock, and this is the case `fired` exists for.
    var yesterday = Alarms.before(alarm, now)
    compare(hourOf(yesterday), 10)
    alarm.fired = yesterday
    compare(Alarms.due(alarm, now), 0)
  }

  function test_one_that_has_already_rung_does_not_ring_again() {
    var alarm = at(10, 0)
    var now = new Date(2026, 8, 15, 10, 0, 30, 0).getTime()
    var at0 = Alarms.due(alarm, now)
    verify(at0 > 0)
    var after = Alarms.rang(alarm, at0)
    compare(Alarms.due(after, now), 0)
    compare(Alarms.due(after, now + 60000), 0)
  }

  function test_a_phone_that_was_off_for_ten_minutes_still_rings() {
    var alarm = at(10, 0)
    var now = new Date(2026, 8, 15, 10, 10, 0, 0).getTime()
    verify(Alarms.due(alarm, now) > 0)
    compare(Alarms.missed(alarm, now), 0)
    compare(Alarms.lateLabel(now - Alarms.due(alarm, now)), "10 minutes late")
  }

  function test_a_phone_that_was_off_for_three_hours_records_it_as_missed() {
    var alarm = at(10, 0)
    var now = new Date(2026, 8, 15, 13, 0, 0, 0).getTime()
    compare(Alarms.due(alarm, now), 0)
    verify(Alarms.missed(alarm, now) > 0)
    compare(hourOf(Alarms.missed(alarm, now)), 10)
  }

  function test_the_hour_is_the_line_and_it_is_a_parameter() {
    var alarm = at(10, 0)
    var now = new Date(2026, 8, 15, 10, 30, 0, 0).getTime()
    verify(Alarms.due(alarm, now, 3600) > 0)
    compare(Alarms.due(alarm, now, 600), 0)
    verify(Alarms.missed(alarm, now, 600) > 0)
  }

  function test_a_one_off_switches_itself_off_after_it_has_rung() {
    var once = at(10, 0)
    var repeating = at(10, 0, [1, 2, 3, 4, 5])
    var now = new Date(2026, 8, 15, 10, 0, 0, 0).getTime()
    compare(Alarms.rang(once, now).enabled, false)
    compare(Alarms.rang(repeating, now).enabled, true)
  }

  // --- arming --------------------------------------------------------------
  //
  // `fired` is the occurrence that has been dealt with, and these three are the
  // reason the app writes it the instant an alarm is set or switched on rather
  // than leaving it at zero. Every one of them was a real bug first.

  function test_an_alarm_set_for_five_minutes_time_is_not_one_that_was_missed() {
    var now = new Date(2026, 8, 15, 10, 9, 0, 0).getTime()
    var alarm = at(10, 15, [], { fired: 0 })
    // Zero: the most recent occurrence of 10:15 is *yesterday's*, unrung and
    // more than an hour ago, so a brand new alarm is announced as slept
    // through. This is what the editor must not do.
    verify(Alarms.missed(alarm, now) > 0)
    // Armed from now: nothing before this instant counts.
    alarm.fired = now
    compare(Alarms.missed(alarm, now), 0)
    compare(Alarms.due(alarm, now), 0)
    // ...and it still goes off in six minutes.
    var when = Alarms.nextFire(alarm, now)
    compare(when - now, 6 * 60000)
    verify(Alarms.due(alarm, when) > 0)
  }

  function test_an_alarm_set_for_nine_minutes_ago_does_not_go_off_at_once() {
    var now = new Date(2026, 8, 15, 10, 9, 0, 0).getTime()
    var alarm = at(10, 0, [], { fired: 0 })
    verify(Alarms.due(alarm, now) > 0)
    alarm.fired = now
    compare(Alarms.due(alarm, now), 0)
    compare(dayOf(Alarms.nextFire(alarm, now)), 3)
  }

  function test_arming_does_not_swallow_the_next_morning() {
    // The other half of the same rule: arming must not be a way of switching
    // an alarm off. Tomorrow's occurrence is after `fired`, so it is still due.
    var now = new Date(2026, 8, 15, 10, 9, 0, 0).getTime()
    var alarm = at(6, 40, [1, 2, 3, 4, 5], { fired: now })
    var when = Alarms.nextFire(alarm, now)
    compare(hourOf(when), 6)
    compare(dayOf(when), 3)
    compare(Alarms.due(alarm, when), when)
  }

  // --- snoozing ------------------------------------------------------------

  function test_a_snooze_is_nine_minutes_and_outranks_the_schedule() {
    var alarm = at(10, 0)
    var now = new Date(2026, 8, 15, 10, 0, 5, 0).getTime()
    var snoozed = Alarms.snooze(alarm, now)
    compare(snoozed.snoozed - now, 9 * 60000)
    compare(Alarms.nextFire(snoozed, now), snoozed.snoozed)
    compare(Alarms.due(snoozed, now), 0)
    compare(Alarms.due(snoozed, snoozed.snoozed), snoozed.snoozed)
  }

  function test_snoozing_records_the_occurrence_so_it_cannot_come_round_twice() {
    var alarm = at(10, 0)
    var now = new Date(2026, 8, 15, 10, 0, 5, 0).getTime()
    var snoozed = Alarms.snooze(alarm, now)
    var rung = Alarms.rang(snoozed, snoozed.snoozed)
    compare(rung.snoozed, 0)
    compare(Alarms.due(rung, snoozed.snoozed + 1000), 0)
  }

  function test_a_snooze_slept_through_is_missed_rather_than_rung_late() {
    var alarm = at(10, 0)
    var now = new Date(2026, 8, 15, 10, 0, 0, 0).getTime()
    var snoozed = Alarms.snooze(alarm, now)
    var late = snoozed.snoozed + 2 * 3600 * 1000
    compare(Alarms.due(snoozed, late), 0)
    compare(Alarms.missed(snoozed, late), snoozed.snoozed)
  }

  // --- what it all reads as ------------------------------------------------

  function test_the_repeat_is_named_where_it_has_a_name() {
    compare(Alarms.repeatLabel([]), "Once")
    compare(Alarms.repeatLabel([0, 1, 2, 3, 4, 5, 6]), "Every day")
    compare(Alarms.repeatLabel([1, 2, 3, 4, 5]), "Weekdays")
    compare(Alarms.repeatLabel([0, 6]), "Weekends")
    compare(Alarms.repeatLabel([1, 3, 5]), "Mon Wed Fri")
  }

  function test_twelve_and_twenty_four_hour_clocks() {
    compare(Alarms.timeText(0, 5, true), "00:05")
    compare(Alarms.timeText(0, 5, false), "12:05")
    compare(Alarms.timeText(13, 30, true), "13:30")
    compare(Alarms.timeText(13, 30, false), "1:30")
    compare(Alarms.timeText(12, 0, false), "12:00")
    compare(Alarms.meridiem(0), "AM")
    compare(Alarms.meridiem(11), "AM")
    compare(Alarms.meridiem(12), "PM")
    compare(Alarms.meridiem(23), "PM")
  }

  function test_how_long_until_it_goes_off() {
    compare(Alarms.untilLabel(0), "now")
    compare(Alarms.untilLabel(20 * 1000), "in under a minute")
    compare(Alarms.untilLabel(45 * 60000), "in 45 min")
    compare(Alarms.untilLabel(60 * 60000), "in 1 h")
    compare(Alarms.untilLabel((7 * 60 + 20) * 60000), "in 7 h 20 min")
    compare(Alarms.untilLabel(24 * 3600 * 1000), "in 1 d")
    compare(Alarms.untilLabel(45 * 3600 * 1000), "in 1 d 21 h")
  }

  function test_how_late_it_is_and_when_that_stops_being_worth_saying() {
    compare(Alarms.lateLabel(30 * 1000), "")
    compare(Alarms.lateLabel(60 * 1000), "a minute late")
    compare(Alarms.lateLabel(4 * 60000), "4 minutes late")
    compare(Alarms.lateLabel(3600 * 1000), "an hour late")
    compare(Alarms.lateLabel(3 * 3600 * 1000), "3 hours late")
  }
}
