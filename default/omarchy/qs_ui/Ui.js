// The shape half of the UI settings file: corners and control center sizes.
//
// Keep in step with default/omarchy/plugins/moarchy.common/Ui.js -- the
// plugins cannot import qs_ui, and the apps cannot import moarchy.common, so
// this exists twice. The file they both read is one, ~/.config/omarchy/ui.toml,
// and so is the reader: Toml.js here is a byte-for-byte copy of the shell's,
// and `shapeFrom` below is the same function as the shell's. style-check.sh
// compares both, because a corners pick the shell and the apps read
// differently is a phone with two shapes on it.
.pragma library

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

function fallback() {
  return shapeFrom({})
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

// The section's key, else the flat name a file from before the sections used.
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

function parse(text) {
  var r = Toml.parse(text)
  return shapeFrom(r.ok ? r.data : Toml.flat(text))
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
