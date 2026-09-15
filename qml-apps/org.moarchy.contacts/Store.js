// One file, and the rows in it this app cannot read.
//
// `~/.local/share/moarchy-contacts/contacts.json` is a list of contacts with a
// schema number on it. The list is written in name order, because the file is
// meant to be legible to the person whose book it is -- and the ones who will
// read it are a person with a text editor and a script with `jq`, in that
// order.
//
// The part worth explaining is `strays`. Quickshell's FileView already refuses
// to overwrite a file that will not parse, and moves it aside when it is
// broken; that guards the document. It does not guard a *row*: a file that
// parses cleanly can hold a contact with nothing on it, this app has nowhere
// to draw such a thing, and the next save would write the file back without
// it. So every row that cannot be read is kept exactly as it was found and
// written back untouched.
.pragma library
.import "Contacts.js" as Contacts

var SCHEMA = 1

function parse(data) {
  var out = { contacts: [], strays: [] }
  if (!data || typeof data !== "object") return out
  var rows = data.contacts
  if (!rows || rows.constructor !== Array) return out

  var seen = {}
  for (var i = 0; i < rows.length; i++) {
    var c = Contacts.normalise(rows[i], i + 1)
    if (c === null) { out.strays.push(rows[i]); continue }
    if (seen[c.id]) c.id = Contacts.newId(i + 1)
    seen[c.id] = true
    out.contacts.push(c)
  }
  out.contacts.sort(Contacts.byName)
  return out
}

function toJson(c) {
  var out = { id: c.id }
  if (c.name) out.name = c.name
  if (c.phone) out.phone = c.phone
  if (c.email) out.email = c.email
  if (c.note) out.note = c.note
  return out
}

function serialize(contacts, strays) {
  var rows = []
  var list = (contacts || []).slice()
  list.sort(Contacts.byName)
  for (var i = 0; i < list.length; i++) rows.push(toJson(list[i]))
  for (var j = 0; j < (strays || []).length; j++) rows.push(strays[j])
  return JSON.stringify({ schema: SCHEMA, contacts: rows }, null, 1)
}
