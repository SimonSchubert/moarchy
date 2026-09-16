// People, as mail names them: a display name and an address, typed as a line.
//
// The To field is text, the way it is in every mail app, because a person
// types "ada" and picks from Contacts as often as they paste an address. So
// this file goes both ways: a list of people into a line somebody can read and
// edit, and a line back into people -- with the ones that are not addresses
// named, so Send can say which.
//
// moarchy-mail checks every address again before anything is sent. These rules
// are for saying so while the field is still on screen.
.pragma library

function str(v) {
  return typeof v === "string" ? v : ""
}

function label(p) {
  if (!p) return ""
  return str(p.name).trim() || str(p.email).trim()
}

// "A" for Ada, from the first letter or digit, so a name in quotes or brackets
// still gets one.
function initial(p) {
  var text = label(p)
  var match = text.match(/[A-Za-z0-9]|[^\s\x21-\x40\x5b-\x60\x7b-\x7e]/)
  return match ? match[0].toUpperCase() : "?"
}

function same(a, b) {
  return str(a).trim().toLowerCase() === str(b).trim().toLowerCase() && str(a).trim() !== ""
}

function format(p) {
  var email = str(p && p.email).trim()
  var name = str(p && p.name).trim()
  if (!name || name === email) return email
  if (/[",;<>@()\[\]:\\.]/.test(name)) name = '"' + name.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
  return name + " <" + email + ">"
}

function formatList(list) {
  return (list || []).map(format).filter(function (s) { return s.length > 0 }).join(", ")
}

// A typed line, split at the commas and semicolons that are between people
// rather than inside a quoted name.
function split(typed) {
  var parts = []
  var current = ""
  var quoted = false
  var angled = false
  var text = str(typed)
  for (var i = 0; i < text.length; i++) {
    var ch = text.charAt(i)
    if (ch === '"' && text.charAt(i - 1) !== "\\") quoted = !quoted
    else if (ch === "<" && !quoted) angled = true
    else if (ch === ">" && !quoted) angled = false
    if ((ch === "," || ch === ";") && !quoted && !angled) {
      parts.push(current)
      current = ""
    } else {
      current += ch
    }
  }
  parts.push(current)
  return parts.map(function (s) { return s.trim() }).filter(function (s) { return s.length > 0 })
}

function looksLikeAddress(email) {
  return /^[^\s@<>(),;:"]+@[^\s@<>(),;:"]+$/.test(str(email)) && email.charAt(email.length - 1) !== "."
}

function parseOne(token) {
  var t = str(token).trim()
  var m = t.match(/^(.*)<([^<>]*)>\s*$/)
  if (m) {
    var name = m[1].trim()
    if (name.length > 1 && name.charAt(0) === '"' && name.charAt(name.length - 1) === '"')
      name = name.slice(1, -1).replace(/\\(.)/g, "$1")
    return { name: name, email: m[2].trim() }
  }
  return { name: "", email: t }
}

// { people: [...], bad: ["what was typed", ...] }
function parseList(typed) {
  var out = { people: [], bad: [] }
  var tokens = split(typed)
  for (var i = 0; i < tokens.length; i++) {
    var p = parseOne(tokens[i])
    if (looksLikeAddress(p.email)) out.people.push(p)
    else out.bad.push(tokens[i])
  }
  return out
}

// What is being typed now: everything after the last separator.
function lastToken(typed) {
  var text = str(typed)
  var cut = Math.max(text.lastIndexOf(","), text.lastIndexOf(";"))
  return text.slice(cut + 1).trim()
}

function replaceLastToken(typed, p) {
  var text = str(typed)
  var cut = Math.max(text.lastIndexOf(","), text.lastIndexOf(";"))
  var head = cut >= 0 ? text.slice(0, cut + 1) + " " : ""
  return head + format(p) + ", "
}

// --- contacts -------------------------------------------------------------------

// Everybody in Contacts' file with an address. Read, never written.
function people(data) {
  var out = []
  var rows = data && data.contacts && data.contacts.constructor === Array ? data.contacts : []
  for (var i = 0; i < rows.length; i++) {
    var c = rows[i]
    if (!c || typeof c !== "object") continue
    var emails = str(c.email).split(/[,;\s]+/)
    for (var j = 0; j < emails.length; j++)
      if (looksLikeAddress(emails[j])) out.push({ name: str(c.name).trim(), email: emails[j] })
  }
  out.sort(function (a, b) { return label(a).toLowerCase() < label(b).toLowerCase() ? -1 : 1 })
  return out
}

function matching(list, typed, limit) {
  var token = lastToken(typed).toLowerCase()
  if (!token.length) return []
  var chosen = parseList(typed).people
  var out = []
  for (var i = 0; i < (list || []).length && out.length < (limit || 5); i++) {
    var p = list[i]
    var taken = chosen.some(function (c) { return same(c.email, p.email) })
    if (taken) continue
    var words = (p.name + " " + p.email).toLowerCase().split(/[\s.@_-]+/)
    var hit = words.some(function (w) { return w.indexOf(token) === 0 })
             || p.email.toLowerCase().indexOf(token) === 0
    if (hit) out.push(p)
  }
  return out
}

// --- replies --------------------------------------------------------------------

function without(list, emails) {
  var out = []
  for (var i = 0; i < (list || []).length; i++) {
    var p = list[i]
    if (!p || !str(p.email)) continue
    var dup = emails.some(function (e) { return same(e, p.email) })
    if (dup) continue
    emails.push(p.email)
    out.push(p)
  }
  return out
}

// Who a reply goes to. Reply-To wins, because a mailing list or a shop that
// sets it is saying where answers are read.
function replyTo(body, me) {
  var list = body && body.replyTo && body.replyTo.length ? body.replyTo : (body ? body.from : [])
  var to = without(list, [])
  // Replying to a message you sent yourself goes to the people you sent it to.
  if (to.length === 1 && same(to[0].email, me)) return without(body.to, [me])
  return to
}

function replyAll(body, me) {
  var taken = [me]
  var to = without(replyTo(body, me), taken)
  var cc = without((body ? body.to : []).concat(body ? body.cc : []), taken)
  return { to: to, cc: cc }
}
