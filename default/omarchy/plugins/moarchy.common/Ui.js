// The UI settings file, ~/.config/omarchy/ui.toml, read into one object
// (docs/home.md §G).
//
// Colours stay in colors.toml -- omarchy-theme-set already stages those, and
// every surface already follows them. What this file owns is the half that
// is a preference rather than a theme: D1's radii, the control center's sizes,
// what each gesture opens, and home's grid and frame. It survives a palette
// swap because it is not part of one.
//
// The file is sectioned -- [shape], [control-center], [gestures], [home] --
// and the packaged /usr/share/moarchy/ui.toml documents every key. A file
// written before the sections, with flat `corners = ...` and
// `gesture_bottom = ...` lines, reads exactly as it did (HM29): each value is
// looked for in its section first and under its old flat name second.
//
// `.pragma library` for the reason Theme.js is: pure functions, one shared
// instance. Reading is Toml.js (HM30); the FileView that watches the path is
// UiFile.qml, because a library cannot own I/O; and the one writer is
// `moarchy-ui`, so nothing here serialises.
.pragma library

.import "Sheet.js" as Sheet
.import "Toml.js" as Toml

// The `frame` column is home's tiles (HM10a): Omalauncher's 16px times its
// corner scale of 1, 0.5 or 0.
var CORNERS = {
  large:  { sheet: 28, tile: 20, card: 18, frame: 16 },
  modest: { sheet: 12, tile: 8,  card: 6,  frame: 8  },
  square: { sheet: 0,  tile: 0,  card: 0,  frame: 0  }
}

var CONTROL_CENTER = {
  roomy:   { controlCenterTile: 62, controlCenterSlider: 48, controlCenterRound: 36 },
  compact: { controlCenterTile: 48, controlCenterSlider: 36, controlCenterRound: 32 }
}

// HM10, HM20, HM21. Omalauncher's own defaults (its theme/Style.kt), so home
// looks like it before anybody has touched a setting.
var HOME = { columns: 6, opacity: 0.88, border: 2, gapsIn: 6, gapsOut: 6,
             recent: 8, promptBar: true }

// gestures.md Q1. What the two configurable edges may raise, as words. The
// file, `bin/moarchy-ui` and the Settings rows all speak these and never a
// plugin id, so Sheet.js stays the one place an id is written (refactor.md
// I2) and a hand-edited `ui.toml` cannot name a plugin that is not a sheet.
//
// The theme picker is deliberately absent: it is a sheet by rank but it has
// no drag contract at all -- no `progress`, no `dragging` -- so an edge set
// to it would follow no finger. Adding one is what would put it here.
var GESTURE_TARGETS = {
  none:                   "",
  "app-drawer":           Sheet.APP_DRAWER,
  "app-drawer-minimal":   Sheet.APP_DRAWER_MINIMAL,
  "workspace-overview":   Sheet.WORKSPACE_OVERVIEW,
  "control-center":       Sheet.CONTROL_CENTER
}

var GESTURE_LABELS = {
  none:                   "Nothing",
  "app-drawer":           "App drawer",
  "app-drawer-minimal":   "Minimal app drawer",
  "workspace-overview":   "Workspace overview",
  "control-center":       "Control Center"
}

// gestures.md Q10. The triggers that are a tap rather than a drag -- the
// strip's hold (C1) and the power button's double press -- take a wider
// vocabulary, because nothing about them has to follow a finger. Three
// kinds of value:
//
//   none                 the trigger does nothing
//   a word from above    that sheet is summoned, not dragged
//   agent                the default coding agent (C1's original meaning)
//   anything else        a desktop entry id, opened the way the app drawer
//                        opens it
//
// The third is why these cannot be normalised against a table the way an
// edge is: the value space is every app on the phone, and it changes when
// somebody installs one. An unknown word is therefore passed through as an
// id rather than replaced by a default -- and `moarchy-trigger` is the one
// place that decides what a value means, so this file only has to keep the
// two words that are not ids.
var TAP_WORDS = { none: "Nothing", agent: "Coding agent" }

// A tap target, normalised: a known word stays a word, everything else is
// an id and is left alone. Empty falls back to the caller's default, the
// same rule normTarget() follows and for the same reason.
function normTap(s, fallbackName) {
  var n = String(s || "").toLowerCase().trim()
  if (n === "off" || n === "nothing") n = "none"
  if (n === "") {
    var f = String(fallbackName || "none").trim()
    return f === "" ? "none" : f
  }
  if (TAP_WORDS[n] || GESTURE_TARGETS[n] !== undefined) return n
  // An id, and case is not ours to fold: desktop ids are case sensitive.
  return String(s).trim()
}

// What a tap target is called, for a row's detail line. An id is left as it
// is here -- the name behind it lives in the desktop entry, which only the
// shell has read, so `moarchy-trigger label` is what resolves it.
function labelTap(s, fallbackName) {
  var n = normTap(s, fallbackName)
  return TAP_WORDS[n] || GESTURE_LABELS[n] || n
}

function fallback() {
  return fromData({})
}

function normCorners(s) {
  var n = String(s || "large").toLowerCase().trim()
  if (n === "none" || n === "off" || n === "flat" || n === "0") return "square"
  if (n === "small" || n === "little" || n === "soft") return "modest"
  if (n === "round" || n === "rounded" || n === "big") return "large"
  return CORNERS[n] ? n : "large"
}

function normShade(s) {
  var n = String(s || "roomy").toLowerCase().trim()
  if (n === "comfortable" || n === "large" || n === "big" || n === "huge") return "roomy"
  if (n === "small" || n === "dense" || n === "tight") return "compact"
  return CONTROL_CENTER[n] ? n : "roomy"
}

// A word, or the caller's default. A full plugin id is accepted too, so a
// file edited by hand against `omarchy-shell shell listPlugins` still works
// -- but nothing this project writes ever puts one there.
function normTarget(s, fallbackName) {
  var n = String(s || "").toLowerCase().trim()
  // "off" is a choice; absent is not one. Collapsing the empty string into
  // "none" here is what turned a file with no gesture keys in it -- which is
  // every file written before this existed -- into a phone with both edges
  // switched off.
  if (n === "off" || n === "nothing") n = "none"
  if (n !== "" && GESTURE_TARGETS[n] !== undefined) return n
  for (var k in GESTURE_TARGETS)
    if (GESTURE_TARGETS[k] !== "" && GESTURE_TARGETS[k] === n) return k
  var f = String(fallbackName || "").toLowerCase().trim()
  return GESTURE_TARGETS[f] !== undefined ? f : "none"
}

// The plugin id an edge raises, or "" for none -- which is what
// `resolveTarget()` already treats as nothing to drag (Q5).
function targetId(name, fallbackName) {
  return GESTURE_TARGETS[normTarget(name, fallbackName)]
}

function labelTarget(name, fallbackName) {
  return GESTURE_LABELS[normTarget(name, fallbackName)]
}

// ---------------------------------------------------------------------------
// Reading a value
// ---------------------------------------------------------------------------
// `pick(data, "shape.corners", ["corners"])` is the section's key, else the
// first of the flat names a file from before the sections used (HM29). The
// flat names are written down here and in `moarchy-ui`'s migration table and
// nowhere else.
function pick(data, path, legacy) {
  var v = Toml.get(data, path, undefined)
  if (v !== undefined && v !== "") return v
  for (var i = 0; i < (legacy || []).length; i++) {
    var w = data[legacy[i]]
    if (w !== undefined && w !== "" && typeof w !== "object") return w
  }
  return undefined
}

function num(v, fallbackValue, lo, hi) {
  if (v === undefined || v === "" || v === null || typeof v === "boolean") return fallbackValue
  var n = Number(v)
  if (!isFinite(n)) return fallbackValue
  if (lo !== undefined && n < lo) return fallbackValue
  if (hi !== undefined && n > hi) return fallbackValue
  return n
}

function bool(v, fallbackValue) {
  if (v === true || v === false) return v
  var s = String(v === undefined ? "" : v).toLowerCase().trim()
  if (s === "true" || s === "yes" || s === "on" || s === "1") return true
  if (s === "false" || s === "no" || s === "off" || s === "0") return false
  return fallbackValue
}

// The [shape] and [control-center] half, which the apps read as well
// (qs_ui/Ui.js). Kept the same function in both files, and style-check.sh
// compares them, because a corners pick that the shell and the apps read
// differently is a phone with two shapes on it.
function shapeFrom(data) {
  var corners = normCorners(pick(data, "shape.corners", ["corners"]))
  var controlCenter = normShade(pick(data, "control-center.density", ["control_center", "controlCenter", "density"]))
  var c = CORNERS[corners]
  var s = CONTROL_CENTER[controlCenter]
  return {
    corners: corners,
    controlCenter: controlCenter,
    sheet: num(pick(data, "shape.sheet", ["sheet"]), c.sheet, 0),
    tile: num(pick(data, "shape.tile", ["tile"]), c.tile, 0),
    card: num(pick(data, "shape.card", ["card"]), c.card, 0),
    frame: num(pick(data, "shape.frame", []), c.frame, 0),
    controlCenterTile: num(pick(data, "control-center.tile-height", ["control_center_tile", "controlCenterTile"]), s.controlCenterTile, 0),
    controlCenterSlider: num(pick(data, "control-center.slider-height", ["control_center_slider", "controlCenterSlider"]), s.controlCenterSlider, 0),
    controlCenterRound: num(pick(data, "control-center.button-size", ["control_center_round", "controlCenterRound"]), s.controlCenterRound, 0)
  }
}

function fromData(data) {
  data = data || {}
  var out = shapeFrom(data)
  // Q1. The defaults are today's wiring, so a home with no ui.toml is the
  // phone as it shipped -- themed by presence, never broken by absence.
  out.gestureBottom = normTarget(pick(data, "gestures.bottom", ["gesture_bottom", "gestureBottom"]), "app-drawer")
  out.gestureRight = normTarget(pick(data, "gestures.right", ["gesture_right", "gestureRight"]), "workspace-overview")
  // Q10. The hold keeps C1's meaning as its default, so a phone nobody has
  // touched still opens the coding agent. The power button's double press
  // starts off.
  out.gestureHold = normTap(pick(data, "gestures.hold", ["gesture_hold", "gestureHold"]), "agent")
  out.gesturePower = normTap(pick(data, "gestures.power", ["gesture_power", "gesturePower"]), "none")
  // HM10, HM20, HM21. Out-of-range is the default rather than a clamp: a
  // grid of 40 columns is a typo, not a request for 12.
  out.homeColumns = Math.round(num(pick(data, "home.columns", []), HOME.columns, 2, 12))
  out.homeOpacity = num(pick(data, "home.opacity", []), HOME.opacity, 0, 1)
  out.homeBorder = num(pick(data, "home.border", []), HOME.border, 0, 8)
  out.homeGapsIn = num(pick(data, "home.gaps-in", []), HOME.gapsIn, 0, 24)
  out.homeGapsOut = num(pick(data, "home.gaps-out", []), HOME.gapsOut, 0, 48)
  out.homeRecent = Math.round(num(pick(data, "home.recent", []), HOME.recent, 0, 12))
  out.homePromptBar = bool(pick(data, "home.prompt-bar", []), HOME.promptBar)
  return out
}

// A file that is not strict TOML is read the forgiving way every version of
// this file was read before (Toml.flat), so `corners = large` with no quotes
// still means large (HM29). Only text neither reader can use is the defaults.
function parse(text) {
  var r = Toml.parse(text)
  return fromData(r.ok ? r.data : Toml.flat(text))
}

// The optimistic value a picker draws on the tap, before `moarchy-ui` has
// written the file and the FileView has read it back (Themes.qml). `patch`
// takes `corners` and `controlCenter`. Choosing a preset drops that preset's
// overrides, as `moarchy-ui` does on disk; every other setting is carried
// over, or the gesture and home keys would read as their defaults for as long
// as the optimistic value is on screen.
function merge(chrome, patch) {
  var cur = chrome || fallback()
  var p = patch || {}
  var data = {
    shape: { corners: p.corners !== undefined ? p.corners : cur.corners },
    "control-center": { density: p.controlCenter !== undefined ? p.controlCenter : cur.controlCenter },
    gestures: { bottom: cur.gestureBottom, right: cur.gestureRight,
                hold: cur.gestureHold, power: cur.gesturePower },
    home: { columns: cur.homeColumns, opacity: cur.homeOpacity, border: cur.homeBorder,
            "gaps-in": cur.homeGapsIn, "gaps-out": cur.homeGapsOut,
            recent: cur.homeRecent, "prompt-bar": cur.homePromptBar }
  }
  if (p.corners === undefined) {
    data.shape.sheet = cur.sheet; data.shape.tile = cur.tile
    data.shape.card = cur.card; data.shape.frame = cur.frame
  }
  if (p.controlCenter === undefined) {
    data["control-center"]["tile-height"] = cur.controlCenterTile
    data["control-center"]["slider-height"] = cur.controlCenterSlider
    data["control-center"]["button-size"] = cur.controlCenterRound
  }
  return fromData(data)
}

function labelCorners(name) {
  var n = normCorners(name)
  if (n === "modest") return "Modest"
  if (n === "square") return "Square"
  return "Large"
}

function labelShade(name) {
  return normShade(name) === "compact" ? "Compact" : "Roomy"
}

// Tile radius, never more than a half-side. Large stays a pill/circle,
// Modest matches the tiles, Square is square.
function radiusOn(tile, size) {
  var t = Number(tile)
  var half = Number(size) / 2
  if (!isFinite(t) || t < 0) t = 0
  if (!isFinite(half) || half < 0) half = 0
  return Math.min(t, half)
}
