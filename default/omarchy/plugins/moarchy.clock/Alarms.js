// When an alarm goes off, and what happens when nothing was listening.
//
// Every time in this app is an epoch in **milliseconds**, here and in the file
// on disk. One unit rather than two: the stopwatch next door needs tenths of a
// second, seconds would not carry them, and a module that took seconds beside
// one that took milliseconds is a division by a thousand waiting to be
// forgotten in the one place where being out by that factor means an alarm
// that rings in 1970.
//
// The arithmetic is local wall time and it is done with `Date`. That is
// deliberate, and it is the opposite of what Calendar's Dates.js does: a
// calendar's nine o'clock is *floating* -- nine on Tuesday wherever you are --
// and an alarm's seven o'clock is an instant, the one at which this phone's
// clock reads 07:00. `setHours` and `setDate` are the only two operations that
// know where the daylight saving boundaries are, so they are the two used.
// Spring forward over an alarm set for 02:30 and `setHours(2, 30)` lands on
// 03:30, which is the hour that exists and the answer every phone gives.
//
// Nothing here touches QML, which is what lets the part that can be wrong --
// does a weekday alarm skip Sunday, does one that came due while the phone was
// asleep still ring -- be answered by a test rather than by waiting until
// tomorrow morning.
.pragma library

var SCHEMA = 1

// More alarms than anybody keeps, and few enough that the list stays one
// screen of scrolling rather than a search problem.
var MAX = 24

// Nine, which is the number every mechanical clock radio used because the
// gear that drove the snooze could not divide ten into the hour cleanly. It
// has outlived its reason and is still the number people expect.
var SNOOZE_MINUTES = 9

// How late an alarm may be and still be worth ringing, in seconds.
//
// This is the whole of what this app can honestly do about a phone that was
// asleep or switched off: nothing here can wake it -- see the README -- so an
// alarm that came due while it was off rings when it comes back, and says how
// late it is. An hour is the line. Ringing at ten for a seven o'clock alarm is
// not a late alarm, it is a confusing one, and it gets recorded as missed
// instead.
var LATE_LIMIT = 3600

var DAY_INITIAL = ["S", "M", "T", "W", "T", "F", "S"]
var DAY_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

var WEEKDAYS = [1, 2, 3, 4, 5]
var WEEKEND = [0, 6]

// --- reading a row somebody may have typed --------------------------------

function str(value) {
  return typeof value === "string" ? value.trim() : ""
}

function whole(value, lo, hi) {
  if (typeof value !== "number" || !isFinite(value)) return null
  var n = Math.floor(value)
  return (n < lo || n > hi) ? null : n
}

function stamp(value) {
  if (typeof value !== "number" || !isFinite(value) || value <= 0) return 0
  return Math.floor(value)
}

function dayList(value) {
  if (!value || value.constructor !== Array) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    var day = whole(value[i], 0, 6)
    if (day === null || out.indexOf(day) >= 0) continue
    out.push(day)
  }
  out.sort(function (a, b) { return a - b })
  return out
}

function newId(seq) {
  return "a" + Date.now().toString(36) + "-" + seq
}

// An alarm, or null for a row this app has nowhere to draw. Store.js keeps
// those rather than dropping them; a row with no hour on it is still somebody's
// file.
function normalise(data, seq) {
  if (!data || typeof data !== "object") return null
  var hour = whole(data.hour, 0, 23)
  var minute = whole(data.minute, 0, 59)
  if (hour === null || minute === null) return null
  return {
    id: str(data.id) || newId(seq),
    hour: hour,
    minute: minute,
    label: str(data.label),
    days: dayList(data.days),
    enabled: data.enabled !== false,
    // The occurrence that has already rung, so that a tick two seconds later
    // does not ring it again.
    fired: stamp(data.fired),
    // When a snooze is up. Zero for an alarm nobody has snoozed.
    snoozed: stamp(data.snoozed)
  }
}

function blank(hour, minute) {
  return {
    id: "", hour: hour, minute: minute, label: "",
    days: [], enabled: true, fired: 0, snoozed: 0
  }
}

function clone(alarm) {
  return {
    id: alarm.id, hour: alarm.hour, minute: alarm.minute, label: alarm.label,
    days: alarm.days.slice(), enabled: alarm.enabled,
    fired: alarm.fired, snoozed: alarm.snoozed
  }
}

function find(alarms, id) {
  for (var i = 0; i < alarms.length; i++) if (alarms[i].id === id) return alarms[i]
  return null
}

// --- the clock ------------------------------------------------------------

// The instant at which the local clock on the day containing `ms` reads
// hour:minute.
function atLocal(ms, hour, minute) {
  var d = new Date(ms)
  d.setHours(hour, minute, 0, 0)
  return d.getTime()
}

// `n` days on from `ms`, in local days rather than in 86400000s. The two
// differ twice a year and the difference is the whole bug.
function shiftDays(ms, n) {
  var d = new Date(ms)
  d.setDate(d.getDate() + n)
  return d.getTime()
}

function onDay(alarm, ms) {
  if (!alarm.days.length) return true
  return alarm.days.indexOf(new Date(ms).getDay()) >= 0
}

// The first occurrence strictly after `from`, or 0 for an alarm with no day it
// can fall on -- which cannot happen through the editor and can through a file
// somebody has typed.
function after(alarm, from) {
  for (var i = 0; i <= 8; i++) {
    var at = atLocal(shiftDays(from, i), alarm.hour, alarm.minute)
    if (at <= from || !onDay(alarm, at)) continue
    return at
  }
  return 0
}

// The most recent occurrence at or before `at`.
function before(alarm, at) {
  for (var i = 0; i <= 8; i++) {
    var was = atLocal(shiftDays(at, -i), alarm.hour, alarm.minute)
    if (was > at || !onDay(alarm, was)) continue
    return was
  }
  return 0
}

// When this alarm will next go off, snooze included, or 0 if it will not.
function nextFire(alarm, now) {
  if (!alarm.enabled) return 0
  if (alarm.snoozed > now) return alarm.snoozed
  return after(alarm, now)
}

function limitMs(lateLimit) {
  return (lateLimit === undefined ? LATE_LIMIT : lateLimit) * 1000
}

// The occurrence that should be ringing at `now`, or 0.
//
// A snooze outranks the schedule: an alarm snoozed at 07:30 for nine minutes
// is due at 07:39 whatever its own time says.
function due(alarm, now, lateLimit) {
  if (!alarm.enabled) return 0
  var limit = limitMs(lateLimit)
  if (alarm.snoozed > 0) {
    if (now < alarm.snoozed) return 0
    return (now - alarm.snoozed <= limit) ? alarm.snoozed : 0
  }
  var at = before(alarm, now)
  if (!at || at <= alarm.fired) return 0
  return (now - at <= limit) ? at : 0
}

// An occurrence that came and went with nothing awake to ring it. The app
// clears it and says so; saying nothing is how a phone gets the reputation.
function missed(alarm, now, lateLimit) {
  if (!alarm.enabled) return 0
  var limit = limitMs(lateLimit)
  if (alarm.snoozed > 0)
    return (now - alarm.snoozed > limit) ? alarm.snoozed : 0
  var at = before(alarm, now)
  if (!at || at <= alarm.fired) return 0
  return (now - at > limit) ? at : 0
}

// The alarm that goes off first, as { alarm, at }, or null.
function soonest(alarms, now) {
  var best = null
  for (var i = 0; i < alarms.length; i++) {
    var at = nextFire(alarms[i], now)
    if (!at) continue
    if (!best || at < best.at) best = { alarm: alarms[i], at: at }
  }
  return best
}

// What an alarm looks like after it has rung: the occurrence is recorded, any
// snooze is cleared, and a one-off switches itself off rather than sitting in
// the list looking armed.
function rang(alarm, at) {
  var next = clone(alarm)
  next.fired = at
  next.snoozed = 0
  if (!next.days.length) next.enabled = false
  return next
}

function snooze(alarm, now, minutes) {
  var next = clone(alarm)
  next.snoozed = now + (minutes === undefined ? SNOOZE_MINUTES : minutes) * 60000
  // Recorded as rung, so that the occurrence it was snoozed from does not come
  // due again the moment the snooze is cleared.
  next.fired = Math.max(next.fired, before(alarm, now) || now)
  next.enabled = true
  return next
}

// --- what the screen says -------------------------------------------------

function sameDays(a, b) {
  if (a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
  return true
}

function repeatLabel(days) {
  if (!days.length) return "Once"
  if (days.length === 7) return "Every day"
  if (sameDays(days, WEEKDAYS)) return "Weekdays"
  if (sameDays(days, WEEKEND)) return "Weekends"
  var out = []
  for (var i = 0; i < days.length; i++) out.push(DAY_SHORT[days[i]])
  return out.join(" ")
}

function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

function timeText(hour, minute, hour24) {
  if (hour24) return pad(hour) + ":" + pad(minute)
  var h = hour % 12
  return (h === 0 ? 12 : h) + ":" + pad(minute)
}

function meridiem(hour) {
  return hour < 12 ? "AM" : "PM"
}

// "in 7 h 20 min". Rounded to the minute, because an alarm is set to the
// minute and a seconds field here would be a number that changes for nothing.
function untilLabel(ms) {
  if (ms <= 0) return "now"
  var mins = Math.round(ms / 60000)
  if (mins < 1) return "in under a minute"
  if (mins < 60) return "in " + mins + " min"
  var hours = Math.floor(mins / 60)
  var rest = mins % 60
  if (hours < 24) return rest ? "in " + hours + " h " + rest + " min" : "in " + hours + " h"
  var days = Math.floor(hours / 24)
  hours = hours % 24
  return hours ? "in " + days + " d " + hours + " h" : "in " + days + " d"
}

// How late a ring is, for the sentence on the ringing screen. Empty under a
// minute: an alarm forty seconds late is an alarm on time.
function lateLabel(ms) {
  var mins = Math.floor(ms / 60000)
  if (mins < 1) return ""
  if (mins === 1) return "a minute late"
  if (mins < 60) return mins + " minutes late"
  var hours = Math.floor(mins / 60)
  return hours === 1 ? "an hour late" : hours + " hours late"
}

// The day an occurrence falls on, said the way somebody would: "today",
// "tomorrow", or the weekday.
function whichDay(at, now) {
  var today = atLocal(now, 0, 0)
  var when = atLocal(at, 0, 0)
  if (when === today) return "today"
  if (when === atLocal(shiftDays(now, 1), 0, 0)) return "tomorrow"
  return DAY_SHORT[new Date(at).getDay()]
}
