// Phone chrome: corners and shade control sizes, from one user file.
//
// Colours stay in colors.toml -- omarchy-theme-set already stages those, and
// every surface already follows them. What this file owns is the half that
// used to be hardcoded per plugin: D1's three radii, and the shade's tile /
// slider / round-button heights. Those are a preference, not a theme, so they
// live in ~/.config/omarchy/ui.toml and survive a palette swap.
//
// `.pragma library` for the same reason Theme.js is: pure functions, one
// shared instance. The FileView that watches the path is UiFile.qml, because
// a library cannot own I/O.
.pragma library

var CORNERS = {
  large:  { sheet: 28, tile: 20, card: 18 },
  modest: { sheet: 12, tile: 8,  card: 6  },
  square: { sheet: 0,  tile: 0,  card: 0  }
}

var SHADE = {
  roomy:   { shadeTile: 62, shadeSlider: 48, shadeRound: 36 },
  compact: { shadeTile: 48, shadeSlider: 36, shadeRound: 32 }
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
  return SHADE[n] ? n : "roomy"
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
  var shade = normShade(data.shade || data.density)
  var c = CORNERS[corners]
  var s = SHADE[shade]
  return {
    corners: corners,
    shade: shade,
    sheet: num(data, ["sheet"], c.sheet),
    tile: num(data, ["tile"], c.tile),
    card: num(data, ["card"], c.card),
    shadeTile: num(data, ["shade_tile", "shadeTile"], s.shadeTile),
    shadeSlider: num(data, ["shade_slider", "shadeSlider"], s.shadeSlider),
    shadeRound: num(data, ["shade_round", "shadeRound"], s.shadeRound)
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
  var presetS = SHADE[c.shade] || SHADE.roomy
  var lines = [
    "# Phone chrome. Independent of the colour theme.",
    "# Colours live in ~/.local/state/omarchy/current/theme/colors.toml",
    "# and change with omarchy-theme-set. This file reshapes the UI.",
    "#",
    "# corners: large | modest | square",
    "# shade:   roomy | compact",
    "#",
    "# Optional numbers (logical px) override the preset for that key:",
    "#   sheet, tile, card, shade_tile, shade_slider, shade_round",
    "",
    "corners = \"" + c.corners + "\"",
    "shade = \"" + c.shade + "\""
  ]
  if (differs(c, "sheet", presetC.sheet)) lines.push("sheet = " + c.sheet)
  if (differs(c, "tile", presetC.tile)) lines.push("tile = " + c.tile)
  if (differs(c, "card", presetC.card)) lines.push("card = " + c.card)
  if (differs(c, "shadeTile", presetS.shadeTile)) lines.push("shade_tile = " + c.shadeTile)
  if (differs(c, "shadeSlider", presetS.shadeSlider)) lines.push("shade_slider = " + c.shadeSlider)
  if (differs(c, "shadeRound", presetS.shadeRound)) lines.push("shade_round = " + c.shadeRound)
  lines.push("")
  return lines.join("\n")
}

function merge(chrome, patch) {
  var cur = chrome || fallback()
  var data = { corners: cur.corners, shade: cur.shade }
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
