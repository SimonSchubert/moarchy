// Phone numbers, and whether two of them are the same person.
//
// The same number reaches this phone in several spellings. Contacts holds
// what somebody typed -- "+44 7700 900412", "0170 1234567" -- and the modem
// reports what the network sent, which is usually the international form with
// no spaces and sometimes the national one. A caller whose name is in the book
// has to be shown by name whichever of the two arrived.
//
// The rule is the one every phone uses in some form: compare the last nine
// digits. Nine is long enough that two different subscribers do not collide
// and short enough to be past every country code and trunk prefix. A number
// shorter than that -- a short code, a voicemail box -- only ever matches
// itself. A sender that is a word ("DHL", "Vodafone") is compared as a word.
//
// This file is identical in moarchy.phone and moarchy.messages. A
// plugin cannot import another plugin's files, and these are the rules both
// apps must agree on for a text and a call from one person to show one name.
.pragma library

var TAIL = 9

function text(value) {
  return value === undefined || value === null ? "" : String(value).trim()
}

function digits(value) {
  return text(value).replace(/[^0-9]/g, "")
}

function isWord(value) {
  return /[A-Za-z]/.test(text(value))
}

// What a person may dial: an optional leading plus, digits, star and hash,
// with the spaces, dashes, dots and brackets people type taken out. Anything
// else comes back empty, and an empty number never reaches the modem.
function dialable(value) {
  var t = text(value).replace(/[\s().\-\/]/g, "")
  if (!/^\+?[0-9*#]+$/.test(t)) return ""
  if (t.length > 32) return ""
  return t
}

// The key a number is matched and grouped by.
function key(value) {
  if (isWord(value)) return text(value).toLowerCase()
  var d = digits(value)
  return d.length >= TAIL ? d.slice(d.length - TAIL) : d
}

function same(a, b) {
  var ka = key(a)
  return ka.length > 0 && ka === key(b)
}

// Everyone in contacts.json with a number, sorted by name. The file is read
// rather than parsed with Contacts' own Store.js, which this plugin cannot
// see; the only fields that matter here are two strings.
function people(data) {
  var out = []
  var rows = data && data.contacts
  if (!rows || rows.constructor !== Array) return out
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!row || typeof row !== "object") continue
    var phone = text(row.phone)
    if (!phone || !key(phone)) continue
    out.push({ name: text(row.name) || phone, phone: phone })
  }
  out.sort(function (a, b) {
    var x = a.name.toLowerCase(), y = b.name.toLowerCase()
    return x < y ? -1 : x > y ? 1 : 0
  })
  return out
}

// key -> name, first entry wins.
function index(list) {
  var out = {}
  for (var i = 0; i < (list || []).length; i++) {
    var k = key(list[i].phone)
    if (k && out[k] === undefined) out[k] = list[i].name
  }
  return out
}

function nameFor(names, number) {
  var k = key(number)
  if (!k || !names) return ""
  var name = names[k]
  return name === undefined ? "" : name
}

// The name if there is one, the number as it was given if not.
function label(names, number) {
  return nameFor(names, number) || text(number) || "Unknown"
}

function matching(list, query) {
  var q = text(query).toLowerCase()
  if (!q) return (list || []).slice()
  var d = digits(q)
  var out = []
  for (var i = 0; i < (list || []).length; i++) {
    var p = list[i]
    if (p.name.toLowerCase().indexOf(q) >= 0
        || (d.length > 0 && digits(p.phone).indexOf(d) >= 0))
      out.push(p)
  }
  return out
}
