// The stopwatch and the timer, as arithmetic.
//
// The property worth testing is the one the file's comment claims: neither
// counts. Both are a subtraction from a remembered instant, so a tick that
// never arrives -- a phone asleep for twenty minutes in the middle of a run --
// cannot lose the time it was asleep for. That is what most of these are: the
// clock jumped, and the answer is still right.
import QtQuick
import QtTest
import "../Watch.js" as Watch

TestCase {
  name: "Watch"

  // --- the stopwatch -------------------------------------------------------

  function test_a_watch_nobody_has_started_reads_zero() {
    var w = Watch.blankWatch()
    compare(Watch.elapsed(w, 1000), 0)
    compare(Watch.watchText(Watch.elapsed(w, 1000)), "00:00.0")
    compare(w.laps.length, 0)
  }

  function test_a_running_watch_is_the_clock_minus_when_it_started() {
    var w = Watch.startWatch(Watch.blankWatch(), 1000)
    compare(Watch.elapsed(w, 1000), 0)
    compare(Watch.elapsed(w, 4600), 3600)
  }

  function test_the_time_a_phone_spent_asleep_is_still_measured() {
    var w = Watch.startWatch(Watch.blankWatch(), 0)
    // No ticks at all between these two readings, which is exactly what a
    // suspended phone gives the app.
    compare(Watch.elapsed(w, 20 * 60000), 20 * 60000)
  }

  function test_stopping_banks_what_has_run_and_resuming_adds_to_it() {
    var w = Watch.startWatch(Watch.blankWatch(), 0)
    w = Watch.stopWatch(w, 5000)
    compare(w.running, false)
    compare(Watch.elapsed(w, 900000), 5000)
    w = Watch.startWatch(w, 100000)
    compare(Watch.elapsed(w, 101000), 6000)
  }

  function test_starting_a_running_watch_and_stopping_a_stopped_one_do_nothing() {
    var w = Watch.startWatch(Watch.blankWatch(), 0)
    compare(Watch.startWatch(w, 5000).since, 0)
    var s = Watch.stopWatch(w, 5000)
    compare(Watch.stopWatch(s, 9000).accrued, 5000)
  }

  function test_a_lap_is_a_mark_on_the_elapsed_time() {
    var w = Watch.startWatch(Watch.blankWatch(), 0)
    w = Watch.lapWatch(w, 58400)
    w = Watch.lapWatch(w, 117200)
    compare(JSON.stringify(w.laps), "[58400,117200]")
  }

  function test_a_lap_on_a_stopped_watch_is_not_a_lap() {
    var w = Watch.stopWatch(Watch.startWatch(Watch.blankWatch(), 0), 5000)
    compare(Watch.lapWatch(w, 6000).laps.length, 0)
  }

  function test_two_taps_in_the_same_millisecond_are_one_lap() {
    var w = Watch.startWatch(Watch.blankWatch(), 0)
    w = Watch.lapWatch(w, 5000)
    w = Watch.lapWatch(w, 5000)
    compare(w.laps.length, 1)
  }

  function test_the_lap_list_is_newest_first_with_the_one_in_progress_on_top() {
    var w = Watch.startWatch(Watch.blankWatch(), 0)
    w = Watch.lapWatch(w, 58400)
    w = Watch.lapWatch(w, 117200)
    w = Watch.lapWatch(w, 179900)
    var rows = Watch.lapRows(w, 221600)
    compare(rows.length, 4)
    compare(rows[0].index, 4)
    compare(rows[0].running, true)
    compare(rows[0].lap, 41700)
    compare(rows[1].index, 3)
    compare(rows[3].index, 1)
    compare(rows[3].lap, 58400)
  }

  function test_best_and_worst_are_over_the_finished_laps_only() {
    var w = Watch.startWatch(Watch.blankWatch(), 0)
    w = Watch.lapWatch(w, 58400)
    w = Watch.lapWatch(w, 117200)
    w = Watch.lapWatch(w, 179900)
    var rows = Watch.lapRows(w, 221600)
    // 58400, 58800, 62700 -- and 41700 still running, which is quicker than
    // any of them and must not be the best.
    compare(rows[0].best, false)
    compare(rows[3].best, true)
    compare(rows[1].worst, true)
  }

  function test_a_single_lap_is_neither_the_best_nor_the_worst() {
    var w = Watch.lapWatch(Watch.startWatch(Watch.blankWatch(), 0), 5000)
    var rows = Watch.lapRows(Watch.stopWatch(w, 9000), 9000)
    compare(rows.length, 1)
    compare(rows[0].best, false)
    compare(rows[0].worst, false)
  }

  function test_two_identical_laps_are_not_marked_either() {
    var w = Watch.startWatch(Watch.blankWatch(), 0)
    w = Watch.lapWatch(w, 5000)
    w = Watch.lapWatch(w, 10000)
    var rows = Watch.lapRows(Watch.stopWatch(w, 10000), 10000)
    compare(rows[0].best, false)
    compare(rows[1].worst, false)
  }

  function test_the_digits_stop_at_a_tenth_and_grow_an_hour_when_they_need_one() {
    compare(Watch.watchText(0), "00:00.0")
    compare(Watch.watchText(999), "00:00.9")
    compare(Watch.watchText(59999), "00:59.9")
    compare(Watch.watchText(221600), "03:41.6")
    compare(Watch.watchText(3600000), "1:00:00.0")
    compare(Watch.watchText(3723400), "1:02:03.4")
    // Truncated, not rounded: a stopwatch that reads 1.0 when it has run for
    // 0.96 seconds is a stopwatch that is ahead of itself.
    compare(Watch.watchText(1960), "00:01.9")
  }

  function test_the_ring_follows_the_second_hand_of_the_thing_being_timed() {
    compare(Watch.watchSweep(0), 0)
    compare(Watch.watchSweep(30000), 0.5)
    compare(Watch.watchSweep(59999), 59 / 60)
    compare(Watch.watchSweep(60000), 0)
    compare(Watch.watchSweep(221600), 41 / 60)
  }

  // --- the timer -----------------------------------------------------------

  function test_a_timer_is_when_it_ends_rather_than_what_is_left() {
    var t = Watch.startTimer(300000, 1000)
    compare(t.endsAt, 301000)
    compare(Watch.timerLeft(t, 1000), 300000)
    compare(Watch.timerLeft(t, 101000), 200000)
    // Twenty minutes with no ticks in them.
    compare(Watch.timerLeft(t, 1000 + 20 * 60000), 0)
  }

  function test_a_timer_of_nothing_is_not_a_timer() {
    compare(Watch.startTimer(0, 1000).total, 0)
    compare(Watch.startTimer(-5, 1000).running, false)
  }

  function test_pausing_keeps_what_is_left_and_resuming_puts_it_back_on_the_clock() {
    var t = Watch.startTimer(300000, 0)
    t = Watch.pauseTimer(t, 100000)
    compare(t.running, false)
    compare(t.left, 200000)
    compare(Watch.timerLeft(t, 999999), 200000)
    t = Watch.resumeTimer(t, 500000)
    compare(t.endsAt, 700000)
    compare(Watch.timerLeft(t, 600000), 100000)
  }

  function test_resuming_one_that_has_nothing_left_does_nothing() {
    var t = Watch.pauseTimer(Watch.startTimer(1000, 0), 5000)
    compare(t.left, 0)
    compare(Watch.resumeTimer(t, 6000).running, false)
  }

  function test_a_minute_on_grows_the_total_with_it() {
    var t = Watch.startTimer(300000, 0)
    t = Watch.extendTimer(t, 100000, 60000)
    compare(t.total, 360000)
    compare(t.endsAt, 360000)
    compare(Watch.timerLeft(t, 100000), 260000)
    // ...so the ring is never asked to draw more than a full turn.
    verify(Watch.timerProgress(t, 100000) <= 1)
  }

  function test_a_minute_on_while_paused_stays_paused() {
    var t = Watch.pauseTimer(Watch.startTimer(300000, 0), 100000)
    t = Watch.extendTimer(t, 100000, 60000)
    compare(t.running, false)
    compare(t.left, 260000)
    compare(t.total, 360000)
  }

  function test_the_ring_empties_and_never_goes_past_either_end() {
    var t = Watch.startTimer(300000, 0)
    compare(Watch.timerProgress(t, 0), 1)
    compare(Watch.timerProgress(t, 150000), 0.5)
    compare(Watch.timerProgress(t, 300000), 0)
    compare(Watch.timerProgress(t, 900000), 0)
    compare(Watch.timerProgress(Watch.blankTimer(), 0), 0)
  }

  function test_a_finished_timer_is_due_and_one_slept_through_is_missed() {
    var t = Watch.startTimer(300000, 0)
    compare(Watch.timerDue(t, 299000), 0)
    compare(Watch.timerDue(t, 300000), 300000)
    compare(Watch.timerDue(t, 300000 + 10 * 60000), 300000)
    compare(Watch.timerDue(t, 300000 + 3 * 3600 * 1000), 0)
    compare(Watch.timerMissed(t, 300000 + 10 * 60000), 0)
    compare(Watch.timerMissed(t, 300000 + 3 * 3600 * 1000), 300000)
  }

  function test_a_paused_timer_is_never_due() {
    var t = Watch.pauseTimer(Watch.startTimer(300000, 0), 100000)
    compare(Watch.timerDue(t, 9999999), 0)
    compare(Watch.timerMissed(t, 9999999), 0)
  }

  function test_the_countdown_is_rounded_up_so_the_last_second_is_shown() {
    compare(Watch.timerText(0), "00:00")
    compare(Watch.timerText(1), "00:01")
    compare(Watch.timerText(1000), "00:01")
    compare(Watch.timerText(1001), "00:02")
    compare(Watch.timerText(202000), "03:22")
    compare(Watch.timerText(3600000), "1:00:00")
  }

  function test_a_duration_in_words() {
    compare(Watch.spanLabel(45000), "45 s")
    compare(Watch.spanLabel(60000), "1 min")
    compare(Watch.spanLabel(300000), "5 min")
    compare(Watch.spanLabel(330000), "5 min 30 s")
    compare(Watch.spanLabel(3600000), "1 h")
    compare(Watch.spanLabel(5400000), "1 h 30 min")
  }

  // --- the keypad ----------------------------------------------------------

  function test_digits_push_in_from_the_right() {
    var d = []
    d = Watch.push(d, 5)
    compare(Watch.keypadMs(d), 5000)
    d = Watch.push(d, 0)
    compare(Watch.keypadMs(d), 50000)
    d = Watch.push(d, 0)
    compare(Watch.keypadMs(d), 5 * 60000)
    compare(Watch.keypadClock(d), "00:05:00")
  }

  function test_a_leading_zero_would_waste_one_of_the_six() {
    compare(Watch.push([], 0).length, 0)
    compare(Watch.push([1], 0).length, 2)
  }

  function test_six_digits_is_the_lot() {
    var d = []
    for (var i = 0; i < 9; i++) d = Watch.push(d, 1)
    compare(d.length, 6)
    compare(Watch.keypadClock(d), "11:11:11")
  }

  function test_nothing_out_of_range_gets_in() {
    compare(Watch.push([], 10).length, 0)
    compare(Watch.push([], -1).length, 0)
  }

  function test_backspace_takes_one_and_stops_at_empty() {
    compare(Watch.pop([1, 2, 3]).length, 2)
    compare(Watch.pop([]).length, 0)
  }

  function test_ninety_seconds_typed_is_a_minute_and_a_half() {
    // The microwave rule. Nothing normalises what was typed until it runs.
    var d = Watch.push(Watch.push([], 9), 0)
    compare(Watch.keypadClock(d), "00:00:90")
    compare(Watch.keypadMs(d), 90000)
    compare(Watch.spanLabel(Watch.keypadMs(d)), "1 min 30 s")
  }

  function test_the_untyped_leading_zeros_are_the_ones_drawn_dim() {
    compare(Watch.keypadLit([]), 8)
    compare(Watch.keypadLit([5]), 7)
    compare(Watch.keypadLit([5, 0]), 6)
    compare(Watch.keypadLit([5, 0, 0]), 4)
    compare(Watch.keypadLit([1, 5, 0, 0]), 3)
    compare(Watch.keypadLit([1, 2, 3, 4, 5, 6]), 0)
    // The cells themselves, which is what the QML actually draws.
    var cells = Watch.keypadCells([5, 0, 0])
    compare(cells.length, 6)
    compare(cells[0].text, "0")
    compare(cells[0].on, false)
    compare(cells[3].text, "5")
    compare(cells[3].on, true)
  }

  function test_a_preset_lands_on_the_keypad_as_something_editable() {
    compare(Watch.keypadMs(Watch.digitsFor(300000)), 300000)
    compare(JSON.stringify(Watch.digitsFor(300000)), "[5,0,0]")
    compare(JSON.stringify(Watch.digitsFor(1800000)), "[3,0,0,0]")
    compare(JSON.stringify(Watch.digitsFor(3600000)), "[1,0,0,0,0]")
    compare(JSON.stringify(Watch.digitsFor(0)), "[]")
  }
}
