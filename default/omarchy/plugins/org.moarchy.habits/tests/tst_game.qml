// Points, levels and the ten achievements, against apps/habits/.../game.py.
//
// The predicates are the interesting half: they read the store as it is now, so
// an achievement earned before the app could record it is still awarded the
// first time it is checked. Numbers below came from running the Python.
import QtQuick
import QtTest
import "../Habits.js" as Habits
import "../Game.js" as Game

TestCase {
  name: "HabitsGame"

  readonly property string today: "2026-09-15"
  // 2026-09-04 local midnight, which is what Python's datetime.timestamp() gave
  // for the fixtures below.
  readonly property real created: 1788480000

  function run(n) {
    var e = ({})
    for (var i = 0; i < n; i++) e[Habits.addDays(today, -i)] = 1.0
    return e
  }

  function habit(name, entries) {
    return Habits.make({ name: name, kind: Habits.BOOLEAN, freq_num: 1, freq_den: 1,
                         target: 1.0, created: created, entries: entries })
  }

  function two() { return [habit("Read", run(12)), habit("Walk", run(12))] }

  // --- points -------------------------------------------------------------

  function test_a_kept_day_is_worth_ten_plus_its_streak_capped() {
    var a = habit("Read", run(12))
    compare(Game.dayPoints(a, today), 20)
    // The cap is why: a very long streak must not make a new habit feel
    // pointless to start.
    compare(Game.habitPoints(a), 195)
    compare(Game.totalPoints(two()), 390)
  }

  function test_a_day_that_was_not_kept_is_worth_nothing() {
    var a = habit("Read", ({}))
    compare(Game.dayPoints(a, today), 0)
    compare(Game.habitPoints(a), 0)
  }

  function test_levels_data() {
    return [
      { tag: "0",     points: 0,     level: 1, name: "Day one",        into: 0,     toGo: 100 },
      { tag: "99",    points: 99,    level: 1, name: "Day one",        into: 99,    toGo: 1 },
      { tag: "100",   points: 100,   level: 2, name: "Getting going",  into: 0,     toGo: 200 },
      { tag: "699",   points: 699,   level: 3, name: "Regular",        into: 399,   toGo: 1 },
      { tag: "700",   points: 700,   level: 4, name: "Committed",      into: 0,     toGo: 800 },
      { tag: "5999",  points: 5999,  level: 6, name: "Ingrained",      into: 2999,  toGo: 1 },
      // The last level has nowhere to go and says so, rather than inventing a
      // bigger number nobody will reach.
      { tag: "6000",  points: 6000,  level: 7, name: "Second nature",  into: 0,     toGo: null },
      { tag: "99999", points: 99999, level: 7, name: "Second nature",  into: 93999, toGo: null }
    ]
  }
  function test_levels(row) {
    var got = Game.levelFor(row.points)
    compare(got.level, row.level)
    compare(got.name, row.name)
    compare(got.into, row.into)
    compare(got.toGo, row.toGo)
  }

  // --- the sweeps ---------------------------------------------------------

  function test_a_clean_sweep_needs_more_than_one_habit() {
    compare(Game.perfectDays(two()), 12)
    compare(Game.perfectRun(two(), 7, today), true)
    // With a single habit it would be the same event as "First day", handed out
    // twice under two names.
    compare(Game.perfectDays([habit("Read", run(12))]), 0)
    compare(Game.perfectRun([habit("Read", run(12))], 7, today), false)
  }

  function test_a_day_is_not_judged_against_habits_that_did_not_exist_yet() {
    var old = habit("Old", run(12))
    var fresh = Habits.make({ name: "New", kind: Habits.BOOLEAN, target: 1.0,
                              created: created, entries: run(2) })
    // The newer habit is tracked from its first entry, so the ten days before
    // it are still judged on the one habit that existed -- and one habit is
    // under the sweep minimum, so they are not perfect days.
    verify(Game.perfectDays([old, fresh]) <= 2)
  }

  function test_total_kept_counts_every_active_habit() {
    compare(Game.totalKept(two()), 24)
  }

  // --- the comeback -------------------------------------------------------

  function test_a_comeback_needs_a_gap_and_then_a_week() {
    // Five days, a gap, then eight: the one worth rewarding most, because
    // everybody starts and the people who keep a habit are the ones who
    // start again.
    var e = ({})
    for (var i = 0; i < 5; i++) e[Habits.addDays("2026-06-01", i)] = 1.0
    for (var j = 10; j < 18; j++) e[Habits.addDays("2026-06-01", j)] = 1.0
    compare(Game.comeback([habit("Comeback", e)]), true)

    // An unbroken run is not a comeback, however long.
    compare(Game.comeback(two()), false)
  }

  // --- what gets awarded --------------------------------------------------

  function test_newly_earned_matches_python() {
    var got = Game.newlyEarned(two(), ({}), today)
    compare(got.join(","), "first,week,perfect,perfect_week")
  }

  function test_an_achievement_already_credited_is_not_offered_again() {
    var got = Game.newlyEarned(two(), { first: "2026-01-01", week: "2026-01-02" }, today)
    compare(got.join(","), "perfect,perfect_week")
  }

  function test_five_habits_are_a_handful() {
    var many = []
    for (var i = 0; i < 5; i++) many.push(habit("H" + i, ({})))
    compare(Game.qualifies(many, "handful", today), true)
    compare(Game.qualifies(two(), "handful", today), false)
  }

  function test_every_achievement_has_a_name_and_a_blurb() {
    var all = Game.keys()
    compare(all.length, 10)
    for (var i = 0; i < all.length; i++) {
      var d = Game.describe(all[i])
      verify(d.name.length > 0)
      verify(d.blurb.length > 0)
    }
  }

  function test_an_unknown_key_qualifies_for_nothing() {
    compare(Game.qualifies(two(), "not-a-thing", today), false)
    compare(Game.describe("not-a-thing").name, "not-a-thing")
  }
}
