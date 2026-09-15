// The four things this app remembers, which are all about the view.
//
// `~/.local/share/moarchy-files/view.json`. Nothing here is anybody's data --
// the files are the data, and they are on the disk already. This is which
// order the list was in, whether hidden files were showing, and which folder
// was open when the phone reclaimed the app, which on a phone is most of the
// time and is not the same event as somebody closing it.
//
// A path is kept rather than a history, because a history of directories is a
// thing to maintain and the only entry anybody ever wants from it is the last.
.pragma library
.import "Path.js" as Path

var SCHEMA = 1
var SORTS = ["name", "size", "modified"]

// What each order is called on the menu that switches it. The word is the
// sort's own name, not "ascending" -- nobody has ever wanted to know the
// direction, only the key.
var SORT_LABELS = { name: "Name", size: "Size", modified: "Modified" }

function parse(data) {
  var out = { sort: "name", hidden: false, path: "" }
  if (!data || typeof data !== "object") return out
  if (SORTS.indexOf(data.sort) >= 0) out.sort = data.sort
  out.hidden = data.hidden === true
  if (typeof data.path === "string" && data.path.charAt(0) === "/")
    out.path = Path.clean(data.path)
  return out
}

function serialize(sort, hidden, path) {
  var out = {
    schema: SCHEMA,
    sort: SORTS.indexOf(sort) >= 0 ? sort : "name",
    hidden: hidden === true
  }
  // A path is only written when it is one: the empty string would come back as
  // a folder called "" and send the app to the root on the next start.
  if (path && String(path).charAt(0) === "/") out.path = Path.clean(path)
  return JSON.stringify(out, null, 1) + "\n"
}
