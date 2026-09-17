// The sheets this shell draws over a workspace, and what every screen does on
// the way in (docs/refactor.md B1, B6, I1, I2).
//
//     import "../moarchy.common/Sheet.js" as Sheet
//
//     function open(payloadJson) {
//       Sheet.cover(root.shell, root.pluginId, Sheet.WINDOW)
//       var p = Sheet.payload(payloadJson)
//       if (p.returnTo) root.returnTo = String(p.returnTo)
//       ...
//     }
//
// `.pragma library`, so there is one instance rather than a copy per importing
// component. It reaches nothing: `shell` is handed in, which is what lets a
// library script answer a question about the host (E3's shape).
.pragma library

// ---------------------------------------------------------------------------
// One list of sheets, and how they stack
// ---------------------------------------------------------------------------
// Four files kept an answer to "which sheets are there" and gave three
// different ones: Settings named three, four other screens named two, and the
// gestures plugin kept its own `overlayIds`. B1 asked for one list; this is it,
// and `gestures.md` A8 already records what the drift costs -- "three hand-kept
// lists of overlay ids is how Settings and Themes came to be missing from the
// back gesture".
//
// In stacking order, topmost first, which is the order `topmostOverlay()` walks.
// The ids themselves, so a caller that means one particular sheet -- the strip's
// swipe up means the drawer and nothing else -- names it rather than spelling it.
var SHADE = "moarchy.shade"
var DRAWER = "moarchy.drawer"
var OVERVIEW = "moarchy.overview"
var THEMES = "moarchy.themes"

var SHEETS = [
  { id: SHADE, rank: 2 },
  { id: DRAWER, rank: 1 },
  { id: OVERVIEW, rank: 1 },
  { id: THEMES, rank: 1 }
]

// Where the caller sits. B6's rule is "every sheet on its own layer or above",
// and these are the three answers that rule needs:
//
//   OVERLAY  the shade, the only sheet up there, so it covers nothing
//   TOP      the drawer and the theme picker, which cover each other and the
//            shade above them
//   WINDOW   a shell app, which is an ordinary window and therefore *under*
//            every one of them -- so it clears all three
var WINDOW = 0
var TOP = 1
var OVERLAY = 2

// Every sheet id, topmost first.
function ids() {
  var out = []
  for (var i = 0; i < SHEETS.length; i++) out.push(SHEETS[i].id)
  return out
}

// Put away what this screen is about to draw over. Anything ranked at or above
// the caller, never itself, and never anything below -- the shade keeps the
// drawer standing because it draws over it (shade.md S28), and that is the same
// rule read from the other end rather than an exception to it.
function cover(shell, mine, rank) {
  if (!shell || typeof shell.isPluginOpen !== "function") return
  for (var i = 0; i < SHEETS.length; i++) {
    var s = SHEETS[i]
    if (s.id === mine || s.rank < rank) continue
    if (shell.isPluginOpen(s.id)) shell.hide(s.id)
  }
}

// The payload a summon carried, or an empty object. A malformed one is not
// worth refusing to open over, which six screens each said in their own words.
function payload(json) {
  try {
    var p = JSON.parse(String(json || "{}"))
    return (p && typeof p === "object") ? p : {}
  } catch (e) {
    return {}
  }
}

// What a plugin's own `open` IPC verb does: ask the host, so `openPanelIds`
// stays the host's record rather than becoming two records.
function summon(shell, pluginId, json) {
  if (shell && typeof shell.summon === "function")
    shell.summon(pluginId, json || "{}")
}
