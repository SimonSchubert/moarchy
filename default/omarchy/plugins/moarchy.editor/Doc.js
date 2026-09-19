// What a file has to be for this editor to write it back, and the paths and
// words around that.
//
// The rules here are the ones a text editor gets wrong silently. Qt's text
// control hands plain text back with some characters changed -- measured, in
// the container these checks run in, with the phone's Qt: a no-break space
// comes back as a space, U+2028 and U+2029 come back as newlines, a lone
// carriage return comes back as a newline, and CRLF comes back as LF. Saving
// such a file would rewrite characters nobody touched, and nothing on the
// screen would say so. So those files open read-only and say why, and the one
// case that can be put back exactly -- a file that is CRLF throughout -- is put
// back.
.pragma library

// Bigger than this is not opened. A guess, not a measurement: the whole file is
// laid out by one TextEdit on a Cortex-A53, and the number is kept low enough
// that a mistaken tap on a log file costs a second rather than the shell.
var LIMIT = 256 * 1024

// --- what the shell hands over ------------------------------------------

// A summon's payload, which arrives in two shapes.
//
// moarchy-editor sends JSON: `{"path": ..., "wait": ...}`. The desktop entry
// that xdg-open runs cannot build JSON, so it hands over the path bare -- an
// absolute path or a file:// URI, which is all xdg-open ever passes. Anything
// else is an empty request, which opens the window and nothing in it.
//
// `refused` is a path that was named and cannot be used, so the window can say
// so instead of opening on the list as though nothing had been asked.
function parsePayload(raw) {
  var out = { path: "", wait: "", returnTo: "", refused: false }
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  if (!text.length) return out
  var named = text
  if (text.charAt(0) === "{") {
    var data = null
    try { data = JSON.parse(text) } catch (e) { data = null }
    if (!data || typeof data !== "object") return out
    if (typeof data.wait === "string") out.wait = data.wait
    if (typeof data.returnTo === "string") out.returnTo = data.returnTo
    named = typeof data.path === "string" ? data.path : ""
    if (!named.length) return out
  }
  out.path = pathFrom(named)
  out.refused = !out.path.length
  return out
}

// An absolute path from what a caller passed, or "" for anything this cannot
// resolve. A relative path is refused rather than guessed at: the shell's
// working directory is not the caller's, so it would name a different file.
function pathFrom(value) {
  var s = String(value || "")
  if (s.indexOf("file://") === 0) {
    s = s.slice(7)
    // file://host/path -- the host is this machine or it is not a file here.
    if (s.charAt(0) !== "/") {
      var slash = s.indexOf("/")
      if (slash < 0) return ""
      s = s.slice(slash)
    }
    try { s = decodeURIComponent(s) } catch (e) { return "" }
  }
  if (s.charAt(0) !== "/") return ""
  if (s.indexOf("\u0000") >= 0) return ""
  return s
}

// A wait marker is a file moarchy-editor is watching for. Only its own names
// are touched, so a summon cannot be used to create an empty file anywhere a
// caller likes.
function markerOk(path) {
  var s = String(path || "")
  return s.charAt(0) === "/" && basename(s).indexOf("moarchy-editor-") === 0
         && s.indexOf("\n") < 0
}

// --- paths ------------------------------------------------------------------

function basename(path) {
  var s = String(path || "")
  while (s.length > 1 && s.charAt(s.length - 1) === "/") s = s.slice(0, -1)
  var i = s.lastIndexOf("/")
  return i < 0 ? s : s.slice(i + 1)
}

function dirname(path) {
  var s = String(path || "")
  while (s.length > 1 && s.charAt(s.length - 1) === "/") s = s.slice(0, -1)
  var i = s.lastIndexOf("/")
  if (i < 0) return "."
  if (i === 0) return "/"
  return s.slice(0, i)
}

// ~ for home, the way a person reads a path on a 360px screen.
function tilde(path, home) {
  var s = String(path || "")
  var h = String(home || "")
  if (!h.length || h === "/") return s
  if (s === h) return "~"
  if (s.indexOf(h + "/") === 0) return "~" + s.slice(h.length)
  return s
}

// The other way, for a path somebody typed.
function expand(path, home) {
  var s = String(path || "").trim()
  if (s === "~") return String(home || "")
  if (s.indexOf("~/") === 0) return String(home || "") + s.slice(1)
  return s
}

// Why a typed path cannot be saved to, or "".
function saveAsProblem(typed, home) {
  var s = expand(typed, home)
  if (!s.length) return "Type a name for the file."
  if (s.charAt(0) !== "/") return "Start the path with / or ~/."
  if (s.charAt(s.length - 1) === "/") return "That is a folder. Add a file name."
  var name = basename(s)
  if (name === "." || name === "..") return "That is a folder. Add a file name."
  if (s.indexOf("\n") >= 0 || s.indexOf("\u0000") >= 0)
    return "A file name cannot have a line break in it."
  return ""
}

// --- the probe --------------------------------------------------------------

// One fork that says what a path is before anything reads it. The size is the
// point: FileView reads a file whole into the shell's own process, and the
// shell is the phone's UI, so a 400 MB log is refused here rather than
// discovered there.
//
//   dir | other | unreadable
//   missing w | missing ro
//   file <bytes> w | file <bytes> ro
//
// A missing file is judged by the nearest folder above it that does exist,
// because saving creates the ones in between: FileView makes missing parents
// itself, which is measured rather than assumed.
var PROBE = [
  'p=$1',
  'if [ -d "$p" ]; then echo dir; exit 0; fi',
  'if [ ! -e "$p" ]; then',
  '  d=${p%/*}',
  '  while [ -n "$d" ] && [ ! -e "$d" ]; do d=${d%/*}; done',
  '  [ -n "$d" ] || d=/',
  '  if [ -d "$d" ] && [ -w "$d" ]; then echo "missing w"; else echo "missing ro"; fi',
  '  exit 0',
  'fi',
  'if [ ! -f "$p" ]; then echo other; exit 0; fi',
  'if [ ! -r "$p" ]; then echo unreadable; exit 0; fi',
  's=$(stat -L -c %s -- "$p") || exit 1',
  'if [ -w "$p" ]; then echo "file $s w"; else echo "file $s ro"; fi'
].join("\n")

function probeCommand(path) {
  return ["sh", "-c", PROBE, "sh", String(path)]
}

// { kind, size, writable } from the probe's one line. kind is "file",
// "missing", "dir", "unreadable", "other", or "" for output this does not
// recognise -- which is treated as a file that would not open.
function parseProbe(out) {
  var words = String(out || "").trim().split(/\s+/)
  var kind = words[0] || ""
  if (kind === "file") {
    var size = parseInt(words[1], 10)
    return { kind: "file", size: isFinite(size) ? size : 0, writable: words[2] === "w" }
  }
  if (kind === "missing")
    return { kind: "missing", size: 0, writable: words[1] !== "ro" }
  if (kind === "dir" || kind === "unreadable" || kind === "other")
    return { kind: kind, size: 0, writable: false }
  return { kind: "", size: 0, writable: false }
}

// What to say when a probe means the file will not be opened, or "".
function probeTrouble(probe) {
  if (!probe) return "That file would not open."
  if (probe.kind === "dir") return "That is a folder, not a file."
  if (probe.kind === "other") return "That is not a file this can open."
  if (probe.kind === "unreadable") return "You do not have permission to read that file."
  if (probe.kind === "missing" && !probe.writable)
    return "That file does not exist, and its folder is not yours to write in."
  if (probe.kind === "file" && probe.size > LIMIT)
    return "That file is " + sizeLabel(probe.size) + ". This opens files up to "
           + sizeLabel(LIMIT) + "."
  if (probe.kind === "") return "That file would not open."
  return ""
}

// FileViewError's numbers: 2 not found, 3 permission denied, 4 not a file.
// Measured rather than read, in the container the checks run in.
function loadTrouble(code) {
  if (code === 3) return "You do not have permission to read that file."
  if (code === 4) return "That is not a file this can open."
  return "That file would not open."
}

function saveTrouble(code) {
  if (code === 3) return "You do not have permission to change that file."
  if (code === 4) return "There is a folder where that file would go."
  return "That file could not be saved."
}

function sizeLabel(bytes) {
  var n = Number(bytes) || 0
  if (n < 1024) return n + " bytes"
  if (n < 1024 * 1024) return Math.round(n / 1024) + " KB"
  return (Math.round(n / (1024 * 1024) * 10) / 10) + " MB"
}

// --- the text itself --------------------------------------------------------

// "lf", "crlf", or "mixed" -- mixed being any lone carriage return, or CRLF and
// LF in one file. A file with no line break at all is "lf".
function endings(text) {
  var s = String(text || "")
  var crlf = 0, lf = 0
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i)
    if (c === 13) {
      if (s.charCodeAt(i + 1) !== 10) return "mixed"
      crlf++
      i++
    } else if (c === 10) {
      lf++
    }
  }
  if (crlf && lf) return "mixed"
  return crlf ? "crlf" : "lf"
}

// Why this text cannot be written back exactly, or "".
//
//   binary     a NUL. Not a text file, whatever its name says.
//   encoding   U+FFFD. The file was not UTF-8, and the bytes that were not are
//              already gone from what was read -- saving would replace them.
//   spaces     a character Qt's text control changes on the way back out.
//   endings    line breaks that would all become one kind.
function problem(text) {
  var s = String(text || "")
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i)
    if (c === 0) return "binary"
  }
  if (s.indexOf("\ufffd") >= 0) return "encoding"
  if (/[\u00a0\u2028\u2029\ufdd0\ufdd1]/.test(s)) return "spaces"
  if (endings(s) === "mixed") return "endings"
  return ""
}

function problemText(kind) {
  if (kind === "binary")
    return "This is not a text file, so it is open to read only."
  if (kind === "encoding")
    return "This file is not UTF-8. Saving would change the characters that could not be read, so it is open to read only."
  if (kind === "spaces")
    return "This file has a no-break space or a Unicode line separator, which saving from here would change. It is open to read only."
  if (kind === "endings")
    return "This file mixes kinds of line break, which saving from here would make all the same. It is open to read only."
  return ""
}

// The text as the editor should hold it: the problem, if any, and CRLF folded
// to LF when that can be undone exactly on the way out.
function forEditing(text) {
  var s = String(text || "")
  var kind = problem(s)
  var ends = endings(s)
  if (!kind && ends === "crlf") s = s.replace(/\r\n/g, "\n")
  return { text: s, endings: ends, problem: kind }
}

function forDisk(text, ends) {
  var s = String(text || "")
  return ends === "crlf" ? s.replace(/\n/g, "\r\n") : s
}

// --- words ------------------------------------------------------------------

function ago(seconds, now) {
  var t = Number(seconds) || 0
  var n = Number(now) || 0
  if (t <= 0) return ""
  var d = Math.max(0, n - t)
  if (d < 60) return "just now"
  if (d < 3600) return Math.floor(d / 60) + " min ago"
  if (d < 86400) return Math.floor(d / 3600) + " h ago"
  var days = Math.floor(d / 86400)
  if (days === 1) return "yesterday"
  if (days < 30) return days + " days ago"
  var when = new Date(t * 1000)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return when.getDate() + " " + months[when.getMonth()] + " " + when.getFullYear()
}
