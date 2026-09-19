// The short list of places worth a tap, and where they come from.
//
// Two sources, neither of them a guess. The folders are whatever
// `~/.config/user-dirs.dirs` says they are, which is the file xdg-user-dirs
// writes and every desktop app reads -- so a phone set up in German offers
// "Bilder" and "Dokumente", under the names their owner sees everywhere else.
// The volumes are `df`, filtered to the mount points a person put something
// in. Neither list is hardcoded, and both are empty rather than wrong on a
// machine that has neither.
.pragma library
.import "Path.js" as Path

var RS = String.fromCharCode(30)
var US = String.fromCharCode(31)

// The six xdg-user-dirs keys that are places rather than plumbing. TEMPLATES
// and PUBLICSHARE are left out: nobody opens a file manager to go to them, and
// eight rows is already a page.
var USER_DIRS = [
  { key: "XDG_DOWNLOAD_DIR", fallback: "Downloads", glyph: "folder-download-symbolic" },
  { key: "XDG_DOCUMENTS_DIR", fallback: "Documents", glyph: "folder-documents-symbolic" },
  { key: "XDG_PICTURES_DIR", fallback: "Pictures", glyph: "folder-pictures-symbolic" },
  { key: "XDG_MUSIC_DIR", fallback: "Music", glyph: "folder-music-symbolic" },
  { key: "XDG_VIDEOS_DIR", fallback: "Videos", glyph: "folder-videos-symbolic" },
  { key: "XDG_DESKTOP_DIR", fallback: "Desktop", glyph: "user-desktop-symbolic" }
]

// user-dirs.dirs is a shell fragment, and `xdg-user-dir` reads it by sourcing
// it. This parses instead: it is somebody's file, it is in a directory that
// syncs, and running it to find out where the pictures are is a larger promise
// than reading it.
//
// A key set to the home directory itself means "this folder is turned off",
// which is what xdg-user-dirs writes when somebody declines one.
function parseUserDirs(text, home) {
  var out = {}
  var h = Path.clean(home)
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line.length || line.charAt(0) === "#") continue
    var eq = line.indexOf("=")
    if (eq < 1) continue
    var key = line.slice(0, eq).trim()
    if (key.indexOf("XDG_") !== 0) continue
    var raw = line.slice(eq + 1).trim()
    if (raw.length > 1 && (raw.charAt(0) === '"' || raw.charAt(0) === "'")
        && raw.charAt(raw.length - 1) === raw.charAt(0))
      raw = raw.slice(1, -1)
    if (!raw.length) continue
    if (raw.indexOf("$HOME") === 0) raw = h + raw.slice(5)
    else if (raw.indexOf("${HOME}") === 0) raw = h + raw.slice(7)
    if (raw.charAt(0) !== "/") continue
    var path = Path.clean(raw)
    if (path === h) continue
    out[key] = path
  }
  return out
}

// Every folder that might be worth a row, before anything has been asked
// whether it is there. The probe below turns this into the ones that are.
function candidates(home) {
  var out = []
  for (var i = 0; i < USER_DIRS.length; i++)
    out.push(Path.join(Path.clean(home), USER_DIRS[i].fallback))
  return out
}

function wanted(home, dirs) {
  var out = []
  for (var i = 0; i < USER_DIRS.length; i++) {
    var spec = USER_DIRS[i]
    var path = dirs && dirs[spec.key]
              ? dirs[spec.key] : Path.join(Path.clean(home), spec.fallback)
    out.push({ path: path, glyph: spec.glyph })
  }
  return out
}

// One fork for the whole page: which of these directories exist, then df.
// The paths arrive as arguments, so a folder called "Meine Bilder" needs no
// quoting and gets none.
function command(paths) {
  var script = [
    'for p in "$@"; do if [ -d "$p" ]; then printf "%s\\037" "$p"; fi; done',
    'printf "\\036"',
    'df -P 2>/dev/null'
  ].join("\n")
  var argv = ["sh", "-c", script, "sh"]
  for (var i = 0; i < paths.length; i++) argv.push(String(paths[i]))
  return argv
}

// The mount points worth showing, which is not all of them.
//
// A phone's `df` is thirty rows of tmpfs, cgroup and efivarfs before it gets
// to anything a person put a file on. Two filters and not one: a real block
// device, and a mount point somewhere a person's things are -- because / is
// on a real device and so is the boot partition, and only one of those is a
// place.
var VOLUME_ROOTS = ["/run/media/", "/media/", "/mnt/"]

function parseVolumes(text) {
  var lines = String(text || "").split("\n")
  var out = []
  var seen = {}
  for (var i = 1; i < lines.length; i++) {
    var fields = lines[i].trim().split(/\s+/)
    if (fields.length < 6) continue
    var device = fields[0]
    if (device.indexOf("/dev/") !== 0) continue
    if (device.indexOf("/dev/loop") === 0) continue
    // A mount point may contain spaces, and POSIX df does not escape them.
    // It is the last column, so everything from the sixth field on is it.
    var mount = fields.slice(5).join(" ")
    var keep = mount === "/" || mount === "/home"
    for (var r = 0; r < VOLUME_ROOTS.length && !keep; r++)
      if (mount.indexOf(VOLUME_ROOTS[r]) === 0) keep = true
    if (!keep || seen[mount]) continue
    seen[mount] = true
    var blocks = parseInt(fields[1], 10)
    var free = parseInt(fields[3], 10)
    out.push({
      path: mount,
      label: mount === "/" ? "Filesystem" : Path.base(mount),
      glyph: mount === "/" ? "drive-harddisk-symbolic" : "drive-removable-media-symbolic",
      // df counts 1024-byte blocks under -P whatever the filesystem's own
      // block size is, which is the one thing -P is for.
      total: isFinite(blocks) ? blocks * 1024 : 0,
      free: isFinite(free) ? free * 1024 : 0
    })
  }
  return out
}

function parseProbe(text) {
  var halves = String(text || "").split(RS)
  var present = {}
  var found = halves[0] ? halves[0].split(US) : []
  for (var i = 0; i < found.length; i++)
    if (found[i].length) present[found[i]] = true
  return { present: present, volumes: parseVolumes(halves.length > 1 ? halves[1] : "") }
}

// The page itself: home, then the folders that exist, then the trash, then the
// volumes. Home is always shown even if the probe never ran -- an empty places
// page with no way back to the one place everybody wants is worse than a page
// that is briefly one row long.
function rows(home, dirs, probe, trashDir) {
  var out = []
  var h = Path.clean(home)
  out.push({ label: "Home", path: h, glyph: "user-home-symbolic", note: "~" })

  var folders = wanted(h, dirs)
  for (var i = 0; i < folders.length; i++) {
    var folder = folders[i]
    if (!probe || !probe.present || !probe.present[folder.path]) continue
    out.push({
      label: Path.base(folder.path),
      path: folder.path,
      glyph: folder.glyph,
      note: Path.pretty(folder.path, h)
    })
  }

  if (trashDir) {
    var files = Path.join(trashDir, "files")
    out.push({
      label: "Trash", path: files, glyph: "user-trash-symbolic",
      note: "Things this app deleted", trash: true
    })
  }

  var volumes = probe && probe.volumes ? probe.volumes : []
  for (var v = 0; v < volumes.length; v++) {
    var vol = volumes[v]
    out.push({
      label: vol.label, path: vol.path, glyph: vol.glyph,
      note: "", total: vol.total, free: vol.free, volume: true
    })
  }
  return out
}
