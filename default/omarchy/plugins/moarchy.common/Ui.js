// Phone chrome: corners and control center control sizes, from one user file.
//
// Colours stay in colors.toml -- omarchy-theme-set already stages those, and
// every surface already follows them. What this file owns is the half that
// used to be hardcoded per plugin: D1's three radii, and the control center's tile /
// slider / round-button heights. Those are a preference, not a theme, so they
// live in ~/.config/omarchy/ui.toml and survive a palette swap.
//
// `.pragma library` for the same reason Theme.js is: pure functions, one
// shared instance. The FileView that watches the path is UiFile.qml, because
// a library cannot own I/O.
.pragma library

.import "Sheet.js" as Sheet

var CORNERS = {
  large:  { sheet: 28, tile: 20, card: 18 },
  modest: { sheet: 12, tile: 8,  card: 6  },
  square: { sheet: 0,  tile: 0,  card: 0  }
}

var CONTROL_CENTER = {
  roomy:   { controlCenterTile: 62, controlCenterSlider: 48, controlCenterRound: 36 },
  compact: { controlCenterTile: 48, controlCenterSlider: 36, controlCenterRound: 32 }
}

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
  "workspace-overview":   Sheet.WORKSPACE_OVERVIEW,
  "control-center":       Sheet.CONTROL_CENTER
}

var GESTURE_LABELS = {
  none:                   "Nothing",
  "app-drawer":           "App drawer",
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

function num(data, names, fallbackValue) {
  for (var i = 0; i < names.length; i++) {
    var v = data[names[i]]
    if (v === undefined || v === "") continue
    var n = Number(v)
    if (isFinite(n) && n >= 0) return n
  }
  return fallbackValue
}

function fromData(data) {
  data = data || {}
  var corners = normCorners(data.corners)
  var controlCenter = normShade(data.controlCenter || data.density)
  var c = CORNERS[corners]
  var s = CONTROL_CENTER[controlCenter]
  return {
    corners: corners,
    controlCenter: controlCenter,
    sheet: num(data, ["sheet"], c.sheet),
    tile: num(data, ["tile"], c.tile),
    card: num(data, ["card"], c.card),
    controlCenterTile: num(data, ["control_center_tile", "controlCenterTile"], s.controlCenterTile),
    controlCenterSlider: num(data, ["control_center_slider", "controlCenterSlider"], s.controlCenterSlider),
    controlCenterRound: num(data, ["control_center_round", "controlCenterRound"], s.controlCenterRound),
    // Q1. The defaults are today's wiring, so a home with no ui.toml is the
    // phone as it shipped -- themed by presence, never broken by absence.
    gestureBottom: normTarget(data.gesture_bottom || data.gestureBottom, "app-drawer"),
    gestureRight: normTarget(data.gesture_right || data.gestureRight, "workspace-overview"),
    // Q10. The hold keeps C1's meaning as its default, so a phone nobody has
    // touched still opens the coding agent. The power button's double press
    // is new and starts off.
    gestureHold: normTap(data.gesture_hold || data.gestureHold, "agent"),
    gesturePower: normTap(data.gesture_power || data.gesturePower, "none")
  }
}

function parseToml(text) {
  var data = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\s+#.*$/, "").trim()
    if (!line || line[0] === "#" || line[0] === "[") continue
    var eq = line.indexOf("=")
    if (eq < 1) continue
    var key = line.slice(0, eq).trim()
    var raw = line.slice(eq + 1).trim()
    if ((raw[0] === "\"" && raw[raw.length - 1] === "\"") ||
        (raw[0] === "'" && raw[raw.length - 1] === "'"))
      raw = raw.slice(1, -1)
    data[key] = raw
  }
  return data
}

function parse(text) {
  return fromData(parseToml(text))
}

function differs(chrome, key, presetValue) {
  return Number(chrome[key]) !== Number(presetValue)
}

function serialize(chrome) {
  var c = chrome || fallback()
  var presetC = CORNERS[c.corners] || CORNERS.large
  var presetS = CONTROL_CENTER[c.controlCenter] || CONTROL_CENTER.roomy
  var lines = [
    "# Phone chrome. Independent of the colour theme.",
    "# Colours live in ~/.local/state/omarchy/current/theme/colors.toml",
    "# and change with omarchy-theme-set. This file reshapes the UI.",
    "#",
    "# corners: large | modest | square",
    "# control_center:  roomy | compact",
    "#",
    "# Which sheet each swipeable edge raises:",
    "#   gesture_bottom, gesture_right: none | app-drawer | workspace-overview | control-center",
    "#   gesture_hold, gesture_power:   the same, plus agent or an app id",
    "#",
    "# Optional numbers (logical px) override the preset for that key:",
    "#   sheet, tile, card, control_center_tile, control_center_slider, control_center_round",
    "",
    "corners = \"" + c.corners + "\"",
    "control_center = \"" + c.controlCenter + "\"",
    // Written every time and not gated on differs(): these are presets like
    // corners and control center, not overrides of one, so there is nothing to omit.
    "gesture_bottom = \"" + c.gestureBottom + "\"",
    "gesture_right = \"" + c.gestureRight + "\"",
    "gesture_hold = \"" + c.gestureHold + "\"",
    "gesture_power = \"" + c.gesturePower + "\""
  ]
  if (differs(c, "sheet", presetC.sheet)) lines.push("sheet = " + c.sheet)
  if (differs(c, "tile", presetC.tile)) lines.push("tile = " + c.tile)
  if (differs(c, "card", presetC.card)) lines.push("card = " + c.card)
  if (differs(c, "controlCenterTile", presetS.controlCenterTile)) lines.push("control_center_tile = " + c.controlCenterTile)
  if (differs(c, "controlCenterSlider", presetS.controlCenterSlider)) lines.push("control_center_slider = " + c.controlCenterSlider)
  if (differs(c, "controlCenterRound", presetS.controlCenterRound)) lines.push("control_center_round = " + c.controlCenterRound)
  lines.push("")
  return lines.join("\n")
}

function merge(chrome, patch) {
  var cur = chrome || fallback()
  // Every key the file owns, not the two this used to name: `merge` feeds
  // `fromData`, so a key left out here is a key reset to its default for as
  // long as the optimistic value is on screen (Themes.qml's chip tap).
  var data = { corners: cur.corners, controlCenter: cur.controlCenter,
               gesture_bottom: cur.gestureBottom,
               gesture_right: cur.gestureRight,
               gesture_hold: cur.gestureHold,
               gesture_power: cur.gesturePower }
  for (var k in (patch || {})) data[k] = patch[k]
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
