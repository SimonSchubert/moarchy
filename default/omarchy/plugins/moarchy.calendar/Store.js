// One file, and the rows in it this app cannot read.
//
// `~/.local/share/moarchy-calendar/calendar.json` is a list of events with a
// schema number on it. Times go out as "09:30" rather than as 570, and the
// list is written in date order, because the file is meant to be legible to
// the person whose calendar it is -- and the ones who will read it are a
// person with a text editor and a script with `jq`, in that order.
//
// The part worth explaining is `strays`. Quickshell's FileView already refuses
// to overwrite a file that will not parse, and moves it aside when it is
// broken; that guards the document. It does not guard a *row*: a file that
// parses cleanly can hold an event with no date on it, this app has nowhere to
// draw such a thing, and the next save would write the file back without it.
// So every row that cannot be read is kept exactly as it was found and written
// back untouched. The app is then free to ignore it, which is the only way to
// ignore something without destroying it.
.pragma library
.import "Dates.js" as Dates
.import "Events.js" as Events

var SCHEMA = 1

function parse(data) {
  var out = { events: [], strays: [] }
  if (!data || typeof data !== "object") return out
  var rows = data.events
  if (!rows || rows.constructor !== Array) return out

  var seen = {}
  for (var i = 0; i < rows.length; i++) {
    var ev = Events.normalise(rows[i], i + 1, 0)
    if (ev === null) { out.strays.push(rows[i]); continue }
    // Two rows with one id is a file that has been copied and pasted, and it
    // is the shape that makes deleting one event delete two. The second copy
    // is given an id of its own rather than dropped.
    if (seen[ev.id]) ev.id = Events.newId(i + 1)
    seen[ev.id] = true
    out.events.push(ev)
  }
  return out
}

function byDay(a, b) {
  if (a.date !== b.date) return a.date < b.date ? -1 : 1
  return Events.order(a, b)
}

function toJson(ev) {
  var out = { id: ev.id, title: ev.title, date: ev.date }
  if (ev.where) out.where = ev.where
  if (ev.allDay) {
    out.allDay = true
  } else {
    // Both times, always, including an end equal to the start. Leaving the end
    // out when there was no length would be a shorter file and a different
    // event on the way back in.
    out.start = Dates.formatTime(ev.start)
    out.end = Dates.formatTime(ev.end)
  }
  if (ev.repeat !== "none") {
    out.repeat = ev.repeat
    if (ev.until) out.until = ev.until
  }
  out.colour = ev.colour
  return out
}

function serialize(events, strays) {
  var rows = (events || []).slice().sort(byDay)
  var written = []
  for (var i = 0; i < rows.length; i++) written.push(toJson(rows[i]))
  for (var s = 0; s < (strays || []).length; s++) written.push(strays[s])
  return JSON.stringify({ schema: SCHEMA, events: written }, null, 1)
}
