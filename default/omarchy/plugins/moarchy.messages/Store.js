// messages.json: every text, oldest first.
//
// One list rather than a file per conversation, because a conversation here
// is a question asked of the list (Threads.js) and not a thing with a name of
// its own. A row this app cannot read is kept and written back untouched --
// Contacts' rule, for Contacts' reason.
//
// A text that was still "sending" when the file was last written was being
// sent by a process that is not running any more. Nobody knows whether it
// went, so it comes back as failed, which is the state with a retry on it.
.pragma library

var SCHEMA = 1
var STATUS = { received: true, sending: true, sent: true, failed: true }

function str(v) {
  return typeof v === "string" ? v : ""
}

function normalise(row) {
  if (!row || typeof row !== "object") return null
  if (row.dir !== "in" && row.dir !== "out") return null
  if (typeof row.text !== "string" || typeof row.number !== "string") return null
  var at = Number(row.at)
  if (!(at > 0)) return null
  var status = STATUS[row.status] ? row.status : (row.dir === "in" ? "received" : "sent")
  if (status === "sending") status = "failed"
  var stamp = Number(row.stamp)
  return {
    id: str(row.id) || "m" + Math.floor(at),
    number: row.number,
    dir: row.dir,
    text: row.text,
    at: at,
    stamp: isFinite(stamp) && stamp > 0 ? stamp : 0,
    status: status,
    read: row.dir === "out" ? true : row.read === true
  }
}

function parse(data) {
  var out = { messages: [], strays: [] }
  if (!data || typeof data !== "object") return out
  var rows = data.messages
  if (!rows || rows.constructor !== Array) return out
  for (var i = 0; i < rows.length; i++) {
    var m = normalise(rows[i])
    if (m) out.messages.push(m)
    else out.strays.push(rows[i])
  }
  out.messages.sort(function (a, b) { return a.at - b.at })
  return out
}

function serialize(messages, strays) {
  var rows = []
  for (var i = 0; i < (messages || []).length; i++) {
    var m = messages[i]
    var row = { id: m.id, number: m.number, dir: m.dir, text: m.text, at: m.at, status: m.status }
    if (m.stamp) row.stamp = m.stamp
    if (m.dir === "in") row.read = !!m.read
    rows.push(row)
  }
  for (var j = 0; j < (strays || []).length; j++) rows.push(strays[j])
  return JSON.stringify({ schema: SCHEMA, messages: rows }, null, 1)
}
