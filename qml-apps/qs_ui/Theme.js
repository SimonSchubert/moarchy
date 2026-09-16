// The phone's palette, from the same file GTK apps read.
//
// `~/.local/state/omarchy/current/theme/colors.toml` is what
// `omarchy-theme-set` stages. Mixing lives here so chrome in every plugin
// is the same ink as the rest of the shell, not a hardcoded GNOME blue.
.pragma library

var GNOME = {
  red: "#e01b24",
  orange: "#ff7800",
  yellow: "#f5c211",
  green: "#33d17a",
  cyan: "#00b8c4",
  blue: "#3584e4",
  magenta: "#c061cb",
  brown: "#986a44"
}

function hexOk(s) {
  return typeof s === "string" && /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(s.trim())
}

function normHex(s) {
  var h = String(s).trim()
  if (h.length === 4) {
    return ("#" + h[1] + h[1] + h[2] + h[2] + h[3] + h[3]).toLowerCase()
  }
  return h.toLowerCase()
}

function rgb(hex) {
  var h = normHex(hex).slice(1)
  return [
    parseInt(h.slice(0, 2), 16),
    parseInt(h.slice(2, 4), 16),
    parseInt(h.slice(4, 6), 16)
  ]
}

function mix(colour, into, amount) {
  var src = rgb(colour), dst = rgb(into)
  function ch(i) {
    var n = Math.round(src[i] * amount + dst[i] * (1 - amount))
    var t = n.toString(16)
    return t.length === 1 ? "0" + t : t
  }
  return "#" + ch(0) + ch(1) + ch(2)
}

// How bright a colour is, on the crude weighting that has been good enough for
// choosing black-or-white text since the nineteen-fifties. Three plugins had
// their own copy, all three identical.
function shade(colour) {
  var c = rgb(String(colour))
  return (c[0] * 299 + c[1] * 587 + c[2] * 114) / 255000.0
}

// What can be read on a solid fill. Not always the background: on a light
// theme that is white, and white on a pale yellow accent is a Start button
// nobody can find. Calculator's rule, and its reason.
function inkOn(colours, fill) {
  if (!colours) return "#ffffff"
  var level = shade(fill)
  return Math.abs(level - shade(colours.background))
       > Math.abs(level - shade(colours.foreground))
    ? colours.background : colours.foreground
}

// --- elevation ---------------------------------------------------------
//
// A box on this phone is not a border, it is a lighter fill. Which lighter
// fill was a decision every plugin made for itself -- 0.06 in Weather, 0.07 in
// Clock, 0.08 and 0.06 in Files, 0.10 and 0.12 elsewhere -- and the result was
// that the same object read as a different depth depending on which app it was
// in. These five are the whole ramp, and nothing outside this file names a
// mixing amount for a surface again.
//
// They are mixes of the theme's own ink into its own background rather than
// white at an alpha, so a light theme gets a *darker* box and the ramp still
// reads as depth rather than as fog.
//
// Every step is a distance from the *page background*, not from whatever is
// behind the thing being drawn -- so a box inside a box takes the next step
// up, and a track drawn inside a card takes `raised` rather than `well`. On a
// dark theme the two are hard to tell apart either way round; on a light one,
// a `well` inside a `card` is the only combination that comes out lighter than
// its own parent, which reads as a hole rather than as a track.
var LEVEL = {
  // A track something fills, drawn straight onto the page background.
  well: 0.035,
  // The ordinary box. A card on the page, a row in a list.
  card: 0.07,
  // A box inside a box, a track inside a card, and anything that has to read
  // as liftable off one.
  raised: 0.12,
  // Any of the above under a thumb.
  pressed: 0.17,
  // The last resort, for the rare edge that has to be drawn rather than
  // implied. Not a divider: a divider is a gap here.
  edge: 0.22
}

function surface(colours, level) {
  var amount = LEVEL[level]
  if (amount === undefined) amount = LEVEL.card
  if (!colours) return mix("#ffffff", "#1d1d20", amount)
  return mix(colours.foreground, colours.background, amount)
}

// The same ramp in a hue rather than in the ink: a tinted card, for the one
// row in a list that is a warning, a streak or an event with a colour on it.
// Stronger than `surface` at every step because a hue mixed at 0.07 into the
// background is a grey with a rumour of colour in it.
var TINT = { well: 0.10, card: 0.20, raised: 0.28, pressed: 0.36, edge: 0.44 }

function tint(colours, hue, level) {
  var amount = TINT[level]
  if (amount === undefined) amount = TINT.card
  if (!colours) return hue
  return mix(hue, colours.background, amount)
}

// `Util.alpha` in qs.Commons is this function. Ours is a copy rather than an
// import so that fading a press does not drag the whole kit onto a shell that
// only exists on our image.
function alpha(colour, a) {
  return Qt.rgba(colour.r, colour.g, colour.b, a)
}

function pick(data, names) {
  for (var i = 0; i < names.length; i++) {
    var v = data[names[i]]
    if (hexOk(v)) return normHex(v)
  }
  return ""
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

// Stand-ins for a desktop with no Omarchy, a theme with no colors.toml, or a
// malformed one. Themed by the file's presence, never broken by its absence --
// which is theme.py's rule (docs/style.md I2), and these are its own two sets.
var GNOME_DARK = { background: "#1d1d20", surface: "#28282c", foreground: "#ffffff" }
var GNOME_LIGHT = { background: "#fafafa", surface: "#ffffff", foreground: "#2e3436" }

// `dark` defaults true because that is what an app has before it has read
// anything. A light desktop that has never run omarchy-theme-set used to get
// white text on near-black here, which is not a fallback so much as a bug with
// a palette.
function fallback(dark) {
  var light = dark === false
  var base = light ? GNOME_LIGHT : GNOME_DARK
  return {
    accent: "#3584e4",
    background: base.background,
    surface: base.surface,
    raised: base.surface,
    foreground: base.foreground,
    dim: "#9a9996",
    line: mix(base.foreground, base.background, 0.16),
    hues: GNOME,
    dark: !light
  }
}

function fromData(data) {
  // `mode` is read before the bail-out on purpose: a theme can name a mode and
  // still be missing the three colours below, and a light desktop should get
  // the light stand-ins rather than the dark ones.
  var dark = String(data.mode || "dark").toLowerCase() !== "light"
  var accent = pick(data, ["accent", "blue"])
  var background = pick(data, ["background"])
  var foreground = pick(data, ["bright_foreground", "foreground"])
  // Missing any of these leaves half the app themed and half not, which looks
  // worse than not theming it at all -- theme.py:load() says the same.
  if (!(accent && background && foreground)) return fallback(dark)
  var hues = {}
  for (var role in GNOME) {
    hues[role] = pick(data, [role, "bright_" + role]) || GNOME[role]
  }
  var surface = pick(data, ["lighter_background", "selection"]) || background
  var raised = pick(data, ["selection", "lighter_background"]) || background
  var dim = pick(data, ["dark_foreground", "muted"]) || foreground
  return {
    accent: accent,
    background: background,
    surface: surface,
    raised: raised,
    foreground: foreground,
    dim: dim,
    line: mix(foreground, background, 0.16),
    hues: hues,
    dark: dark
  }
}

function parse(text) {
  return fromData(parseToml(text))
}
