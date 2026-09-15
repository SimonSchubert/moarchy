// The notes file, in the same shape the GTK app writes.
//
// ~/.local/share/moarchy-keep/notes.json is the GTK app's file. This plugin
// reads and writes it so a note typed in either place is the same note.
// Nothing here knows about QML ids; every function takes a store object
// `{notes, view}` and returns a new one, so a property write is a new array
// and every binding notices.
.pragma library

var SCHEMA = 1
var TEXT = "text"
var LIST = "list"
var CARD_ITEMS = 7

var COLOURS = [
  "default", "coral", "peach", "sand", "mint", "sage", "fog", "dusk", "clay"
]

function newId() {
  return Date.now().toString(16) + Math.floor(Math.random() * 0x10000).toString(16)
}

function emptyStore() {
  return { notes: [], view: "grid" }
}

function parse(text) {
  var store = emptyStore()
  if (!text || !String(text).trim()) return store
  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return store
  }
  if (!data || !data.notes || data.notes.length === undefined) return store
  var notes = []
  for (var i = 0; i < data.notes.length; i++) {
    var n = noteFrom(data.notes[i])
    if (n) notes.push(n)
  }
  store.notes = notes
  if (data.view === "grid" || data.view === "list") store.view = data.view
  return store
}

function serialize(store) {
  var notes = []
  var list = store && store.notes ? store.notes : []
  for (var i = 0; i < list.length; i++) notes.push(noteTo(list[i]))
  return JSON.stringify({
    schema: SCHEMA,
    view: (store && store.view) || "grid",
    notes: notes
  }, null, 1)
}

function noteFrom(data) {
  if (!data || typeof data !== "object") return null
  var kind = data.kind
  if (kind !== TEXT && kind !== LIST)
    kind = data.items ? LIST : TEXT
  var items = []
  var raw = data.items
  if (raw && raw.length !== undefined) {
    for (var i = 0; i < raw.length; i++) {
      if (!raw[i] || typeof raw[i] !== "object") continue
      items.push({ text: String(raw[i].text || ""), done: !!raw[i].done })
    }
  }
  var now = Date.now() / 1000
  var created = typeof data.created === "number" ? data.created : now
  return {
    id: String(data.id || newId()),
    kind: kind,
    title: String(data.title || ""),
    body: String(data.body || ""),
    items: items,
    colour: String(data.colour || "default"),
    pinned: !!data.pinned,
    created: created,
    edited: typeof data.edited === "number" ? data.edited : created
  }
}

function noteTo(note) {
  var data = {
    id: note.id,
    kind: note.kind,
    title: note.title,
    colour: note.colour,
    pinned: !!note.pinned,
    created: Math.round(note.created * 1000) / 1000,
    edited: Math.round(note.edited * 1000) / 1000
  }
  if (note.kind === LIST) data.items = note.items || []
  else data.body = note.body || ""
  return data
}

function isEmpty(note) {
  if (!note) return true
  if (String(note.title || "").trim()) return false
  if (note.kind === LIST) {
    var items = note.items || []
    for (var i = 0; i < items.length; i++)
      if (String(items[i].text || "").trim()) return false
    return true
  }
  return !String(note.body || "").trim()
}

function matches(note, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return true
  if (String(note.title || "").toLowerCase().indexOf(needle) >= 0) return true
  if (String(note.body || "").toLowerCase().indexOf(needle) >= 0) return true
  var items = note.items || []
  for (var i = 0; i < items.length; i++)
    if (String(items[i].text || "").toLowerCase().indexOf(needle) >= 0) return true
  return false
}

function cloneNote(note) {
  var items = []
  var src = note.items || []
  for (var i = 0; i < src.length; i++)
    items.push({ text: src[i].text, done: !!src[i].done })
  return {
    id: note.id,
    kind: note.kind,
    title: note.title,
    body: note.body,
    items: items,
    colour: note.colour,
    pinned: !!note.pinned,
    created: note.created,
    edited: note.edited
  }
}

function create(kind) {
  var now = Date.now() / 1000
  var note = {
    id: newId(),
    kind: kind === LIST ? LIST : TEXT,
    title: "",
    body: "",
    items: kind === LIST ? [{ text: "", done: false }] : [],
    colour: "default",
    pinned: false,
    created: now,
    edited: now
  }
  return note
}

function toText(note) {
  if (note.kind !== LIST) return note
  var lines = []
  var items = note.items || []
  for (var i = 0; i < items.length; i++) {
    if (!String(items[i].text || "").trim()) continue
    lines.push((items[i].done ? "✓ " : "") + items[i].text)
  }
  note.body = lines.join("\n")
  note.items = []
  note.kind = TEXT
  return note
}

function toList(note) {
  if (note.kind === LIST) return note
  var items = []
  var lines = String(note.body || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var done = line.indexOf("✓ ") === 0
    items.push({ text: done ? line.slice(2) : line, done: done })
  }
  if (!items.length) items.push({ text: "", done: false })
  note.items = items
  note.body = ""
  note.kind = LIST
  return note
}

function sections(notes, query) {
  var matching = []
  var list = notes || []
  for (var i = 0; i < list.length; i++)
    if (matches(list[i], query)) matching.push(list[i])
  matching.sort(function (a, b) { return b.edited - a.edited })
  var pinned = [], others = []
  for (var j = 0; j < matching.length; j++) {
    if (matching[j].pinned) pinned.push(matching[j])
    else others.push(matching[j])
  }
  return { pinned: pinned, others: others }
}

function previewItems(note) {
  var items = note.items || []
  var open = [], done = []
  for (var i = 0; i < items.length; i++) {
    if (!String(items[i].text || "").trim()) continue
    if (items[i].done) done.push(items[i])
    else open.push(items[i])
  }
  var ordered = open.concat(done)
  var shown = []
  for (var j = 0; j < ordered.length && shown.length < CARD_ITEMS; j++)
    shown.push(ordered[j])
  return { items: shown, more: Math.max(0, ordered.length - shown.length) }
}

function editedLabel(when, now) {
  if (!when) return ""
  var stamp = new Date(when * 1000)
  var today = now ? new Date(now * 1000) : new Date()
  function pad(n) { return n < 10 ? "0" + n : String(n) }
  var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
  if (stamp.toDateString() === today.toDateString())
    return "Edited " + pad(stamp.getHours()) + ":" + pad(stamp.getMinutes())
  if (stamp.getFullYear() === today.getFullYear())
    return "Edited " + stamp.getDate() + " " + months[stamp.getMonth()]
  return "Edited " + stamp.getDate() + " " + months[stamp.getMonth()] + " " + stamp.getFullYear()
}

function estimateHeight(note) {
  var h = 36
  if (note.title) h += 20
  if (note.kind === LIST) {
    var n = Math.min((note.items || []).length, CARD_ITEMS)
    h += n * 18
  } else {
    var lines = String(note.body || "").split("\n")
    h += Math.min(lines.length, 6) * 16
  }
  return h
}

function splitColumns(notes) {
  var left = [], right = [], hL = 0, hR = 0
  for (var i = 0; i < (notes || []).length; i++) {
    var n = notes[i]
    var h = estimateHeight(n)
    if (hL <= hR) { left.push(n); hL += h } else { right.push(n); hR += h }
  }
  return { left: left, right: right }
}
