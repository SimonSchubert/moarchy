// Texts: the ones on the modem, the ones kept, and the conversations they
// make.
//
// A text lives in two places for a moment. ModemManager holds it as an SMS
// object from the time the network delivers it until somebody deletes it;
// the app keeps its own copy in messages.json for good. `sweep` decides, for
// everything on the modem, what to copy and what to delete -- Chatty's rule,
// which is the rule that loses nothing: a received text is deleted from the
// modem only once it has been written down, and a text still arriving in
// parts is left alone until the last part is in.
//
// A conversation is every text to or from one number, where "one number" is
// Numbers.same(): "+44 7700 900412" and "07700900412" are one thread.
.pragma library
.import "Numbers.js" as Numbers

var seq = 0

function newId(now) {
  seq += 1
  return "m" + Math.floor(now || Date.now()) + "-" + seq
}

function incoming(sms, now) {
  return {
    id: newId(now),
    number: sms.number,
    dir: "in",
    text: sms.text,
    at: sms.time > 0 ? sms.time : now,
    stamp: sms.time > 0 ? sms.time : 0,
    status: "received",
    read: false
  }
}

function outgoing(number, text, now) {
  return {
    id: newId(now),
    number: String(number),
    dir: "out",
    text: String(text),
    at: now,
    stamp: 0,
    status: "sending",
    read: true
  }
}

function isDelivery(sms) {
  return sms.pduType === "deliver" || sms.pduType === "cdma-deliver"
}

function kept(messages, sms) {
  for (var i = 0; i < (messages || []).length; i++) {
    var m = messages[i]
    if (m.dir === "in" && m.stamp === sms.time && m.number === sms.number && m.text === sms.text)
      return true
  }
  return false
}

// What to do with every SMS the modem holds.
//
//   add      new messages for the file
//   remove   SMS paths to delete from the modem once the file is written
function sweep(list, messages, now) {
  var add = []
  var remove = []
  for (var i = 0; i < (list || []).length; i++) {
    var sms = list[i]
    if (isDelivery(sms)) {
      if (sms.state !== "received") continue
      if (!kept(messages, sms) && !kept(add, sms)) add.push(incoming(sms, now))
      remove.push(sms.path)
    } else if (sms.pduType === "status-report") {
      remove.push(sms.path)
    }
  }
  return { add: add, remove: remove }
}

// --- the list ------------------------------------------------------------

function find(messages, id) {
  for (var i = 0; i < (messages || []).length; i++)
    if (messages[i].id === id) return messages[i]
  return null
}

function copy(m) {
  return { id: m.id, number: m.number, dir: m.dir, text: m.text, at: m.at,
           stamp: m.stamp, status: m.status, read: m.read }
}

function withMessages(messages, add) {
  var out = (messages || []).concat(add || [])
  out.sort(function (a, b) { return a.at - b.at })
  return out
}

function withStatus(messages, id, status, now) {
  var out = []
  for (var i = 0; i < (messages || []).length; i++) {
    var m = messages[i]
    if (m.id === id) {
      m = copy(m)
      m.status = status
      if (status === "sending" && now) m.at = now
    }
    out.push(m)
  }
  if (status === "sending") out.sort(function (a, b) { return a.at - b.at })
  return out
}

function markRead(messages, number) {
  var changed = false
  var out = []
  for (var i = 0; i < (messages || []).length; i++) {
    var m = messages[i]
    if (m.dir === "in" && !m.read && Numbers.same(m.number, number)) {
      m = copy(m)
      m.read = true
      changed = true
    }
    out.push(m)
  }
  return changed ? out : messages
}

function withoutThread(messages, number) {
  var out = []
  for (var i = 0; i < (messages || []).length; i++)
    if (!Numbers.same(messages[i].number, number)) out.push(messages[i])
  return out
}

function unread(messages) {
  var n = 0
  for (var i = 0; i < (messages || []).length; i++)
    if (messages[i].dir === "in" && !messages[i].read) n++
  return n
}

// Newest conversation first.
function threads(messages) {
  var byKey = {}
  var out = []
  for (var i = 0; i < (messages || []).length; i++) {
    var m = messages[i]
    var k = Numbers.key(m.number) || m.number
    var t = byKey[k]
    if (!t) {
      t = { key: k, number: m.number, last: m, unread: 0, count: 0 }
      byKey[k] = t
      out.push(t)
    }
    t.count += 1
    if (m.dir === "in" && !m.read) t.unread += 1
    if (m.at >= t.last.at) {
      t.last = m
      t.number = m.number
    }
  }
  out.sort(function (a, b) { return b.last.at - a.last.at })
  return out
}

// One conversation, newest first: the order a list drawn from the bottom up
// wants it in.
function conversation(messages, number) {
  var out = []
  for (var i = 0; i < (messages || []).length; i++)
    if (Numbers.same(messages[i].number, number)) out.push(messages[i])
  out.sort(function (a, b) { return b.at - a.at })
  return out
}

function preview(m) {
  if (!m) return ""
  var text = String(m.text || "").replace(/\s+/g, " ").trim()
  if (m.dir === "out") {
    if (m.status === "failed") return "Not sent: " + text
    return "You: " + text
  }
  return text
}

// --- time ----------------------------------------------------------------

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

// "14:05" today, "Yesterday", "Tue" this week, "3 Mar" this year.
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

// Under a bubble: the time, and the day too once it is not today.
function stamp(ms, now) {
  var day = when(ms, now)
  var time = clock(ms)
  return day === time ? time : day + " " + time
}
