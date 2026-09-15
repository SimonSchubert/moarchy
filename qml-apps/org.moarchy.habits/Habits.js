// Habits: what was done on which day, and how strong that makes each one.
//
// The port of apps/habits/moarchy_habits/habits.py, keeping its split: nothing
// here touches QML, so the arithmetic that decides a streak, a strength score
// and a milestone is testable with no display -- which is where 58 of that
// app's tests lived, and where they carry over to.
//
// Days are ISO strings and the arithmetic is done in UTC. Python's `date` has
// no timezone at all, so UTC is the faithful translation: a local-time Date
// would put a habit's day boundary on the phone's offset and make a tick near
// midnight land on yesterday after a flight.
.pragma library

var SCHEMA = 2

var BOOLEAN = "boolean"
var MEASURABLE = "measurable"

// How much history the strength score remembers. Thirty days of doing a habit
// puts the score near the top; thirty days of not doing it puts it near the
// bottom. Short enough that a bad fortnight shows, long enough that one missed
// Tuesday does not read as failure.
var HALF_LIFE_DAYS = 30.0

// The streaks worth saying something about. Deliberately short: a list of
// twenty milestones is a list of twenty non-events.
var MILESTONES = [7, 30, 100, 365]

// Days shown across a phone row. Five 44px targets plus gaps is what fits
// beside a readable habit name at 360px.
var STRIP_DAYS = 5

// The longest trailing window a frequency may be expressed over. Guards the
// rolling-window scan from a malformed file asking for ten years of lookback
// on every repaint.
var MAX_PERIOD = 31

// --- days ------------------------------------------------------------------

var DAY_MS = 86400000

function iso(ms) {
  var d = new Date(ms)
  function two(n) { return n < 10 ? "0" + n : String(n) }
  return d.getUTCFullYear() + "-" + two(d.getUTCMonth() + 1) + "-" + two(d.getUTCDate())
}

// An ISO day back to milliseconds, or NaN if it is not one. Strict on purpose:
// a key that is not a date would break every window scan later, where there is
// no good place to report it.
function dayMs(text) {
  var s = String(text || "")
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return NaN
  var parts = s.split("-")
  var y = parseInt(parts[0], 10), m = parseInt(parts[1], 10), d = parseInt(parts[2], 10)
  if (m < 1 || m > 12 || d < 1 || d > 31) return NaN
  var ms = Date.UTC(y, m - 1, d)
  // Rejects 2026-02-31, which Date.UTC would roll into March.
  return iso(ms) === s ? ms : NaN
}

function isDay(text) { return !isNaN(dayMs(text)) }

function addDays(day, n) { return iso(dayMs(day) + n * DAY_MS) }

function daysBetween(from, to) {
  return Math.round((dayMs(to) - dayMs(from)) / DAY_MS)
}

// The day the app believes it is. MOARCHY_HABITS_TODAY is the harness's, and a
// habit is kept on a local calendar day rather than a UTC one -- so "today" is
// read off the phone's own clock and then used as a bare label.
function todayFrom(now, override) {
  if (override && isDay(override)) return override
  var d = now ? new Date(now) : new Date()
  function two(n) { return n < 10 ? "0" + n : String(n) }
  return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate())
}

function recentDays(count, end) {
  var out = []
  var n = count || STRIP_DAYS
  for (var i = n - 1; i >= 0; i--) out.push(addDays(end, -i))
  return out
}

// --- one habit -------------------------------------------------------------

function number(value, fallback) {
  if (typeof value !== "number" || !isFinite(value)) return fallback
  return value
}

function make(fields) {
  var h = {
    id: "", name: "", question: "", kind: BOOLEAN, target: 1.0, unit: "",
    colour: "green", freq_num: 1, freq_den: 1, created: 0, archived: false,
    entries: ({})
  }
  for (var k in (fields || {})) h[k] = fields[k]
  if (!h.id) h.id = newId()
  // on_track is asked the same question thousands of times over: scoring walks
  // every day a habit has recorded and a streak walks back from each. The memo
  // lives on the habit, where every caller benefits, and is dropped by every
  // write below rather than by hand at each call site.
  h._tracked = ({})
  return h
}

// uuid4().hex, near enough: this only has to be unique within one file.
function newId() {
  var out = ""
  for (var i = 0; i < 32; i++) out += Math.floor(Math.random() * 16).toString(16)
  return out
}

function forget(habit) { habit._tracked = ({}) }

function value(habit, day) {
  var v = habit.entries[day]
  return typeof v === "number" ? v : 0
}

// Was the habit's own bar met on this particular day?
function kept(habit, day) {
  return habit.target > 0 ? value(habit, day) >= habit.target : value(habit, day) > 0
}

function keptIsTarget(habit) {
  return habit.kind === MEASURABLE && habit.target > 0
}

function isDaily(habit) { return habit.freq_num >= habit.freq_den }

function setValue(habit, day, amount) {
  if (amount <= 0) delete habit.entries[day]
  else habit.entries[day] = amount
  forget(habit)
}

function toggle(habit, day) {
  if (kept(habit, day)) { setValue(habit, day, 0); return false }
  setValue(habit, day, keptIsTarget(habit) ? habit.target : 1.0)
  return true
}

// Is the habit meeting its own frequency as of this day?
//
// A daily habit is on track on a day it was kept. A "three times a week" habit
// is on track on any day where the trailing week already holds three kept days
// -- which is the whole point of saying three times a week rather than naming
// which three.
function onTrack(habit, day) {
  var memo = habit._tracked
  if (memo === undefined) { habit._tracked = ({}); memo = habit._tracked }
  var answer = memo[day]
  if (answer !== undefined) return answer
  if (isDaily(habit)) {
    answer = kept(habit, day)
  } else {
    var period = Math.min(Math.max(habit.freq_den, 1), MAX_PERIOD)
    var need = Math.min(Math.max(habit.freq_num, 1), period)
    var hit = 0
    for (var i = 0; i < period; i++) if (kept(habit, addDays(day, -i))) hit += 1
    answer = hit >= need
  }
  memo[day] = answer
  return answer
}

// Consecutive on-track days ending today.
//
// Today is forgiving: a day that has not been kept *yet* does not break a
// streak, because the day is not over. Yesterday is not forgiving.
//
// `limit` stops counting once the answer has reached it, for a caller that only
// needs to know whether a streak got that far. A limited count is
// min(real streak, limit), so it may only be compared against numbers at or
// below the limit.
function streak(habit, upto, limit) {
  var day = upto
  if (!onTrack(habit, day)) day = addDays(day, -1)
  var count = 0
  // A habit older than ten years has bigger problems than a wrong number.
  var cap = limit === undefined || limit === null ? 3660 : Math.min(limit, 3660)
  for (var i = 0; i < cap; i++) {
    if (!onTrack(habit, day)) break
    count += 1
    day = addDays(day, -1)
  }
  return count
}

// The milestone a streak just passed, if it passed one. Takes both numbers
// rather than just the new one, because the reward is for *crossing*:
// re-ticking a day inside a 40-day streak must not re-announce the 30.
function milestoneCrossed(before, after) {
  if (after <= before) return null
  for (var i = 0; i < MILESTONES.length; i++) {
    var m = MILESTONES[i]
    if (before < m && m <= after) return m
  }
  return null
}

function nextMilestone(habit, upto) {
  var run = streak(habit, upto)
  for (var i = 0; i < MILESTONES.length; i++)
    if (MILESTONES[i] > run) return { target: MILESTONES[i], away: MILESTONES[i] - run }
  return null
}

function firstDay(habit) {
  var first = null
  for (var key in habit.entries) {
    if (!isDay(key)) continue
    if (first === null || key < first) first = key
  }
  return first
}

function bestStreak(habit, upto) {
  var first = firstDay(habit)
  if (first === null) return 0
  var best = 0, run = 0
  var day = first
  while (day <= upto) {
    if (onTrack(habit, day)) { run += 1; if (run > best) best = run }
    else run = 0
    day = addDays(day, 1)
  }
  return best
}

// Strength, 0.0 to 1.0: an exponential moving average of on-track days.
//
// A streak is binary and cruel -- it says nothing between "42" and "0" -- while
// this drops a little for a missed day and recovers as fast as it fell.
function score(habit, upto) {
  var first = firstDay(habit)
  if (first === null) return 0
  var span = daysBetween(first, upto)
  if (span < 0) return 0
  var decay = Math.pow(0.5, 1.0 / HALF_LIFE_DAYS)
  var total = 0
  // Walk forward from the first record so early days decay away properly.
  for (var i = 0; i <= span; i++) {
    total = total * decay + (1.0 - decay) * (onTrack(habit, addDays(first, i)) ? 1 : 0)
  }
  // Normalise: a perfect run converges on (1 - decay^n), not on 1.
  var ceiling = 1.0 - Math.pow(decay, span + 1)
  return ceiling > 0 ? Math.min(total / ceiling, 1.0) : 0
}

function total(habit) {
  var sum = 0
  for (var k in habit.entries) sum += habit.entries[k]
  return sum
}

function keptDays(habit) {
  var n = 0
  for (var k in habit.entries) if (isDay(k) && kept(habit, k)) n += 1
  return n
}

// --- the file --------------------------------------------------------------

function habitFrom(data) {
  if (!data || typeof data !== "object" || data.constructor === Array) return null
  var entries = ({})
  var raw = data.entries
  if (raw && typeof raw === "object" && raw.constructor !== Array) {
    for (var key in raw) {
      // A key that is not a date would break every window scan later.
      if (!isDay(key)) continue
      var amount = number(raw[key], 0)
      if (amount > 0) entries[key] = amount
    }
  }
  var kind = data.kind === MEASURABLE ? MEASURABLE : BOOLEAN
  var target = number(data.target, 1.0)
  return make({
    id: String(data.id || "") || newId(),
    name: String(data.name || ""),
    question: String(data.question || ""),
    kind: kind,
    target: target > 0 ? target : 1.0,
    unit: String(data.unit || ""),
    colour: String(data.colour || "green"),
    freq_num: Math.max(Math.round(number(data.freq_num, 1)), 1),
    freq_den: Math.min(Math.max(Math.round(number(data.freq_den, 1)), 1), MAX_PERIOD),
    created: number(data.created, 0),
    archived: !!data.archived,
    entries: entries
  })
}

function habitTo(habit) {
  return {
    id: habit.id,
    name: habit.name,
    question: habit.question,
    kind: habit.kind,
    target: habit.target,
    unit: habit.unit,
    colour: habit.colour,
    freq_num: habit.freq_num,
    freq_den: habit.freq_den,
    created: habit.created,
    archived: habit.archived,
    entries: habit.entries
  }
}

function parse(data) {
  var out = { habits: [], achievements: ({}) }
  if (!data || typeof data !== "object") return out
  var records = data.habits
  if (records && records.constructor === Array) {
    for (var i = 0; i < records.length; i++) {
      var habit = habitFrom(records[i])
      if (habit) out.habits.push(habit)
    }
  }
  var meta = data.meta
  var earned = meta && typeof meta === "object" ? meta.achievements : null
  if (earned && typeof earned === "object" && earned.constructor !== Array) {
    for (var key in earned) out.achievements[String(key)] = String(earned[key])
  }
  return out
}

function serialize(habits, achievements) {
  var out = []
  for (var i = 0; i < habits.length; i++) out.push(habitTo(habits[i]))
  return JSON.stringify({
    schema: SCHEMA,
    habits: out,
    meta: { achievements: achievements || ({}) }
  }, null, 1)
}

function active(habits) {
  var out = []
  for (var i = 0; i < habits.length; i++) if (!habits[i].archived) out.push(habits[i])
  return out
}

// (kept, total) for today.
//
// Counts every active habit, including ones whose frequency does not require
// them today. A "3x a week" habit still offers a box to tick on a Tuesday, so a
// day where every box is ticked is a real thing to finish -- and pretending a
// habit is not there today would make the count move for reasons the user
// cannot see.
function todayProgress(habits, day) {
  var list = active(habits)
  var done = 0
  for (var i = 0; i < list.length; i++) if (kept(list[i], day)) done += 1
  return { done: done, due: list.length }
}

// --- the mark ---------------------------------------------------------------

// The ramp a day's mark is filled along, light and dark. Step 0 is untouched.
var RAMP_DARK = [0.0, 0.30, 0.55, 0.80, 1.0]
var RAMP_LIGHT = [0.0, 0.22, 0.44, 0.68, 0.92]
var STEPS = RAMP_DARK.length - 1

// Which rung of the ramp a day sits on, 0 (untouched) to STEPS.
//
// A boolean habit is all or nothing. A measurable one is a proportion of its
// target, so "six of eight glasses" is visibly more than two, and reaching the
// target is the only way to the top rung.
function stepFor(habit, day) {
  var v = value(habit, day)
  if (v <= 0) return 0
  if (habit.kind !== MEASURABLE || habit.target <= 0) return STEPS
  if (v >= habit.target) return STEPS
  var share = v / habit.target
  // Anything started is at least rung 1, so a day worked on never reads empty.
  return Math.max(1, Math.min(STEPS - 1, Math.floor(share * STEPS) + 1))
}

function rampAt(dark, step) {
  var ramp = dark ? RAMP_DARK : RAMP_LIGHT
  return ramp[Math.max(0, Math.min(step, STEPS))]
}
