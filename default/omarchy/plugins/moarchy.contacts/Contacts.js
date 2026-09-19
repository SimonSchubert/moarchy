// One contact, and the questions asked of a list of them.
//
// A contact is a plain object: a name, and three optional strings that are
// usually a phone, an email and a note. Nothing here touches QML, which is
// what lets "does this match the search" and "is this empty enough to throw
// away" be answered by a test rather than by tapping through a form on a
// phone.
.pragma library

var seq = 0

function newId(now) {
  seq += 1
  return "c" + Math.floor(now || Date.now()) + "-" + seq
}

function blank(now) {
  return {
    id: newId(now),
    name: "",
    phone: "",
    email: "",
    note: ""
  }
}

function copy(c) {
  return {
    id: c.id,
    name: c.name,
    phone: c.phone,
    email: c.email,
    note: c.note
  }
}

function str(value) {
  return typeof value === "string" ? value.trim() : ""
}

function normalise(data, now) {
  if (!data || typeof data !== "object") return null
  var name = str(data.name)
  var phone = str(data.phone)
  var email = str(data.email)
  var note = str(data.note)
  // A row with nothing on it is not a contact somebody meant to keep.
  if (!name && !phone && !email && !note) return null
  return {
    id: str(data.id) || newId(now),
    name: name,
    phone: phone,
    email: email,
    note: note
  }
}

function isEmpty(c) {
  if (!c) return true
  return !str(c.name) && !str(c.phone) && !str(c.email) && !str(c.note)
}

// Sort key: name if there is one, otherwise the first field that has anything
// in it. A contact with only a number still has to appear somewhere, and
// burying it under the empty names is how it gets lost.
function sortKey(c) {
  var name = str(c.name)
  if (name) return name.toLowerCase()
  var phone = str(c.phone)
  if (phone) return phone.toLowerCase()
  var email = str(c.email)
  if (email) return email.toLowerCase()
  return str(c.note).toLowerCase()
}

function byName(a, b) {
  var ka = sortKey(a)
  var kb = sortKey(b)
  if (ka < kb) return -1
  if (ka > kb) return 1
  return a.id < b.id ? -1 : 1
}

function matches(c, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return true
  if (String(c.name || "").toLowerCase().indexOf(needle) >= 0) return true
  if (String(c.phone || "").toLowerCase().indexOf(needle) >= 0) return true
  if (String(c.email || "").toLowerCase().indexOf(needle) >= 0) return true
  if (String(c.note || "").toLowerCase().indexOf(needle) >= 0) return true
  return false
}

function filtered(list, query) {
  var out = []
  for (var i = 0; i < (list || []).length; i++)
    if (matches(list[i], query)) out.push(list[i])
  return out
}

function find(list, id) {
  for (var i = 0; i < (list || []).length; i++)
    if (list[i].id === id) return list[i]
  return null
}

function withContact(list, contact) {
  var out = []
  var found = false
  for (var i = 0; i < (list || []).length; i++) {
    if (list[i].id === contact.id) {
      out.push(contact)
      found = true
    } else {
      out.push(list[i])
    }
  }
  if (!found) out.push(contact)
  out.sort(byName)
  return out
}

function without(list, id) {
  var out = []
  for (var i = 0; i < (list || []).length; i++)
    if (list[i].id !== id) out.push(list[i])
  return out
}

// The line under the name on a row. Phone first, then email — the two things
// a person actually opens Contacts to find. A note stays on the editor.
function line(c) {
  if (!c) return ""
  var phone = str(c.phone)
  if (phone) return phone
  return str(c.email)
}

// The letter a section header shows. Digits and punctuation go under "#",
// which is what every address book does and what nobody has to be told.
function initial(c) {
  var key = sortKey(c)
  if (!key) return "#"
  var ch = key.charAt(0).toUpperCase()
  if (ch >= "A" && ch <= "Z") return ch
  return "#"
}

// Group a sorted list into { letter, contacts } sections for the screen.
function sections(list) {
  var out = []
  var current = null
  for (var i = 0; i < (list || []).length; i++) {
    var c = list[i]
    var letter = initial(c)
    if (!current || current.letter !== letter) {
      current = { letter: letter, contacts: [] }
      out.push(current)
    }
    current.contacts.push(c)
  }
  return out
}
