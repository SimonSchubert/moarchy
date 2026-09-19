// Streaks, strength and milestones, against the numbers
// apps/habits/moarchy_habits/habits.py produces.
//
// Every expectation was taken by running the Python, not by reading it. The
// score especially: it is a thirty-day-half-life moving average normalised by
// its own ceiling, and "close enough" is how two halves of one app quietly come
// to disagree about how well somebody is doing.
import QtQuick
import QtTest
import "../Habits.js" as Habits

TestCase {
  name: "Habits"

  readonly property string today: "2026-09-15"

  function run(days) {
    var e = ({})
    for (var i = 0; i < days.length; i++) e[Habits.addDays(today, -days[i])] = 1.0
    return e
  }

  function daily(entries) {
    return Habits.make({ kind: Habits.BOOLEAN, freq_num: 1, freq_den: 1,
                         target: 1.0, entries: entries })
  }

  function seq(from, to) {
    var out = []
    for (var i = from; i < to; i++) out.push(i)
    return out
  }

  // --- days ---------------------------------------------------------------

  function test_day_arithmetic_crosses_months_and_years() {
    compare(Habits.addDays("2026-03-01", -1), "2026-02-28")
    compare(Habits.addDays("2026-01-01", -1), "2025-12-31")
    compare(Habits.addDays("2026-12-31", 1), "2027-01-01")
    // 2028 is a leap year; 2026 is not.
    compare(Habits.addDays("2028-02-28", 1), "2028-02-29")
    compare(Habits.daysBetween("2026-09-01", "2026-09-15"), 14)
  }

  function test_a_key_that_is_not_a_date_is_not_a_day() {
    verify(Habits.isDay("2026-09-15"))
    verify(!Habits.isDay("2026-02-31"))
    verify(!Habits.isDay("2026-9-5"))
    verify(!Habits.isDay("yesterday"))
    verify(!Habits.isDay(""))
  }

  // --- streaks ------------------------------------------------------------

  function test_twelve_straight_days() {
    var h = daily(run(seq(0, 12)))
    compare(Habits.streak(h, today), 12)
    compare(Habits.keptDays(h), 12)
    compare(Habits.total(h), 12)
    compare(Habits.score(h, today), 1.0)
    var next = Habits.nextMilestone(h, today)
    compare(next.target, 30)
    compare(next.away, 18)
  }

  function test_today_is_forgiving_and_yesterday_is_not() {
    // A day that has not been kept *yet* does not break a streak, because the
    // day is not over.
    var soft = daily(run(seq(1, 13)))
    compare(Habits.streak(soft, today), 12)
    fuzzyCompare(Habits.score(soft, today), 0.9119679174, 1e-9)

    // Yesterday missed is a real break.
    var hard = daily(run([0].concat(seq(2, 13))))
    compare(Habits.streak(hard, today), 1)
    fuzzyCompare(Habits.score(hard, today), 0.913978573, 1e-9)
    compare(Habits.nextMilestone(hard, today).target, 7)
    compare(Habits.nextMilestone(hard, today).away, 6)
  }

  function test_three_times_a_week_is_on_track_between_the_three() {
    // The whole point of saying three times a week rather than naming which
    // three: the trailing week holds three kept days, so every day in it counts.
    var days = []
    for (var i = 0; i < 42; i++) if (i % 7 === 0 || i % 7 === 2 || i % 7 === 4) days.push(i)
    var h = Habits.make({ kind: Habits.BOOLEAN, freq_num: 3, freq_den: 7,
                          target: 1.0, entries: run(days) })
    compare(Habits.streak(h, today), 36)
    compare(Habits.keptDays(h), 18)
    fuzzyCompare(Habits.score(h, today), 0.9362927374, 1e-9)
  }

  function test_a_measurable_habit_counts_only_days_that_reached_its_target() {
    var e = ({})
    for (var i = 0; i < 20; i++) e[Habits.addDays(today, -i)] = (i % 3) ? 8.0 : 5.0
    var h = Habits.make({ kind: Habits.MEASURABLE, freq_num: 1, freq_den: 1,
                          target: 8.0, entries: e })
    compare(Habits.streak(h, today), 2)
    compare(Habits.keptDays(h), 13)
    compare(Habits.total(h), 139)
    fuzzyCompare(Habits.score(h, today), 0.6456744062, 1e-9)
  }

  function test_a_habit_with_nothing_in_it() {
    var h = daily(({}))
    compare(Habits.streak(h, today), 0)
    compare(Habits.score(h, today), 0)
    compare(Habits.bestStreak(h, today), 0)
    compare(Habits.nextMilestone(h, today).target, 7)
    compare(Habits.nextMilestone(h, today).away, 7)
  }

  function test_a_long_perfect_run_reaches_the_ceiling_not_past_it() {
    // A perfect run converges on (1 - decay^n), not on 1, so the score is
    // normalised -- without which it would never quite reach full strength.
    var h = daily(run(seq(0, 90)))
    compare(Habits.streak(h, today), 90)
    compare(Habits.score(h, today), 1.0)
    compare(Habits.nextMilestone(h, today).target, 100)
    compare(Habits.nextMilestone(h, today).away, 10)
  }

  function test_best_streak_finds_a_run_that_has_since_ended() {
    var e = ({})
    for (var i = 0; i < 9; i++) e[Habits.addDays("2026-01-10", i)] = 1.0
    var h = daily(e)
    compare(Habits.bestStreak(h, "2026-09-15"), 9)
    compare(Habits.streak(h, "2026-01-18"), 9)
    // The run is long over, so today's streak is nothing.
    compare(Habits.streak(h, today), 0)
  }

  // --- milestones ---------------------------------------------------------

  function test_a_milestone_is_crossed_once_data() {
    return [
      { tag: "into 7",     before: 6,  after: 7,  want: 7 },
      { tag: "past 7",     before: 7,  after: 8,  want: null },
      { tag: "over 30",    before: 29, after: 31, want: 30 },
      { tag: "going down", before: 40, after: 39, want: null },
      { tag: "standing",   before: 10, after: 10, want: null }
    ]
  }
  function test_a_milestone_is_crossed_once(row) {
    // Re-ticking a day inside a 40-day streak must not re-announce the 30.
    compare(Habits.milestoneCrossed(row.before, row.after), row.want)
  }

  // --- ticking ------------------------------------------------------------

  function test_toggle_sets_the_target_for_a_measurable_habit() {
    var h = Habits.make({ kind: Habits.MEASURABLE, target: 8.0, entries: ({}) })
    compare(Habits.toggle(h, today), true)
    compare(Habits.value(h, today), 8.0)
    compare(Habits.toggle(h, today), false)
    compare(Habits.value(h, today), 0)
  }

  function test_toggle_sets_one_for_a_boolean_habit() {
    var h = daily(({}))
    compare(Habits.toggle(h, today), true)
    compare(Habits.value(h, today), 1.0)
  }

  function test_a_zero_removes_the_day_rather_than_storing_it() {
    var h = daily(({}))
    Habits.setValue(h, today, 3)
    Habits.setValue(h, today, 0)
    compare(h.entries[today], undefined)
  }

  function test_the_memo_is_dropped_when_a_day_changes() {
    // on_track is memoised because it is the innermost question in the app; a
    // stale answer after a tick would leave the streak reading the old day.
    var h = daily(run(seq(1, 5)))
    compare(Habits.streak(h, today), 4)
    Habits.toggle(h, today)
    compare(Habits.streak(h, today), 5)
    Habits.toggle(h, Habits.addDays(today, -1))
    compare(Habits.streak(h, today), 1)
  }

  // --- the file -----------------------------------------------------------

  function test_a_file_python_wrote_reads_here() {
    var doc = {
      schema: 2,
      habits: [{ id: "abc", name: "Read", question: "Did you read?", kind: "boolean",
                 target: 1.0, unit: "", colour: "green", freq_num: 1, freq_den: 1,
                 created: 1757930000.0, archived: false,
                 entries: { "2026-09-15": 1.0, "2026-09-14": 1.0 } }],
      meta: { achievements: { "first-week": "2026-09-01" } }
    }
    var got = Habits.parse(doc)
    compare(got.habits.length, 1)
    compare(got.habits[0].name, "Read")
    compare(Habits.streak(got.habits[0], today), 2)
    compare(got.achievements["first-week"], "2026-09-01")
  }

  function test_a_bad_entry_key_is_dropped_not_fatal() {
    var got = Habits.parse({ habits: [{ id: "x", name: "X",
      entries: { "2026-09-15": 1.0, "not-a-date": 2.0, "2026-02-31": 1.0 } }] })
    compare(Habits.keptDays(got.habits[0]), 1)
  }

  function test_a_zero_or_negative_entry_does_not_survive_the_read() {
    var got = Habits.parse({ habits: [{ id: "x", entries: { "2026-09-15": 0, "2026-09-14": -3 } }] })
    compare(Habits.total(got.habits[0]), 0)
  }

  function test_defaults_replace_a_malformed_habit_rather_than_dropping_it() {
    var got = Habits.parse({ habits: [{ id: "x", kind: "nonsense", target: -4,
                                        freq_num: 0, freq_den: 999 }] })
    var h = got.habits[0]
    compare(h.kind, Habits.BOOLEAN)
    compare(h.target, 1.0)
    compare(h.freq_num, 1)
    // MAX_PERIOD guards the rolling-window scan from a ten-year lookback.
    compare(h.freq_den, Habits.MAX_PERIOD)
  }

  function test_what_we_write_round_trips() {
    var h = daily(run(seq(0, 3)))
    h.name = "Walk"
    var back = Habits.parse(JSON.parse(Habits.serialize([h], { "a": "2026-01-01" })))
    compare(back.habits[0].name, "Walk")
    compare(Habits.streak(back.habits[0], today), 3)
    compare(back.achievements["a"], "2026-01-01")
    // schema 2, the same one store.py writes.
    compare(JSON.parse(Habits.serialize([h], ({}))).schema, 2)
  }

  function test_the_memo_never_reaches_the_file() {
    var h = daily(run(seq(0, 2)))
    Habits.streak(h, today)
    var written = JSON.parse(Habits.serialize([h], ({})))
    compare(written.habits[0]._tracked, undefined)
  }

  function test_today_counts_every_active_habit() {
    // Including ones whose frequency does not require them today: a 3x-a-week
    // habit still offers a box to tick on a Tuesday.
    var a = daily(run([0]))
    var b = Habits.make({ kind: Habits.BOOLEAN, freq_num: 3, freq_den: 7, entries: ({}) })
    var c = Habits.make({ kind: Habits.BOOLEAN, archived: true, entries: ({}) })
    var p = Habits.todayProgress([a, b, c], today)
    compare(p.done, 1)
    compare(p.due, 2)
  }

  // --- the mark -----------------------------------------------------------

  function test_a_boolean_day_is_all_or_nothing() {
    var h = daily(({}))
    compare(Habits.stepFor(h, today), 0)
    Habits.setValue(h, today, 1)
    compare(Habits.stepFor(h, today), Habits.STEPS)
  }

  function test_a_measurable_day_is_a_proportion_of_its_target_data() {
    // Six of eight glasses is visibly more than two, and reaching the target is
    // the only way to the top rung.
    return [
      { tag: "none",     amount: 0, step: 0 },
      { tag: "a sip",    amount: 0.5, step: 1 },
      { tag: "two",      amount: 2, step: 2 },
      { tag: "four",     amount: 4, step: 3 },
      { tag: "six",      amount: 6, step: 3 },
      { tag: "eight",    amount: 8, step: Habits.STEPS },
      { tag: "over",     amount: 20, step: Habits.STEPS }
    ]
  }
  function test_a_measurable_day_is_a_proportion_of_its_target(row) {
    var h = Habits.make({ kind: Habits.MEASURABLE, target: 8.0, entries: ({}) })
    if (row.amount > 0) Habits.setValue(h, today, row.amount)
    compare(Habits.stepFor(h, today), row.step)
  }

  function test_anything_started_is_at_least_rung_one() {
    var h = Habits.make({ kind: Habits.MEASURABLE, target: 100.0, entries: ({}) })
    Habits.setValue(h, today, 0.01)
    compare(Habits.stepFor(h, today), 1)
  }
}
