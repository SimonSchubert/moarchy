// Changing something on the disk, which is the half that can lose things.
//
// Every operation here is a shell script with the paths passed in as arguments
// rather than pasted into the text, so nothing is ever quoted and a file named
// `; rm -rf ~` is a file named `; rm -rf ~`. The scripts are short and the
// decisions are not in them: which trash a file goes to, whether a folder may
// be pasted into itself, and whether a name is usable are functions in this
// file with no shell anywhere near them, because those are the three ways an
// app of this kind destroys somebody's afternoon and a test can hold all three.
//
// Nothing here overwrites. A copy or a move into a directory that already has
// that name lands as "holiday (2).jpg"; a rename onto an existing name is
// refused and says so. The one command that removes anything outright is
// `purge`, it only works inside the trash, and the app asks first.
.pragma library
.import "Path.js" as Path

// Free name, then act. Both scripts below want "a name in this directory that
// nothing is using", and the walk stops at a thousand rather than never: a
// loop with no ceiling in a file manager is a phone that has stopped
// responding for a reason nobody can see.
var FREE = [
  'free() {',
  '  d=$1; b=$2',
  '  if [ ! -e "$d/$b" ] && [ ! -L "$d/$b" ]; then printf %s "$b"; return 0; fi',
  '  stem=${b%.*}; ext=',
  '  if [ "$stem" != "$b" ] && [ -n "$stem" ]; then ext=".${b##*.}"; else stem=$b; fi',
  '  n=2',
  '  while [ "$n" -lt 1000 ]; do',
  '    c="$stem ($n)$ext"',
  '    if [ ! -e "$d/$c" ] && [ ! -L "$d/$c" ]; then printf %s "$c"; return 0; fi',
  '    n=$((n+1))',
  '  done',
  '  return 1',
  '}'
].join("\n")

// What went wrong, in a sentence somebody can act on. The numbers are ours
// above 2; below that they are the shell's and the tool's.
var GONE = 4
var NOT_A_DIRECTORY = 5
var NO_FREE_NAME = 6
var IN_THE_WAY = 7

function why(code, what) {
  if (code === GONE) return "That is not there any more."
  if (code === NOT_A_DIRECTORY) return "That is not a folder."
  if (code === NO_FREE_NAME) return "There are too many copies of that name here already."
  if (code === IN_THE_WAY) return "There is already something called that here."
  return (what || "That") + " did not work."
}

// --- what a name may be ------------------------------------------------

// 255 is the limit on every filesystem this phone will meet, and it counts
// bytes rather than characters -- which matters, because the name being typed
// is as likely to be "Urlaubsfotos München" as "holiday".
function utf8Length(text) {
  var n = 0
  for (var i = 0; i < text.length; i++) {
    var c = text.charCodeAt(i)
    if (c < 0x80) n += 1
    else if (c < 0x800) n += 2
    else if (c >= 0xd800 && c < 0xdc00) { n += 4; i += 1 }
    else n += 3
  }
  return n
}

function nameProblem(name) {
  var text = String(name === null || name === undefined ? "" : name)
  if (!text.length) return "It needs a name."
  if (text === "." || text === "..") return "That name means the folder itself."
  if (text.indexOf("/") >= 0) return "A name cannot have a slash in it."
  if (utf8Length(text) > 255) return "That name is too long."
  return ""
}

// --- what may be pasted where -----------------------------------------

// The one that matters is the third: `cp -a ~/Pictures ~/Pictures/backup`
// copies a directory into itself, and what it does next depends on the version
// of cp -- GNU notices and stops part way, having already written some of it.
// Nothing should get that far.
function pasteProblem(kind, src, destDir) {
  var from = Path.clean(src)
  var to = Path.clean(destDir)
  if (Path.isRoot(from)) return "The whole filesystem is not a thing to copy."
  if (kind === "move" && Path.parent(from) === to) return "It is already here."
  if (from === to) return "A folder cannot be put inside itself."
  if (Path.isUnder(to, from)) return "A folder cannot be put inside itself."
  return ""
}

// --- what may be deleted ----------------------------------------------

function trashProblem(path, home) {
  var p = Path.clean(path)
  if (Path.isRoot(p)) return "The filesystem itself is not something to delete."
  // Covers the home folder and everything above it in one comparison: if the
  // home directory is inside what is being deleted, so is everything a person
  // has.
  if (home && Path.isUnder(Path.clean(home), p))
    return "Your home folder is not something this app will delete."
  return ""
}

// --- the operations ---------------------------------------------------

function makeDir(dir, name) {
  var script = [
    '[ -d "$1" ] || exit 5',
    'if [ -e "$1/$2" ] || [ -L "$1/$2" ]; then exit 7; fi',
    'exec mkdir -- "$1/$2"'
  ].join("\n")
  return ["sh", "-c", script, "sh", String(dir), String(name)]
}

// The existence check before the move is advisory: something could take the
// name in between. `-T` is what makes losing that race harmless rather than
// silent -- without it, renaming a folder onto an existing folder puts it
// *inside* it, and the file the person was looking at is suddenly one level
// deeper with nothing said.
function rename(dir, from, to) {
  var script = [
    '[ -e "$1/$2" ] || [ -L "$1/$2" ] || exit 4',
    'if [ -e "$1/$3" ] || [ -L "$1/$3" ]; then exit 7; fi',
    'exec mv -T -- "$1/$2" "$1/$3"'
  ].join("\n")
  return ["sh", "-c", script, "sh", String(dir), String(from), String(to)]
}

// Copy or move one thing into a directory.
//
// `cp -a` and not `cp -r`: an archive copy keeps the modification times, which
// is the difference between a camera roll that is still in date order after it
// has been moved and one that is not.
function place(kind, src, destDir) {
  var verb = kind === "move" ? 'mv -- "$1" "$2/$name"' : 'cp -a -- "$1" "$2/$name"'
  var script = [
    FREE,
    '[ -e "$1" ] || [ -L "$1" ] || exit 4',
    '[ -d "$2" ] || exit 5',
    'name=$(free "$2" "${1##*/}") || exit 6',
    'exec ' + verb
  ].join("\n")
  return ["sh", "-c", script, "sh", String(src), String(destDir)]
}

function openCommand(path) {
  return ["xdg-open", String(path)]
}

// xdg-open's own numbers, which are documented and worth keeping apart: "no
// application is installed for this" and "the application refused" are
// different problems with different answers.
function openTrouble(code) {
  if (code === 2) return "That file is not there any more."
  if (code === 3) return "Nothing on this phone opens that kind of file."
  if (code === 4) return "The app that opens that would not start."
  return "That would not open."
}

// --- the trash ---------------------------------------------------------

// Which volume a path is on, which volume home is on, and who we are. One
// fork, because the answer decides which of two trash directories a file goes
// to and getting it wrong means either a file that vanishes from the trash it
// was supposed to be in, or a four-gigabyte video copied across a card reader
// in order to delete it.
function tops(path, home) {
  var script = [
    'df --output=target -- "$1" 2>/dev/null | tail -n1',
    'df --output=target -- "$2" 2>/dev/null | tail -n1',
    'id -u'
  ].join("\n")
  return ["sh", "-c", script, "sh", String(path), String(home)]
}

function parseTops(text) {
  var lines = String(text || "").split("\n")
  var out = { top: "", homeTop: "", uid: "" }
  if (lines.length >= 1) out.top = lines[0].trim()
  if (lines.length >= 2) out.homeTop = lines[1].trim()
  if (lines.length >= 3) out.uid = lines[2].trim()
  // "Mounted on" is df's header, which is what `tail -n1` returns when df
  // failed and printed nothing else.
  if (out.top === "Mounted on") out.top = ""
  if (out.homeTop === "Mounted on") out.homeTop = ""
  return out
}

// The freedesktop trash, percent-encoded as that specification asks.
// encodeURIComponent would encode the separators too, so the path is encoded
// one segment at a time and the slashes are put back.
function encodePath(path) {
  var parts = String(path).split("/")
  var out = []
  for (var i = 0; i < parts.length; i++) out.push(encodeURIComponent(parts[i]))
  return out.join("/")
}

// Where this file's trash is, and what its info file should say.
//
// Two cases, both from the specification. On the volume home is on, the trash
// is $XDG_DATA_HOME/Trash and `Path=` is absolute. On any other volume it is
// $top/.Trash-$uid, and `Path=` is relative to the top of that volume -- so
// that unplugging the card and plugging it into something else leaves the
// trash still readable.
//
// The third case in the specification, an administrator-made sticky
// $top/.Trash, is not handled: it exists for machines several people share,
// and this is a phone. A volume that has one gets a .Trash-$uid beside it,
// which is still a trash a desktop can read.
function trashPlan(path, home, xdgDataHome, tops) {
  var p = Path.clean(path)
  if (!tops || !tops.top || !tops.homeTop)
    return { problem: "Could not work out which volume that is on." }

  if (tops.top === tops.homeTop) {
    var base = (xdgDataHome && xdgDataHome.length)
               ? Path.clean(xdgDataHome) : Path.join(Path.clean(home), ".local/share")
    return { dir: Path.join(base, "Trash"), line: encodePath(p) }
  }

  if (!tops.uid.length) return { problem: "Could not work out which volume that is on." }
  var top = Path.clean(tops.top)
  var relative = Path.isUnder(p, top) && top !== "/" ? p.slice(top.length + 1) : p
  return { dir: Path.join(top, ".Trash-" + tops.uid), line: encodePath(relative) }
}

// The info file is written before the move and with the shell's own
// noclobber, which is what the specification asks for and why: the name in
// info/ is the claim on the name in files/, so two things being deleted at
// once cannot both take it. If the move then fails the claim is given back.
function trashCommand(trashDir, path, line) {
  var script = [
    'free() {',
    '  d=$1; b=$2; i=$3',
    '  if [ ! -e "$d/$b" ] && [ ! -L "$d/$b" ] && [ ! -e "$i/$b.trashinfo" ]; then printf %s "$b"; return 0; fi',
    '  stem=${b%.*}; ext=',
    '  if [ "$stem" != "$b" ] && [ -n "$stem" ]; then ext=".${b##*.}"; else stem=$b; fi',
    '  n=2',
    '  while [ "$n" -lt 1000 ]; do',
    '    c="$stem ($n)$ext"',
    '    if [ ! -e "$d/$c" ] && [ ! -L "$d/$c" ] && [ ! -e "$i/$c.trashinfo" ]; then printf %s "$c"; return 0; fi',
    '    n=$((n+1))',
    '  done',
    '  return 1',
    '}',
    '[ -e "$2" ] || [ -L "$2" ] || exit 4',
    'mkdir -p "$1/files" "$1/info" || exit 3',
    'name=$(free "$1/files" "${2##*/}" "$1/info") || exit 6',
    'info=$1/info/$name.trashinfo',
    '( set -C; printf "[Trash Info]\\nPath=%s\\nDeletionDate=%s\\n" "$3" "$(date +%Y-%m-%dT%H:%M:%S)" > "$info" ) || exit 8',
    'mv -- "$2" "$1/files/$name" || { rm -f -- "$info"; exit 9; }'
  ].join("\n")
  return ["sh", "-c", script, "sh", String(trashDir), String(path), String(line)]
}

function trashTrouble(code) {
  if (code === 3) return "The trash folder could not be made."
  if (code === 4) return "That is not there any more."
  if (code === 6) return "There are too many things by that name in the trash."
  if (code === 8) return "The trash could not be written to."
  if (code === 9) return "That could not be moved to the trash."
  return "That could not be deleted."
}

// --- the one thing that really deletes ---------------------------------

// Is this path inside a trash's own files/ directory? That is the only place
// in this app where "delete" means gone, and it is gated on this answer rather
// than on which page somebody happens to be looking at.
function trashedName(path, trashDir) {
  var files = Path.join(Path.clean(trashDir), "files")
  var p = Path.clean(path)
  if (!Path.isUnder(p, files) || p === files) return ""
  var rest = p.slice(files.length + 1)
  // Only a direct child of files/ has an info file of its own; something
  // deeper inside a trashed folder is part of that folder, not a trashed
  // thing in its own right.
  return rest.indexOf("/") >= 0 ? "" : rest
}

function purge(path, trashDir, name) {
  var script = [
    'rm -rf -- "$1" || exit 9',
    '[ -n "$3" ] && rm -f -- "$2/info/$3.trashinfo"',
    'exit 0'
  ].join("\n")
  return ["sh", "-c", script, "sh", String(path), String(trashDir), String(name || "")]
}
