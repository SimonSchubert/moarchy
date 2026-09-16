// A message being written: a new one, a reply, a forward, or a mailto: link.
//
// A draft is plain data -- the four fields as typed, the text, and what it is
// an answer to -- so it can be kept in state.json when the window goes away,
// put in the outbox when Send is pressed, and handed back to the form when a
// send failed. moarchy-mail gets it through request() and nothing else.
.pragma library
.import "Address.js" as Address
.import "Mailbox.js" as Mailbox

function str(v) {
  return typeof v === "string" ? v : ""
}

function fingerprint(d) {
  return JSON.stringify([d.to, d.cc, d.bcc, d.subject, d.text])
}

function blank(at) {
  var d = {
    id: "d" + Math.floor(Number(at) || 0),
    mode: "new",
    to: "",
    cc: "",
    bcc: "",
    subject: "",
    text: "",
    inReplyTo: "",
    references: "",
    answered: null,
    forward: null,
    attachments: [],
    at: Number(at) || 0,
    error: "",
    untouched: ""
  }
  d.untouched = fingerprint(d)
  return d
}

function withFields(d, fields) {
  var next = {}
  for (var k in d) next[k] = d[k]
  for (var f in fields) next[f] = fields[f]
  return next
}

// Leaving a reply without typing a word in it keeps nothing.
function untouched(d) {
  return fingerprint(d) === d.untouched
}

function isEmpty(d) {
  return !str(d.to).trim() && !str(d.cc).trim() && !str(d.bcc).trim()
         && !str(d.subject).trim() && !str(d.text).trim()
}

function normalise(d) {
  if (!d || typeof d !== "object") return null
  var out = blank(d.at)
  var keys = ["id", "mode", "to", "cc", "bcc", "subject", "text", "inReplyTo", "references", "error", "untouched"]
  for (var i = 0; i < keys.length; i++)
    if (typeof d[keys[i]] === "string") out[keys[i]] = d[keys[i]]
  if (["new", "reply", "replyAll", "forward"].indexOf(out.mode) < 0) out.mode = "new"
  if (d.answered && typeof d.answered === "object" && str(d.answered.folder) && Number(d.answered.uid) > 0)
    out.answered = { folder: d.answered.folder, uid: Number(d.answered.uid) }
  var f = d.forward
  if (f && typeof f === "object" && str(f.folder) && Number(f.uid) > 0 && Number(f.uidvalidity) > 0) {
    out.forward = {
      folder: f.folder, uid: Number(f.uid), uidvalidity: Number(f.uidvalidity),
      indexes: (f.indexes && f.indexes.constructor === Array ? f.indexes : []).map(Number)
    }
  }
  if (d.attachments && d.attachments.constructor === Array)
    out.attachments = d.attachments.filter(function (a) { return typeof a === "string" })
  return out
}

// --- subjects ----------------------------------------------------------------------

// Not "Re: Re: Re:", and not "Re: AW:" either: the prefixes other languages'
// mail programs put there mean the same thing.
function reSubject(subject) {
  var s = str(subject).trim()
  return /^(re|aw|sv|antw|vs|ref)\s*:/i.test(s) ? s : "Re: " + s
}

function fwdSubject(subject) {
  var s = str(subject).trim()
  return /^(fwd?|wg|tr|rv)\s*:/i.test(s) ? s : "Fwd: " + s
}

// --- quoting --------------------------------------------------------------------------

var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function longDate(ms) {
  if (!(ms > 0)) return ""
  var d = new Date(ms)
  return DAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear()
         + " at " + Mailbox.clock(ms)
}

function quote(text) {
  return str(text).replace(/\s+$/, "").split("\n").map(function (line) {
    return line.charAt(0) === ">" ? ">" + line : "> " + line
  }).join("\n")
}

function attribution(body) {
  var who = body.from && body.from.length ? Address.label(body.from[0]) : "Somebody"
  var date = longDate(body.date)
  return (date ? "On " + date + ", " : "") + who + " wrote:"
}

// A References header that has been through a long thread can outgrow what
// servers accept on a line. The first and the last few are the ones threading
// programs read.
function references(body) {
  var ids = (str(body.references) + " " + str(body.messageId)).trim().split(/\s+/)
  ids = ids.filter(function (id) { return id.length > 0 })
  if (ids.length > 10) ids = [ids[0]].concat(ids.slice(ids.length - 9))
  return ids.join(" ")
}

function reply(body, folder, me, all, at) {
  var d = blank(at)
  d.mode = all ? "replyAll" : "reply"
  if (all) {
    var both = Address.replyAll(body, me)
    d.to = Address.formatList(both.to)
    d.cc = Address.formatList(both.cc)
  } else {
    d.to = Address.formatList(Address.replyTo(body, me))
  }
  d.subject = reSubject(body.subject)
  d.inReplyTo = str(body.messageId)
  d.references = references(body)
  d.answered = { folder: folder, uid: Number(body.uid) }
  d.text = "\n\n" + attribution(body) + "\n" + quote(body.text)
  d.untouched = fingerprint(d)
  return d
}

function forward(body, folder, at) {
  var d = blank(at)
  d.mode = "forward"
  d.subject = fwdSubject(body.subject)
  var lines = ["", "", "---------- Forwarded message ----------"]
  if (body.from && body.from.length) lines.push("From: " + Address.formatList(body.from))
  if (body.date) lines.push("Date: " + longDate(body.date))
  lines.push("Subject: " + str(body.subject))
  if (body.to && body.to.length) lines.push("To: " + Address.formatList(body.to))
  if (body.cc && body.cc.length) lines.push("Cc: " + Address.formatList(body.cc))
  lines.push("")
  d.text = lines.join("\n") + str(body.text)
  var files = body.attachments || []
  if (files.length) {
    d.forward = {
      folder: folder, uid: Number(body.uid), uidvalidity: Number(body.uidvalidity),
      indexes: files.map(function (a) { return Number(a.index) })
    }
    d.attachments = files.map(function (a) { return str(a.name) })
  }
  d.untouched = fingerprint(d)
  return d
}

// --- mailto: -------------------------------------------------------------------------

function decode(part) {
  try {
    return decodeURIComponent(part)
  } catch (e) {
    return part
  }
}

// RFC 6068. "+" is a plus here, not a space: an address can have one in it.
function fromMailto(uri, at) {
  var s = str(uri).trim()
  if (!/^mailto:/i.test(s)) return null
  s = s.slice(7)
  var d = blank(at)
  var q = s.indexOf("?")
  var to = [decode(q >= 0 ? s.slice(0, q) : s)]
  if (q >= 0) {
    var pairs = s.slice(q + 1).split("&")
    for (var i = 0; i < pairs.length; i++) {
      var eq = pairs[i].indexOf("=")
      if (eq < 0) continue
      var key = decode(pairs[i].slice(0, eq)).toLowerCase()
      var value = decode(pairs[i].slice(eq + 1))
      if (key === "to") to.push(value)
      else if (key === "cc") d.cc = value
      else if (key === "bcc") d.bcc = value
      else if (key === "subject") d.subject = value.replace(/[\r\n]+/g, " ")
      else if (key === "body") d.text = value.replace(/\r\n/g, "\n")
      else if (key === "in-reply-to") d.inReplyTo = value
    }
  }
  d.to = to.filter(function (t) { return t.trim().length > 0 }).join(", ")
  d.untouched = JSON.stringify(["", "", "", "", ""])
  return d
}

// What omarchy-shell hands open(): a JSON object from the drawer or another
// plugin, or the bare mailto: URI xdg-open put where %u was.
function parsePayload(payload, at) {
  var out = { returnTo: "", draft: null }
  var raw = str(payload).trim()
  if (/^mailto:/i.test(raw)) {
    out.draft = fromMailto(raw, at)
    return out
  }
  var data = null
  try {
    data = JSON.parse(raw || "{}")
  } catch (e) {
    return out
  }
  if (!data || typeof data !== "object") return out
  out.returnTo = str(data.returnTo)
  if (str(data.mailto)) out.draft = fromMailto(data.mailto, at)
  else if (str(data.to)) out.draft = fromMailto("mailto:" + encodeURIComponent(data.to), at)
  return out
}

// --- sending ---------------------------------------------------------------------------

// A sentence when the draft cannot go, "" when it can.
function check(d) {
  var fields = [["To", d.to], ["Cc", d.cc], ["Bcc", d.bcc]]
  var count = 0
  for (var i = 0; i < fields.length; i++) {
    var parsed = Address.parseList(fields[i][1])
    if (parsed.bad.length) return "“" + parsed.bad[0] + "” in " + fields[i][0] + " is not an email address."
    count += parsed.people.length
  }
  return count ? "" : "Who is it to? Add an address."
}

function request(d, sent) {
  return {
    to: str(d.to), cc: str(d.cc), bcc: str(d.bcc),
    subject: str(d.subject), text: str(d.text),
    inReplyTo: str(d.inReplyTo), references: str(d.references),
    answered: d.answered, forward: d.forward,
    sent: str(sent)
  }
}

function title(d) {
  if (!d) return "New message"
  if (d.mode === "reply") return "Reply"
  if (d.mode === "replyAll") return "Reply all"
  if (d.mode === "forward") return "Forward"
  return "New message"
}

function summary(d) {
  var people = Address.parseList(str(d.to) + "," + str(d.cc) + "," + str(d.bcc)).people
  var who = people.length ? Address.label(people[0]) : "Nobody yet"
  if (people.length > 1) who += " +" + (people.length - 1)
  var subject = str(d.subject).trim() || "No subject"
  return who + " · " + subject
}
