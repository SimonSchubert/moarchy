// One file, and the rows in it this app cannot read.
//
// `~/.local/share/moarchy-clock/clock.json` holds three unrelated things that
// share a file because they share an app: the alarms somebody set, the
// stopwatch as it was left, and the timer as it was left. Only the first is
// worth keeping in the sense that losing it matters; the other two are in
// there so that answering the door does not reset a stopwatch, which is the
// single thing that makes a phone stopwatch useless.
//
// `strays` is Calendar's arrangement and it is here for its reason. FileView
// already refuses to overwrite a file that will not parse and moves a broken
// one aside, so the *document* is guarded. A row is not: a file that parses
// cleanly can hold an alarm with no hour on it, there is nowhere to draw such
// a thing, and the next save would write the file back without it. So every
// row that cannot be read is kept exactly as found and written back untouched.
// The app is then free to ignore it, which is the only way to ignore something
// without destroying it.
.pragma library
.import "Alarms.js" as Alarms
.import "Watch.js" as Watch

var SCHEMA = 1

function defaults() {
  // `hour24` is deliberately absent rather than false. Nobody has chosen yet,
  // and the app resolves that against the phone's own locale -- a boolean here
  // would be this file choosing on their behalf, in a repository whose other
  // half already gets the twelve-or-twenty-four question from the desktop.
  return { hour24: null, silent: false }
}

function bool(value, fallback) {
  return typeof value === "boolean" ? value : fallback
}

function number(value) {
  if (typeof value !== "number" || !isFinite(value) || value < 0) return 0
  return Math.floor(value)
}

function readSettings(data) {
  var out = defaults()
  if (!data || typeof data !== "object") return out
  if (typeof data.hour24 === "boolean") out.hour24 = data.hour24
  out.silent = bool(data.silent, false)
  return out
}

function readWatch(data) {
  var out = Watch.blankWatch()
  if (!data || typeof data !== "object") return out
  out.running = bool(data.running, false)
  out.since = number(data.since)
  out.accrued = number(data.accrued)
  var marks = data.laps
  if (marks && marks.constructor === Array) {
    var previous = 0
    for (var i = 0; i < marks.length && out.laps.length < Watch.MAX_LAPS; i++) {
      var at = number(marks[i])
      // Marks have to climb, or the lap arithmetic produces negative laps out
      // of a file somebody has reordered by hand.
      if (at <= previous) continue
      out.laps.push(at)
      previous = at
    }
  }
  // A watch that says it is running with no start is a file written while the
  // power went. It stops where it stood rather than starting from 1970.
  if (out.running && !out.since) out.running = false
  return out
}

function readTimer(data) {
  var out = Watch.blankTimer()
  if (!data || typeof data !== "object") return out
  out.running = bool(data.running, false)
  out.total = Math.min(Watch.TIMER_MAX, number(data.total))
  out.endsAt = number(data.endsAt)
  out.left = Math.min(Watch.TIMER_MAX, number(data.left))
  if (out.running && !out.endsAt) out.running = false
  if (!out.total) return Watch.blankTimer()
  return out
}

// Returns { alarms, strays, watch, timer, settings }.
function parse(data) {
  var out = {
    alarms: [], strays: [],
    watch: Watch.blankWatch(), timer: Watch.blankTimer(),
    settings: defaults()
  }
  if (!data || typeof data !== "object") return out

  var rows = data.alarms
  if (rows && rows.constructor === Array) {
    var seen = {}
    for (var i = 0; i < rows.length; i++) {
      if (out.alarms.length >= Alarms.MAX) break
      var alarm = Alarms.normalise(rows[i], i + 1)
      if (alarm === null) { out.strays.push(rows[i]); continue }
      // Two rows with one id is a file that has been copied and pasted, and it
      // is the shape that makes deleting one alarm delete two. The second copy
      // is given an id of its own rather than dropped.
      if (seen[alarm.id]) alarm.id = Alarms.newId(i + 1)
      seen[alarm.id] = true
      out.alarms.push(alarm)
    }
  }

  out.watch = readWatch(data.stopwatch)
  out.timer = readTimer(data.timer)
  out.settings = readSettings(data.settings)
  return out
}

// In the order the screen shows them: earliest in the day first, so that the
// file and the list agree and a diff of the file reads like the app.
function sorted(alarms) {
  var out = alarms.slice()
  out.sort(function (a, b) {
    if (a.hour !== b.hour) return a.hour - b.hour
    if (a.minute !== b.minute) return a.minute - b.minute
    return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0)
  })
  return out
}

function alarmTo(alarm) {
  var row = {
    id: alarm.id,
    hour: alarm.hour,
    minute: alarm.minute,
    label: alarm.label,
    days: alarm.days.slice(),
    enabled: alarm.enabled
  }
  // Absent rather than zero. These two are bookkeeping, not settings, and a
  // file whose every alarm carries `"fired": 0` invites somebody to wonder
  // what it means.
  if (alarm.fired) row.fired = alarm.fired
  if (alarm.snoozed) row.snoozed = alarm.snoozed
  return row
}

function serialize(state) {
  var rows = []
  var ordered = sorted(state.alarms)
  for (var i = 0; i < ordered.length; i++) rows.push(alarmTo(ordered[i]))
  // The strays go back on the end. Anywhere else and they would move about
  // between saves for no reason a reader could see.
  var strays = state.strays || []
  for (var j = 0; j < strays.length; j++) rows.push(strays[j])

  var settings = { silent: !!state.settings.silent }
  if (typeof state.settings.hour24 === "boolean") settings.hour24 = state.settings.hour24

  return JSON.stringify({
    schema: SCHEMA,
    alarms: rows,
    stopwatch: {
      running: !!state.watch.running,
      since: state.watch.since,
      accrued: state.watch.accrued,
      laps: state.watch.laps.slice()
    },
    timer: {
      running: !!state.timer.running,
      total: state.timer.total,
      endsAt: state.timer.endsAt,
      left: state.timer.left
    },
    settings: settings
  }, null, 1) + "\n"
}

// --- the list -------------------------------------------------------------

function put(alarms, alarm) {
  var out = []
  var replaced = false
  for (var i = 0; i < alarms.length; i++) {
    if (alarms[i].id === alarm.id) { out.push(alarm); replaced = true; continue }
    out.push(alarms[i])
  }
  if (!replaced) out.push(alarm)
  return out
}

function drop(alarms, id) {
  var out = []
  for (var i = 0; i < alarms.length; i++)
    if (alarms[i].id !== id) out.push(alarms[i])
  return out
}
