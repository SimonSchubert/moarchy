// Telling "there is no file yet" apart from "the file is broken".
//
// Both look like an empty store to a parser that returns a default on failure,
// and they need opposite handling: an absent file should be created on the next
// save, a corrupt one must be moved aside first. Python's stores have always
// made this distinction -- store.py moves an unparseable file to
// `.broken-<epoch>.json` because "the broken copy is the only evidence of what
// went wrong", and because the next save would otherwise destroy whatever the
// user actually had.
//
// Kept as plain JS with no QML in it so the decision can be tested without a
// display; JsonFile.qml is the twenty lines that act on it.
.pragma library

var EMPTY = "empty"
var CORRUPT = "corrupt"
var OK = "ok"

// What is in this text: nothing, rubbish, or an object.
//
// A JSON document that parses to a non-object -- `[]`, `12`, `null`, `"x"` --
// counts as corrupt rather than empty. Every store here writes an object at
// the top level, so anything else is a file that is not ours, and overwriting
// it silently is the thing to avoid.
function classify(text) {
  var raw = String(text === null || text === undefined ? "" : text)
  if (!raw.trim()) return { state: EMPTY, data: null }
  var data
  try {
    data = JSON.parse(raw)
  } catch (e) {
    return { state: CORRUPT, data: null }
  }
  if (!data || typeof data !== "object" || data.constructor === Array) {
    return { state: CORRUPT, data: null }
  }
  return { state: OK, data: data }
}

// Where a corrupt file goes. The same name Python's `path.with_suffix()`
// produces, so a phone that has run both halves has one convention in the
// directory rather than two: notes.json -> notes.broken-1757930000.json
function brokenPath(path, epochSeconds) {
  var p = String(path || "")
  var slash = p.lastIndexOf("/")
  var dot = p.lastIndexOf(".")
  var stem = dot > slash ? p.slice(0, dot) : p
  return stem + ".broken-" + Math.floor(epochSeconds) + ".json"
}
