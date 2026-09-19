// calls.json: the log, and when the missed calls in it were last looked at.
//
// Newest first, capped at Calls.MAX. A row this app cannot read is kept as it
// was found and written back after the others, which is Contacts' rule and
// its reason: FileView guards a file that will not parse, and nothing guards a
// row inside a file that does.
.pragma library
.import "Calls.js" as Calls

var SCHEMA = 1

function str(v) {
  return typeof v === "string" ? v : ""
}

function normalise(row) {
  if (!row || typeof row !== "object") return null
  var at = Number(row.at)
  if (!(at > 0)) return null
  if (row.dir !== "in" && row.dir !== "out") return null
  var seconds = Number(row.seconds)
  return {
    id: str(row.id) || "k" + Math.floor(at),
    number: str(row.number),
    dir: row.dir,
    answered: row.answered === true,
    missed: row.missed === true,
    at: at,
    seconds: isFinite(seconds) && seconds > 0 ? Math.floor(seconds) : 0
  }
}

function parse(data) {
  var out = { log: [], strays: [], seen: 0 }
  if (!data || typeof data !== "object") return out
  var seen = Number(data.seen)
  out.seen = isFinite(seen) && seen > 0 ? seen : 0
  var rows = data.calls
  if (!rows || rows.constructor !== Array) return out
  for (var i = 0; i < rows.length; i++) {
    var e = normalise(rows[i])
    if (e) out.log.push(e)
    else out.strays.push(rows[i])
  }
  out.log.sort(function (a, b) { return b.at - a.at })
  out.log = out.log.slice(0, Calls.MAX)
  return out
}

function serialize(log, strays, seen) {
  var rows = []
  for (var i = 0; i < (log || []).length; i++) {
    var e = log[i]
    var row = { id: e.id, number: e.number, dir: e.dir, at: e.at }
    if (e.answered) row.answered = true
    if (e.missed) row.missed = true
    if (e.seconds) row.seconds = e.seconds
    rows.push(row)
  }
  for (var j = 0; j < (strays || []).length; j++) rows.push(strays[j])
  return JSON.stringify({ schema: SCHEMA, seen: seen || 0, calls: rows }, null, 1)
}
