// A window, and what to draw for it: icon, name, page title, glyph
// (docs/refactor.md E7, gestures.md K5/M4).
//
//     import "../moarchy.common/Apps.js" as Apps
//
//     property var appIdIndex: ({})
//     function buildIndex(): void { root.appIdIndex = Apps.index(root.shell) }
//     function openIconFor(app) { return Apps.iconFor(root.shell, root.appIdIndex, app) }
//
// Two surfaces draw a window as a tile: the drawer's shelf (M4) and the
// overview's workspace cards (P5). They are the same tile -- the same icon, the
// same name, the same glyph for a shell app -- because they are answering the
// same question about the same handle, and a second implementation of that
// answer is how the shelf came to draw `org.quickshell` with no icon for every
// plugin that was not in ShellApps.IDS.
//
// `.pragma library`, so there is one index-builder rather than a copy per
// importing component. It reaches nothing: `shell` is handed in, which is what
// lets a library script answer a question about the host (E3's shape).
//
// ---------------------------------------------------------------------------
// What it does not own
// ---------------------------------------------------------------------------
// **The index itself.** `index()` builds a map and hands it back; the surface
// holds it and decides when to rebuild. The drawer rebuilds on `appsChanged`
// and the overview when its sheet comes up, and neither wants the other's
// timing.
//
// **Which windows there are.** That is `ToplevelManager` for the drawer and the
// sway tree for the overview, and they are different questions: the shelf is
// every window in MRU order, a card is the windows on one workspace.
.pragma library

.import "ShellApps.js" as ShellApps

// appId -> desktop entry, plus `plugin:<id>` for the entries that summon a
// plugin rather than starting a process.
//
// `appLibrary` can sort entries and turn an icon name into a source, but it has
// no lookup by id. Built once and rebuilt when the app list moves: scanning
// sortedEntries() inside a delegate would be O(apps) per tile per frame.
function index(shell) {
  var map = ({})
  if (!shell || !shell.appLibrary) return map
  var rows = shell.appLibrary.sortedEntries("")
  for (var i = 0; i < rows.length; i++) {
    var entry = rows[i].entry
    if (!entry) continue
    var id = String(entry.id || "").toLowerCase().replace(/\.desktop$/, "")
    if (!id) continue
    if (map[id] === undefined) map[id] = entry
    // Sway reports the app_id an app sets for itself, which is often the last
    // segment of a reverse-DNS desktop id -- org.gnome.Papers maps to an
    // app_id of "papers". Index both; first writer wins, so an exact match is
    // never displaced by a suffix collision.
    var tail = id.split(".").pop()
    if (tail && map[tail] === undefined) map[tail] = entry

    // A shell app's window carries the shell process's own app id (K9), so
    // nothing above can ever find its entry. The entry names the plugin in its
    // Exec line -- `omarchy-shell shell toggle <id>` -- and that is the only
    // place the two are joined: Quickshell's DesktopEntry exposes name, icon,
    // categories and exec, and no way to read an X- key, so the X-Moarchy-Plugin
    // these entries also carry is unreachable from here.
    //
    // Kept under a prefix so a plugin id can never be returned for an app_id
    // that happens to spell the same thing.
    var toggled = pluginSummonedBy(entry)
    if (toggled) {
      var key = "plugin:" + toggled[1].toLowerCase()
      if (map[key] === undefined) map[key] = entry
    }
  }
  return map
}

// The plugin id an entry summons, as a one-element match, or null for an entry
// that starts a process. Written once: index() keys the shelf's icons off it
// (K5) and the drawer's launch() asks it whether a window is coming (L10).
function pluginSummonedBy(entry) {
  if (!entry) return null
  return /(?:^|\s)shell\s+toggle\s+(\S+)/.exec(String(entry.execString || ""))
}

function entryForAppId(map, appId) {
  if (!map || !appId) return null
  var e = map[String(appId).toLowerCase()]
  return e === undefined ? null : e
}

function entryForPluginId(map, pluginId) {
  if (!map || !pluginId) return null
  var e = map["plugin:" + String(pluginId).toLowerCase()]
  return e === undefined ? null : e
}

// K5, M4. A shell app names and draws itself: its app id is the shell process's
// own (K9), so there is no desktop entry to look either up in. The plugin that
// draws the window is asked instead, and asked by *handle* --
// ShellApps.forToplevel compares the toplevel against each plugin's
// appWindow.toplevel, which the window itself resolved once when it mapped.
function shellAppFor(shell, tl) {
  return ShellApps.forToplevel(shell, tl)
}

function iconFor(shell, map, tl) {
  if (!tl || !shell || !shell.appLibrary) return ""
  var own = shellAppFor(shell, tl)
  var entry = own ? entryForPluginId(map, own.pluginId)
                  : entryForAppId(map, tl.appId)
  if (!entry) return ""
  return shell.appLibrary.iconSource(entry.icon)
}

function nameFor(shell, map, tl) {
  if (!tl) return ""
  var own = shellAppFor(shell, tl)
  if (own) return String(own.appWindow.appName || "")
  var entry = entryForAppId(map, tl.appId)
  if (entry && shell && shell.appLibrary) return shell.appLibrary.entryName(entry)
  return tl.appId || tl.title || "Window"
}

// The page a shell app is on, which its own window already carries, and the
// window title for anything else. A shell app's title is "<name> -- <page>", so
// reading it off the window rather than off the toplevel is what keeps a line
// from repeating its own name.
function titleFor(shell, tl) {
  if (!tl) return ""
  var own = shellAppFor(shell, tl)
  if (own) return String(own.appWindow.pageTitle || "")
  return String(tl.title || "")
}

// Non-empty for a shell app and empty for anything else, which is what a tile
// branches on: an Image with an empty source draws nothing at all (M4).
function glyphFor(shell, tl) {
  var own = shellAppFor(shell, tl)
  return own ? String(own.appWindow.glyph || "") : ""
}
