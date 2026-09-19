// What is in a directory, and how it is asked for.
//
// QML has no filesystem. Vitals' Collect.js made the same discovery about
// /proc and came to the same shape: one `sh -c` per read, with the answer
// parsed back here. `ls` is not that command -- its output is for people, it
// escapes nothing, and a name with a space in it is already ambiguous by the
// time it reaches us. GNU find's `-printf` is: the fields are asked for by
// name, in a fixed order, with separators we choose.
//
// The separators are octal 036 and 037, the ASCII record and unit separators,
// which is what they are for. A filename may legally contain either, because a
// filename may contain any byte but NUL and "/" -- and NUL is the one
// separator that cannot be used here, since stdout is read as text and a NUL
// in it is dropped or truncates the stream. So: a file whose name contains a
// record separator is listed wrong. It is the only byte this app is confused
// by, and the alternative is being confused by spaces and newlines instead,
// which people actually have.
.pragma library

var RS = String.fromCharCode(30)
var US = String.fromCharCode(31)

// What a run of the listing can go wrong as. `find` uses 1 for its own
// failures, so ours start at 3.
var OK = 0
var UNREADABLE = 3
var MISSING = 4
var NOT_A_DIRECTORY = 5

// `%y` is the type of the entry, `%Y` the type of what it points at -- so a
// symlink to a directory sorts and opens as a directory, which is the whole
// reason both are asked for. `%Y` answers "N" for a link to nothing and "L"
// for a loop.
var SCRIPT = [
  '[ -e "$1" ] || exit 4',
  '[ -d "$1" ] || exit 5',
  'cd -- "$1" 2>/dev/null || exit 3',
  "exec find . -maxdepth 1 -mindepth 1 -printf '%y\\037%Y\\037%s\\037%T@\\037%f\\036'"
].join("\n")

// The directory arrives as an argument rather than inside the script, so that
// nothing here has to quote it. `sh -c script sh DIR` puts DIR in $1: the
// second "sh" is $0, which is what the shell calls itself in its own errors.
function command(dir) {
  return ["sh", "-c", SCRIPT, "sh", String(dir || "/")]
}

function trouble(code) {
  if (code === MISSING) return "That folder is not there any more."
  if (code === NOT_A_DIRECTORY) return "That is a file, not a folder."
  if (code === UNREADABLE) return "That folder is not yours to read."
  return "That folder could not be read."
}

// The blob back into entries.
//
// A field that will not parse takes its default rather than dropping the whole
// entry: a listing that silently loses a file is worse than one that says a
// file is 0 bytes, because only one of those is visible.
function parse(blob) {
  var text = String(blob === null || blob === undefined ? "" : blob)
  var records = text.split(RS)
  var out = []
  for (var i = 0; i < records.length; i++) {
    if (!records[i].length) continue
    var field = records[i].split(US)
    if (field.length < 5) continue
    var name = field[4]
    if (!name.length || name === "." || name === "..") continue
    var kind = field[0]
    var target = field[1]
    var size = parseInt(field[2], 10)
    var when = parseFloat(field[3])
    var link = kind === "l"
    // "N" is a link to nothing, "L" a loop, "?" anything else find could not
    // stat. All three are shown -- a broken link is a thing on the disk, and
    // an app that hides it is an app that cannot be used to delete it.
    var broken = link && (target === "N" || target === "L" || target === "?")
    var real = link && !broken ? target : kind
    out.push({
      name: name,
      folder: real === "d",
      link: link,
      broken: broken,
      size: isFinite(size) ? size : 0,
      modified: isFinite(when) ? when : 0
    })
  }
  return out
}

// Folders first, then the sort somebody asked for.
//
// Folders first is not a preference and is not offered as one: the list is
// walked with a thumb, and a directory is the only row that leads anywhere.
// Mixing thirty photographs into it costs a scroll every time.
//
// Each key has one direction and it is the useful one -- names up, because
// that is how names are looked for; sizes and dates down, because nobody opens
// a file manager to find the smallest file or the oldest.
function arrange(entries, sort, hidden, query) {
  var list = []
  var needle = String(query || "").toLowerCase()
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (!hidden && e.name.charAt(0) === ".") continue
    if (needle.length && e.name.toLowerCase().indexOf(needle) < 0) continue
    list.push(e)
  }
  var key = sort === "size" || sort === "modified" ? sort : "name"
  list.sort(function (a, b) {
    if (a.folder !== b.folder) return a.folder ? -1 : 1
    if (key === "size" && !a.folder && a.size !== b.size) return b.size - a.size
    if (key === "modified" && a.modified !== b.modified) return b.modified - a.modified
    return byName(a.name, b.name)
  })
  return list
}

// Case-insensitive, and digits compared as numbers so that "photo 9" comes
// before "photo 10". A camera roll is the list this app is most often pointed
// at, and it is numbered.
function byName(a, b) {
  var x = String(a), y = String(b)
  var re = /(\d+)|(\D+)/g
  var ax = x.toLowerCase().match(re) || []
  var bx = y.toLowerCase().match(re) || []
  for (var i = 0; i < ax.length && i < bx.length; i++) {
    var an = /^\d/.test(ax[i]), bn = /^\d/.test(bx[i])
    if (an && bn) {
      var d = parseInt(ax[i], 10) - parseInt(bx[i], 10)
      if (d) return d
    } else if (ax[i] !== bx[i]) {
      return ax[i] < bx[i] ? -1 : 1
    }
  }
  if (ax.length !== bx.length) return ax.length - bx.length
  // Two names that differ only in case still have an order, or a sort that is
  // asked the same question twice can answer it differently.
  return x === y ? 0 : (x < y ? -1 : 1)
}

var UNITS = ["B", "kB", "MB", "GB", "TB"]

// Powers of a thousand, not of 1024: it is what the disk was sold as, what
// `df` on this phone reports with -H, and what Vitals already shows.
function human(bytes) {
  var amount = Math.max(0, Number(bytes) || 0)
  var scale = 0
  while (amount >= 1000 && scale < UNITS.length - 1) { amount /= 1000.0; scale += 1 }
  var places = (amount < 10 && scale) ? 1 : 0
  return amount.toFixed(places) + " " + UNITS[scale]
}

var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function two(n) { return n < 10 ? "0" + n : String(n) }

// A time, at the precision that is worth the column.
//
// Nobody reads "2026-09-15 14:32:07" in a list; they read "14:32" and know it
// was today. So the answer gets shorter as it gets closer, and the year
// appears only when it is not this one.
function when(epochSeconds, nowMs) {
  var at = new Date((Number(epochSeconds) || 0) * 1000)
  if (!(Number(epochSeconds) > 0)) return ""
  var now = new Date(nowMs || Date.now())
  var midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  var t = at.getTime()
  if (t >= midnight) return two(at.getHours()) + ":" + two(at.getMinutes())
  if (t >= midnight - 86400000) return "Yesterday"
  if (t >= midnight - 6 * 86400000) return DAYS[at.getDay()]
  var stamp = at.getDate() + " " + MONTHS[at.getMonth()]
  if (at.getFullYear() !== now.getFullYear()) stamp += " " + at.getFullYear()
  return stamp
}

// The line under a name: what it is, and when it was last touched.
function note(entry, nowMs) {
  var age = when(entry.modified, nowMs)
  if (entry.broken) return "Link to nothing"
  var what = entry.folder ? (entry.link ? "Folder link" : "Folder")
                          : (entry.link ? "Link · " + human(entry.size) : human(entry.size))
  return age.length ? what + " · " + age : what
}

// What a whole directory is, in the one line under its name.
function summary(entries) {
  var folders = 0, files = 0
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].folder) folders += 1; else files += 1
  }
  if (!folders && !files) return "Empty"
  var out = []
  if (folders) out.push(folders + (folders === 1 ? " folder" : " folders"))
  if (files) out.push(files + (files === 1 ? " file" : " files"))
  return out.join(" · ")
}

function extension(name) {
  var text = String(name || "")
  var dot = text.lastIndexOf(".")
  // A leading dot is a hidden file, not an extension: ".bashrc" is not a file
  // of type "bashrc".
  if (dot <= 0 || dot === text.length - 1) return ""
  return text.slice(dot + 1).toLowerCase()
}

var BY_KIND = {
  image: ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "tif",
          "heic", "heif", "avif", "ico", "raw", "dng"],
  audio: ["mp3", "ogg", "oga", "opus", "flac", "wav", "m4a", "aac", "wma", "mid"],
  video: ["mp4", "mkv", "webm", "avi", "mov", "m4v", "mpg", "mpeg", "wmv", "3gp"],
  document: ["pdf", "odt", "doc", "docx", "rtf", "epub", "mobi", "djvu"],
  spreadsheet: ["ods", "xls", "xlsx", "csv", "tsv"],
  presentation: ["odp", "ppt", "pptx"],
  archive: ["zip", "tar", "gz", "tgz", "bz2", "xz", "zst", "7z", "rar", "iso",
            "pkg", "deb", "rpm", "apk", "jar"],
  font: ["ttf", "otf", "woff", "woff2", "pfb"],
  text: ["txt", "md", "log", "conf", "cfg", "ini", "json", "xml", "yaml", "yml",
         "toml", "html", "htm", "css", "js", "qml", "py", "sh", "c", "h", "cpp",
         "rs", "go", "java", "kt", "sql", "desktop", "service", "patch", "diff"]
}

// Adwaita's mimetype set, which is small on purpose: nine pictures rather than
// a lookup of every type the machine knows. A phone's list is photographs,
// videos, music and documents, and a glyph is there to be told apart at a
// glance from a metre away rather than to be precise.
var GLYPHS = {
  image: "image-x-generic-symbolic",
  audio: "audio-x-generic-symbolic",
  video: "video-x-generic-symbolic",
  document: "x-office-document-symbolic",
  spreadsheet: "x-office-spreadsheet-symbolic",
  presentation: "x-office-presentation-symbolic",
  archive: "package-x-generic-symbolic",
  font: "font-x-generic-symbolic",
  text: "text-x-generic-symbolic"
}

function kindOf(name) {
  var ext = extension(name)
  if (!ext.length) return ""
  for (var kind in BY_KIND) {
    if (BY_KIND[kind].indexOf(ext) >= 0) return kind
  }
  return ""
}

// The icon names for one row, best first. Chrome.Icon walks the list, so the
// generic page is always last and a row is never blank.
function glyphs(entry) {
  if (entry.broken) return ["action-unavailable-symbolic", "text-x-generic-symbolic"]
  if (entry.folder) return ["folder-symbolic", "inode-directory-symbolic"]
  var kind = kindOf(entry.name)
  if (kind) return [GLYPHS[kind], "text-x-generic-symbolic"]
  return ["text-x-generic-symbolic"]
}
