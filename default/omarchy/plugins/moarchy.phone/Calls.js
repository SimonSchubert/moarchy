// Calls: the ones happening now, and the log of the ones that happened.
//
// ModemManager describes a call as it is at the moment it is read -- a path,
// a number, a direction and a state -- and forgets nothing until it is told
// to delete it. What it cannot say is anything across time: whether a call
// that is ending now was ever answered, how long it was up, whether it rang
// out or was declined. So the app follows each call by its path from one read
// to the next (`follow`), and writes a line to its log when one ends.
.pragma library

var MAX = 500

// States in which the call's audio is up, or about to be: callaudiod goes to
// the call profile for these. Not `ringing-in` -- gnome-calls does not switch
// until an incoming call is answered, and a ring through the earpiece would be
// a ring nobody hears.
var AUDIO = ["dialing", "ringing-out", "active", "held"]

// Which call the screen is about when there are two.
var ORDER = ["active", "held", "dialing", "ringing-out", "", "ringing-in", "waiting"]

var seq = 0

function has(list, item) {
  return list.indexOf(item) >= 0
}

function live(calls) {
  var out = []
  for (var i = 0; i < (calls || []).length; i++)
    if (calls[i].state !== "terminated") out.push(calls[i])
  return out
}

function audioWanted(calls) {
  for (var i = 0; i < (calls || []).length; i++)
    if (has(AUDIO, calls[i].state)) return true
  return false
}

function primary(calls) {
  var up = live(calls)
  for (var o = 0; o < ORDER.length; o++)
    for (var i = 0; i < up.length; i++)
      if (up[i].state === ORDER[o]) return up[i]
  return up.length ? up[0] : null
}

// An incoming call with nothing else going on: the one that rings out loud.
function ringing(calls) {
  var up = live(calls)
  return up.length === 1 && up[0].state === "ringing-in" ? up[0] : null
}

// An incoming call on top of one that is already up.
function waiting(calls) {
  var up = live(calls)
  if (up.length < 2) return null
  for (var i = 0; i < up.length; i++)
    if (up[i].state === "waiting" || up[i].state === "ringing-in") return up[i]
  return null
}

function blank(now) {
  return { number: "", direction: "", first: now, activeAt: 0, declined: false, logged: false, state: "" }
}

function copy(r) {
  return {
    number: r.number, direction: r.direction, first: r.first, activeAt: r.activeAt,
    declined: r.declined, logged: r.logged, state: r.state
  }
}

function entry(r, now) {
  seq += 1
  var outgoing = r.direction === "outgoing"
  return {
    id: "k" + Math.floor(r.first) + "-" + seq,
    number: r.number,
    dir: outgoing ? "out" : "in",
    answered: r.activeAt > 0,
    missed: !outgoing && !(r.activeAt > 0) && !r.declined,
    at: r.first,
    seconds: r.activeAt > 0 ? Math.max(0, Math.round((now - r.activeAt) / 1000)) : 0
  }
}

// One successful read of the modem's calls, against what was known before.
//
//   seen      path -> what has been learned about that call
//   calls     what the modem says now
//
// Returns the next `seen`, the log entries for calls that ended, and the
// paths ModemManager should now be told to delete. A call that was already
// over the first time it was read -- left behind by a shell that restarted,
// or by gnome-calls -- is deleted and not logged: nothing is known about it.
function follow(seen, calls, now) {
  var before = seen || {}
  var next = {}
  var ended = []
  var finished = []
  for (var i = 0; i < (calls || []).length; i++) {
    var c = calls[i]
    var known = before[c.path]
    var r = known ? copy(known) : blank(now)
    if (c.number) r.number = c.number
    if (c.direction) r.direction = c.direction
    if (c.state === "active" && !(r.activeAt > 0)) r.activeAt = now
    r.state = c.state
    if (c.state === "terminated") {
      if (known && !r.logged) ended.push(entry(r, now))
      r.logged = true
      finished.push(c.path)
    }
    next[c.path] = r
  }
  // Gone between two reads without being seen to end: ModemManager dropped
  // it, or somebody else deleted it. It still happened.
  for (var path in before) {
    if (next[path] || before[path].logged) continue
    ended.push(entry(before[path], now))
  }
  return { seen: next, ended: ended, finished: finished }
}

function decline(seen, path) {
  var out = {}
  for (var p in (seen || {})) {
    out[p] = copy(seen[p])
    if (p === path) out[p].declined = true
  }
  return out
}

function since(seen, path) {
  var r = seen && seen[path]
  return r ? r.activeAt : 0
}

// --- the log -------------------------------------------------------------

function withEntry(log, e) {
  return [e].concat(log || []).slice(0, MAX)
}

function without(log, id) {
  var out = []
  for (var i = 0; i < (log || []).length; i++)
    if (log[i].id !== id) out.push(log[i])
  return out
}

function unseenMissed(log, seenAt) {
  var n = 0
  for (var i = 0; i < (log || []).length; i++)
    if (log[i].missed && log[i].at > (seenAt || 0)) n++
  return n
}

function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

function duration(seconds) {
  var s = Math.max(0, Math.floor(seconds || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var r = s % 60
  return h > 0 ? h + ":" + pad(m) + ":" + pad(r) : m + ":" + pad(r)
}

var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function midnight(ms) {
  var d = new Date(ms)
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

// "14:05" today, "Yesterday", "Tue" this week, "3 Mar" this year.
function when(ms, now) {
  if (!(ms > 0)) return ""
  var d = new Date(ms)
  var days = Math.round((midnight(now) - midnight(ms)) / 86400000)
  if (days <= 0) return pad(d.getHours()) + ":" + pad(d.getMinutes())
  if (days === 1) return "Yesterday"
  if (days < 7) return DAYS[d.getDay()]
  var out = d.getDate() + " " + MONTHS[d.getMonth()]
  if (d.getFullYear() !== new Date(now).getFullYear()) out += " " + d.getFullYear()
  return out
}

function kind(e) {
  if (e.missed) return "missed"
  return e.dir === "out" ? "out" : "in"
}

function describe(e) {
  if (e.missed) return "Missed"
  if (e.dir === "out")
    return e.answered ? "Outgoing · " + duration(e.seconds) : "Outgoing · no answer"
  return e.answered ? "Incoming · " + duration(e.seconds) : "Declined"
}
