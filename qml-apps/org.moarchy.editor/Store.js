// The one file this app keeps of its own: which files were opened, and whether
// long lines wrap.
//
// ~/.local/share/moarchy-editor/state.json. The files themselves are wherever
// they are; this is a list of paths, and a path that has gone is dropped from
// the list when it is tapped rather than checked for on every open, because
// checking twenty paths is twenty stats on a window that is supposed to be
// instant.
.pragma library

var SCHEMA = 1

// A home screen of twenty rows is already a list to scroll. Older ones fall off.
var MAX = 20

function blank() {
  return { recent: [], wrap: true }
}

// Whatever was on disk, as a state this app can use. JsonFile hands over null
// for a file that is absent, empty or corrupt, and every one of those is a
// first run.
function parse(data) {
  var out = blank()
  if (!data || typeof data !== "object") return out
  if (data.wrap === false) out.wrap = false
  var rows = Array.isArray(data.recent) ? data.recent : []
  var seen = {}
  for (var i = 0; i < rows.length && out.recent.length < MAX; i++) {
    var row = rows[i]
    if (!row || typeof row.path !== "string") continue
    if (row.path.charAt(0) !== "/" || seen[row.path]) continue
    seen[row.path] = true
    var opened = Number(row.opened)
    out.recent.push({ path: row.path, opened: isFinite(opened) ? opened : 0 })
  }
  return out
}

function serialize(state) {
  var s = state || blank()
  return JSON.stringify({
    schema: SCHEMA,
    wrap: s.wrap !== false,
    recent: (s.recent || []).slice(0, MAX)
  }, null, 1) + "\n"
}

// `path` at the top of the list, opened `now`.
function touch(list, path, now) {
  var out = [{ path: String(path), opened: Number(now) || 0 }]
  var rows = list || []
  for (var i = 0; i < rows.length && out.length < MAX; i++)
    if (rows[i].path !== path) out.push(rows[i])
  return out
}

function forget(list, path) {
  var out = []
  var rows = list || []
  for (var i = 0; i < rows.length; i++)
    if (rows[i].path !== path) out.push(rows[i])
  return out
}
