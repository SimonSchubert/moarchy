// Points, levels and the ten achievements.
//
// The port of apps/habits/moarchy_habits/game.py. Every predicate reads the
// store as it is now rather than as it just changed, so an achievement whose
// condition was met before the app learned to record it is still awarded the
// first time it is checked -- which is why they are written as questions about
// history rather than about the last tap.
.pragma library
.import "Habits.js" as Habits

// A kept day is worth this much on its own...
var BASE_POINTS = 10

// ...plus one per day of the streak it belongs to, capped so that a very long
// streak does not make a new habit feel pointless to start.
var STREAK_BONUS_CAP = 10

// A single daily habit earns 10-20 a day, so the first level is about a week
// and the last is a year of several habits -- far enough apart that arriving is
// an event.
var LEVELS = [
  [0, "Day one"],
  [100, "Getting going"],
  [300, "Regular"],
  [700, "Committed"],
  [1500, "Steady"],
  [3000, "Ingrained"],
  [6000, "Second nature"]
]

// A sweep means sweeping more than one thing. With a single habit it would be
// the same event as "First day", handed out twice under two names.
var SWEEP_MINIMUM = 2

function dayPoints(habit, day) {
  if (!Habits.kept(habit, day)) return 0
  // The bonus is capped, so the streak is only counted as far as the cap. This
  // is summed over every day a habit has been kept, and counting the whole of a
  // long streak to then throw all but ten of it away is most of what a tap used
  // to cost.
  var run = Habits.streak(habit, day, STREAK_BONUS_CAP)
  return BASE_POINTS + Math.min(run, STREAK_BONUS_CAP)
}

function habitPoints(habit) {
  var total = 0
  for (var key in habit.entries) {
    if (!Habits.isDay(key)) continue
    total += dayPoints(habit, key)
  }
  return total
}

function totalPoints(habits) {
  var list = Habits.active(habits)
  var total = 0
  for (var i = 0; i < list.length; i++) total += habitPoints(list[i])
  return total
}

// (level from 1, its name, points into it, points still to go). The last level
// has nowhere to go and says so with null rather than inventing a bigger number
// nobody will reach.
function levelFor(points) {
  var index = 0
  for (var i = 0; i < LEVELS.length; i++) if (points >= LEVELS[i][0]) index = i
  var floor = LEVELS[index][0], name = LEVELS[index][1]
  if (index + 1 >= LEVELS.length)
    return { level: index + 1, name: name, into: points - floor, toGo: null }
  return { level: index + 1, name: name, into: points - floor,
           toGo: LEVELS[index + 1][0] - points }
}

// --- the predicates --------------------------------------------------------

function anyStreak(habits, length, today) {
  var list = Habits.active(habits)
  for (var i = 0; i < list.length; i++)
    if (Habits.bestStreak(list[i], today) >= length) return true
  return false
}

// The first day a habit can fairly be judged on: its creation date normally,
// but a habit whose history was imported has entries older than the record of
// its own creation, and judging it from the later of the two would throw that
// history away. The earlier wins.
function trackedSince(habit) {
  var days = []
  if (habit.created > 0) days.push(Habits.iso(habit.created * 1000))
  for (var key in habit.entries) if (Habits.isDay(key)) days.push(key)
  if (!days.length) return null
  var first = days[0]
  for (var i = 1; i < days.length; i++) if (days[i] < first) first = days[i]
  return first
}

// Worked out once and handed down, because trackedSince reads a habit's whole
// history and the two sweeps below ask about hundreds of days.
function trackedFrom(habits) {
  var list = Habits.active(habits)
  var out = []
  for (var i = 0; i < list.length; i++)
    out.push({ habit: list[i], since: trackedSince(list[i]) })
  return out
}

// The habits that existed on a day, so a day is not judged against habits that
// had not been started yet.
function dueOn(tracked, day) {
  var out = []
  for (var i = 0; i < tracked.length; i++)
    if (tracked[i].since !== null && tracked[i].since <= day) out.push(tracked[i].habit)
  return out
}

function allKept(list, day) {
  for (var i = 0; i < list.length; i++) if (!Habits.kept(list[i], day)) return false
  return true
}

function perfectDays(habits) {
  var seen = ({})
  var list = Habits.active(habits)
  for (var i = 0; i < list.length; i++)
    for (var key in list[i].entries) if (Habits.isDay(key)) seen[key] = true
  var tracked = trackedFrom(habits)
  var count = 0
  for (var day in seen) {
    var due = dueOn(tracked, day)
    if (due.length >= SWEEP_MINIMUM && allKept(due, day)) count += 1
  }
  return count
}

function perfectRun(habits, length, today) {
  if (!Habits.active(habits).length) return false
  var tracked = trackedFrom(habits)
  var run = 0
  for (var back = 0; back < 400; back++) {
    var day = Habits.addDays(today, -back)
    var due = dueOn(tracked, day)
    if (due.length < SWEEP_MINIMUM) continue
    if (allKept(due, day)) {
      run += 1
      if (run >= length) return true
    } else {
      run = 0
    }
  }
  return false
}

// A streak of a week or more, built after a gap of three days or more. The one
// worth rewarding most: everybody starts; the people who keep a habit are the
// ones who start again.
function comeback(habits) {
  var list = Habits.active(habits)
  for (var i = 0; i < list.length; i++) {
    var keys = []
    for (var key in list[i].entries) if (Habits.isDay(key)) keys.push(key)
    if (keys.length < 2) continue
    keys.sort()
    var gapSeen = false, run = 0, previous = null
    for (var j = 0; j < keys.length; j++) {
      var day = keys[j]
      var apart = previous === null ? null : Habits.daysBetween(previous, day)
      if (apart !== null && apart >= 4) { gapSeen = true; run = 0 }
      run = (previous === null || apart === 1) ? run + 1 : 1
      if (gapSeen && run >= 7) return true
      previous = day
    }
  }
  return false
}

function totalKept(habits) {
  var list = Habits.active(habits)
  var total = 0
  for (var i = 0; i < list.length; i++) total += Habits.keptDays(list[i])
  return total
}

// --- the ten ---------------------------------------------------------------

var ACHIEVEMENTS = [
  ["first", "First day", "Keep any habit once"],
  ["week", "A full week", "Reach a 7-day streak"],
  ["month", "A month", "Reach a 30-day streak"],
  ["century", "A hundred", "Reach a 100-day streak"],
  ["year", "A year", "Reach a 365-day streak"],
  ["perfect", "Clean sweep", "Keep every habit on the same day"],
  ["perfect_week", "Seven clean", "Keep every habit, seven days running"],
  ["comeback", "Back on it", "Build a week-long streak after a lapse"],
  ["handful", "A handful", "Track five habits at once"],
  ["hundred_days", "Hundred days", "Keep habits on a hundred days in total"]
]

function keys() {
  var out = []
  for (var i = 0; i < ACHIEVEMENTS.length; i++) out.push(ACHIEVEMENTS[i][0])
  return out
}

function qualifies(habits, key, today) {
  switch (key) {
    case "first":        return totalKept(habits) >= 1
    case "week":         return anyStreak(habits, Habits.MILESTONES[0], today)
    case "month":        return anyStreak(habits, Habits.MILESTONES[1], today)
    case "century":      return anyStreak(habits, Habits.MILESTONES[2], today)
    case "year":         return anyStreak(habits, Habits.MILESTONES[3], today)
    case "perfect":      return perfectDays(habits) >= 1
    case "perfect_week": return perfectRun(habits, 7, today)
    case "comeback":     return comeback(habits)
    case "handful":      return Habits.active(habits).length >= 5
    case "hundred_days": return totalKept(habits) >= 100
  }
  return false
}

// Achievements the store qualifies for and has not been credited with. Does not
// record them -- the caller does, so the UI decides when to say so and the
// storage layer stays the only thing that writes.
function newlyEarned(habits, earned, today) {
  var out = []
  var all = keys()
  for (var i = 0; i < all.length; i++) {
    var key = all[i]
    if (earned[key] === undefined && qualifies(habits, key, today)) out.push(key)
  }
  return out
}

function describe(key) {
  for (var i = 0; i < ACHIEVEMENTS.length; i++)
    if (ACHIEVEMENTS[i][0] === key)
      return { name: ACHIEVEMENTS[i][1], blurb: ACHIEVEMENTS[i][2] }
  return { name: key, blurb: "" }
}
