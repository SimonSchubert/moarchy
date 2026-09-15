// What is on, and when it comes round again.
//
// An event is a plain object: a day, a name, two times in minutes, and a rule
// for repeating. Nothing here touches QML, which is what lets the part that
// can be wrong -- does a monthly event on the 31st happen in February, does a
// yearly one on the 29th happen in 2027 -- be answered by a test rather than
// by tapping through six months on a phone.
//
// There is no expansion into a list of occurrences and no cache of one. An
// occurrence is a question asked of a day: `occursOn(event, "2026-09-15")`.
// The month grid asks it 42 times per event and the agenda asks it 400 times,
// which is a few thousand string comparisons for a calendar with fifty things
// in it -- less work than the animation that put the grid on screen.
.pragma library
.import "Dates.js" as Dates

// The theme's own hues, by name. An event's colour is stored as "green" and
// resolved through the palette, so the same file under a different theme
// draws in that theme's green rather than in a green from 2026.
var COLOURS = ["blue", "green", "yellow", "orange", "red", "magenta", "cyan", "brown"]

// Five rules, and not RFC 5545.
//
// A phone calendar's recurrences are a birthday, a standup, a rent day and a
// bin collection. BYSETPOS, BYDAY=-1SU and an RRULE parser are the other
// ninety per cent of iCalendar, they are what a person types into a desktop
// once a year, and every one of them is a screen of controls this app would
// have to grow to enter.
var REPEATS = [
  { key: "none", label: "Once" },
  { key: "daily", label: "Daily" },
  { key: "weekly", label: "Weekly" },
  { key: "monthly", label: "Monthly" },
  { key: "yearly", label: "Yearly" }
]

// How far ahead the agenda looks, and how many days with something on them it
// will show. A year and a bit, because a birthday repeats yearly and an agenda
// that could not see it would be an agenda that said "nothing".
var HORIZON = 400
var AGENDA_DAYS = 60

// Dots under a date. Four is where they stop being countable at 51px wide.
var DOTS = 4

var DEFAULT_START = 9 * 60
var DEFAULT_LENGTH = 60

function hue(colours, name) {
  var hues = (colours && colours.hues) || {}
  return hues[name] || (colours ? colours.accent : "#3584e4")
}

function isColour(name) {
  return COLOURS.indexOf(String(name)) >= 0
}

function isRepeat(key) {
  for (var i = 0; i < REPEATS.length; i++) if (REPEATS[i].key === key) return true
  return false
}

function repeatLabel(key) {
  for (var i = 0; i < REPEATS.length; i++) if (REPEATS[i].key === key) return REPEATS[i].label
  return REPEATS[0].label
}

// --- one event -------------------------------------------------------------

// Unique enough for a file one person edits on one phone. The counter is
// there because two events added inside the same millisecond -- which is what
// a script or a screenshot harness does -- would otherwise share an id, and an
// id that is not unique is a delete that takes the wrong row with it.
var seq = 0

function newId(now) {
  seq += 1
  return "e" + Math.floor(now || 0) + "-" + seq
}

function blank(iso, minutes, colour, now) {
  var start = typeof minutes === "number" && minutes >= 0 ? minutes : DEFAULT_START
  return {
    id: newId(now),
    title: "",
    where: "",
    date: iso,
    allDay: false,
    start: start,
    end: Math.min(start + DEFAULT_LENGTH, Dates.MINUTES - 1),
    repeat: "none",
    until: "",
    colour: isColour(colour) ? colour : COLOURS[0]
  }
}

function copy(ev) {
  return {
    id: ev.id, title: ev.title, where: ev.where, date: ev.date,
    allDay: ev.allDay, start: ev.start, end: ev.end,
    repeat: ev.repeat, until: ev.until, colour: ev.colour
  }
}

// A row from the file, made safe, or null when it cannot be placed on a day at
// all. Null is not "throw this away": Store.js keeps such a row aside and
// writes it back untouched, because a row this app cannot read is still
// somebody's appointment.
function normalise(raw, index, now) {
  if (!raw || typeof raw !== "object" || raw.constructor === Array) return null
  if (!Dates.isDay(raw.date)) return null

  var title = typeof raw.title === "string" ? raw.title.trim() : ""
  var start = minutesFrom(raw.start, DEFAULT_START)
  // No end at all is a moment, not an hour. The app writes both times on every
  // save, so a row with one is a row somebody wrote by hand or a script sent
  // through `add` -- and "16:00" with nothing after it is a point in time in
  // both. Guessing an hour there is how an event that was saved as a moment
  // came back an hour long, which is a file quietly editing itself.
  var end = minutesFrom(raw.end, start)

  return {
    id: typeof raw.id === "string" && raw.id.length ? raw.id : newId(now || index || 0),
    // A file somebody has edited can hold a nameless event. It is drawn with a
    // name rather than dropped, because a blank row in a calendar is still a
    // day somebody has to be somewhere.
    title: title.length ? title : "Untitled",
    where: typeof raw.where === "string" ? raw.where.trim() : "",
    date: raw.date,
    allDay: !!raw.allDay,
    start: start,
    // Not a clamp to start + an hour: an event can be a moment, and "09:00"
    // with nothing after it is how a reminder looks. Going *backwards* is the
    // only thing ruled out.
    end: Math.max(start, end),
    repeat: isRepeat(raw.repeat) ? raw.repeat : "none",
    until: Dates.isDay(raw.until) && raw.until >= raw.date ? raw.until : "",
    colour: isColour(raw.colour) ? raw.colour : COLOURS[0]
  }
}

// The file writes "09:30" and the app holds 570. Both are accepted coming in,
// because the file is meant to be readable by a person and a person who edits
// it will write one or the other.
function minutesFrom(value, fallback) {
  if (typeof value === "number" && isFinite(value)) return Dates.clampMinutes(value)
  if (typeof value === "string") {
    var at = Dates.parseTime(value)
    if (at >= 0) return at
  }
  return Dates.clampMinutes(fallback)
}

// --- when it happens -------------------------------------------------------

// The whole recurrence engine.
//
// Monthly keeps the day of the month, so an event on the 31st simply does not
// happen in a month that has no 31st -- it is not moved to the 30th and it is
// not moved to the 1st. Yearly keeps the date, so the 29th of February happens
// in leap years and in no others. Both are RFC 5545's rule for BYMONTHDAY
// ("recurrence instances that are invalid dates are ignored"), and both are
// the answer that does not invent an appointment on a day nobody chose.
function occursOn(ev, iso) {
  if (!ev || !Dates.isDay(iso)) return false
  if (iso < ev.date) return false
  if (ev.repeat === "none") return iso === ev.date
  if (ev.until && iso > ev.until) return false

  if (ev.repeat === "daily") return true
  if (ev.repeat === "weekly") return Dates.weekday(iso) === Dates.weekday(ev.date)

  var on = Dates.parts(iso)
  var from = Dates.parts(ev.date)
  if (on === null || from === null) return false
  if (ev.repeat === "monthly") return on.d === from.d
  if (ev.repeat === "yearly") return on.d === from.d && on.m === from.m
  return false
}

// All-day first, then by the clock, then by name so that two things at nine
// keep the same order every time the screen is drawn.
function order(a, b) {
  if (a.allDay !== b.allDay) return a.allDay ? -1 : 1
  if (!a.allDay && a.start !== b.start) return a.start - b.start
  var left = String(a.title).toLowerCase()
  var right = String(b.title).toLowerCase()
  if (left !== right) return left < right ? -1 : 1
  return 0
}

function onDay(events, iso) {
  var out = []
  for (var i = 0; i < (events || []).length; i++)
    if (occursOn(events[i], iso)) out.push(events[i])
  return out.sort(order)
}

// One list of colours per cell of a month grid, in the order they are drawn.
// Built in a single pass over the cells rather than a call per cell, because
// this runs for three months at once while a swipe is in flight.
function marks(events, cells) {
  var out = []
  for (var c = 0; c < (cells || []).length; c++) {
    var found = []
    for (var i = 0; i < (events || []).length && found.length < DOTS; i++)
      if (occursOn(events[i], cells[c].iso)) found.push(events[i].colour)
    out.push(found)
  }
  return out
}

// The days from here on that have something on them. Stops at the first of
// `maxDays` days found or `days` days looked at, whichever comes first -- a
// daily event would otherwise fill the list with four hundred identical rows.
function agenda(events, fromIso, days, maxDays) {
  var out = []
  var iso = fromIso
  var horizon = days || HORIZON
  var cap = maxDays || AGENDA_DAYS
  for (var i = 0; i <= horizon && out.length < cap; i++) {
    var items = onDay(events, iso)
    if (items.length) out.push({ iso: iso, items: items })
    iso = Dates.addDays(iso, 1)
  }
  return out
}

// The next day this happens on, or "" if it never does again. Used by nothing
// on screen; it is the answer the IPC handler gives, and the reason the agenda
// can say "nothing at all" rather than "nothing in the next year".
function nextOn(ev, fromIso, days) {
  var iso = fromIso
  for (var i = 0; i <= (days || HORIZON); i++) {
    if (occursOn(ev, iso)) return iso
    iso = Dates.addDays(iso, 1)
  }
  return ""
}

// --- saying it out loud ----------------------------------------------------

function ordinal(n) {
  var tens = n % 100
  if (tens >= 11 && tens <= 13) return n + "th"
  var last = n % 10
  return n + (last === 1 ? "st" : last === 2 ? "nd" : last === 3 ? "rd" : "th")
}

function describeRepeat(ev) {
  if (!ev || ev.repeat === "none") return ""
  var p = Dates.parts(ev.date)
  var said = ""
  if (ev.repeat === "daily") said = "Every day"
  else if (ev.repeat === "weekly") said = "Every " + Dates.DAYS[Dates.weekday(ev.date)]
  else if (ev.repeat === "monthly") said = "Every month on the " + ordinal(p ? p.d : 1)
  else if (ev.repeat === "yearly") said = "Every " + (p ? p.d : 1) + " " + Dates.MONTHS[(p ? p.m : 1) - 1]
  if (ev.until) said += ", until " + Dates.shortDayLabel(ev.until)
  return said
}

function summary(ev) {
  if (!ev) return ""
  return ev.allDay ? "All day" : Dates.formatSpan(ev.start, ev.end)
}

function line(ev) {
  var said = summary(ev)
  if (ev && ev.where) said += (said.length ? " · " : "") + ev.where
  return said
}

// --- the list ---------------------------------------------------------------

function find(events, id) {
  for (var i = 0; i < (events || []).length; i++)
    if (events[i].id === id) return events[i]
  return null
}

// A new array every time rather than a push, so that a binding on the list
// sees a different object and redraws. Habits mutates in place and carries a
// revision counter to make up for it; this is the other way round and there is
// no third way that works.
function withEvent(events, ev) {
  var out = []
  var replaced = false
  for (var i = 0; i < (events || []).length; i++) {
    if (events[i].id === ev.id) { out.push(ev); replaced = true }
    else out.push(events[i])
  }
  if (!replaced) out.push(ev)
  return out
}

function without(events, id) {
  var out = []
  for (var i = 0; i < (events || []).length; i++)
    if (events[i].id !== id) out.push(events[i])
  return out
}

// The colour a new event gets: whichever is used least, earliest in the list
// on a tie. Nobody is asked to choose a colour and the calendar still comes
// out looking like one, which is the only reason colours are here at all.
function nextColour(events) {
  var used = {}
  for (var c = 0; c < COLOURS.length; c++) used[COLOURS[c]] = 0
  for (var i = 0; i < (events || []).length; i++)
    if (isColour(events[i].colour)) used[events[i].colour] += 1
  var best = COLOURS[0]
  for (var k = 1; k < COLOURS.length; k++)
    if (used[COLOURS[k]] < used[best]) best = COLOURS[k]
  return best
}
