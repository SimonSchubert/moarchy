// A folder as the app keeps it: the rows it has drawn, and what the server
// said about the folder the last time it was asked.
//
// One file per folder, cache/<md5 of the name>.json, written only by the app.
// moarchy-mail never touches it -- `sync` is told which UIDs the app has and
// answers with what changed, and merge() below is the whole of what is done
// with that answer. So the rule that decides what a folder shows is here, in
// plain JS that tests/tst_mailbox.qml can run without a server.
//
// A UID means one message for as long as the folder's UIDVALIDITY stays the
// same (RFC 3501 2.3.1.1), which is what makes a cache of rows safe at all.
// When it changes, everything cached for the folder is thrown away.
.pragma library

var SCHEMA = 1
var SEEN = "\\Seen"
var FLAGGED = "\\Flagged"
var ANSWERED = "\\Answered"
// A folder that has been read keeps no more rows than this, newest first.
// "Older" can walk past it; the file just does not remember that far.
var KEEP = 500

function str(v) {
  return typeof v === "string" ? v : ""
}

function num(v) {
  var n = Number(v)
  return isFinite(n) ? n : 0
}

function person(p) {
  return { name: str(p && p.name), email: str(p && p.email) }
}

function empty(folder) {
  return {
    folder: String(folder || "INBOX"),
    uidvalidity: 0,
    uidnext: 0,
    exists: 0,
    unseen: 0,
    more: false,
    at: 0,
    rows: []
  }
}

function flagsOf(value) {
  var out = []
  if (!value || value.constructor !== Array) return out
  for (var i = 0; i < value.length; i++)
    if (typeof value[i] === "string") out.push(value[i])
  return out
}

function normaliseRow(r) {
  if (!r || typeof r !== "object") return null
  var uid = Math.floor(num(r.uid))
  if (!(uid > 0)) return null
  var to = []
  if (r.to && r.to.constructor === Array)
    for (var i = 0; i < r.to.length && to.length < 3; i++) to.push(person(r.to[i]))
  var at = num(r.at)
  return {
    uid: uid,
    flags: flagsOf(r.flags),
    at: at,
    date: num(r.date) || at,
    from: person(r.from),
    to: to,
    subject: str(r.subject),
    preview: str(r.preview),
    attachment: r.attachment === true,
    size: num(r.size)
  }
}

// Newest first by when the server got it, which is the order mail arrived in
// and cannot be set by the sender the way a Date header can.
function byArrival(a, b) {
  if (b.at !== a.at) return b.at - a.at
  return b.uid - a.uid
}

function parse(data, folder) {
  var box = empty(folder)
  if (!data || typeof data !== "object" || data.folder !== box.folder) return box
  box.uidvalidity = num(data.uidvalidity)
  box.uidnext = num(data.uidnext)
  box.exists = num(data.exists)
  box.unseen = num(data.unseen)
  box.more = data.more === true
  box.at = num(data.at)
  var rows = data.rows && data.rows.constructor === Array ? data.rows : []
  var seen = {}
  for (var i = 0; i < rows.length; i++) {
    var row = normaliseRow(rows[i])
    if (!row || seen[row.uid]) continue
    seen[row.uid] = true
    box.rows.push(row)
  }
  box.rows.sort(byArrival)
  return box
}

function serialize(box) {
  return JSON.stringify({
    schema: SCHEMA,
    folder: box.folder,
    uidvalidity: box.uidvalidity,
    uidnext: box.uidnext,
    exists: box.exists,
    unseen: box.unseen,
    more: box.more,
    at: box.at,
    rows: box.rows
  })
}

function uids(box) {
  var out = []
  for (var i = 0; i < box.rows.length; i++) out.push(box.rows[i].uid)
  return out
}

function has(row, flag) {
  return !!row && row.flags.indexOf(flag) >= 0
}

function withFlags(row, flags) {
  var copy = {}
  for (var k in row) copy[k] = row[k]
  copy.flags = flags
  return copy
}

// What `sync` answered, folded into what the app had.
//
// `present` is every UID the server still has from the oldest the app knew of
// up, with its flags; a cached row whose UID is not in it was expunged
// somewhere else. `rows` are the rows the app did not have.
function merge(box, result, at) {
  if (!result || result.folder !== box.folder) return box
  var next = empty(box.folder)
  next.uidvalidity = num(result.uidvalidity)
  next.uidnext = num(result.uidnext)
  next.exists = num(result.exists)
  next.unseen = num(result.unseen)
  next.more = result.more === true
  next.at = num(at)

  var flags = {}
  var present = result.present && result.present.constructor === Array ? result.present : []
  for (var i = 0; i < present.length; i++) {
    var pair = present[i]
    if (pair && pair.length === 2) flags[pair[0]] = flagsOf(pair[1])
  }

  var reset = result.reset === true || num(result.uidvalidity) !== box.uidvalidity
  var kept = {}
  var rows = []
  if (!reset) {
    for (var j = 0; j < box.rows.length; j++) {
      var old = box.rows[j]
      if (!flags.hasOwnProperty(old.uid) || kept[old.uid]) continue
      kept[old.uid] = true
      rows.push(withFlags(old, flags[old.uid]))
    }
  }
  var fresh = result.rows && result.rows.constructor === Array ? result.rows : []
  for (var n = 0; n < fresh.length; n++) {
    var row = normaliseRow(fresh[n])
    if (!row || kept[row.uid]) continue
    if (flags.hasOwnProperty(row.uid)) row.flags = flags[row.uid]
    kept[row.uid] = true
    rows.push(row)
  }
  rows.sort(byArrival)
  if (rows.length > KEEP) {
    rows = rows.slice(0, KEEP)
    next.more = true
  }
  next.rows = rows
  return next
}

function withFlag(box, list, flag, on) {
  var wanted = {}
  for (var i = 0; i < list.length; i++) wanted[list[i]] = true
  var next = {}
  for (var k in box) next[k] = box[k]
  var unseen = box.unseen
  next.rows = box.rows.map(function (row) {
    if (!wanted[row.uid] || has(row, flag) === on) return row
    if (flag === SEEN) unseen += on ? -1 : 1
    var flags = on ? row.flags.concat([flag])
                   : row.flags.filter(function (f) { return f !== flag })
    return withFlags(row, flags)
  })
  next.unseen = Math.max(0, unseen)
  return next
}

function without(box, list) {
  var gone = {}
  for (var i = 0; i < list.length; i++) gone[list[i]] = true
  var next = {}
  for (var k in box) next[k] = box[k]
  var unseen = box.unseen
  var removed = 0
  next.rows = box.rows.filter(function (row) {
    if (!gone[row.uid]) return true
    if (!has(row, SEEN)) unseen -= 1
    removed += 1
    return false
  })
  next.unseen = Math.max(0, unseen)
  next.exists = Math.max(0, box.exists - removed)
  return next
}

function find(box, uid) {
  for (var i = 0; i < box.rows.length; i++)
    if (box.rows[i].uid === uid) return box.rows[i]
  return null
}

// --- what has been asked for and not yet answered ---------------------------
//
// Marking a message read is drawn at once, and told to the server after. Until
// the server says yes, a refresh that happens to be running still has the old
// flags in it -- so the change is held here and laid over every row drawn,
// and let go only by the job that made it. Each carries a number, so that a
// star tapped on and off again is not let go by the first of the two answers.

function key(folder, uid) {
  return folder + "\n" + uid
}

function withPending(pending, folder, list, what, value, seq) {
  var next = {}
  for (var k in pending) next[k] = pending[k]
  for (var i = 0; i < list.length; i++) {
    var id = key(folder, list[i])
    var entry = {}
    for (var e in (next[id] || {})) entry[e] = next[id][e]
    entry[what] = { value: value, seq: seq }
    next[id] = entry
  }
  return next
}

function clearPending(pending, folder, list, what, seq) {
  var next = {}
  for (var k in pending) next[k] = pending[k]
  for (var i = 0; i < list.length; i++) {
    var id = key(folder, list[i])
    if (!next[id] || !next[id][what] || next[id][what].seq !== seq) continue
    var entry = {}
    var left = 0
    for (var e in next[id]) {
      if (e === what) continue
      entry[e] = next[id][e]
      left += 1
    }
    if (left) next[id] = entry
    else delete next[id]
  }
  return next
}

function overlaid(row, entry) {
  if (!entry) return row
  var flags = row.flags
  function set(flag, on) {
    var there = flags.indexOf(flag) >= 0
    if (there === on) return
    flags = on ? flags.concat([flag]) : flags.filter(function (f) { return f !== flag })
  }
  if (entry.seen) set(SEEN, entry.seen.value)
  if (entry.flagged) set(FLAGGED, entry.flagged.value)
  return flags === row.flags ? row : withFlags(row, flags)
}

// One row as it is to be drawn.
function shown(folder, row, pending) {
  if (!row) return null
  return overlaid(row, pending[key(folder, row.uid)])
}

// The rows to draw.
function view(box, pending) {
  var out = []
  for (var i = 0; i < box.rows.length; i++) {
    var entry = pending[key(box.folder, box.rows[i].uid)]
    if (entry && entry.gone && entry.gone.value) continue
    out.push(overlaid(box.rows[i], entry))
  }
  return out
}

function unseen(box, pending) {
  var count = box.unseen
  for (var i = 0; i < box.rows.length; i++) {
    var row = box.rows[i]
    var entry = pending[key(box.folder, row.uid)]
    if (!entry) continue
    var before = !has(row, SEEN)
    var shown = overlaid(row, entry)
    var after = !(entry.gone && entry.gone.value) && !has(shown, SEEN)
    if (before !== after) count += after ? 1 : -1
  }
  return Math.max(0, count)
}

// --- how a row reads ------------------------------------------------------------

function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function midnight(ms) {
  var d = new Date(ms)
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

function clock(ms) {
  var d = new Date(ms)
  return pad(d.getHours()) + ":" + pad(d.getMinutes())
}

// "14:05" today, "Yesterday", "Tue" this week, "3 Mar" this year. Messages'
// words, so the two apps say the same thing about the same afternoon.
function when(ms, now) {
  if (!(ms > 0)) return ""
  var d = new Date(ms)
  var days = Math.round((midnight(now) - midnight(ms)) / 86400000)
  if (days <= 0) return clock(ms)
  if (days === 1) return "Yesterday"
  if (days < 7) return DAYS[d.getDay()]
  var out = d.getDate() + " " + MONTHS[d.getMonth()]
  if (d.getFullYear() !== new Date(now).getFullYear()) out += " " + d.getFullYear()
  return out
}

// Over a message: the time, and the day too once it is not today.
function stamp(ms, now) {
  if (!(ms > 0)) return ""
  var day = when(ms, now)
  var time = clock(ms)
  return day === time ? time : day + ", " + time
}

function size(bytes) {
  var n = num(bytes)
  if (n < 1000) return n + " B"
  if (n < 1000000) return Math.round(n / 1000) + " KB"
  return (Math.round(n / 100000) / 10) + " MB"
}

// Where a message's parsed body is cached, as moarchy-mail writes it.
// `folderHash` is Qt.md5 of the folder name, which this library cannot call.
function bodyPath(dataDir, folderHash, uidvalidity, uid) {
  return dataDir + "/bodies/" + folderHash + "/" + uidvalidity + "-" + uid + ".json"
}
