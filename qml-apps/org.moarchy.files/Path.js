// A path, as arithmetic on a string.
//
// Nothing here touches the disk, which is the point: where "up" goes, what a
// breadcrumb says, and whether one path is inside another are decisions that
// can be wrong, and a decision that can be wrong should be testable without a
// filesystem to be wrong about. `isUnder` in particular is the guard that
// stops a folder being copied into itself, and that one is worth a test file
// of its own rather than a hope.
//
// Textual only. `..` is never resolved here because resolving it textually is
// wrong the moment a symlink is involved -- /a/link/.. is not /a. This app
// never builds a path containing `..`: it goes up by truncating, and down by
// appending a name that came from a directory listing.
.pragma library

// Collapse repeated slashes and drop a trailing one. "/" survives both.
function clean(path) {
  var text = String(path === null || path === undefined ? "" : path)
  if (!text.length) return "/"
  text = text.replace(/\/+/g, "/")
  if (text.length > 1 && text.charAt(text.length - 1) === "/")
    text = text.slice(0, -1)
  return text.length ? text : "/"
}

function isRoot(path) {
  return clean(path) === "/"
}

// One level up. The root is its own parent, which is what makes "keep going
// up" terminate rather than needing a separate check at every call site.
function parent(path) {
  var text = clean(path)
  if (text === "/") return "/"
  var cut = text.lastIndexOf("/")
  if (cut <= 0) return "/"
  return text.slice(0, cut)
}

function base(path) {
  var text = clean(path)
  if (text === "/") return "/"
  return text.slice(text.lastIndexOf("/") + 1)
}

function join(dir, name) {
  var head = clean(dir)
  var tail = String(name === null || name === undefined ? "" : name)
  if (!tail.length) return head
  if (head === "/") return "/" + tail
  return head + "/" + tail
}

// Is `path` the same as `root`, or inside it?
//
// The string compare has to be against `root + "/"` and not against `root`:
// "/home/simon-old" starts with "/home/simon" and is not in it. That is the
// off-by-one that turns a containment check into a licence to recurse.
function isUnder(path, root) {
  var p = clean(path)
  var r = clean(root)
  if (p === r) return true
  if (r === "/") return true
  return p.indexOf(r + "/") === 0
}

// How deep, counting from the root. "/" is 0, "/home" is 1.
function depth(path) {
  var text = clean(path)
  if (text === "/") return 0
  return text.split("/").length - 1
}

// What a person calls this path: "~", "~/Pictures", "/etc".
function pretty(path, home) {
  var p = clean(path)
  var h = clean(home)
  if (!home || h === "/") return p
  if (p === h) return "~"
  if (isUnder(p, h)) return "~" + p.slice(h.length)
  return p
}

// The breadcrumb: every step from the root to here, each with the path a tap
// on it should go to.
//
// Home is one crumb rather than three, because "/", "home" and "simon" are
// three taps of scrolling to reach the only one of them anybody wants -- and
// because a phone's strip is 360px wide and has room for about four.
function crumbs(path, home) {
  var p = clean(path)
  var h = clean(home)
  var out = []
  var inHome = home && h !== "/" && isUnder(p, h)

  if (inHome) {
    out.push({ label: "Home", path: h })
    if (p === h) return out
    var rest = p.slice(h.length + 1).split("/")
    var walk = h
    for (var i = 0; i < rest.length; i++) {
      walk = join(walk, rest[i])
      out.push({ label: rest[i], path: walk })
    }
    return out
  }

  out.push({ label: "/", path: "/" })
  if (p === "/") return out
  var parts = p.slice(1).split("/")
  var here = ""
  for (var k = 0; k < parts.length; k++) {
    here = here + "/" + parts[k]
    out.push({ label: parts[k], path: here })
  }
  return out
}
