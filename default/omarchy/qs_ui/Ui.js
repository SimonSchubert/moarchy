// Phone chrome: corners and control center control sizes, from one user file.
//
// Keep in step with default/omarchy/plugins/moarchy.common/Ui.js -- the
// plugins cannot import qs_ui, and the apps cannot import moarchy.common,
// so the parser exists twice. The file they both read is one:
// ~/.config/omarchy/ui.toml.
.pragma library

var CORNERS = {
  large:  { sheet: 28, tile: 20, card: 18 },
  modest: { sheet: 12, tile: 8,  card: 6  },
  square: { sheet: 0,  tile: 0,  card: 0  }
}

var CONTROL_CENTER = {
  roomy:   { controlCenterTile: 62, controlCenterSlider: 48, controlCenterRound: 36 },
  compact: { controlCenterTile: 48, controlCenterSlider: 36, controlCenterRound: 32 }
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
    controlCenterRound: num(data, ["control_center_round", "controlCenterRound"], s.controlCenterRound)
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
    "# Optional numbers (logical px) override the preset for that key:",
    "#   sheet, tile, card, control_center_tile, control_center_slider, control_center_round",
    "",
    "corners = \"" + c.corners + "\"",
    "control_center = \"" + c.controlCenter + "\""
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
  var data = { corners: cur.corners, controlCenter: cur.controlCenter }
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
